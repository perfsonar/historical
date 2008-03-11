=head1 NAME

perfSONAR_PS::DB::PingER -A module that provides base Rose::DB implementation of 
data access for PingER databases

=head1 DESCRIPTION

This module provides access to the relevant Rose::DB methods given the relevant
contact points for the database. It also provides some transparency to the numerous
data tables that is used by PingER in order to provide performance.

=head1 SYNOPSIS

  # create a new database object but calling the Rose::DB register db function
  # note that this allows more than one database to be defined, however
  # we will only use the default/default one.
  perfSONAR_PS::DB::PingER->register_db(
    domain	=> 'default',
    type	=> 'default',
    driver	=> $db_driver,
    database => $db_name,
    host	=> $host,
    port	=> $port,
    username	=> $username,
    password	=> $password,
  );
	
  # try to open the db
  my $db = perfSONAR_PS::DB::PingER->new_or_cached();
 
  # open the database
  if ( $db->openDB() == 0 ) {
  	
  	# There are two ways of getting at the data, either use the wrapper classes
  	# or use the Rose::DB::Objects directly.
  	
  	# get the appropiate rose::db::object that represents a host; this will
  	# automatically insert the entries into the host table if it does not exist
  	my $src = $db->get_host( 'localhost', '127.0.0.1' );
  	my $dst = $db->get_host( 'iepm-resp.slac.stanford.edu', '134.79.240.36' );

	# setup some values for the metadata entry
	my $transport = 'ICMP';
	my $packetSize = '1008';
	my $count = 10;
	my $packetInterval = 1;
	my $ttl = '64';
  	
  	# get the rose::db::object for the metadata, again, this will automatically
  	# insert the entry into the database if it does not exist
  	my $metadata = $db->get_metadata( $src, $dst, $transport, $packetSize, $count, $packetInterval, $ttl );
  	
  	# say we have the data we want to insert as a hash
  	$hash = {
				'timestamp' => '1000000000', # REQUIRED
				'minRtt'	=> '0.023',
				'maxRtt'	=> '0.030',
				'meanRtt'	=> '0.026',
				'minIpd'	=> '0.0',
				'maxIpd'	=> '0.002',
				'meanIpd'	=> '0.006',
				'iqrIpd'	=> '0.0001',
				'lossPercent'	=> '0.0',
				'outOfOrder'	=> 'true',									
				'duplicates'	=> 'false',	
  	}'
  	
  	# now, given that we have the metadata, insert some data into database
  	my $data = $db->insert_data( $metadata, $hash );
  	
  } else 
  	print "Something went wrong with the database init.";
  }
  
=cut


package perfSONAR_PS::DB::PingER;
use Rose::DB;
our @ISA = qw(Rose::DB);

use version; our $VERSION = 0.08; 

use Log::Log4perl qw( get_logger );
our $logger = get_logger("perfSONAR_PS::DB::PingER");

use Rose::DB::Object::Loader;
use POSIX qw( strftime );

use warnings;
use strict;

our $basename = 'perfSONAR_PS::DB::PingER';

# use private registry for this class
__PACKAGE__->use_private_registry;


=head2 error( $ )

accessor/mutator for the last error message

=cut
sub error
{
	my $self = shift;
	if ( @_ ) {
		$self->{'ERRORMSG'} = shift;
	}
	return $self->{'ERRORMSG'};
}




=head2 openDB

opens a connection to the database, creating the rose db object loaders necessary to 
instantiate the in-memory objects for further query of the tables directly

Returns 
   0 = if everything is okay
  -1 = somethign went wrong
  
=cut
sub openDB {
	my $self = shift;
	
	# create the rose db objects
	eval {
		$self->{'RoseDbLoader'} = Rose::DB::Object::Loader->new(
						db			=> perfSONAR_PS::DB::PingER->new_or_cached(),
						class_prefix => $basename,
						include_tables => '^(metaData|data|host)$',
						db_options => { AutoCommit =>1, ChopBlanks => 1, 
                            RaiseError => 0, PrintError => 0, Warn => 0 },  
        );
	};
	if ( $@ ) {
		my $err =  "Could not connect to database: " . $@;
		$logger->error( $self->error( $err ) );
		return -1;
	} else {
        $logger->debug( 'Connection successful' );
    }
	
	# create the objects dynamically
	my @classes = $self->{'RoseDbLoader'}->make_classes(); 
        $logger->debug( 'after make_classes' );
	my %check = ();

	# make sure we have all the classes necessary
	my @must = qw( ::Host ::Host::Manager ::MetaData ::MetaData::Manager ::Data ::Data::Manager );
	foreach my $c ( @must ) {
		my $obj_class = $basename . $c;
		$check{$obj_class} = 0;
		no strict 'refs';
		eval {			
			if( UNIVERSAL::can( $obj_class, 'isa' ) ) {
				$check{$obj_class}++;
			}
		};		
		use strict;
	}
	
	foreach my $k ( @classes ) {
			$logger->debug( "Created rose::db::object '$k'");
	}
	
	my $err = 0;
	while( my ($k,$v) = each %check ) {
		if( $v == 0 ) {
			$logger->fatal( "Could not instantiate rose::db::object '$k'" );
			$err++;
		} 
	}
	
	return ( $err > 0 ? -1 : 0 );
}

=head2 closeDB

closes the connection to the database

=cut
sub closeDB
{
	my $self = shift;
	# close database connection
	# destroy objects classes in memory
	return;	
}


=head2 soi_host( $ip_name, $ip_number )

'select or insert host': wrapper method to look for the table host for the row with 
ip_name $ip_name and ip_number $ip_number' and return the appropiate Rose::DB::Object 
for the host table entry.

=cut
sub soi_host
{
	my $self = shift;
	my $ip_name = shift;
	my $ip_number = shift;
	
	if ( ! defined $ip_name ) {
		$logger->fatal( "ip_name not defined");
		return undef;
	}
	if (  ! defined $ip_number ) {
		$logger->fatal( "ip_number not defined");
		return undef;
	}
		
		
	my $manager = $basename . '::Host::Manager';
	no strict 'refs';
	my $query = $manager->get_host( 
		query => [ 'ip_name' => { 'eq' => $ip_name },
					'ip_number' => { 'eq' => $ip_number }, ],
	);
	use strict;

	# insert if not there
	my $n = scalar @$query;
	if ( $n == 0 ) {
		my $object = $basename . '::Host';
		no strict 'refs';
		my $host = $object->new(
					'ip_name' => $ip_name,
					'ip_number' => $ip_number,
				)->save;
		use strict;
		$logger->debug( "insert'd new host '$ip_name'/'$ip_number'");
		return $host;
	}
	elsif ( $n == 1 ) {
		$logger->debug( "found host '$ip_name'/'$ip_number");
		return $query->[0];
	} else {
		$logger->error( "Found more than one element!");
		return undef;
	}
	
}


=head2 get_metadata( $src, $dst, $transport, $packetSize, $count, $packetInterval, $ttl )

wrapper method to retrieve the relevant rose::db:object of the metadata entry given
rose::db::objects of the source $src to destination $dst using a hash of key/value pairs:
$hash ={
	'transport' = # ICMP, TCP, UDP
	'packetSize' = # packet size of pings in bytes
	'count' 	= # number of packets sent
	'packetInterval' = # inter packet time in seconds
	'ttl' 		= # time to live of packets
	
}

=cut
sub soi_metadata
{
	my $self = shift;
	my $src = shift;
	my $dst = shift;

	my $hash = shift;	
	
	my $manager = $basename . '::MetaData::Manager';
	no strict 'refs';
	my $query = $manager->get_metaData( 
		query => [ 	'ip_name_src' => { 'eq' => $src->ip_name() },
					'ip_name_dst' => { 'eq' => $dst->ip_name() },
					'transport'	  => { 'eq' => $hash->{'transport'} },
					'packetSize'  => { 'eq' => $hash->{'packetSize'} },
					'count'		  => { 'eq' => $hash->{'count'} },
					'packetInterval' => { 'eq' => $hash->{'packetInterval'} },
					'ttl'		  => { 'eq' => $hash->{'ttl'} },
				 ] );
	use strict;
	
	my $n = scalar @$query;
	if ( $n == 0 ) {
		my $object = $basename . '::MetaData';
		no strict 'refs';
		my $md = $object->new(
					'ip_name_src' => $src->ip_name(),
					'ip_name_dst' => $dst->ip_name(),
					'transport'	  => $hash->{'transport'},
					'packetSize'  => $hash->{'packetSize'},
					'count'		  => $hash->{'count'},
					'packetInterval' => $hash->{'packetInterval'},
					'ttl'		  => $hash->{'ttl'},
				)->save;
		use strict;
		$logger->debug( "insert'd new metadata " . $md->metaID );
		return $md;
	} elsif ( $n == 1 ) {
		$logger->debug( 'Found metadata ' . $query->[0]->metaID );
		return $query->[0];
	} else {
		$logger->error( 'found more than one element!');
		return undef;
	}
}



=head2 insert_data( $metadata, $hash );

inserts into the database the information presented with the rose::db::metadata object
$metadata (also the output of get_metadata()) with the information presented in the 
hash $hash. $hash should contain
$hash = {

	# REQUIRED values
	'timestamp' => # epoch seconds timestamp of test

	# RTT values
	'minRtt'	=> # minimum rtt of ping measurement
	'meanRtt'	=> # mean rtt of ping measurement
	'maxRtt'	=> # maximum rtt of ping measurement
	
	# IPD
	'minIpd'	=> # minimum ipd of ping measurement
	'meanIpd'	=> # mean ipd of ping measurement
	'maxIpd'	=> # maximum ipd of ping measurement
	
	# LOSS
	'lossPercent' => # percentage of packets lost
	'clp'		=> # conditional loss probability of measurement
	
	# JITTER
	'iqrIpd'	=> # interquartile range of ipd value of measurement
	'medianRtt'	=> # median value of rtts
	
	# OTHER
	'outOfOrder'	=> # boolean value of whether any packets arrived out of order
	'duplicates'	=> # boolean value of whether any duplicate packets were recvd.

	# LOG
	'rtts'		=> [] # array of rtt values of the measurement
	'seqNums'	=> [] # array of the order in which sequence numbers are recvd
}

Returns
   0 = everything okay
  -1 = somethign went wrong
	
}

=cut
sub insert_data
{
	my $self = shift;
	my $metadata = shift;
	my $hash = shift;
		
	use Data::Dumper;
	$logger->debug( "input hash: " . Dumper $hash );
	
	if( ! exists $hash->{'timestamp'} || ! defined $hash->{'timestamp'} ) {
		$self->error( "Data set does not contain a timestamp");
		return -1;
	}
	
	# remap the timestamp if it's not valid
	if ( $hash->{'timestamp'} =~ m/^(\d+)$/ ) {
		# fine
	} elsif ( $hash->{'timestamp'} =~ m/^(\d+)\./ ) {
		$hash->{'timestamp'} = sprintf "%.0f", $hash->{'timestamp'};
	} else {
		$self->error( "Timestamp format unparseable");
		return -1;
	}
	
	# get the data table objects and create them if necessary (1)
	my ( $object, $manager ) = 
			$self->get_rose_objects_for_timestamp( $hash->{'timestamp'}, undef, 1 );

	# handle mysql problems with booleans
	if ( defined $hash->{'duplicates'} ) {
		if ( $hash->{'duplicates'} eq 'false' 
			|| ! $hash->{'duplicates'} ) {
			$hash->{'duplicates'} = 0;
		} else {
			$hash->{'duplicates'} = 1;
		}
	}
	if ( defined $hash->{'outOfOrder'} ) {
		if ( $hash->{'outOfOrder'} eq 'false' 
			|| ! $hash->{'outOfOrder'} ) {
			$hash->{'outOfOrder'} = 0;
		} else {
			$hash->{'outOfOrder'} = 1;
		}
	}

	my $data = $object->[0]->new(
					'metaID'	=> $metadata->metaID(),
					
					# time
					'timestamp' => $hash->{'timestamp'},
					
					# rtt
					'minRtt'	=> $hash->{'minRtt'},
					'maxRtt'	=> $hash->{'maxRtt'},
					'meanRtt'	=> $hash->{'meanRtt'},
					# medianRtt
					
					# ipd
					'minIpd'	=> $hash->{'minIpd'},
					'meanIpd'	=> $hash->{'meanIpd'},
					'maxIpd'	=> $hash->{'maxIpd'},
					
					# jitter
					'iqrIpd'	=> $hash->{'iqrIpd'},
					'medianRtt'	=> $hash->{'medianRtt'},
					
					# other - set as 0/1?
					'duplicates' => $hash->{'duplicates'},
					'outOfOrder' => $hash->{'outOfOrder'},
					
					#loss
					'lossPercent'	=> $hash->{'lossPercent'},
					'clp'	=> $hash->{'clp'},

					#log
					'rtts'	=> $hash->{'rtts'},
					'seqNums' => $hash->{'seqs'},
					
	);

	# commit the object into the database
	$logger->debug( "inserting new data row");
	$data->save;
	
	# return 0 if okay
	if ( $data ) {
		return 0;
	}
	
	# otherwise return -1
	$self->error( "Could not insert data.");
	return -1;
}


=head2 get_table_for_timestamp( $ )

from the provided timestamp (in epoch seconds), determines the names of the
rose::db object and manager classes required for the data tables used in PingER.
Will automatically include (use) the relevant modules.

the final argument 'createNewTables' defines a boolean for whether tables within
the timetange should be created or not if it does not exist in the database.

If a second argument is provided, will assume that a time range is given and will load
all necessary tables;

Returns
  ( rose data table array of strings, rose data manager array of string )

=cut
sub get_rose_objects_for_timestamp
{
	my $self = shift;
	my $startTime = shift;
	my $endTime = shift;

	my $createNewTables = shift;	

	# call as object
	if( ref($self) 
		&& UNIVERSAL::can( $self, 'isa') 
		&& $self->isa( 'perfSONAR_PS::DB::PingER' ) ) {
			#$logger->debug( 'object call');
	} 
	# call by static method
	else {
		$endTime = $startTime;
		$startTime = $self;
	}

	# determine the datatable to use depending on the timestamp
	$endTime = $startTime 
		if ! defined $endTime;
	
	my @dates = ();
	my %list = ();

	$logger->debug( "Loading data tables for time period $startTime to $endTime");
		
	# go through every day and populate with new months
	for( my $i = $startTime; $i <= $endTime ; $i += 86400 ) {
		my $table = strftime( "data_%Y%m", gmtime( $i ) );
    	$list{strftime("%Y%m", gmtime($i))}++;
    }
	@dates = sort { $a <=> $b } keys %list;
	undef %list;
	
	my @objects = ();
	my @managers = ();
	
	foreach my $table ( @dates ) {
		
		my $table = 'data_' . $table;
		
		# rewrite the class name to use for this rose object
		my $class = $table;
		$class =~ s/\_//g;
		$class =~ s/^d/D/g;
		# define the actual name of the object
		my $object = $basename . '::' . $class;
		my $manager = $object . '::Manager';
		
		push @objects, $object;
		push @managers, $manager;
		
		# inherit the base data table and create it if necessary
		unless ( $object->isa( $basename . '::Data' )
				&& $object->meta->is_initialized 
				&& $manager->isa( 'Rose::DB::Object::Manager')
				) {
	
			$logger->debug( "Dynamic load of '$object' with manager '$manager'" );
			# need to turn off strict to enable dynamic loading
			no strict; # would like more strict use, but 'refs' makes the sub object_class fail
			my $str = "
				package $object;
				use base ($basename . '::Data');
				__PACKAGE__->meta->setup(
	    			table   => $table,
				);
				1;
				
				package $manager;
				use base qw(Rose::DB::Object::Manager);
				sub object_class { '$object' };
				__PACKAGE__->make_manager_methods('$table');
				1;
			";
			eval $str;
			use strict;
			if ( $@ ) {
				$logger->error( "Could not create dynamic Rose::DB objects: $@" );
				return ( undef, undef );
			}

			if ( defined $createNewTables 
					&& $createNewTables ) {
						
				# we need to always try to create the table as it's the only
				# way to determine if the table exists agnostically
				eval {
					my $dataTable = $object->new();
					$logger->debug( "creating new data table $table");
					# create the database table if necessary		
					$dataTable->dbh->do( "CREATE TABLE $table AS SELECT * FROM data" );	
					undef $dataTable;		
				};
				#if ( $@ ) {
				#	$logger->debug( "table $table already exists");
				#}
			}
		}
	}

	return ( \@objects, \@managers );
}


1;

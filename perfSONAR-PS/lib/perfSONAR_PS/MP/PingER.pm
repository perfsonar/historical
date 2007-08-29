#!/usr/bin/perl -w

=head1 NAME

perfSONAR_PS::MP::PingER - A module that performs the tasks of an MP designed for the 
ping measurement under the framework of the PingER project

=head1 DESCRIPTION

The purpose of this module is to create objects that contain all necessary information
to make ping measurements to various hosts. It supports a scheduler of to perform the pings
as defined in the store.xml file (which is locally stored under $self->{'STORE'}).

Internally, two helper packages are part of this module: an Agent class, which performs the tests, 
a Scheduler class which organises the tests to be run, and a Config class which parses the STORE
file.

=head1 SYNOPSIS

    use perfSONAR_PS::MP::PingER;

    my %conf = ();
    
    # definition of where the list of hosts and parameters to ping are located
    $conf{"METADATA_DB_TYPE"} = "file";
    $conf{"METADATA_DB_NAME"} = "";
    $conf{"METADATA_DB_FILE"} = "store.xml";

    # command to run pings; the various variables will be subsituted upon execution
    # with the specific parameters of the test
    $conf{"PING"} = "/bin/ping -n -c %count% -i %interval% -s %packetSize% -t %ttl%  %destination%";

    # port and endpoint for the MP to listen on for on-demand measurements
    $conf{"PORT"} = 8080;
    $conf{"ENDPOINT"} = '/perfSONAR_PS/services/pingMP';
    $conf{"LS_REGISTRATION_INTERVAL"} = 60;
    $conf{"LS_INSTANCE"} = 'http://mead:8080/axis/services/LS';

    # namespace definitions    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      pinger => "http://ggf.org/ns/nmwg/tools/pinger/2.0/"    
    );
    
    # create a new instance of the MP
    my $mp = new perfSONAR_PS::MP::PingER(\%conf, \%ns, "");
    
    # or:
    #
    # $mp = new perfSONAR_PS::MP::PingER;
    # $mp->setConf(\%conf);
    # $mp->setNamespaces(\%ns);
    # $mp->setStore();

    my $mp = new perfSONAR_PS::MP::PingER( \%conf, \%ns,);
    $mp->parseMetadata;
    $mp->prepareMetadata;

    # start scheduler for pings
    $mp->run( );


=cut


use perfSONAR_PS::Common;

use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::DB::MA;
use perfSONAR_PS::Transport;

package perfSONAR_PS::MP::PingER;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MP::General;
use POSIX;
use Data::Dumper;

use perfSONAR_PS::MP::Base;
our @ISA = qw(perfSONAR_PS::MP::Base);


my $logger = get_logger("perfSONAR_PS::MP::PingER");


=head2 new(\%conf, \%ns, $store)

The first argument represents the 'conf' hash from the calling MP.  The second argument
is a hash of namespace values.  The final value is an LibXML DOM object representing
a store.


=head2 conf( \%conf )

Gets/sets the instance of %conf
=cut
sub conf
{
	my $self = shift;
	if ( @_ ) {
		$self->{CONF} = shift;
	}
	return $self->{CONF};
}


=head2 config( \%conf )

Gets/sets the instance of xml file
=cut
sub config
{
	my $self = shift;
	if ( @_ ) {
		$self->{CONFIG} = shift;
	}
	return $self->{CONFIG};
}

=head2 shedule( $scheduler )

Gets/sets the instance of the Scheduler
=cut

sub schedule
{
	my $self = shift;
	if ( @_ ) {
		$self->{SCHEDULE} = shift;
	}
	return $self->{SCHEDULE};
}


=head2 parseMetadata( )

Parses the config file (defined by $conf{'METADATA_DB_TYPE'} and $conf{'METADATA_DB_FILE'}), then
stores it internally as $self->{STORE} (as DOM)

Currently only supports $conf{'METADATA_DB_TYPE'} == 'file'

=cut

sub parseMetadata {
  my($self) = @_;

  if( $self->{CONF}->{'METADATA_DB_TYPE'} eq 'file' ) {   
    $self->{STORE} = parseFile($self);
    cleanMetadata(\%{$self});
  }
  else {
    $logger->error($self->{CONF}->{"METADATA_DB_TYPE"}." is not supported."); 
  }
  return;
}


=head2 prepareMetadata()

Generates the config and schedules to be used for the instance of the MP

=cut
sub prepareMetadata 
{
  my($self) = @_;
  
  # config 
  my $dom = perfSONAR_PS::MP::PingER::Config->new( $self->{STORE} );
  # setup the source details
  $dom->sourceIP( $self->conf()->{LOCAL_IP} );
  $dom->sourceName( $self->conf()->{LOCAL_HOSTNAME} );
  
  $self->config( $dom );
  #$logger->info( "CONFIG: " . $self->config()->dump() );
  
  # schedule 
  my $schedule = perfSONAR_PS::MP::PingER::Schedule->new( $self->config() );
  $self->schedule( $schedule );
  $self->schedule()->initiate();
  #$logger->info( "SCHEDULE: " . Dumper $self->schedule() );	

  return;

}


=head2 run( )

Starts an endless loop scheduling and running tests as defined in $self->{'STORE'} until the
program is terminated.
=cut
my $numChildren = 0;
my %child = ();
my $i = 0;
$SIG{CHLD} = \&REAPER;
	
sub run
{
	my $self = shift;
	
  	$logger->info( "SCHEDULE RUN: " . Dumper $self->schedule() );	
	while( 1 )
	{
    
		my $badExit = 0;

		#$logger->info( "MAX THREADS: "  . $self->conf()->{MAX_THREADS} );
	
		# wait for a signal from a dead child or something
		# if all children are occupised
		if ( $numChildren >= $self->conf()->{MAX_THREADS} ) {
			$logger->debug("at max forks; waiting...");
			sleep;
		}
	
		if (! exists $child{$i} )
		{
			my ( $testTime, $pingId ) = $self->waitForNextTest();
	
			if ( defined $pingId )
			{
				( $testTime, $pingId ) = $self->schedule()->popTest( );
				$self->schedule()->addNextTest( $pingId );
				$self->startTest( $i, $pingId );
			} 
			else {
				$badExit = 1;
			}
		}
	
		if ( ! $badExit ) {
			$i++;
			$i -= $self->conf()->{MAX_THREADS} if( $i >= $self->conf()->{MAX_THREADS} );
		}	    

	}
	return;
}

=head2 waitForNextTest( )

Blocking function that sleeps until the next test. Problem is that ipc can cause the sleep to exit
for any signal. Therefore, some cleverness in determine the actual slept time is required.
=cut
sub waitForNextTest
{
	my $self = shift;

	my ( $time, $pingId ) = $self->schedule()->peekTest();
	my $now = &perfSONAR_PS::MP::PingER::Schedule::getNowTime();
	my $wait = $time - $now;

	# wait some time for a signal
	if ( $wait > 0.0 ) {
		select( undef, undef, undef, $wait );

		# if we are before the next test time, do not do anything!
		if ( $now < $time )
		{
			return ( undef, undef );
		}

	# we are behind schedule
	} else {
		
	}

	return ( $time, $pingId );

}

# takes care of dead children
sub REAPER {                        
    $SIG{CHLD} = \&REAPER;
    my $pid = undef;
    while( ( $pid = waitpid( -1, &WNOHANG) ) > 0 ) 
    {
 		$numChildren--;
		#print "CHILD $pid died ($numChildren)\n\n\n";
		my %map = reverse %child;
   	 	my $child = $map{$pid};
			
		delete $child{$child};
    }
    return;
}


=head2 startTest( $pid, $Test )

Spawns off a forked instance in order to run the object Test that defines the metadataId of the test
to the run at the time this function is called. The forked instance will also deal with the storage
defintions fo the Test. The $pid is required to keep a state of all tests that are currently being
run.
=cut
sub startTest
{
	my $self = shift;
	my $forkedProcessNumber = shift;
	my $pingId = shift;
	
	   # block signal for fork
	    my $sigset = POSIX::SigSet->new(SIGINT);
	    sigprocmask( SIG_BLOCK, $sigset)
	        or die "Can't block SIGINT for fork: $!\n";
	 
	    # fork!
	    die "fork: $!" unless defined ($pid = fork);
	    
	    if ($pid) 
	    {
	        # Parent records the child's birth and returns.
	        sigprocmask(SIG_UNBLOCK, $sigset)
	            or die "Can't unblock SIGINT for fork: $!\n";
	
	        # keep state for the parent to keep count of children etc.
	        $child{$forkedProcessNumber} = $pid;
	        $numChildren++;
	        
	        return;
	        
	    }
	    else 
	    {
	   
	        $SIG{INT} = 'DEFAULT';      # make SIGINT kill us as it did before
			$SIG{USR1} = 'DEFAULT';
			$SIG{USR2} = 'DEFAULT';
		    $SIG{HUP} ='DEFAULT';
			
			# run the test
			my $test = $self->schedule()->getTest( $pingId );
			my $agent = $self->prepareCollector( $test );

			$logger->info( "Staring test using metadataId $pingId...");
			
			if ( $agent->collect() < 0 ) {
				
				# error!
				$logger->fatal( "Could not perform test with metadataId " . $self->schedule()->getTestPingId( $test ) );
				
			} else {

				# get the results out
				$logger->debug( "RESULTS for\n" . Dumper $agent->getResults() );
		
				# write to teh stores
				#my $host = $self->schedule()->getTestHost( $test );
				#my $nodemetadata = $self->config()->getNodeMetadata( $host );
				#$logger->info( Dumper $test );
				$self->prepareData( $pingId );
				$self->storeData( $pingId, $agent );

			}			
			exit;
	    }

}


=head2 prepareData( $metadataId )

Prepares the storage of PingER data to the stores defined in $self->{'STORE'}.
=cut
sub prepareData {
	
  my $self = shift;
  my $pingId = shift;
  
  my $stores = $self->config()->getStores( $pingId );

  foreach my $id ( keys %$stores ) {
  	
	my $type = $stores->{$id}->{type};
  	my $uri = $stores->{$id}->{file};
  	
  	$logger->debug( "Type: $type, $uri: $uri");
  	  	
  	if ( $type eq 'MA') {
  		my ( $host, $port, $endpoint ) = &perfSONAR_PS::Transport::splitURI( $uri );
  		$logger->info("Preparing data storage for Measurement Archive ($uri).");

  		$self->{DATADB}->{$uri} = new perfSONAR_PS::DB::MA( $host, $port, $endpoint );
  		$self->{DATADB}->{$uri}->openDB();
  		#$logger->debug( $self->{DATADB}->{$uri}); 
  	}
  	elsif ( $type eq 'sqlite') {
  		# TODO: need schema
  		$logger->info("Preparing data storage for SQLite ($uri).");
        my @dbSchema = ("id", "time", "value", "eventtype", "misc");  
        $self->{DATADB}->{$uri} = new perfSONAR_PS::DB::SQL(
          "DBI:SQLite:dbname=".$uri, 
          "", 
	        "", 
	        \@dbSchema
        );
  	}  	
  	else {
  		$logger->error("Store of type $type is not supported.");
  	}
  }

  return;
}


=head2 prepareCollector( $Test )

Creates and returns a PingER Agent to run the given $Test
=cut
sub prepareCollector {
  my $self = shift;
  my $test = shift;
  
  # get the command line string
  $logger->info( Dumper $test );
  
  my $cmd = $self->{'CONF'}->{'PING'};
  if ( ! defined $cmd ) {
  	$logger->fatal( "Do not understand Ping Protocol '" . Dumper $test . "'.");
  }

  $logger->info( Dumper $self->{'NAMESPACES'});

  return perfSONAR_PS::MP::PingER::Agent->new( $cmd, $test, $self->{'NAMESPACES'} );

}


=head2 storeData( $metadataId, $Agent )

Stores the results from the Agent instance into the stores as defined with a metaDataRefId of $metadataId
=cut
sub storeData
{
	my $self = shift;
	my $pingId = shift;
	my $agent = shift;

	#foreach store of the node, insert the data
	my $stores = $self->config()->getStores( $pingId );
	#$logger->info( "Storing agent results into \n". Dumper $store );
	
	foreach my $id ( keys %$stores ) {
		my $type = $stores->{$id}->{type};
		my $uri = $stores->{$id}->{file};
		
		next if (! defined $type || $type eq '') || (! defined $uri || $uri eq '' ); 
		
		if( ! exists $self->{DATADB}->{$uri} ){
		
			$logger->fatal( "Store of type '$type' for '$uri' does not exist.")
		 	
		} else {	
			if ( $type eq 'MA' ) {

				my $dom = $agent->getResultsDOM();
				$logger->info( "Inserting data into MA $uri (" . $self->{DATADB}->{$uri}. "):\n" . $dom->toString() );
	
				my $status = $self->{DATADB}->{$uri}->insert( $dom );
				if ( $status == 0 ) {
					# okay
				} elsif ( $status == -1 ) {
					$logger->fatal( "Could not insert into remote MA $uri");
				} else {
					$logger->fatal( "Unknown error in insert into remote MA $uri: " . $self->error() );
				}
				
			} 
			else {
				$logger->error( "Unknown storage type " . $type . ".");
			}
	        $self->{DATADB}->{$uri}->closeDB if exists $self->{DATADB}->{$uri};
		}
	}
	return;
}



=head1 SEE ALSO

L<perfSONAR_PS::MP::Base>, L<perfSONAR_PS::MP::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::SQL>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: PingER.pm 242 2007-06-19 21:22:24Z zurawski $

=head1 AUTHOR

Yee-Ting Li, E<lt>ytl@slac.stanford.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut



# ================ Internal Package perfSONAR_PS::MP::PingER::Config ================

package perfSONAR_PS::MP::PingER::Config;

use Log::Log4perl qw(get_logger);

use Data::Dumper;



sub new {
  my ($package, $dom) = @_; 
  my %hash = ();
  if(defined $dom and $dom ne "") {
    $hash{"STORE"} = $dom;
  }    
  bless \%hash => $package;
}

sub sourceName()
{
	my $self = shift;
	if ( @_ ) {
		$self->{SOURCENAME} = shift;
	}
	return $self->{SOURCENAME};
}

sub sourceIP()
{
	my $self = shift;
	if ( @_ ) {
		$self->{SOURCEIP} = shift;
	}
	return $self->{SOURCEIP};
}


sub dump
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Config");	

	$logger->info( "Config: " . Dumper $self->{STORE});
}


sub parse
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Config");	

	# get the dest host 
	my $xpath = '/nmwg:store/nmwg:metadata';

	# source information filter
	my $srcNode = $self->sourceName();
	my $srcIP = $self->sourceIP();
	if ( defined $srcNode ) {
	 $xpath .= '[child::pinger:subject/nmtl4:endPointPair/nmtl4:endPoint[@role=\'src\'][@protocol=\'icmp\']/nmtl3:interface/nmtl3:ifHostName=\'' . $srcNode . '\']';
	}
	if ( defined $srcIP ) {
	 $xpath .= '[child::pinger:subject/nmtl4:endPointPair/nmtl4:endPoint[@role=\'src\'][@protocol=\'icmp\']/nmtl3:interface/nmtl3:ipAddress=\'' . $srcIP . '\']';
	}

	$logger->debug("Finding: $xpath");

	my $hostElement = $self->{STORE}->findnodes( $xpath );

	# create an xml element of the defaults, then override it with the overwrite settings
	my $host = {};
		
	foreach my $nodes ( $hostElement->get_nodelist ) {

		#$logger->debug( $nodes->toString() );

		# use the id attr as unique pointer to the test
		my $id = $nodes->find( './@id' );
		$host->{'PingER'}->{$id} = {};
		
		foreach my $param ( $nodes->findnodes('./pinger:parameters/nmwg:parameter' )->get_nodelist )
		{
			#$logger->debug( "Found: " . $param->toString() );
			my $name = $param->getAttribute( 'name' );
	        my $val = $param->textContent();
			next if ! $name || $name eq '';
    	    #$logger->debug( "  found $name $val");
        	$host->{'PingER'}->{$id}->{$name} = $val;
		}
		
		# add the host details to the item
		$host->{'PingER'}->{$id}->{'destIP'} = $nodes->findnodes('./pinger:subject/nmtl4:endPointPair/nmtl4:endPoint[@role=\'dst\']/nmtl3:interface/nmtl3:ipAddress')->[0]->textContent();
		$host->{'PingER'}->{$id}->{'destName'} = $nodes->findnodes('./pinger:subject/nmtl4:endPointPair/nmtl4:endPoint[@role=\'dst\']/nmtl3:interface/nmtl3:ifHostName')->[0]->textContent();
		
		$host->{'PingER'}->{$id}->{'srcName'} = $self->sourceName();
		$host->{'PingER'}->{$id}->{'srcIP'} = $self->sourceIP();
		
	}
	
	$logger->debug( Dumper $host );
	
	return $host;

}


sub getStores
{
	my $self = shift;
	my $id = shift;

	my $xpath = '/nmwg:store/nmwg:data[@metadataIdRef=\'' . $id . '\']';
	$logger->debug( "looking for id: $id with '$xpath'");

	my $nodes = $self->{STORE}->findnodes( $xpath );

	my $out = {};
	foreach my $node ( $nodes->get_nodelist ) {
		my $id = $node->getAttribute( 'id');
		#$logger->info( $node->toString() );
		foreach my $n ( $node->findnodes( './nmwg:key/nmwg:parameters/nmwg:parameter' )->get_nodelist ) {
			my $name = $n->getAttribute("name");
			my $value = $n->textContent();
			$out->{$id}->{$name} = $value;
		}
	}
	
	#$logger->info( "out; " . Dumper $out);
		
	return $out;

}



# ================ Internal Package perfSONAR_PS::MP::PingER::Schedule ================

package perfSONAR_PS::MP::PingER::Schedule;

use Log::Log4perl qw(get_logger);
use Time::HiRes qw ( &gettimeofday );
use Data::Dumper;

###
# keep two datastructures of itnerest: METADATA which contains all the tests indexed by the metadataId, and
# SCHEDULE which maintains a hash of epoch time of the test with the metadataId (we do not point to the METADATA
# datastructure directly as we need the id's sometimes.)
###

sub new {
  my ( $package, $config ) = @_; 
  my %hash = ();
  $hash{"CONFIG"} = $config;
  %{$hash{"SCHEDULE"}} = ();
  $hash{"CHILDREN_OCCUPIED"} = 0;
  $hash{"METADATA"} = undef;
  bless \%hash => $package;
}

sub children
{
	my $self = shift;
	if ( @_ ) {
		$self->{"CHILDREN_OCCUPIED"} = shift;
	}
	return $self-{"CHILDREN_OCCUPIED"};
}


sub config
{
	my $self = shift;
	if ( @_ ) {
		$self->{CONFIG} = shift;
	}
	return $self->{CONFIG};
}

sub getNowTime
{
  	my ( $nowTime, $nowMSec ) = &gettimeofday;
	return $nowTime . '.' . $nowMSec;
}


# returns the info about a node
#TODO: ensure namespaec agnositicity in xpaths
sub getTest
{
	my $self = shift;
	my $pingId = shift;
	
	return \%{$self->{"METADATA"}->{PingER}->{$pingId}};
} 

# sets the schedule for tests
sub initiate
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Schedule");

	my %schedule = ();

	$self->{"METADATA"} = $self->config()->parse( );
	my @pingIds = keys %{$self->{"METADATA"}->{'PingER'}} ;
	if ( scalar @pingIds < 1 ) {
		$logger->logdie( "Schedular could not determine any tests to run");
	}
	foreach my $id ( @pingIds ) {
		$logger->debug( "Add PING: $id" );
		$self->addNextTest( $id );
	}

	return;
}


sub popTest
{
	my $self = shift;
	my ( $time, $pingId ) = $self->peekTest();

	if ( defined $time ) {
		# may be an array	
		my $array = $self->{SCHEDULE}->{$time};
		my $test = pop @$array;

		if ( scalar @$array ) {
			$self->{SCHEDULE}->{$time} = $array;
		}
		else {
			delete $self->{SCHEDULE}->{$time};
		}	
		return ( $time, $pingId );
	}
	return ( undef, undef );
}


sub peekTest
{
	my $self = shift;
	
	my @times = sort {$a<=>$b} keys %{$self->{SCHEDULE}};
	if ( scalar @times ) {

		my $start = $times[0];
		my $pingId = $self->{SCHEDULE}->{$start}->[0];
	
		return ( $start, $pingId );

	}
	
	return ( undef, undef );
}

##
# 
##
sub addNextTest
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Schedule");
	my $pingId = shift;

	my $since = shift; # this is so that we add the test at the offset + since (epoch)

    my $now = $since;
	if ( ! defined $now ) {
		$now = &getNowTime();
	}

    my $nextTime = $self->getNextTestTime( $pingId );

    $self->addTest( $nextTime, $pingId );
	
	return;
}

sub addTest
{
	my $self = shift;
	my $time = shift;
	my $pingId = shift;

	# if tehre is already at test at this time, append it
	push @{$self->{SCHEDULE}->{$time}}, $pingId;

	return;	
}


sub getNextTestTime
{
	my $self = shift;
	my $pingId = shift;

	my $test = $self->getTest( $pingId );

	my $period = $test->{testPeriod};
	my $offset = $test->{testOffset};

	my $rand = 0;
	if ( $offset > 0 ) {
		$rand = rand( $offset/2 ) - $offset;
	}

	my $now = &getNowTime();

	return $now + $period + $rand;
}


# ================ Internal Package perfSONAR_PS::MP::Ping::Agent ================

package perfSONAR_PS::MP::PingER::Agent;

use IEPM::PingER::Statistics;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

use perfSONAR_PS::XML::PingER;

use Data::Dumper;



sub new {
  my ($package, $ping, $options, $ns ) = @_; 
  my %hash = ();
  if(defined $ping and $ping ne "") {
    $hash{"PING"} = $ping;
  }
  if(defined $options and $options ne "") {
    $hash{"OPTIONS"} = $options;
  } 
   if(defined $ns and $ns ne "") {
    $hash{"NAMESPACES"} = $ns;
  }
  %{$hash{"RESULTS"}} = ();

  bless \%hash => $package;
}

sub ping
{
	my $self = shift;
	if ( @_ ) {
		$self->{"PING"} = shift;
	}
	return $self->{"PING"};
}

sub options
{
	my $self = shift;
	if ( @_ ) {
		$self->{"OPTIONS"} = shift;
	}
	return $self->{"OPTIONS"};
}


sub namespaces
{
	my $self = shift;
	if ( @_ ) {
		$self->{"NAMESPACES"} = shift;
	}
	return $self->{"NAMESPACES"};
}



sub collect 
{
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::PingER::Agent");
  
  # parse the options into a commandline
  $self->{CMD} = $self->ping();
  while( my ($k,$v) = each %{$self->{"OPTIONS"}} ) {
		$self->{CMD} =~ s/\%$k\%/$v/g;
	}

  my $host = $self->options()->{destIP};
  if ( ! defined $host ) {
 	 $host = $self->options()->{destName};
  }

  $self->{CMD} =~ s/\%destination\%/$host/g;
  
  if(defined $self->{CMD} and $self->{CMD} ne "") {   
  	
    undef $self->{RESULTS};
     
    my($sec, $frac) = Time::HiRes::gettimeofday;
    my $time = eval($sec.".".$frac);
        
    open(CMD, $self->{CMD}." 2>&1 |") or 
    $logger->error("Cannot open \"".$self->{CMD}."\"");
      
    $logger->info( "Running '$self->{CMD}'... ");
    my @results = <CMD>;
    close(CMD);
    
    #/unknown host/
    # with ping we would get at least 3 lines of output; a header line, and two stats lines
    if ( scalar @results < 4 ) {
    	$logger->fatal( "Something went wrong running command '$self->{CMD}': @results");
    	return -1;
    } else {
    	$self->{'RESULTS'} = $self->parse( \@results, $time );
    }
    
  }
  else {
    $logger->error("Missing command string.");     
  }
  return 0;
}


sub parse
{
	my $self = shift;
	my $cmdOutput = shift;
	
    # parse the results into a hash
    my $vars = {};
    
    my $time = shift; # work out start time of time
    
    for( my $x = 1; $x < scalar @$cmdOutput - 4; $x++ ) {
    	$logger->debug( "LINE: " . $cmdOutput->[$x] );
    	my @string = split /:/, $cmdOutput->[$x];
    	my $v = {};
		( $v->{'bytes'} = $string[0] ) =~ s/\s*bytes.*$//;
		foreach my $t ( split /\s+/, $string[1] ) {
		  $logger->debug( "looking at $t");
          if( $t =~ m/(.*)=(\s*\d+\.?\d*)/ ) { 
	        $v->{$1} = $2;
	        $logger->debug( "  found $1 with $2");
          } else {
            $v->{'units'} = $t; 
          }
		}
		
    	push @{$vars->{'bytes'}}, $v->{'bytes'};
    	push @{$vars->{'rtts'}}, $v->{'time'};
    	push @{$vars->{'seqs'}}, $v->{'icmp_seq'};
		push @{$vars->{'ttls'}}, $v->{'ttl'};
        push @{$vars->{'timeValues'}}, $time + eval($v->{'time'}/1000);
      	$time = $time + eval($v->{'time'}/1000);
    
    }
   
    
	# hires result?
    ( $vars->{minRtt}, $vars->{meanRtt}, $vars->{maxRtt}, undef ) = &IEPM::PingER::Statistics::RTT::calculate( $vars->{'rtts'} );
	# ipd
    ( $vars->{minIpd}, $vars->{meanIpd}, $vars->{maxIpd}, undef, $vars->{iprIpd} ) = &IEPM::PingER::Statistics::IPD::calculate( $vars->{'rtts'} );
	
	
	# get rest of results
	# hires results from ping output
	for( my $x = (scalar @$cmdOutput - 2); $x < (scalar @$cmdOutput) ; $x++ ) {
		$logger->debug( "LINE: " . $cmdOutput->[$x]);
 		if ( $cmdOutput->[$x] =~ /^(\d+) packets transmitted, (\d+) received/ ) {
			$vars->{sent} = $1;
			$vars->{recv} = $2;
        } elsif ( $cmdOutput->[$x] =~ /^rtt min\/avg\/max\/mdev \= (\d+\.\d+)\/(\d+\.\d+)\/(\d+\.\d+)\/\d+\.\d+ ms/ ) {
			$vars->{minRtt} = $1;
			$vars->{maxRtt} = $3;
			$vars->{meanRtt} = $2;
 		}
	}
	
    # loss
    $vars->{lossPercent} = &IEPM::PingER::Statistics::Loss::calculate( $vars->{sent}, $vars->{recv} );
    $vars->{clp} = &IEPM::PingER::Statistics::Loss::CLP::calculate( $vars->{sent}, $vars->{recv}, $vars->{'seqs'} );

	# duplicates
	($vars->{outOfOrder}, $vars->{duplicates}) = &IEPM::PingER::Statistics::Other::calculate( $vars->{'seqs'} );

	# remove calculation variables
	delete $vars->{sent};
	delete $vars->{recv};

	#$logger->info( Dumper $vars );

	return $vars;
}


sub getResults {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::PingER::Agent");
  
  if(defined $self->{RESULTS} and $self->{RESULTS} ne "") {   
    return $self->{RESULTS};
  }
  else {
    $logger->error("Cannot return NULL results.");    
  }
  return;
}

###
# returns the results of the ping in nmwg format
###
sub getResultsDOM {
  my $self = shift;
  my $ns = shift;
  my $logger = get_logger("perfSONAR_PS::MP::PingER::Agent");
  
  if(defined $self->{RESULTS} and $self->{RESULTS} ne "") {   

	$logger->debug( "NS: " . Dumper $self->namespaces() );

	my $doc = XML::LibXML::Document->new();
	$doc->createElementNS( $self->namespaces()->{'nmwg'}, 'nmwg' );
	$doc->createElementNS( $self->namespaces()->{'pinger'}, 'pinger' );
	$doc->createElementNS( $self->namespaces()->{'nmtl3'}, 'nmwgt3' );
	$doc->createElementNS( $self->namespaces()->{'nmtl4'}, 'nmwgt4' );

	my $root = $doc->createElement('message');
	$root->setNamespace( $self->namespaces()->{'nmwg'}, 'nmwg' );
	$doc->setDocumentElement($root);

	my $metaId = '#id';
	my $dataId = '#data';

	my $metadata = &perfSONAR_PS::XML::PingER::createMetaData(
		$doc, $self->namespaces(),
		$self->options()->{srcName}, $self->options()->{destName}, $self->options()->{destIP}, $self->options()->{destIP},
		$self->options(),
		$metaId
	    ); 
	$root->appendChild($metadata);

	# data
	my $data = &perfSONAR_PS::XML::PingER::createData( 
		$doc, $self->namespaces(), 
		$self->getResults(),
		$dataId, $metaId
		 );
	$root->appendChild( $data );
	
	#$logger->debug( "done!" );
	return $doc;

  }
  else {
    $logger->error("Cannot return NULL results.");    
  }
  return;
}


1;


__END__

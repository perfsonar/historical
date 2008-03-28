=head1 NAME

perfSONAR_PS::DB::SQL::PingER  - A module that provides  data access for PingER databases 

=head1 DESCRIPTION

This module provides access to the relevant DBI wrapped methods given the relevant
contact points for the database. It also provides some transparency to the numerous
data tables that is used by PingER in order to provide performance.

=head1 SYNOPSIS

  # create a new database object  
  my $db =  perfSONAR_PS::DB::SQL::PingER->new();
  ## 
  #  inititalize db object
  #
  $db->init( {
   
    driver	=> $db_driver,
    database    => $db_name,
    host	=> $host,
    port	=> $port,
    username	=> $username,
    password	=> $password,
    });
  
  # connect to DB
  if(   $db->connect()  == 0 ) {
  
     # everything is OK
  } else {
     $logger->logdie( $db->ERRORMSG );
  }
  #
  #  or redefine  some parameters
  #
  if(   $db->connect(
    {
   
    driver	=> $db_driver,
    database    => $db_name,
    host	=> $host,
    port	=> $port,
    username	=> $username,
    password	=> $password,
    }
  ) == 0 ) {
        #      ......................do something useful with DB ........
  } else {
     $logger->logdie( $db->ERRORMSG );
  }
 
  
  	 
        #
  	# automatically insert   entries into the host table if it does not exist
  	 if($db->soi_host( {ip_name => 'localhost', ip_number => '127.0.0.1' }) < 0) {
	    ### NOT OK
	     $logger->logdie( $db->ERRORMSG );
	 }  
  	if(  $db->soi_host( {ip_name => 'iepm-resp.slac.stanford.edu' } )< 0) {
	    ### NOT OK 
	     $logger->logdie( $db->ERRORMSG );
	 }

	# setup some values for the metadata entry
	my $transport = 'ICMP';
	my $packetSize = '1008';
	my $count = 10;
	my $packetInterval = 1;
	my $ttl = '64';
  	
  	# get the metaID  for the metadata, again, this will automatically
  	# insert the entry into the database if it does not exist  
	 
  	
	my $metaID  = $db->soi_metadata(  { ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl });
  	
        #
	#
	
	#  one can  also query for ip_number_src and ip_number_dst - in this case it will query host table
	#  it returns hashref keyd by metaIDs ( see DBI docs about selectall_hashref )
	
	my $metaIDs  = $db->getMetaID(  [ ip_name_src => { like =>  '%fnal.gov'}, 
	                              ip_number_dst => '127.0.0.1']);
	# 
	#  or just ip_number_dst
	# then query is:  
	 
	my $metaIDs = $db->getMetaID(   [  ip_number_dst => '134.79.240.30']);
	#
	 
	# there is  method insertTable to provide just insert functionality and updateTable for updating one
	
	 if( $db->insertTable(  { ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl }, 'metaData') < 0) {
	   ### NOT OK
	   $logger->error( $db->ERRORMSG );			   
	}
  	
	 
	
	if( $db->updateTable(  {  ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl }, 'metaData', [metaID => '3345' ]) < 0 ) {
	
	     $logger->error( $db->ERRORMSG );
	   
	}
  	
	 } 
	
	
  	# say we have the data we want to insert  
  	my $hash = {             table => 'data_200803',
	                        'metaID' =>      '3402',
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
  	
  	# now,  insert some data into database
  	my $data = $db->insertTable(   $hash, 'data_200803' );
	
	# or update some Data
	my $data = $db->updatTable(   $hash  , 'data_200803' , [metaID =>  '3402', 'timestamp' => '1000000000']  );
	
	#
	#
	#  there are 2 helper methods for data insertion and update
	#   they designed for the case when data table name should be found by the timestamp in the $hash or where clause part
	#
	
	# now,  insert some data into database
  	my $data = $db->insertData(   $hash );
	
	# or update some Data, the second argument is where clause
	my $data = $db->updateData(   $hash  ,  [metaID =>  '3402', 'timestamp' => '1000000000']  );
	
	
	
	#
	## also if table name is missed then it will  find it by timestamp
  	my $tablename = $db->get_table_for_timestamp({startime => $timestamp});
	#####
	#
	#   query for  data, will return hashref keyd by metaID - timestamp pair
	# 
	#  for example $data_ref->{30034}->{10222223323}->{meanRtt} will give you the meanRtt value for metaID=3--34 and timestamp=10222223323
	#
	my $data_ref = $db->getData( [ metaID => '30034', timestamp => { gt => '1000000'}, timestamp => {lt => '999999999'}] );
	
  } else 
  	print "Something went wrong with the database init.";
  }


=head1 METHODS
  
=cut



package perfSONAR_PS::DB::SQL::PingER;
use warnings;
use strict; 
use version; our $VERSION = 0.08; 
use English '-no_match_vars';
use Scalar::Util qw(blessed);
use Log::Log4perl qw( get_logger ); 
 
use POSIX qw( strftime );
use perfSONAR_PS::DB::SQL::Base;
use base qw(perfSONAR_PS::DB::SQL::Base);
 
use constant  CLASSPATH  => 'perfSONAR_PS::DB::SQL::PingER'; 
use constant  METADATA => {
                 'metaID'     =>   1,
                 'ip_name_src' =>  2,
	         'ip_name_dst' =>  3,
	  	 'transport'	  => 4,
	         'packetSize'  =>  5,
	         'count'		  =>  6,
	         'packetInterval' => 7,
	         'ttl'		  => 8,
};
use constant  HOST => {
                 'ip_name' =>  1,
	         'ip_number' =>  2,
	  	 'comments'	  => 3,
	          
};
use constant  DATA => { 
                 'metaID'     =>   1,
                 'minRtt'      =>  2,
                 'meanRtt'     =>  3,     
                 'medianRtt'     => 4,    
                 'maxRtt'     =>     5,   
                 'timestamp'     =>  6,   
                 'minIpd'     =>     7,   
                 'meanIpd'     =>    8,  
                 'maxIpd'     =>     9,  
                 'duplicates'     =>  10,  
                 'outOfOrder'     =>   11, 
                 'clp'     =>   	12,     
                 'iqrIpd'     =>    13,   
                 'lossPercent'     =>  14, 
                 'rtts'     =>   	15,    
                 'seqNums'     =>    16,
}; 
 
 
 

=head2 soi_host( $param )

'select or insert host': wrapper method to look for the table host for the row with 
   $param = { ip_name => '',    ip_number  => ''}

returns 

     
   -1 = somethign went wrong 
   everything else is good ( could be 0 or ip_name )



=cut


sub soi_host {
	my ($self, $param) = @_;
	unless( $param &&  ref($param) eq  'HASH'  &&  $self->validateQuery($param, HOST, { ip_name => 1, ip_number => 2}) ==0)  {
	    $self->ERRORMSG("soi_host  requires single HASH ref parameter with ip_name and ip_number set");
	    return -1;
	} 
	my $query = $self->getFromTable({query=>  [ 'ip_name' => { 'eq' =>  $param->{ip_name} },
					             'ip_number' => { 'eq' =>  $param->{ip_number} }], 
					 table => 'host', 
					 validate => HOST, 
					 index => 'ip_name',
					 limit => 1
					});
	return $query if(!ref($query) && $query < 0);
	# insert if not there
	my $n = scalar (keys %{$query});
	if ( $n == 0  ) {
	    return $self->insertTable({ insert => { 'ip_name' =>  $param->{ip_name}, 'ip_number' =>  $param->{ip_number}},
	                                 table => 'host'
				      });
	} elsif ( $n == 1 ) {
	    $self->LOGGER->debug( "found host ". $param->{ip_name} . "/ " .  $param->{ip_number} );
	    return   (keys  %{$query})[0] ;
	} else {
	    $self->ERRORMSG( "Found more than one element!");
	    return -1;
	}	
}

 

=head2  soi_metadata

wrapper method to retrieve the relevant   metadata entry given  the parameters hashref
 
        'ip_name_src' => 
         'ip_name_dst' =>
	 'ip_number_src' =>    ##  this one will be converted into name by quering host table
	  'ip_number_dst' =>   ## this one will be converted into name by quering host table
	  
	'transport' = # ICMP, TCP, UDP
	'packetSize' = # packet size of pings in bytes
	'count' 	= # number of packets sent
	'packetInterval' = # inter packet time in seconds
	'ttl' 		= # time to live of packets
	
}

returns 

    0 = if everything is okay
   -1 = somethign went wrong 


=cut

sub soi_metadata {
	my ($self,  $param) = @_;
	unless (   $param  && ref($param) eq 'HASH' && $self->validateQuery($param, METADATA) == 0)  {
	    $self->ERRORMSG("soi_metadata requires single HASH ref parameter");
	    return -1;
	} 
	foreach my $name  (qw/ip_name_src ip_name_dst/) {
	   ( my $what_num = $name ) =~ s/name/number/;
	   unless (defined $param->{$name}) {
	       if($param->{$what_num}) {
	          my $host =   $self->getFromTable({ query=>  [ $what_num  => { 'eq' =>  $param->{$what_num} }], 
		                                     table => 'host',
						     validate =>  HOST, 
						     index => 'ip_name',
					             limit => 1
						  });
		  if($host && ref($host) eq 'HASH') {
		      my ($ip_name, $ip_num) =   each (%$host);
		      $param->{$name} = $ip_name;
		  }  
	      }      
	    }  
	    unless(defined $param->{$name}) {
	        $self->ERRORMSG("soi_metadata requires $name or $what_num set and  ");
	       return -1;
	    }
	}  
        my $query = $self->getFromTable({ query =>  ['ip_name_src'    => { 'eq' => $param->{ip_name_src}  },
					             'ip_name_dst'    => { 'eq' =>  $param->{ip_name_dst} },
					             'transport'      => { 'eq' => $param->{'transport'} },
					             'packetSize'     => { 'eq' => $param->{'packetSize'} },
					             'count'	      => { 'eq' => $param->{'count'} },
					             'packetInterval' => { 'eq' => $param->{'packetInterval'} },
					             'ttl'	      => { 'eq' => $param->{'ttl'} },
				                    ],
				          table  => 'metaData',
					  validate => METADATA, 
					  index => 'metaID',
					  limit => 1
					});
	 
	my $n =  scalar (keys %{$query});
	if ( $n == 0 ) {
	       return $self->insertTable({ insert => $param, table => 'metaData'});   
					  
	} else {
	     $self->LOGGER->debug( "found host ". $param->{ip_name_src} . "/ " .  $param->{ip_name_dst} . " metaID=". (keys  %{$query})[0] ); 
	     return  (keys  %{$query})[0] ;
	}  
}

 

=head2 getMetaID
 
  helper method to get sorted list of metaID for some query
  arguments: query , limit on results
  
=cut


sub  getMetaID {
     my ($self, $param, $limit) = @_;  
     my $results = $self->getFromTable({ query =>  $param, 
                                        table => 'metaData', 
				  	index => 'metaID',
					limit => $limit,
				      });
    return  sort {$a <=> $b} keys %$results if ($results && ref($results) eq 'HASH') ;
    return $results; 
}

=head2 getMeta
 
  helper method to get hashref keyd by metaID with metadata
  accepts query  and limit arg
 

=cut


sub  getMeta  {
     my ($self, $param, $limit) = @_;    
     my $results = $self->getFromTable({ query =>  $param, 
                                        table => 'metaData', 
					validate => METADATA,
				  	index => 'metaID',
					limit => $limit,
				      });  
    return $results; 
}

=head2 getData
 
  helper method to get data for some query
  arguments: query , tablename ( if missed then it wil lbe defined from timestamp), limit on results

=cut


sub  getData {
     my ($self, $param, $table, $limit) = @_;
    
    unless( $param || $table)  {
    	 $self->ERRORMSG(" getData   requires  query parameter or tablename ");
    	 return -1;
    } 
    unless($table) {
	my $stime = undef;
	my $etime = undef;
	my $param_sz = scalar @{$param};
	for(my $i=0;$i<$param_sz;$i+=2) {
	   if ($param->[$i] eq 'timestamp') {
              if(! ref($param->[$i+1]) || $param->[$i+1]->{eq}) {
		$stime = $param->[$i+1];
		$etime = undef;
		last;
	      }  elsif($param->[$i+1]->{gt}) {
		 $stime = $param->[$i+1]->{gt}+1;
	      }  elsif( $param->[$i+1]->{ge}) {
		 $stime = $param->[$i+1]->{ge};
	      } elsif($param->[$i+1]->{lt}) {
		 $etime = $param->[$i+1]->{lt}-1;
	      } elsif($param->[$i+1]->{le}) {
		$etime = $param->[$i+1]->{le};
	      }
	   }   
	} 
	my $table_arref  =  $self->get_table_for_timestamp( { startTime =>  $stime , endTime => $etime}); 
	return -1 unless $table_arref && ref($table_arref) eq 'ARRAY' && scalar @{$table_arref};
	$table  = $table_arref->[0]->[0];
    }
  
    my $results = $self->getFromTable({ query =>  $param, 
                                        table =>  $table, 
					validate =>  DATA, 
					index =>  [qw(metaID timestamp)],
					limit =>  $limit,
				     });
    return $results; 
} 

=head2 insertData (   $hashref );

inserts info from the required hashref paremater  into the database   data table, where 
$hash = {
         metaID => 'metaid',
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

sub insertData {
	my ($self , $hash) = @_;
	unless (  $hash && ref($hash ) eq 'HASH' && $self->validateQuery($hash,  DATA, {metaID => 1, timestamp => 2}) ==0)  {
	    $self->ERRORMSG("insertData   requires single HASH ref parameter  with proper keys " . $self->ERRORMSG);
	    return -1;
	} 	
	 $hash->{'timestamp'} = $self->fixTimestamp( $hash->{'timestamp'} );  
	return -1 unless    $hash->{'timestamp'}  ;  
	 
	# get the data table  and create them if necessary (1)
	my    $table  =  $self->get_table_for_timestamp( { startTime => $hash->{'timestamp'} , createNewTables =>   1 });
        return -1 unless $table && ref($table) eq 'ARRAY' && scalar @{$table};
	# handle mysql problems with booleans
	$hash->{'duplicates'} = $self->booleanToInt($hash->{'duplicates'}); 
	$hash->{'outOfOrder'} = $self->booleanToInt($hash->{'outOfOrder'}); 
	return $self->insertTable({ insert => $hash, table => $table->[0]->[0] });
							 
}

=head2 updateData (   $hashref, $where_clause );

inserts info from the required hashref parameter  into the database   data table, where 
$hash = {
         metaID => 'metaid',
	 
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

and $where_clause is query  formatted  as Rose::DB::Object query

Returns
   0 = everything okay
  -1 = somethign went wrong
	
}

=cut

sub updateData {
	my ($self,  $hash, $where) = @_;
	if ( ! $hash  || ref($hash ) ne 'HASH' || $self->validateQuery($hash,  DATA) < 0)  {
	    $self->ERRORMSG("updateData   requires single HASH ref parameter");
	    return -1;
	} 	
	 
	# remap the timestamp if it's not valid
	my $timestamp = $self->fixTimestamp( $where->{'timestamp'}?$where->{'timestamp'}:$hash->{'timestamp'}?$hash->{'timestamp'}:'');  
	return -1 unless   $timestamp;
	
	# get the data table  and create them if necessary (1)
	my  $table  =  $self->get_table_for_timestamp( { startTime => $timestamp });
        return -1 unless $table && ref($table) eq 'ARRAY' && scalar @{$table};
	# handle mysql problems with booleans
	$hash->{'duplicates'} = $self->booleanToInt($hash->{'duplicates'}); 
	$hash->{'outOfOrder'} = $self->booleanToInt($hash->{'outOfOrder'}); 
	return $self->updateTable({ set => $hash, 
	                            table => $table->[0]->[0], 
				    where => $where
				 });							 
}

 

=head2 get_table_for_timestamp 

from the provided timestamps (in epoch seconds), determines the names of the  data tables used in PingER.
arg: $param - hashref to keys parameters:
 startTime,  endTime, createNewTables
 
the   argument createNewTables defines a boolean for whether tables within
the timetange should be created or not if it does not exist in the database.
if  createNewTables is not set and table does not exist then it wont be returned in the list of tables


If   endTime  is provided, will assume that a time range is given and will load
all necessary tables;

Returns
   array ref of array refs to tablename => date_formatted
  or -1 if something failed
=cut


sub get_table_for_timestamp {
	my ( $self, $param ) = @_;
	$param = $self unless(blessed $self);
	if ( ! $param  || ref($param ) ne  'HASH' || ! $param->{startTime} )  {
	    $self->ERRORMSG("get_table_for_timestamp   requires single HASH ref parameter with at least defined startTime");
	    return -1;
	} 
	my $startTime =  $param->{startTime};
	my $endTime =  $param->{endTime};
	my $createNewTables = $param->{createNewTables};	

	# call as object
	
	# determine the datatable to use depending on the timestamp
	$endTime = $startTime  if ! defined $endTime;
	my %list = ();

	$self->LOGGER->debug( "Loading data tables for time period $startTime to $endTime");
		
	# go through every day and populate with new months
	for( my $i = $startTime; $i <= $endTime ; $i += 86400 ) {
	    my $date_fmt = strftime("%Y%m", gmtime($i));
	    my $table =  "data_$date_fmt";
    	    $list{$date_fmt} = $table ;
        }
	my @tables = (); 
	foreach my $date_fmt ( sort { $a <=> $b } keys %list ) {
	     if($self->tableExists(  $list{$date_fmt}) ) {
	          push @tables,  [$list{$date_fmt}  => $date_fmt];
	     } elsif ( defined $createNewTables) {
	          if($self->createTable($list{$date_fmt}, 'data')==0) {
		      push @tables,   [$list{$date_fmt}   => $date_fmt];
		  }
		  return -1 if    $self->ERRORMSG; 
	     }  
	}
        unless(scalar @tables) {
	    $self->ERRORMSG(" No tables found  ");
	    return -1; 
	}     
	return  \@tables;
}

 


1;

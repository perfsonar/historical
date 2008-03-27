=head1 NAME

perfSONAR_PS::DB::PingER_suctom -A module that provides base Rose::DB implementation of 
data access for PingER databases 

=head1 DESCRIPTION

This module provides access to the relevant DBI wrapped methods given the relevant
contact points for the database. It also provides some transparency to the numerous
data tables that is used by PingER in order to provide performance.

=head1 SYNOPSIS

  # create a new database object  
  my $db =  perfSONAR_PS::DB::PingER_custom->new();
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
     $logger->logdie(" Failed to connect " );
  }
 
  
  	 
        #
  	# automatically insert the entries into the host table if it does not exist
  	 if($db->soi_host( {ip_name => 'localhost', ip_number => '127.0.0.1' }) == 0) {
	    ### OK
	 }
  	if(  $db->soi_host( {ip_name => 'iepm-resp.slac.stanford.edu' } ) == 0) {
	    ### OK
	 }

	# setup some values for the metadata entry
	my $transport = 'ICMP';
	my $packetSize = '1008';
	my $count = 10;
	my $packetInterval = 1;
	my $ttl = '64';
  	
  	# get the metaID  for the metadata, again, this will automatically
  	# insert the entry into the database if it does not exist  
	 
  	
	my $metaIDs = $db->soi_metadata(  { ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl });
  	
        #
	#
	
	#  it will also query for ip_number_src and ip_number_dst - in this case it will query host table
	#
	
	my $metaIDs = $db->getMetaID(  [ ip_name_src => { like =>  '%fnal.gov'}, 
	                              ip_number_dst => '127.0.0.1']);
	# 
	#  or just ip_number_dst
	# then query is:  
	 
	my $metaIDs = $db->getMetaID(   [  ip_number_dst => '134.79.240.30']);
	#
	 
	# there is  method insertTable to provide just insert functionality and updateTable for updating one
	
	 if( $db->insertTable(  { ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl }, 'metaData') == 0) {
	   ### OK
				   
	}
  	
	 
	
	if( $db->updateTable(  {  ip_name_src => $src, ip_name_dst => $dst, 
	                           transport => $transport,  packetSize => $packetSize, 
				   count => $count, packetINterval => $packetInterval, ttl => $ttl }, 'metaData', [metaID => '3345' ]) == 0 ) {
	
	   # .... everything is OK			   
	} else {
	     $logger->error(" Update failed, see error log ");
	}
  	
	
	unless($metaId) {
	  $logger->error(" Insert failed, probably duplicated primary key ");
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
  	my $data = $db->insert_data(   $hash );
	
	# or update some Data
	my $data = $db->updatData(   $hash  ,  [metaID =>  '3402', 'timestamp' => '1000000000']  );
	
	
	
	#
	## also if table name is missed then it will  find it by timestamp
  	my $tablename = $db->get_table_for_timestamp({startime => $timestamp});
	#####
	#
	#   query for  data, will return array ref to the list of rows as hash_refs 
	#
	my $data_ref = $db->getData({table => $tablename->[0], query => $query});
	
  } else 
  	print "Something went wrong with the database init.";
  }


=head1 METHODS
  
=cut



package perfSONAR_PS::DB::PingER_custom;
use warnings;
use strict; 
use DBI;
use version; our $VERSION = 0.08; 
use English '-no_match_vars';
use Scalar::Util qw(blessed);
use Log::Log4perl qw( get_logger ); 
 
use POSIX qw( strftime );
use perfSONAR_PS::DB::QueryBuilder qw(build_select);

use constant  CLASSPATH  => 'perfSONAR_PS::DB::PingER_custom';
use constant  PARAMS =>  qw(driver database handle ERRORMSG LOGGER host port username password attributes);
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
                 'iqrIpd '     =>    13,   
                 'lossPercent'     =>  14, 
                 'rtts'     =>   	15,    
                 'seqNums'     =>    16,
};
use fields  (PARAMS);

=head2  new

    constructor accepts hashref as parameter
    returns object

=cut 

sub new { 
    my $that = shift;
    my $param = shift;
    my $logger  = get_logger( CLASSPATH ); 
    my $class = ref($that) || $that;
    my $self =  fields::new($class );
    ## injecting accessor/mutator for each field
    foreach my $key  (PARAMS)  { 
       *{"$key"} = sub {  my $obj = shift; my $a = shift;
                          if($a) {
			     $obj->{"$key"} = $a;
			  }  
			  return $obj->{"$key"}}; 
    }  
        
    $self->LOGGER($logger);
    $self->attributes(  {RaiseError => 1} ); 
    if( $self->init($param) == -1 ) {
       $self->LOGGER()->error($self->ERRORMSG); 
       return;
    }
    return   $self;
}


sub DESTROY {
    my $self = shift;
     $self->closeDB;
    $self->SUPER::DESTROY  if $self->can("SUPER::DESTROY");
    return;
}
 
=head2 init 

   accepts hashref as single parameter and initializes object
  returns  
 
    0 = if everything is okay
   -1 = somethign went wrong 

=cut


sub init {
  my ($self, $param) = @_;
  if($param) {
      if(ref($param) ne 'HASH')   {
            $self->ERRORMSG("ONLY hash ref accepted as param " . $param );         
            return -1;
      } 
   
      $self->{LOGGER}->debug("Parsing parameters: " . (join " : ", keys %{$param}));    
      foreach my $key (PARAMS) {
            $self->{$key} = $param->{$key} if exists  $param->{$key}; ###  
      } 
      return 0;
   } else {
      $self->ERRORMSG(" Undefined parameter "); 
      return -1;
   }
   
}

=head2 connect

opens a connection to the database or reuses the cached one

Returns 
     0 = if everything is okay
   -1 = somethign went wrong
  
=cut

sub  openDB {
    my $self = shift;   
    my $param = shift;
    if($param && $self->init($param) == -1 ) {
         return -1;
    } 
    eval {
        $self->handle(DBI->connect_cached("DBI:" .  $self->driver . ":database=" .  $self->database  . 
	                      ($self->host?";host=" . $self->host:'') .
			      ($self->port?";port=" . $self->port:'') , $self->username, $self->password, $self->attributes)) 
			      or  die $DBI::errstr; 
    };
    if ($EVAL_ERROR) {
        $self->ERRORMSG("Connect DB error \"" . $EVAL_ERROR . "\"." );
        return -1;
    }
    return 0;
}

=head2 closeDB

closes the connection to the database
Returns 
     0 = if everything is okay
   -1 = somethign went wrong
   
=cut

sub closeDB {
    my $self = shift;
    # close database connection
    # destroy objects classes in memory
    eval {
        $self->handle->disconnect if $self->handle && ref($self->handle) =~ /DBI/;
    };
    if ($EVAL_ERROR) {
        $self->ERRORMSG("Close DB error \"" . $EVAL_ERROR . "\"." );
        return -1;
    }
    return 0;	    
}

=head2 alive

   checks if db handle is alive
   Returns 
     0 = if everything is okay
   -1 = somethign went wrong

=cut

sub alive {
    my $self = shift;
    # close database connection
    # destroy objects classes in memory
    my $ping = -1;
    eval {
    	$ping = 0 if($self->handle && ref($self->handle) =~ /DBI/ && $self->handle->ping);
    };
    if ($EVAL_ERROR) {
        $self->ERRORMSG("Ping  DB error \"" . $EVAL_ERROR . "\"." );
        return -1;
    }
    return $ping;	    
}


=head2 soi_host( $param )

'select or insert host': wrapper method to look for the table host for the row with 
   $param = { ip_name => '',    ip_number  => ''}

returns 

    0 = if everything is okay
   -1 = somethign went wrong 




=cut


sub soi_host {
	my ($self, $param) = @_;
	if ( ! $param || ref($param) ne 'HASH' || $self->validateQuery($param, HOST, { ip_name => 1, ip_number => 2}) < 0)  {
	    $self->ERRORMSG("soi_host  requires single HASH ref parameter with ip_name and ip_number set");
	    return -1;
	} 
	my $query = $self->_getFromTable(  [ 'ip_name' => { 'eq' =>  $param->{ip_name} },
					   'ip_number' => { 'eq' =>  $param->{ip_number} }], 'host', HOST, 'ip_name' );
	return $query if(!ref($query) && $query < 0);
	# insert if not there
	my $n = scalar (keys %{$query});
	if ( $n == 0  ) {
	    return $self->insertTable({ 'ip_name' =>  $param->{ip_name}, 'ip_number' =>  $param->{ip_number}}, 'host');
	} elsif ( $n == 1 ) {
	    $self->LOGGER->debug( "found host ". $param->{ip_name} . "/ " .  $param->{ip_number} );
	    return   (keys  %{$query})[0] ;
	} else {
	    $self->ERRORMSG( "Found more than one element!");
	    return -1;
	}	
}

=head2  _getFromTable

      accepts Rose::DB::Object::QueryBuilder type of query, table name and table validation HASHref constant
      last optional parameter is $index = name of the indexing key
      returns result as hashref keyd by $index
      or undef and set ERRORMSG 

=cut


sub _getFromTable {
     my ($self, $query, $table, $validation, $index) = @_;    
     my $results = -1;
     my @array_of_names = keys %{$validation};
     my  $stringified_names  = join ", ",  @array_of_names;
      
     eval {
         my $sql_query =  build_select({ dbh => $self->handle, 
	                                 select =>   $stringified_names,
                                         tables => [$table], 
				         query => $query, 
					 query_is_sql => 1, 
				         columns => { $table  => \@array_of_names},
				      });
	 $self->openDB  if !($self->alive == 0);	      
	 $results = $self->handle->selectall_hashref($sql_query, $index);
     };
     if ($EVAL_ERROR) {
        $self->ERRORMSG("_getFromTable  failed with error \"" . $EVAL_ERROR . "\"." );
     } 
     return $results;
}

=head2   updateTable

      accepts hashref {  'ip_name' => $ip_name, 'ip_number' => $ip_number }, table_name, where query ( formatted as Rose::DB::Object query )
      returns  
      
    0  if OK
   -1 = somethign went wrong 


=cut


sub updateTable{
     my ($self, $params,  $table, $where) = @_;
     my $stringified_names  = ''; 
     my @array_of_names = keys %{$params};
     foreach my $key (@array_of_names ) {
         $stringified_names  .=  " $key='" . $params->{$key} ."'," if defined $params->{$key};
     } 
      my $query_sql = build_where_clause({ dbh => $self->handle, 
	                                 tables => [$table], 
				         query =>  $where, 
					 query_is_sql => 1, 
				         columns => { $table  => \@array_of_names},
				      });
 
     chop $stringified_names if $stringified_names;
    
     eval {
           $self->openDB  if !($self->alive == 0);
           $self->handle->do("update  $table set  $stringified_names  $query_sql "); 
	  
      };
      if ($EVAL_ERROR) {
          $self->ERRORMSG("updateTable failed with error \"" . $EVAL_ERROR . "\"." );
	  return -1;
      } 
      return   0;
}

=head2   insertTable

      accepts hashref {  'ip_name' => $ip_name, 'ip_number' => $ip_number }, table_name 
      returns  
      
    0  or last inserted id number 
   -1 = somethign went wrong 


=cut


sub insertTable{
    my ($self, $params,  $table) = @_;
    my $stringified_names  = ''; 
    my $stringified_values  = ''; 
    my $rv = 0;
    foreach my $key (keys %{$params}) {
        if(defined $params->{$key}) {
	      $stringified_names   .=  "'$key',";
	      $stringified_values  .=  "'".$params->{$key}."',";
	}
    } 
    if($stringified_names &&  $stringified_values) {
         chop $stringified_names;
         chop $stringified_values; 
         eval {
            $self->openDB  if !($self->alive == 0);
            $self->handle->do("insert into $table  ($stringified_names) values ($stringified_values)"); 
	    $rv =  ($self->driver =~ /mysql/i)? $self->handle->{q{mysql_insertid}}:$self->handle->last_insert_id(undef, undef, $table, undef);
        };
        if ($EVAL_ERROR) {
            $self->ERRORMSG("insertTable failed with error \"" . $EVAL_ERROR . "\"." );
	    return -1;
        }
    } else {
        $self->ERRORMSG("insertTable failed  because of empty list of parameters" );
	return -1;
    }
    return   $rv;
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
	my $self = shift;
	my $param = shift;
	if ( ! $param || ref($param) ne 'HASH' || $self->validateQuery($param, METADATA) < 0)  {
	    $self->ERRORMSG("soi_metadata requires single HASH ref parameter");
	    return -1;
	} 
	foreach my $name  (qw/ip_name_src ip_name_dst/) {
	   ( my $what_num = $name ) =~ s/name/number/;
	   unless (defined $param->{$name}) {
	       if($param->{$what_num}) {
	          my $host =   $self->_getFromTable( [  $what_num  => { 'eq' =>  $param->{$what_num} }], 'host', HOST, 'ip_name' );
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
        my $query = $self->_getFromTable(   [ 	'ip_name_src' => { 'eq' => $param->{ip_name_src}  },
					'ip_name_dst' => { 'eq' =>  $param->{ip_name_dst} },
					'transport'	  => { 'eq' => $param->{'transport'} },
					'packetSize'  => { 'eq' => $param->{'packetSize'} },
					'count'		  => { 'eq' => $param->{'count'} },
					'packetInterval' => { 'eq' => $param->{'packetInterval'} },
					'ttl'		  => { 'eq' => $param->{'ttl'} },
				 ] , 'metaData', METADATA, 'metaID');
	 
	my $n = scalar @$query;
	if ( $n == 0 ) {
	       return $self->insertTable($param, 'metaData');   
					  
	} elsif ( $n == 1 ) {
	     $self->LOGGER->debug( "found host ". $param->{ip_name_src} . "/ " .  $param->{ip_name_dst} . " metaID=". (keys  %{$query})[0] ); 
	     return  (keys  %{$query})[0] ;
	} else {
	    $self->ERRORMSG( "Found more than one element!");
	    return -1; 
	}
}

=head2 validateQuery

   vlaidated supplied query parameters against defined  fields for particular table
   optional arg $required is a hash of the required  table fields
   returns 
         
    0 = if everything is okay
   -1 = somethign went wrong 


=cut

sub validateQuery {
   my ($self, $params, $valid_const, $required) = @_;
   foreach my $key (keys %{$params}) {
       return -1 unless defined  $valid_const->{$key};
       delete $required->{$key}  if $required->{$key} &&  defined $params->{$key};
       
   }
   return -1 if $required && scalar $required;
   return 0;
}

=head2 getMetaID
 
  helper method to get list of metaID for some query

=cut


sub  getMetaID {
     my ($self, $param) = @_;
    
     if ( ! $param || ref($param) ne 'ARRAY'  )  {
    	 $self->ERRORMSG("soi_host  requires single ARRAY ref parameter  ");
    	 return -1;
    } 
    my $results = $self->_getFromTable(  $param  , 'metaData', METADATA,  'metaID');
  
    return  sort {$a <=> $b} keys %$results if ($results && ref($results) eq 'HASH') ;
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
	my $self = shift;
        my $hash = shift;
	if ( ! $hash  || ref($hash ) ne 'HASH' || $self->validateQuery($hash,  DATA, {timestamp => '1', metaID => '2'}) < 0)  {
	    $self->ERRORMSG("insert_data   requires single HASH ref parameter");
	    return -1;
	} 	
	 $hash->{'timestamp'} = $self->_fixTimestamp( $hash->{'timestamp'} );  
	return -1 unless    $hash->{'timestamp'}  ;  
	 
	# get the data table  and create them if necessary (1)
	my ( $table) =  $self->get_table_for_timestamp(   $hash->{'timestamp'} , undef, 1 );
        return -1 if  $table<0;
	# handle mysql problems with booleans
	$hash->{'duplicates'} = _booleanToInt($hash->{'duplicates'}); 
	$hash->{'outOfOrder'} = _booleanToInt($hash->{'outOfOrder'}); 
	return $self->insertTable( $hash, $table);
							 
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
	my $timestamp = $self->_fixTimestamp( $where->{'timestamp'}?$where->{'timestamp'}:$hash->{'timestamp'}?$hash->{'timestamp'}:'');  
	return -1 unless   $timestamp;
	
	# get the data table  and create them if necessary (1)
	my ( $table) =  $self->get_table_for_timestamp(  $timestamp , undef, 0 );
        return -1 if  $table<0;
	# handle mysql problems with booleans
	$hash->{'duplicates'} = _booleanToInt($hash->{'duplicates'}); 
	$hash->{'outOfOrder'} = _booleanToInt($hash->{'outOfOrder'}); 
	return $self->updateTable($hash, $table, $where);							 
}

#
#  fix timestamp
#

sub _fixTimestamp {
    my ($self, $timestamp) = @_;
# remap the timestamp if it's not valid
    if ($timestamp &&  $timestamp  !~ m/^(\d+)$/  &&  $timestamp =~ m/^(\d+)\./ ) {
        return  sprintf "%.0f",  $timestamp;
    } else {
        $self->ERRORMSG( "Timestamp $timestamp format unparseable");
        return;
    }
    return $timestamp;
}


###
#
#    converts any boolean to 0/1 unt
#

sub _booleanToInt {
    my ($self, $param) = @_;
    if ( defined $param) {
        if ( $param  eq 'false'  || !$param) {
	   return 0;
	 } else {
	   return 1;
	 }
    }
    return;
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
	          eval {
	  	     	   $self->LOGGER->debug( "creating new data table  $list{$date_fmt}");
	  	     	   # create the database table if necessary 
			   $self->openDB  if !($self->alive == 0);			   
	  	     	   $self->handle->do( "CREATE TABLE   $list{$date_fmt} AS SELECT * FROM data" );	   
	  	  };
	  	  if ( $EVAL_ERROR ) {
	  	 	 $self->ERRORMSG(" Failed to create    $list{$date_fmt}  ");
		 	 return -1; 
	         }
		 push @tables,   [$list{$date_fmt}   => $date_fmt];
	  	 
	      }  
	 
	}
        unless(scalar @tables) {
	    $self->ERRORMSG(" No tables found  ");
	    return -1; 
	}     
	return  \@tables;
}

=head2 tableExists

     check presence of the table

Returns

   
   0 = no table
   1 = table exists

=cut

sub  tableExists {
    my  ($self, $table) = @_; 
    my $result = undef;
    eval {
     	  $self->LOGGER->debug( "...testing presence of the table $table");
     	  # create the database table if necessary 
	  $self->openDB  if !($self->alive == 0);	
	  # next line will fail if table does not exist	  
     	  ($result)  =  $self->handle->selectrow_array("select * from  $table where 1=0 " );  
    }; 
    $EVAL_ERROR?return 0:return 1;
}


1;

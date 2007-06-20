#!/usr/bin/perl -w
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


###
# overload new to support new configuraiton from xml
###
sub new {
  my ($package, $config, $ns ) = @_; 
  my %hash = ();
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }    
  if(defined $config and $config ne "") {
  	# xpath
    $hash{"CONF"}{'METADATA_DB_TYPE'} = 'file';
    $hash{"CONF"}{'METADATA_DB_FILE'} = $config;
  }
  
  %{$hash{"DATADB"}} = ();
  %{$hash{"LOOKUP"}} = ();
  
  $hash{"CONFIG"} = undef;
  $hash{"SCHEDULE"} = undef;

  bless \%hash => $package;
}



sub config
{
	my $self = shift;
	if ( @_ ) {
		$self->{CONFIG} = shift;
	}
	return $self->{CONFIG};
}

sub schedule
{
	my $self = shift;
	if ( @_ ) {
		$self->{SCHEDULE} = shift;
	}
	return $self->{SCHEDULE};
}


###
# parses the config file and stores it internally as $self->{STORE} (as dom)
###
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


###
# generates config and schedules to be used
###
sub prepareMetadata {

  my($self) = @_;
  
  # config 
  my $dom = perfSONAR_PS::MP::PingER::Config->new( $self->{STORE} );
  $self->config( $dom  );
  #$logger->info( "CONFIG: " . $self->config()->dump() );
  
  # schedule 
  my $schedule = perfSONAR_PS::MP::PingER::Schedule->new( $self->config() );
  $self->schedule( $schedule );
  $self->schedule()->initiate();
  #$logger->info( "SCHEDULE: " . Dumper $self->schedule() );	

  return;

}


###
# starts the thread so that it will go through the schedule and determine when and how to run
# tests
###
my $numChildren = 0;
my $maxChildren = 8;
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
	
		# wait for a signal from a dead child or something
		# if all children are occupised
		if ( $numChildren >= $maxChildren ) {
			$logger->debug("at max forks; waiting...");
			sleep;
		}
	
		if (! exists $child{$i} )
		{
			my ( $testTime, $test ) = $self->waitForNextTest();
	
			if ( defined $test )
			{
				$logger->debug("[$i] About to run test " . $self->schedule()->getTestHost($test) . " using " . $self->schedule()->getTestPingId($test));
				( $testTime, $test ) = $self->schedule()->popTest( );
				$self->schedule()->addNextTest( $test );
				$self->startTest( $i, $test );
			} 
			else {
				$badExit = 1;
			}
		}
	
		if ( ! $badExit ) {
			$i++;
			$i -= $maxChildren if( $i >= $maxChildren );
		}	    

	}
	return;
}

###
# sleeps around unti lthe next test; prob is that ipc can cause this to exit for any other
# signal. therefore, need some cleverness
###
sub waitForNextTest
{
	my $self = shift;

	my ( $time, $test ) = $self->schedule()->peekTest();
	my $now = &perfSONAR_PS::MP::PingER::Schedule::getNowTime();
	my $wait = $time - $now;
	#$logger->debug( "TEST: $time, NOW:: $now ($wait) $test");

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

	return ( $time, $test );

}

sub REAPER {                        # takes care of dead children
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



sub startTest
{
	my $self = shift;
	my $forkedProcessNumber = shift;
	my $test = shift;

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
			my $agent = $self->prepareCollector( $test, $self->{"NAMESPACES"} );
			$agent->collect();

			# get the results out
			$logger->info( "RESULTS for\n" . Dumper $agent->getResults() );
			#my $dom = $agent->getResultsDOM();
			#$logger->info( "RESULTS for\n" . $dom->toString() );
	
			# write to teh stores
			my $host = $self->schedule()->getTestHost( $test );
			my $nodemetadata = $self->config()->getNodeMetadata( $host );
			$self->prepareData( $host, $nodemetadata );
			$self->storeData( $host, $agent, $nodemetadata );
			
			exit;
	    }

}


sub prepareData {
  my $self = shift;
  my $node = shift;
  my $nodeMetaData = shift;
 
   my $store = $self->config()->getNodeStores( $node, $nodeMetaData );

  foreach my $id ( keys %$store ) {
	my $type = $store->{$id}->{Type};
  	my $uri = $store->{$id}->{URI};
  	  	
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


###
# returns a agent to run test given
###
sub prepareCollector {
  my $self = shift;
  my $test = shift;
  my $ns = shift;
  
  # need to get the relevant datastrcuture for the node test
  my $node = $self->schedule()->getTestHost( $test );
  my $ping = $self->schedule()->getTestPingId( $test );
  my $hash = $self->config()->getNodeMetadata( $node, $ping );
  
  # get the command line string
  my $cmd = undef;

  if ( $hash->{$node}->{Ping}->{$ping}->{TestProtocol} eq 'IPV4') {
    $cmd = $self->config()->getSystemParam( 'PingV4Cmd' );
  } elsif ( $hash->{$node}->{Ping}->{$ping}->{TestProtocol} eq 'IPV6' ) {
	$cmd = $self->config()->getSystemParam( 'PingV6Cmd' ); 
  } else {
  	$logger->fatal( "Do not understand Ping Protocol '" . $hash->{$node}->{Ping}->{$ping}->{Protocol} . "'.");
  }

  return perfSONAR_PS::MP::PingER::Agent->new( $cmd, $hash->{$node}->{Ping}->{$ping}, $node, $ns );

}


###
# smae as collect measurments
###
sub storeData
{
	my $self = shift;
	my $node = shift;
	my $agent = shift;
	my $nodeMetaData = shift;

	#foreach store of the node, insert the data
	my $store = $self->config()->getNodeStores( $node, $nodeMetaData );
	#$logger->info( "Storing agent results into \n". Dumper $store );
	
	foreach my $id ( keys %$store ) {
		my $type = $store->{$id}->{Type};
		my $uri = $store->{$id}->{URI};
		
		next if (! defined $type || $type eq '') || (! defined $uri || $uri eq '' ); 
		
		if( ! exists $self->{DATADB}->{$uri} ){
		
			$logger->fatal( "Store of type '$type' for '$uri' does not exist.")
		 	
		} else {	
			if ( $type eq 'MA' ) {
				# TODO: 
				my $dom = $agent->getResultsDOM();
				$logger->info( "Inserting data into MA $uri (" . $self->{DATADB}->{$uri}. "):\n" . $dom->toString() );
						
	
				$self->{DATADB}->{$uri}->insert( $dom );
				
			} elsif ( $type eq 'sqlite') {
				$logger->info( "Storing data into sqlite.");
		# TODO: need schema
	
			}
			else {
				$logger->error( "Unknown storage type " . $type . ".");
			}
	        $self->{DATADB}->{$uri}->closeDB if exists $self->{DATADB}->{$uri};
			}
	}
	return;
}


sub collectMeasurements {

}


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

sub dump
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Config");	

	$logger->info( "Config: " . Dumper $self->{STORE});
}

sub getPings
{
	my $self = shift;
	my $node = shift;
	my $hash = shift;

	return ( keys %{$hash->{$node}->{Ping}} );
}

# returns the info about a node
sub getNodeMetadata
{
	my $self = shift;
	my $node = shift;
	
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Config");	

	# get the host 
	my $hostElement = $self->{STORE}->findnodes(
        			'/PingER/Hosts/Host[@id="' . $node . '"]' 
                           )->[0];


	#$logger->debug("GET: " . $hostElement->toString());

	# create an xml element of the defaults, then override it with the overwrite settings
	my %host = ();
		
	#$logger->debug( $n->toString() );
		
	foreach my $p ( $hostElement->findnodes( './param' ) ) {
        	my $name = $p->getAttribute( 'name' );
                my $val = $p->getAttribute('value' );
		next if ! $name || $name eq '';
                $host{$node}{$name} = $val if( $name && $val );
        }



	foreach my $c ( $hostElement->childNodes() ) {
		
		#$logger->debug( $c->toString() );

		my $tag = $c->localName();
		next if ( ! $tag || $tag ne 'param' );

		my $ref = $c->getAttribute( 'ref' );
		if ( defined $ref ) {
		
			#$logger->debug( "FOUND: " . $ref );
			my @defaults = $self->{STORE}->findnodes( '/PingER/Defaults/param[@name="' . $ref . '"]/*');
				
			$logger->fatal( "Could not find param reference to '$ref' for '$node'." ) if scalar @defaults == 0;
			foreach my $def ( @defaults ) { 
				my $name = $def->localName();
				next if ! $name || $name eq '';
				my $id = $def->getAttribute(  'id' );
				#$logger->debug( " GOT: '" . $def->toString() . ";" );
				# populate params
				foreach my $p ( $def->findnodes( './param' ) ) {
					my $key = $p->getAttribute( 'name' );
					my $val = $p->getAttribute( 'value' );
					next if !$key || $key eq '';
					#$logger->debug( "NODE: $node, NAME: $name, ID: $id, KEY: $key");
					$host{$node}{$name}{$id}{$key} = $val;
				}
			}

		
		}
	} # foreach findnodes

	# now override with the settings within the host
	foreach my $n ( $hostElement->childNodes() ) {
		my $tag = $n->localName();
		next if ( !$tag || $tag eq 'param' );	# we should have processed all of them above
		my $id = $n->getAttribute( 'id' );
		next if ! $id || $id eq '';
		foreach my $p ( $n->findnodes( './param' ) ) {
			my $name = $p->getAttribute( 'name' );
			my $val = $p->getAttribute( 'value' );
			next if ! $name || $name eq '' ;
			$host{$node}{$tag}{$id}{$name} = $val;

		}
	}


	#$logger->debug( $host );
	
	return \%host;
} 

sub getAllNodes
{
	my $self = shift;
	
	my @out = ();
	my %seen = ();
	#$logger->debug("get all nodes");
	foreach my $n ( $self->{STORE}->findnodes( '/PingER/Hosts/Host') ) {
		my $tag = $n->localName();
		my $node = $n->getAttribute( 'id' );
		next if $node eq '';
		push @out, $node unless $seen{$node}++;
	}
	
	return @out;

}

sub getSystemParam
{
	my $self = shift;
	my $param = shift;
	foreach my $n ( $self->{STORE}->findnodes( '/PingER/Configuration/System/param') ) {
		my $name = $n->getAttribute( 'name' );
		my $value = $n->getAttribute( 'value' );
		next if ! $name || $name eq '';
		return $value if ( $name eq $param );
	}
	return undef;
}

sub getNodeStores
{
	my $self = shift;
	my $node = shift;
	my $nodeMetaData = shift;
	
	if ( ! defined $nodeMetaData ) {
		$nodeMetaData = $self->getNodeMetadata( $node );
	}
	#print Dumper $nodeMetaData;
	return $nodeMetaData->{$node}->{'Store'};

}



# ================ Internal Package perfSONAR_PS::MP::PingER::Schedule ================

package perfSONAR_PS::MP::PingER::Schedule;

use Log::Log4perl qw(get_logger);
use Time::HiRes qw ( &gettimeofday );
use Data::Dumper;



sub new {
  my ( $package, $config ) = @_; 
  my %hash = ();
  $hash{"CONFIG"} = $config;
  %{$hash{"SCHEDULE"}} = ();
  $hash{"CHIDLREN_OCCUPIED"} = 0;
  $hash{"MAX_CHILDREN"} = 2;
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

sub maxChildren
{
	my $self = shift;
	if ( @_ ) {
		$self->{"MAX_CHILDREN"} = shift;
	}
	return $self-{"MAX_CHILDREN"};
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


# sets the schedule for tests
sub initiate
{
	my $self = shift;
	my $logger = get_logger("perfSONAR_PS::MP::PingER::Schedule");

	my %schedule = ();
	foreach my $host ( $self->config()->getAllNodes() ) {
		my $hostMetadata = $self->config()->getNodeMetadata($host ); 
		my @pings = $self->config()->getPings( $host, $hostMetadata );
		foreach my $ping ( @pings ) {
			#$logger->debug( "Add Test: HOST: $host, PING: $ping" );
			my $test = &createTest ( $host, $ping );
			$self->addNextTest( $test, $hostMetadata );
		}
	}

	return;
}


sub popTest
{
	my $self = shift;
	my ( $time, $test ) = $self->peekTest();

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
		return ( $time, $test );
	}
	return ( undef, undef );
}


sub peekTest
{
	my $self = shift;
	my @times = sort {$a<=>$b} keys %{$self->{SCHEDULE}};

	if ( scalar @times ) {

		my $start = $times[0];
		my $test = $self->{SCHEDULE}->{$start}->[0];

		return ( $start, $test );

	}
	
	return ( undef, undef );
}

##
# 
##
sub addNextTest
{
	my $self = shift;
	my $test = shift;

	my $node = $self->getTestHost( $test );
	my $pingId = $self->getTestPingId( $test );

	my $hostMetadata = shift;	# optional
	my $since = shift; # this is so that we add the test at the offset + since (epoch)

    my $now = $since;
	if ( ! defined $now ) {
		$now = &getNowTime();
	}
	if ( ! defined $hostMetadata ) {
		$hostMetadata = $self->config()->getNodeMetadata( $node );
	}
    my $nextTime = &getNextTestTime( $hostMetadata, $node, $pingId );

    $self->addTest( $nextTime, $test );
	
	return;
}

sub addTest
{
	my $self = shift;
	my $time = shift;
	my $test = shift;

	#$logger->info( "ADDIN: $time "  . Dumper( $test ));

	# if tehre is already at test at this time, append it
	push @{$self->{SCHEDULE}->{$time}}, $test;

	return;	
}

sub getTestHost
{
	my $self = shift;
	my $test = shift;
	
	my @out = keys %$test; 
	return $out[0];
}

sub getTestPingId
{
	my $self = shift;
	my $test = shift;
	
	return $test->{$self->getTestHost($test)};

}

sub createTest
{
	my $host = shift;
	my $pingId = shift;

	my %test = ();
	$test{$host} = $pingId;

	return \%test;
}

sub getNextTestTime
{
	my $hash = shift;
	my $node = shift;
	my $ping = shift;

	my $period = $hash->{$node}->{Ping}->{$ping}->{TestPeriod};
	my $offset = $hash->{$node}->{Ping}->{$ping}->{TestOffset};

	#$logger->debug( "PERIOD: $period, OFFSET: $offset" );
	my $rand = 0;
	if ( $offset > 0 ) {
		$rand = rand( $offset/2 ) - $offset;
	}

	my $now = &getNowTime();

	return $now + $period + $rand;
}


# ================ Internal Package perfSONAR_PS::MP::Ping::Agent ================

package perfSONAR_PS::MP::PingER::Agent;

use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use Data::Dumper;



sub new {
  my ($package, $ping, $options, $host, $ns ) = @_; 
  my %hash = ();
  if(defined $ping and $ping ne "") {
    $hash{"PING"} = $ping;
  }
  if(defined $options and $options ne "") {
    $hash{"OPTIONS"} = $options;
  } 
   if(defined $host and $host ne "") {
    $hash{"HOST"} = $host;
  }
   if(defined $ns and $ns ne "") {
    $hash{"NAMESPACES"} = $ns;
  }
  %{$hash{"RESULTS"}} = ();
  $hash{'MINRTT'} = undef;
  $hash{'MAXRTT'} = undef;
  $hash{'MEANRTT'} = undef;
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


sub host
{
	my $self = shift;
	if ( @_ ) {
		$self->{"HOST"} = shift;
	}
	return $self->{"HOST"};
}


sub namespaces
{
	my $self = shift;
	if ( @_ ) {
		$self->{"NAMESPACES"} = shift;
	}
	return $self->{"NAMESPACES"};
}



sub collect {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::PingER::Agent");

  
  # parse the options into a commandline
  $self->{CMD} = $self->ping();
  while( my ($k,$v) = each %{$self->{"OPTIONS"}} ) {
		#print "$k: $v\n";
		$self->{CMD} =~ s/\%$k\%/$v/g;
	}

  my $host = $self->{"HOST"};
  $self->{CMD} =~ s/\%destination\%/$host/g;
  
  
  if(defined $self->{CMD} and $self->{CMD} ne "") {   
    undef $self->{RESULTS};
     
    my($sec, $frac) = Time::HiRes::gettimeofday;
    my $time = eval($sec.".".$frac);
        
    open(CMD, $self->{CMD}." |") or 
      $logger->error("Cannot open \"".$self->{CMD}."\"");
      
      $logger->info( "Running '$self->{CMD}'... ");
    my @results = <CMD>;    
    close(CMD);
    
    # parse the results into a hash
    for(my $x = 1; $x <= ($#results-4); $x++) { 
      my @resultString = split(/:/,$results[$x]);        
      ($self->{RESULTS}->{$x}->{"bytes"} = $resultString[0]) =~ s/\sbytes.*$//;
      for ($resultString[1]) {
        s/\n//;
        s/^\s*//;
      }
    
      my @tok = split(/ /, $resultString[1]);
      foreach my $t (@tok) {
        if($t =~ m/^.*=.*$/) {
          (my $first = $t) =~ s/=.*$//;
	        (my $second = $t) =~ s/^.*=//;
	        $self->{RESULTS}->{$x}->{$first} = $second;  
        }
        else {
          $self->{RESULTS}->{$x}->{"units"} = $t;
        }
      }
      $self->{RESULTS}->{$x}->{"timeValue"} = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);
      $time = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);
    }
    # loop to get summary stats
    for( my $x = $#results-1; $x <= $#results; $x++ ) {
	#$logger->debug( "$x :: $results[$x]");
      if ( $results[$x] =~ /^(\d+) packets transmitted, (\d+) received/ ) {
	$self->{SENT} = $1;
	$self->{RECV} = $2;
      } elsif ( $results[$x] =~ /^rtt min\/avg\/max\/mdev \= (\d+\.\d+)\/(\d+\.\d+)\/(\d+\.\d+)\/\d+\.\d+ ms/ ) {
	$self->{MINRTT} = $1;
	$self->{MAXRTT} = $3;
	$self->{MEANRTT} = $2;
      }
    }
    
  }
  else {
    $logger->error("Missing command string.");     
  }
  return;
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

	#$logger->debug( "NS: " . Dumper $self->namespaces() );

	my $doc = XML::LibXML::Document->new();
	$doc->createElementNS( $self->namespaces()->{'nmwg'}, 'nmwg' );
	$doc->createElementNS( $self->namespaces()->{'pinger'}, 'pinger' );
	$doc->createElementNS( $self->namespaces()->{'nmwgt4'}, 'nmwgt4' );

	my $root = $doc->createElement('message');
	$root->setNamespace( $self->namespaces()->{'nmwg'}, 'nmwg' );

	$doc->setDocumentElement($root);

	#$logger->debug( "creating metadata" );	
	my $metadata = $doc->createElement('metadata');
	$metadata->setAttribute( 'id', '#id' );
	$metadata->setNamespace( $self->namespaces()->{'nmwg'}, 'nmwg' );
	$root->appendChild($metadata);

	# subject
	#$logger->debug( "creating subject" );	
	my $subj = $doc->createElement( 'subject' );
	$subj->setNamespace( $self->namespaces()->{'pinger'}, 'pinger' );
	$metadata->appendChild( $subj );

	#$logger->debug( "creating endpoint pair" );	
	my $endPoint = $doc->createElement( 'endPointPair' );
	$endPoint->setNamespace( $self->namespaces()->{nmwgt4}, 'nmwgt4' );
	$subj->appendChild( $endPoint );	

	#$logger->debug( "creating source" );	
	my $source = $doc->createElement( 'endPoint' );
	$source->setNamespace( $self->namespaces()->{nmwgt4}, 'nmwgt4' );
	$source->setAttribute( 'role', 'src' );
	$source->setAttribute( 'protocol', 'icmp' );
	$endPoint->appendChild( $source );

	my $sourceNode = $doc->createElement( 'address' );
	$sourceNode->setNamespace( $self->namespaces()->{nmwgt4}, 'nmwgt4' );
	$sourceNode->setAttribute( 'value', 'FILL ME IN' ); #TODO:
	$source->appendChild( $sourceNode );


	#$logger->debug( "creating dest" );	
	my $dest = $doc->createElement( 'endPoint' );
	$dest->setNamespace( $self->namespaces()->{nmwgt4}, 'nmwgt4' );
	$dest->setAttribute( 'role', 'dst' );
	$dest->setAttribute( 'protocol', 'icmp' );
	$endPoint->appendChild( $dest );

	my $destNode = $doc->createElement( 'address' );
	$destNode->setNamespace( $self->namespaces()->{nmwgt4}, 'nmwgt4' );
	$destNode->setAttribute( 'value', $self->host() );
	$dest->appendChild( $destNode );

	# parameters
	#$logger->debug( "creating params" );	
	my $param = $doc->createElement( 'parameters' );
	$param->setNamespace( $self->namespaces()->{'pinger'}, 'pinger' );
	$metadata->appendChild( $param );
	
	while( my ($k,$v) = each %{$self->options()} ) {
		next if $k =~ /^Test/;
		my $p = $doc->createElement( 'parameter' );
		$p->setNamespace( $self->namespaces()->{'nmwg'}, 'nmwg' );
		$p->setAttribute( 'name', $k );
		my $text = XML::LibXML::Text->new( $v );
		$p->appendChild( $text );
		$param->appendChild( $p );
	}


	my $data = $doc->createElement('data');
	$data->setNamespace( $self->namespaces()->{'nmwg'}, 'nmwg' );
	$data->setAttribute( 'id', '#data');
	$data->setAttribute( 'metadataIdRef', '#id');
	$root->appendChild( $data );

	my $vars = {
		'minRtt' => undef,
		'maxRtt' => undef,
		'meanRtt' => undef,
		'minIpd' => undef,
		'maxIpd' => undef,
		'lossPercent' => undef,
		'iprIpd' => undef,
		'meanIpd' => undef,
		'outOfOrder' => 'false',
		'duplicates' => 'false'
		};


	my $totalRtt = undef;
	my $countRtt = 0;
	my $totalIpd = undef;
	my @ipd = ();
	
	my $lastSeq = 0;

	my $lastLatency = undef;
	#$logger->debug( "creating real datums" );	
	foreach my $ping (sort {$a<=>$b} keys (%{$self->{RESULTS}} )) {
	   
	   my $datum = $doc->createElement( 'datum' );
	   $datum->setNamespace( $self->namespaces()->{'pinger'}, 'pinger' );

	   my $latency = $self->{RESULTS}->{$ping}->{'time'};
	   $datum->setAttribute('value', $latency);
	   $datum->setAttribute('seqNum', $self->{RESULTS}->{$ping}->{'icmp_seq'});
	   $datum->setAttribute('numBytes', $self->{RESULTS}->{$ping}->{'bytes'});
	   $datum->setAttribute('ttl', $self->{RESULTS}->{$ping}->{'ttl'});
	   $datum->setAttribute('timeType', 'unix' );
	   $datum->setAttribute('timeValue', $self->{RESULTS}->{$ping}->{'timeValue'});

	   $data->appendChild( $datum );	   

	   # determine mins etc
	   $vars->{minRtt} = $latency if !defined $vars->{minRtt} || $latency < $vars->{minRtt};
	   $vars->{maxRtt} = $latency if !defined $vars->{maxRtt} || $latency > $vars->{maxRtt};
	   $totalRtt += $latency;
	   $countRtt++;
	
	   # last seq
	   $vars->{outOfOrder} = 'true' if $self->{RESULTS}->{$ping}->{'icmp_seq'} < $lastSeq;
	   $lastSeq = $self->{RESULTS}->{$ping}->{'icmp_seq'};

	   # duplicates
	   # ???

	   if ( $lastLatency ) {
		push @ipd, $latency - $lastLatency;
	   }
	  $lastLatency = $latency;

	}

	$vars->{meanRtt} = $totalRtt / $countRtt;
	# ipd
	foreach my $i ( @ipd ) {
		$vars->{minIpd} = $i if !defined $vars->{minIpd} || $i < $vars->{minIpd};
		$vars->{maxIpd} = $i if !defined $vars->{maxIpd} ||  $i > $vars->{maxIpd};
		$totalIpd += $i;
	}
	$vars->{meanIpd} = $totalIpd / scalar @ipd;

	# hires results from output
	$vars->{minRtt} = $self->{'MINRTT'} if defined $self->{'MINRTT'};
	$vars->{maxRtt} = $self->{'MAXRTT'} if defined $self->{'MAXRTT'};
	$vars->{minRtt} = $self->{'MEANRTT'} if defined $self->{'MEANRTT'};

	# lossPercent
	if ( defined $self->{SENT} && defined $self->{RECV} ) {
		$vars->{lossPercent} = 1.0 - $self->{RECV} / $self->{SENT};
	}	

	# duplicates
	#
	# iqrRtt
	#

	#$logger->debug( "creating derived datums" );	
	# owrk out the averages etc
	while( my ( $k,$v ) = each %$vars ) {
		next if (  (!defined $k || $k eq '' )  ||  (!defined $v || $v eq '' ) );
		my $datum = $doc->createElement( 'datum' );
                $datum->setNamespace( $self->namespaces()->{'pinger'}, 'pinger' );
		$datum->setAttribute( 'name', $k );
		$datum->setAttribute( 'value', $v );
		$data->appendChild( $datum );
	}
	
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

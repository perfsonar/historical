package perfSONAR_PS::Services::MP::Agent::PingER;

use strict;
use warnings;
use version; our $VERSION = 0.09;
 
=head1 NAME

perfSONAR_PS::Services::MP::Agent::Ping - A module that will run a ping and
return it's output in a suitable internal data structure.

=head1 DESCRIPTION

Inherited perfSONAR_PS::MP::Agent::Ping class that allows a ping to 
be executed. This class extends the features of the ping class to enable:

- storage of ping results into PingER databases.
- ping 'priming'; where by the first ping singleton value is ignore as it
  it expected that it will be anomolous due to the effect of various caches
  along the path
  
   
=head1 SYNOPSIS

  # create and setup a new Agent  
  my $agent = perfSONAR_PS::Services::MP::Agent::Ping( );
  $agent->init();
  
  # collect the results (i.e. run the command)
  if( $mp->collectMeasurements() == 0 )
  {
  	
  	# get the raw datastructure for the measurement
  	use Data::Dumper;
  	print "Results:\n" . Dumper $self->results() . "\n";

  }
  # opps! something went wrong! :(
  else {
    
    print STDERR "Command: '" . $self->commandString() . "' failed with result '" . $self->results() . "': " . $agent->error() . "\n"; 
    
  }


head1 API

=cut
 
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair::EndPoint';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::pinger::Message::Metadata::Subject' => 'PingerSubj';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::pinger::Message::Metadata::Parameters' => 'PingerParams';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmwg::Message::Metadata::Parameters::Parameter';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmwg::Message::Metadata';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmwg::Message::Data';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::pinger::Message::Data::Datum' => 'PingerDatum';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmwg::Message::Data::CommonTime';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface';
use aliased 'perfSONAR_PS::PINGER_DATATYPES::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface::IpAddress';


# to get the event types
use perfSONAR_PS::Datatypes::EventTypes;

# stats calcs
use IEPM::PingER::Statistics;

use perfSONAR_PS::Common;

# derive from teh base agent class
use perfSONAR_PS::Services::MP::Agent::Ping;
use base  'perfSONAR_PS::Services::MP::Agent::Ping';
 
use Log::Log4perl qw(get_logger);
our $logger = Log::Log4perl::get_logger( 'perfSONAR_PS::Services::MP::Agent::Pinger' );

# command line
our $default_command = $perfSONAR_PS::Services::MP::Agent::Ping::default_command;
  
 


=head2 pingPriming

accessor/mutator class to determine whether we are conducting ping priming or not

=cut

sub pingPriming
{
	my $self = shift;
	
	return 1;
}


=head2 deadline

deadline is not supported in pinger

=cut 

sub deadline {
    my $self = shift;
    $logger->logdie( "Deadline is not supported in PingER");
    return;
}


=head2 collectMeasurements( )

Runs the command with the options specified in constructor. 
The return of this method should be

 -1 = something failed
  0 = command ran okay

on success, this method should call the parse() method to determine 
the relevant performance output from the tool.

We do something a bit more involved with PingER as we wish to prime the network
by running a single independent ping prior to the real test.

=cut

sub collectMeasurements {
    my $self = shift;

    # keep a temp variable count then set it back after priming
    my $count = $self->count();

    # set the up the appropiate destinations
    # if we have an ip address, use this as the destination
    my $cmd = $self->command();
    #$logger->debug( "DEST: " . $self->destination() . " / " . $self->destinationIp() );
    if ( $self->destinationIp() ) {
    	    $logger->debug( "using destination ip '" . $self->destinationIp() 
    			    . "' instead of '" . $self->destination() . "'");
    	    $cmd =~ s/\%destination\%/\%destinationIp\%/g;
    } elsif ( ! defined $self->destination() ) {
    	    $logger->fatal( "No destination defined!");
    	    return -1;
    }

    # set it back
    $self->command( $cmd );

    if ( $self->pingPriming() ) {
    	    # prime a single packet
    	    $self->count( 1 );
    	    
    	    $logger->debug( "Priming caches by running singleton ping..." );

    	    # we don't care about the results, so don't bother
    	    # TODO: this parses the unwanted variables tho...
    	    $self->SUPER::collectMeasurements();

    	    # don't forget to reset the countesr
    	    delete $self->{RESULTS};
    	    $self->{RESULTS} = {};
    	    
    	    $logger->debug( "Continuing test..." )

    }

    $self->count( $count );

    return $self->SUPER::collectMeasurements( );
}

=head2 parse()

parses the output from a command line measurement of pings. we must take care to ensure
that we ignore the first ping if we are doing ping priming.

=cut
sub parse
{
	my $self = shift;
	my $cmdOutput = shift;
	
	# use this as indication of the start of the test in epoch secs
	my $time = shift;
	my $endtime = shift;

	my $cmdRan = shift;

	$logger->debug( "Parsing output:\n@$cmdOutput" );

	# run the normal ping parsing
	$self->SUPER::parse( $cmdOutput, $time, $endtime, $cmdRan );

	my @results  = &IEPM::PingER::Statistics::RTT::calculate( \@{$self->results()->{'rtts'}} );
	if(@results) {
	    $self->results()->{'minRtt'} = sprintf( "%0.3f", $results[0] || '0.0' )
		    if ! defined $self->results()->{'minRtt'};
	    $self->results()->{'meanRtt'} = sprintf( "%0.3f", $results[1]|| '0.0'  )
		    if ! defined $self->results()->{'meanRtt'};
	    $self->results()->{'maxRtt'} = sprintf( "%0.3f", $results[2] || '0.0' )
		    if ! defined $self->results()->{'maxRtt'};
	    $self->results()->{'medianRtt'} = sprintf( "%0.3f", $results[3]|| '0.0'  )
		    if ! defined $self->results()->{'medianRtt'};
        }
	# ipd
	@results = &IEPM::PingER::Statistics::IPD::calculate( \@{$self->results()->{'rtts'}} );
        if(@results) {
	    $self->results()->{'minIpd'} = sprintf( "%0.3f", $results[0] || '0.0' ); 	
	    $self->results()->{'meanIpd'} = sprintf( "%0.3f", $results[1] || '0.0' ); 	
	    $self->results()->{'maxIpd'} = sprintf( "%0.3f", $results[2] || '0.0' ); 	
	    $self->results()->{'iqrIpd'} = sprintf( "%0.3f", $results[3] || '0.0' ); 	

	    # loss
	    $self->results()->{'lossPercent'} = sprintf( "%0.3f", &IEPM::PingER::Statistics::Loss::calculate( 
				    $self->results()->{'sent'}, $self->results()->{'recv'} ) || '0.0' );

	    $self->results()->{'clp'} = &IEPM::PingER::Statistics::Loss::CLP::calculate( 
				    $self->results()->{'sent'}, $self->results()->{'recv'}, \@{$self->results()->{'seqs'}} );
	    $self->results()->{'clp'} = sprintf( "%0.3f",$self->results()->{'clp'} )
		    if defined $self->results()->{'clp'} && $self->results()->{'clp'} > 0;
        }
	# duplicates
	@results =  &IEPM::PingER::Statistics::Other::calculate( 
			$self->results()->{'sent'}, $self->results()->{'recv'}, \@{$self->results()->{'seqs'}} );
	if(@results) {
	    $self->results()->{'duplicates'} = $results[0];
	    $self->results()->{'outOfOrder'} = $results[1];
        }
	# if loss is 100%, nothing is certain
	# normalise data
	if ( ! defined $self->results()->{'lossPercent'} 
		|| $self->results()->{'lossPercent'} == 100 ) {
		$self->results()->{'minRtt'} = undef;
		$self->results()->{'maxRtt'} = undef;
		$self->results()->{'meanRtt'} = undef;
		$self->results()->{'minIpd'} = undef;
		$self->results()->{'maxIpd'} = undef;
		$self->results()->{'meanIpd'} = undef;
		$self->results()->{'iqrIpd'} = undef;
		$self->results()->{'medianRtt'} = undef;
 		$self->results()->{'duplicates'} = undef;
		$self->results()->{'outOfOrder'} = undef;
		$self->results()->{'rtts'} = undef;
		$self->results()->{'seqs'} = undef;
	}

	$self->results()->{'startTime'} = $time;
	$self->results()->{'endTime'} = $endtime;

	undef @results;

	return 0;
}

=head2 toAPI

casts the data (results()) into api to easy casting etc.

=cut

sub toAPI
{
	my $self = shift;
	my $metadataId = shift;
	my $dataId = shift;
	
	$metadataId = "metadata.". perfSONAR_PS::Common::genuid() if ( ! defined $metadataId );
        $dataId = "data.". perfSONAR_PS::Common::genuid() if ( ! defined $dataId );
	
	# create the metadata element
	# create the subject
	# nmtl3 interface
	my $src = $self->_createInterface( 'src', $self->source(), $self->sourceIp() );
	my $dst = $self->_createInterface( 'dst', $self->destination(), $self->destinationIp() );

	my $endpoints =  EndPointPair->new({endPoint => [$src, $dst]});	 
	my $subject = PingerSubj->new({endPointPair => $endpoints});
	 
	# setup parameters  
	my @params = ();
	#no strict 'refs';
	foreach my $p ( qw/count packetSize interval ttl/ ) {
	    my $param =  Parameter->new({ 'name' => $p, text =>  $self->$p});
	    push @params, $param;
	}
	#use strict 'refs';
	my $parameters =  PingerParams->new({parameter => \@params});	
		
	# finally set metadata
	my $metadata =  Metadata->new({ 'id' => $metadataId, subject => $subject, parameters => $parameters});
	 
	# add event type
	my $eventType = perfSONAR_PS::Datatypes::EventTypes->new();
	$metadata->set_eventType( $eventType->tools->pinger );
	
	# create the data element
	my $data =  Data->new({ 'metadataIdRef' => $metadataId, 'id' =>  $dataId });
	  
	# raw data
	my @singletons = ();
	foreach my $singleton ( @{$self->results()->{'singletons'}} ) {
	    # remap some values
	    $singleton->{'timeType'} = 'unix';
	    $singleton->{'valueUnits'} = $singleton->{'units'};
	    push @singletons, PingerDatum->new( $singleton );
	}
	
	# set the internal results
	#use Data::Dumper;
	#$logger->debug( 'RESULTS: ' . Dumper $self->results() );
	#$logger->debug( 'END: ' . $self->results()->{'endTime'} . ' STARt: '. $self->results()->{'startTime'} );
	my $duration = $self->results()->{'endTime'} - $self->results()->{'startTime'};
	
	my $commonTime  =   CommonTime->new({
					       'value' =>  $self->results()->{'startTime'},
					       'duration' =>  $duration,
					       'type' =>  'unix', 
					    });
	# add the datums to the commonTime
	$commonTime->set_datum( \@singletons );
	$commonTime->addDatum( $self->_datumAPI('minRtt') );	
	$commonTime->addDatum( $self->_datumAPI('meanRtt') );
	$commonTime->addDatum( $self->_datumAPI('maxRtt') );
	$commonTime->addDatum( $self->_datumAPI('minIpd') );	
	$commonTime->addDatum( $self->_datumAPI('meanIpd') );
	$commonTime->addDatum( $self->_datumAPI('maxIpd') );	
	$commonTime->addDatum( $self->_datumAPI('iqrIpd') );
	$commonTime->addDatum( $self->_datumAPI('lossPercent') );
	$commonTime->addDatum( $self->_datumAPI('clp') );
	$commonTime->addDatum( $self->_datumAPI('outOfOrder') );
	$commonTime->addDatum( $self->_datumAPI('duplicates') );
	
	#$logger->fatal("TIME: " . $commonTime->asString() );
	
	# add commontime to teh data 
	$data->set_commonTime( [$commonTime] );
	#$logger->fatal("DATA: " . $data->asString() );
	
	# create the message
	my $message = perfSONAR_PS::Datatypes::Message->new({	'type' =>  'Store',
							        'id' =>  'message.' .  perfSONAR_PS::Common::genuid() , 
								metadata => [$metadata],
								data => [$data],
							    });
	 
	return $message;
}


=head2 toDOM()

returns the object as a LibXML dom

=cut

sub toDOM {
	my $self = shift;
	my $message = $self->toAPI();
	$logger->debug("ALL TO DOM: " . $message->asString() );	
	return $message->getDOM();
}


sub _createInterface
{
	my $self = shift;
	my $role = shift;
	my $dns = shift;
	my $ip = shift;
	
	my $ipInt = IpAddress->new({
			     	     'value' =>  $ip,
			     	     'type'  =>  'IPv4', 
			      	  });

	my $interface = Interface->new({ipAddress =>  $ipInt, ifHostName => $dns});
		
	my $src = EndPoint->new({
				'protocol' =>  'ICMP',
				'role' =>  $role,
				interface => $interface,
				});
	return $src;
}


sub _datumAPI
{
	my $self = shift;
	my $name = shift;
	
	return undef
		if ( $name eq 'clp' && ! defined $self->results()->{$name} );	
	return PingerDatum->new({ 'name' => $name, 'value' =>  $self->results()->{$name},}); 
}


1;


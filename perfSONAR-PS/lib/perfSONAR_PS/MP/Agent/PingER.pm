#!/bin/env perl

use perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum;
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data::CommonTime;
use perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Subject;
# nmtl3
use perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Src;
use perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Dst;
# nmtl4
use perfSONAR_PS::Datatypes::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair::EndPoint::Address;
use perfSONAR_PS::Datatypes::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair::EndPoint;
use perfSONAR_PS::Datatypes::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair;

use perfSONAR_PS::Datatypes::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface;
use perfSONAR_PS::Datatypes::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface::IpAddress;

# parameter lists
use perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Parameters;
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter;

# messages
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata;
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data;
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message;

# to get the event types
use perfSONAR_PS::Datatypes::EventTypes;

use IEPM::PingER::Statistics;

package perfSONAR_PS::MP::Agent::PingER;

=head1 NAME

perfSONAR_PS::MP::Agent::Ping - A module that will run a ping and
return it's output in a suitable internal data structure.

=head1 DESCRIPTION

Inherited perfSONAR_PS::MP::Agent::CommandLine class that allows a command to 
be executed. This class overwrites the parse and 

=head1 SYNOPSIS

  # create and setup a new Agent  
  my $agent = perfSONAR_PS::MP::Agent::Ping( );
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


=cut

# derive from teh base agent class
use perfSONAR_PS::MP::Agent::Ping;
our @ISA = qw(perfSONAR_PS::MP::Agent::Ping);

use strict;

use Log::Log4perl qw(get_logger);
our $logger = Log::Log4perl::get_logger( 'perfSONAR_PS::MP::Agent::Ping' );

# command line
our $command = '/bin/ping -c %count% -i %interval% -s %packetSize% -t %ttl% %destination%';

=head2 new( $command, $options, $namespace)

Creates a new ping agent class

=cut
sub new
{
	my $package = shift;
	
	my %hash = ();
	# grab from the global variable
    if(defined $command and $command ne "") {
      $hash{"CMD"} = $command;
    }
    $hash{"OPTIONS"} = {};
  	%{$hash{"RESULTS"}} = ();

  	bless \%hash => $package;
}


=head2 init()

inherited from parent classes. makes sure that the ping executable is existing.

=cute

=head2 deadline

deadline is not supported in pinger

=cut 
sub deadline
{
	my $self = shift;
	$logger->logdie( "Deadline is not supported in PingER");
	return;
}



=head2 parse()

parses the output from a command line measurement of pings

=cut
sub parse
{
	my $self = shift;
	my $cmdOutput = shift;
    # use this as indication of the start of the test in epoch secs
    my $time = shift; # work out start time of time
	my $endtime = shift;

	my $cmdRan = shift;

    my @singletons = ();
    my @rtts = ();
    my @seqs = ();
    for( my $x = 1; $x < scalar @$cmdOutput - 4; $x++ ) {
    	
    	$logger->debug( "Analysing line: " . $cmdOutput->[$x] );
    	my @string = split /:/, $cmdOutput->[$x];
    	my $v = {};
    	
		( $v->{'bytes'} = $string[0] ) =~ s/\s*bytes.*$//;
		if ( $string[0] =~ /\((.*)\)/ ) {
			$self->destinationIp( $1 );
		}
			
		foreach my $t ( split /\s+/, $string[1] ) {
		  $logger->debug( "looking at $t");
          if( $t =~ m/(.*)=(\s*\d+\.?\d*)/ ) { 
	        $v->{$1} = $2;
	        $logger->debug( "  found $1 with $2");
          } else {
            $v->{'units'} = $t; 
          }
		}
		
		push( @singletons, 
			perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new(
				{  	'timeType' 	=>  'unix',
					'ttl' 		=>  $v->{'ttl'},
					'numBytes' 	=> $v->{'bytes'},
					'value'  	=>  $v->{'time'},
					'valueUnits' =>  $v->{'units'} || 'ms',
					'timeValue' => $time + eval($v->{'time'}/1000),
					'seqNum' 	=>  $v->{'icmp_seq'} ,
				})
		); # push
		push( @rtts, $v->{'time'} );
		push( @seqs, $v->{'icmp_seq'} );
		
  		# next time stamp
     	$time = $time + eval($v->{'time'}/1000);
    
    }

    my @results = ();
    
	# hires result?
    @results = &IEPM::PingER::Statistics::RTT::calculate( \@rtts );
    my $minRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'minRtt',  'value' =>  $results[0], }); 
	my $meanRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'meanRtt',  'value' =>  $results[1], }); 
	my $maxRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'maxRtt',  'value' =>  $results[2], } ); 
	
	# ipd
	@results = ();
    @results = &IEPM::PingER::Statistics::IPD::calculate( \@rtts );
    
    $logger->fatal( "IPD: @results");
	my $minIpd = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'minIpd',  'value' =>  $results[0], }); 	
	my $meanIpd = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'meanIpd',  'value' =>  $results[1], }); 	
	my $maxIpd = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'maxIpd',  'value' =>  $results[2], }); 	
	my $iprIpd = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'iqrIpd',  'value' =>  $results[3], }); 	
		
	# get rest of results
	my $sent = undef;
	my $recv = undef;
	# hires results from ping output
	for( my $x = (scalar @$cmdOutput - 2); $x < (scalar @$cmdOutput) ; $x++ ) {
		$logger->debug( "Analysing line: " . $cmdOutput->[$x]);
 		if ( $cmdOutput->[$x] =~ /^(\d+) packets transmitted, (\d+) received/ ) {
			$sent = $1;
			$recv = $2;
        } elsif ( $cmdOutput->[$x] =~ /^rtt min\/avg\/max\/mdev \= (\d+\.\d+)\/(\d+\.\d+)\/(\d+\.\d+)\/\d+\.\d+ ms/ ) {
    		$minRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'minRtt',  'value' =>  $1, }); 
			$meanRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'meanRtt',  'value' =>  $2, }); 
			$maxRtt = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'maxRtt',  'value' =>  $3, }); 
 		}
	}
	
    # loss
    #$logger->fatal( "LOSS: " .  &IEPM::PingER::Statistics::Loss::calculate( $sent, $recv ) );
    my $lossPercent = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    					{ 'name' =>  'lossPercent',  'value' =>  &IEPM::PingER::Statistics::Loss::calculate( $sent, $recv ) || '0.0', });
    
    #$logger->fatal( "CLP: " . &IEPM::PingER::Statistics::Loss::CLP::calculate( $sent, $recv, \@seqs ) );
    my $clp = undef;
	my $clpValue = &IEPM::PingER::Statistics::Loss::CLP::calculate( $sent, $recv, \@seqs );
    perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'clp',  'value' => $clpValue }) if $clpValue;	

	# duplicates
	@results = ();
	@results = &IEPM::PingER::Statistics::Other::calculate( $sent, $recv, \@seqs );
	my $outOfOrder = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    					{ 'name' =>  'outOfOrder',  'value' => $results[0],  });
	my $duplicates = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::Datum->new( 
    				{ 'name' =>  'duplicates',  'value' => $results[1],  });
	
	# set the internal results
	my $commonTime  =  perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data::CommonTime->new( {
							'value' =>  $time,
							'duration' =>  $endtime - $time,
							'type' =>  'unix', 
						});
	# add the datums to the commonTime
	$commonTime->datum( @singletons );
	$commonTime->addDatum( $minRtt );	
	$commonTime->addDatum( $meanRtt );
	$commonTime->addDatum( $maxRtt );
	$commonTime->addDatum( $minIpd );	
	$commonTime->addDatum( $meanIpd );
	$commonTime->addDatum( $maxIpd );	
	$commonTime->addDatum( $iprIpd );
	$commonTime->addDatum( $lossPercent );
	$commonTime->addDatum( $clp ) if $clpValue;
	$commonTime->addDatum( $outOfOrder );
	$commonTime->addDatum( $duplicates );
	
	# store it internally
	$self->results( $commonTime );

	return 0;
}

=header2 toAPI

casts the data (results()) into maxim's api to easy casting etc.

=cut
sub toAPI
{
	my $self = shift;
	
	# create the metadata element
	# create the subject
# nmtl3
#	my $src = perfSONAR_PS::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Src->new(
#				{ 'value' =>  'SOURCE_NODE',  'type' =>  'ipv4'	});
#	my $dst = perfSONAR_PS::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Dst->new(
#				{ 'value' =>  $self->destination(),  'type' =>  'ipv4'	});	
#	my $endpoints = new perfSONAR_PS::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair();
#	$endpoints->src( $src );
#	$endpoints->dst( $dst );
	# nmtl3 interface
	my $src = $self->createInterface( 'src', $self->source(), $self->sourceIp() );
	my $dst = $self->createInterface( 'dst', $self->destination(), $self->destinationIp() );

	my $endpoints = perfSONAR_PS::Datatypes::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair->new();
	$endpoints->endPoint( [$src, $dst ] );
	
	my $subject = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Subject->new({
			#'metadataIdRef' =>  'valuemetadataIdRef',
			'id' =>  '#id',
		});
	$subject->endPointPair( $endpoints );
	
	# setup parameters
	my $parameters = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Parameters->new();
	my @params = ();
	my $param = undef;
	$param = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter->new({
					'name' => 'count' });
	$param->text( $self->count() );
	push @params, $param;
	$param = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter->new({
					'name' => 'packetSize' });
	$param->text( $self->packetSize() );
	push @params, $param;
	$param = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter->new({
					'name' => 'interval' });
	$param->text( $self->interval() );
	push @params, $param;
	$param = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter->new({
					'name' => 'ttl' });
	$param->text( $self->ttl() );
	push @params, $param;
	
	# add the params to the parameters
	$parameters->parameter( @params );
	
	# finally set metadata
	my $metadata = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata->new( 
					{ 'id' => '#metadata' });
	$metadata->subject( $subject );
	$metadata->parameters( $parameters );
	# add event type
	my $eventType = perfSONAR_PS::Datatypes::EventTypes->new();
	$metadata->eventType( $eventType->tools->pinger );
	#$logger->fatal("META: " . $metadata->asString() );
	
	# create the data element
	my $data = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data->new({
					'metadataIdRef' =>  '#metadata',
					'id' =>  '#data',
	});
	$data->commonTime( [$self->results()] );
	#$logger->fatal("DATA: " . $data->asString() );
	
	# create the message
	my $message = perfSONAR_PS::Datatypes::v2_0::nmwg::Message->new(
						{	'type' =>  'Store',
							'id' =>  '#message', });
	$message->metadata( [$metadata] );	
	$message->data( [$data] );			
	
	return $message;
}


=head2 toDOM()

returns the object as a LibXML dom

=cut
sub toDOM {
	my $self = shift;
	my $message = $self->toAPI();
	#$logger->fatal("ALL: " . $message->asString() );	
	return $message->getDOM();
}


sub createInterface
{
	my $self = shift;
	my $role = shift;
	my $dns = shift;
	my $ip = shift;
	
	my $interface = perfSONAR_PS::Datatypes::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface->new( {
							'id' => '#' . $role
						});
	my $ip = perfSONAR_PS::Datatypes::v2_0::nmtl3::Message::Metadata::Subject::EndPointPair::EndPoint::Interface::IpAddress->new( {
							'value' =>  $ip,
							'type'  =>  'IPv4', 
						});
	$interface->ipAddress( $ip );
	$interface->ifHostName( $dns );
		
	my $src = perfSONAR_PS::Datatypes::v2_0::nmtl4::Message::Metadata::Subject::EndPointPair::EndPoint->new({
				'protocol' =>  'ICMP',
				'role' =>  $role,
				});
	$src->interface( $interface );
	
	$logger->debug("INTERFACE: " . $interface->asString() );
	return $src;
}

1;


package perfSONAR_PS::Services::MP::TracerouteOnDemandMP;

use strict;
use warnings;

our $VERSION = 3.3;

use base 'perfSONAR_PS::Services::Base';
use constant TRACEROUTE_EVENT_TYPE => 'http://ggf.org/ns/nmwg/tools/traceroute/2.0';
use constant TRACEROUTE_PREFIX => 'traceroute';
use constant NMWG_NS => 'http://ggf.org/ns/nmwg/base/2.0/';
use constant NMWG_PREFIX => 'nmwg';
use constant NMWGT_NS => 'http://ggf.org/ns/nmwg/topology/2.0/';
use constant NMWGT_PREFIX => 'nmwgt';
use constant DEFAULT_TIMEOUT => 30;
use fields 'LOGGER','NETLOGGER', 'DATADIR', 'TRACE_TIMEOUT';

use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Config::OWP::Conf;
use perfSONAR_PS::Services::MP::TracerouteTest;

use constant PARAM_MAP => { 'firstTtl' => 'first_hop' , 'maxTtl' => 'max_ttl', 'waitTime' => 'query_timeout', 'pause' => 'pause', 'packetSize' => 'packetlen', 'noDataRegister' => 'no_data_register' };

sub init {
    my ( $self, $handler ) = @_;
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MP::TracerouteOnDemandMP" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.init.start");
    $self->{NETLOGGER}->info( $nlmsg );
    
    #Check configuration
    if ( exists $self->{CONF}->{"tracerouteMP"}->{"owmesh"} and $self->{CONF}->{"tracerouteMP"}->{"owmesh"} ) {
        unless ( -d $self->{CONF}->{"tracerouteMP"}->{"owmesh"} ) {           
            my($filename, $dirname) = fileparse( $self->{CONF}->{"tracerouteMP"}->{"owmesh"} );
            if ( $filename and lc( $filename ) eq "owmesh.conf" ) {
                $self->{LOGGER}->info( "The 'owmesh' value was set to '" . $self->{CONF}->{"tracerouteMP"}->{"owmesh"} . "', which is not a directory; converting to '" . $dirname . "'." );
                $self->{CONF}->{"tracerouteMP"}->{"owmesh"} = $dirname;
            }
            else {
                $self->{LOGGER}->fatal( "Value for 'owmesh' is '" . $self->{CONF}->{"tracerouteMP"}->{"owmesh"} . "', please set to the *directory* that contains the owmesh.conf file" );
                $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.init.end", { status => -1, msg => "owmesh not a directory" });
                $self->{NETLOGGER}->fatal( $nlmsg );
                return -1;
            }
        }
        if ( exists $self->{DIRECTORY} and $self->{DIRECTORY} and -d $self->{DIRECTORY} ) {
            unless ( $self->{CONF}->{"tracerouteMP"}->{"owmesh"} =~ "^/" ) {
                $self->{LOGGER}->warn( "Setting value for 'owmesn' to \"" . $self->{DIRECTORY} . "/" . $self->{CONF}->{"tracerouteMP"}->{"owmesh"} . "\"" );
                $self->{CONF}->{"tracerouteMP"}->{"owmesh"} = $self->{DIRECTORY} . "/" . $self->{CONF}->{"tracerouteMP"}->{"owmesh"};
            }
        }        
    }
    else {
        $self->{LOGGER}->fatal( "Value for 'owmesh' is not set." );
         $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.init.end", { status => -1, msg => "owmesh not set" });
                $self->{NETLOGGER}->fatal( $nlmsg );
        return -1;
    }
    
    $self->{'TRACE_TIMEOUT'} = DEFAULT_TIMEOUT;
    if ( exists $self->{CONF}->{"tracerouteMP"}->{"traceroute_timeout"} && $self->{CONF}->{"tracerouteMP"}->{"traceroute_timeout"}){
        $self->{'TRACE_TIMEOUT'} = $self->{CONF}->{"tracerouteMP"}->{"traceroute_timeout"};
    }
    
    my %defaults = (
        CONFDIR => $self->{CONF}->{"tracerouteMP"}->{"owmesh"}
    );
    my $conf = new perfSONAR_PS::Config::OWP::Conf( %defaults );
    $self->{DATADIR} = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DATADIR" } );
    
    #Register handlers
    $handler->registerMessageHandler( "SetupDataRequest",   $self );
    
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.init.end");
    $self->{NETLOGGER}->info( $nlmsg );
    
    return 0;
}

=head2 needLS($self {})

This particular service (traceroute MA) should register with a lookup
service.  This function simply returns the value set in the configuration file
(either yes or no, depending on user preference) to let other parts of the
framework know if LS registration is required.

=cut

sub needLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );
    
    return 0;
    #return ( $self->{CONF}->{"tracerouteMP"}->{enable_registration} or $self->{CONF}->{enable_registration} );
}

=head2 handleMessageBegin($self, { ret_message, messageId, messageType, msgParams, request, retMessageType, retMessageNamespaces })

Stub function that is currently unused.
=cut

sub handleMessageBegin {
    my ( $self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces ) = @_;

    return 0;
}

=head2 handleMessageEnd($self, { ret_message, messageId })

Stub function that is currently unused.

=cut

sub handleMessageEnd {
    my ( $self, $ret_message, $messageId ) = @_;

    return 0;
}

=head2 handleEvent($self, { output, messageId, messageType, messageParameters, eventType, subject, filterChain, data, rawRequest, doOutputMetadata })

Current workaround to the daemons message handler.  All messages that enter
will be routed based on the message type.  The appropriate solution to this
problem is to route on eventType and message type and will be implemented in
future releases.

=cut

sub handleEvent {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            output            => 1,
            messageId         => 1,
            messageType       => 1,
            messageParameters => 1,
            eventType         => 1,
            subject           => 1,
            filterChain       => 1,
            data              => 1,
            rawRequest        => 1,
            doOutputMetadata  => 1,
        }
    );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.handleEvent.start", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}});
    $self->{NETLOGGER}->debug( $nlmsg );
    
    my @subjects = @{ $parameters->{subject} };
    my @filters  = @{ $parameters->{filterChain} };
    my $md       = $subjects[0];
    
    #Get the time settings
    my $timeSettings = getFilterParameters( { m => $md, namespaces => $parameters->{rawRequest}->getNamespaces() } );
    if ( $#filters > -1 ) {
        foreach my $filter_arr ( @filters ) {
            my @filters = @{$filter_arr};
            my $filter  = $filters[-1];
            $timeSettings = getFilterParameters( { m => $filter, namespaces => $parameters->{rawRequest}->getNamespaces() } );
        }
    }
    
    # this module outputs its own metadata so it needs to turn off the daemon's
    # metadata output routines.
    ${ $parameters->{doOutputMetadata} } = 0;
    
    $parameters->{eventType} =~ s/\/$//; #remove trailing slashes
    if($parameters->{eventType} ne TRACEROUTE_EVENT_TYPE){
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid event type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid eventType given " . $parameters->{eventType} );
    }
    
    if($parameters->{messageType} eq 'SetupDataRequest'){
        $self->maSetupDataRequest({ output => $parameters->{output},
                                    metadata => $md, 
                                    time_settings => $timeSettings,
                                    message_parameters => $parameters->{messageParameters}
                                 });
    }else{
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid message type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid message type given " . $parameters->{messageType} );
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.handleEvent.end", );
    $self->{NETLOGGER}->debug( $nlmsg );
}

sub maSetupDataRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            output             => 1,
            metadata           => 1,
            time_settings      => 1,
            message_parameters => 1
        }
    );
    
    #init
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.start");
    $self->{NETLOGGER}->debug( $nlmsg );
   
    #parse parameters
    my %trace_test_params = ();
    $trace_test_params{'timeout'} = $self->{'TRACE_TIMEOUT'};
    
    my $srcDOM = find( $parameters->{metadata}, "./*[local-name()='subject']/*[local-name()='endPointPair']/*[local-name()='src']", 1 );
    my $src = extract( $srcDOM, 0 )  if(defined $srcDOM);
    if($src && $src =~ /^([A-Za-z0-9][A-Za-z0-9\-\.]+)$/){
        $trace_test_params{'source_address'} =  $1 ;
    }else{
        my $msg = "Invalid source address given $src";
        $self->{LOGGER}->error( $msg );
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.end", {status => -1, msg => $msg});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.mp.traceroute_error", $msg );
    }
    my $dstDOM = find( $parameters->{metadata}, "./*[local-name()='subject']/*[local-name()='endPointPair']/*[local-name()='dst']", 1 );
    unless(defined $dstDOM && $dstDOM){
        my $msg = "A destination address must be specified";
        $self->{LOGGER}->error( $msg );
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.end", {status => -1, msg => $msg});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.mp.invalid_input", $msg );
    }
    my $dst = extract( $dstDOM, 0 );
    if($dst && $dst =~ /^([A-Za-z0-9][A-Za-z0-9\-\.]+)$/){
        $trace_test_params{'host'} =  $1 ;
    }else{
        my $msg = "Invalid destination address given $dst";
        $self->{LOGGER}->error( $msg );
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.end", {status => -1, msg => $msg});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.mp.traceroute_error", $msg );
    }
    
    my $param_map = PARAM_MAP;
    foreach my $param( keys %{$param_map} ){
        #NOTE: All parameters are currently numeric so check if numeric to untaint
        #     May need to change this if non-numeric options added
        if(defined $parameters->{message_parameters}->{$param} && $parameters->{message_parameters}->{$param} =~ /^(\d+)$/){
            $trace_test_params{ $param_map->{$param} } = $1;
        }
    }
    
    #run traceroute
    eval{
        my $tracerouteTest = new perfSONAR_PS::Services::MP::TracerouteTest(undef, $self->{DATADIR}, \%trace_test_params);
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.start", \%trace_test_params);
        $self->{NETLOGGER}->debug($nlmsg);
        my $data = $tracerouteTest->run();
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.end");
        $self->{NETLOGGER}->debug($nlmsg);
        $parameters->{output}->addExistingXMLElement( $tracerouteTest->getMetaData() );
        $parameters->{output}->addExistingXMLElement( $data );
    };
    if($@){
        my $msg = "Error running traceroute: " . $@;
        $self->{LOGGER}->error( $msg );
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.end", {status => -1, , msg => $msg});
        $self->{NETLOGGER}->debug($nlmsg);
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.end", {status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.mp.traceroute_error", $msg );
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteOnDemandMP.maSetupDataRequest.end");
    $self->{NETLOGGER}->debug( $nlmsg );
}

#Copied from pSB MA
sub confHierarchy {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { conf => 1, type => 1, variable => 1 } );

    if ( exists $parameters->{conf}->{ $parameters->{variable} } and $parameters->{conf}->{ $parameters->{variable} } ) {
        return $parameters->{conf}->{ $parameters->{variable} };
    }
    elsif ( exists $parameters->{conf}->{ $parameters->{type} . $parameters->{variable} } and $parameters->{conf}->{ $parameters->{type} . $parameters->{variable} } ) {
        return $parameters->{conf}->{ $parameters->{type} . $parameters->{variable} };
    }
    elsif ( exists $parameters->{conf}->{ "CENTRAL" . $parameters->{variable} } and $parameters->{conf}->{ "CENTRAL" . $parameters->{variable} } ) {
        return $parameters->{conf}->{ "CENTRAL" . $parameters->{variable} };
    }
    elsif ( exists $parameters->{conf}->{ $parameters->{type} . "CENTRAL" . $parameters->{variable} } and $parameters->{conf}->{ $parameters->{type} . "CENTRAL" . $parameters->{variable} } ) {
        return $parameters->{conf}->{ $parameters->{type} . "CENTRAL" . $parameters->{variable} };
    }
    return;

}

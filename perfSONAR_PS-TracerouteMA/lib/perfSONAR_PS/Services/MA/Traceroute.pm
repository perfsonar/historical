package perfSONAR_PS::Services::MA::Traceroute;

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
use constant METADATA_PARAMS => ['firstTtl', 'maxTtl', 'waitTime', 'pause', 'packetSize', 'numBytes', 'arguments'];
use fields 'LOGGER','NETLOGGER', 'DB_PARAMS', 'LS_CLIENT', 'LS_URL';

use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Utils::MARegistrationManager;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Config::OWP::Conf;
use perfSONAR_PS::DB::SQL;
use SimpleLookupService::Client::Bootstrap;

sub init {
    my ( $self, $handler ) = @_;
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MA::Traceroute" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.init.start");
    $self->{NETLOGGER}->info( $nlmsg );
    
    #Check configuration
    if ( exists $self->{CONF}->{"tracerouteMA"}->{"owmesh"} and $self->{CONF}->{"tracerouteMA"}->{"owmesh"} ) {
        unless ( -d $self->{CONF}->{"tracerouteMA"}->{"owmesh"} ) {           
            my($filename, $dirname) = fileparse( $self->{CONF}->{"tracerouteMA"}->{"owmesh"} );
            if ( $filename and lc( $filename ) eq "owmesh.conf" ) {
                $self->{LOGGER}->info( "The 'owmesh' value was set to '" . $self->{CONF}->{"tracerouteMA"}->{"owmesh"} . "', which is not a directory; converting to '" . $dirname . "'." );
                $self->{CONF}->{"tracerouteMA"}->{"owmesh"} = $dirname;
            }
            else {
                $self->{LOGGER}->fatal( "Value for 'owmesh' is '" . $self->{CONF}->{"tracerouteMA"}->{"owmesh"} . "', please set to the *directory* that contains the owmesh.conf file" );
                $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.init.end", { status => -1, msg => "owmesh not a directory" });
                $self->{NETLOGGER}->fatal( $nlmsg );
                return -1;
            }
        }
        if ( exists $self->{DIRECTORY} and $self->{DIRECTORY} and -d $self->{DIRECTORY} ) {
            unless ( $self->{CONF}->{"tracerouteMA"}->{"owmesh"} =~ "^/" ) {
                $self->{LOGGER}->warn( "Setting value for 'owmesn' to \"" . $self->{DIRECTORY} . "/" . $self->{CONF}->{"tracerouteMA"}->{"owmesh"} . "\"" );
                $self->{CONF}->{"tracerouteMA"}->{"owmesh"} = $self->{DIRECTORY} . "/" . $self->{CONF}->{"tracerouteMA"}->{"owmesh"};
            }
        }        
    }
    else {
        $self->{LOGGER}->fatal( "Value for 'owmesh' is not set." );
         $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.init.end", { status => -1, msg => "owmesh not set" });
                $self->{NETLOGGER}->fatal( $nlmsg );
        return -1;
    }
    
    #Handle LS Registration
    unless ( exists $self->{CONF}->{"tracerouteMA"}->{enable_registration} ) {
        if ( exists $self->{CONF}->{enable_registration} and $self->{CONF}->{enable_registration} ) {
            $self->{CONF}->{"tracerouteMA"}->{enable_registration} = $self->{CONF}->{enable_registration};
        }
        else {
            $self->{CONF}->{enable_registration} = 0;
            $self->{CONF}->{"tracerouteMA"}->{enable_registration} = 0;
        }
        $self->{LOGGER}->warn( "Setting 'enable_registration' to \"" . $self->{CONF}->{"tracerouteMA"}->{enable_registration} . "\"." );
    }

    if ( $self->{CONF}->{"tracerouteMA"}->{"enable_registration"} ) {
    
        
        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"ls_bootstrap_file"}
            and $self->{CONF}->{"tracerouteMA"}->{"ls_bootstrap_file"} )
        {
            if ( defined $self->{CONF}->{"ls_bootstrap_file"}
                and $self->{CONF}->{"ls_bootstrap_file"} )
            {
                $self->{LOGGER}->warn( "Setting \"ls_bootstrap_file\" to \"" . $self->{CONF}->{"ls_bootstrap_file"} . "\"" );
                $self->{CONF}->{"tracerouteMA"}->{"ls_bootstrap_file"} = $self->{CONF}->{"ls_bootstrap_file"};
            }
        }

        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"ls_registration_interval"}
            and $self->{CONF}->{"tracerouteMA"}->{"ls_registration_interval"} )
        {
            if ( defined $self->{CONF}->{"ls_registration_interval"}
                and $self->{CONF}->{"ls_registration_interval"} )
            {
                $self->{LOGGER}->warn( "Setting \"ls_registration_interval\" to \"" . $self->{CONF}->{"ls_registration_interval"} . "\"" );
                $self->{CONF}->{"tracerouteMA"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
            }
            else {
                $self->{LOGGER}->warn( "Setting registration interval to 4 hours" );
                $self->{CONF}->{"tracerouteMA"}->{"ls_registration_interval"} = 14400;
            }
        }

        if ( not $self->{CONF}->{"tracerouteMA"}->{"service_accesspoint"} ) {
            unless ( $self->{CONF}->{external_address} ) {
                $self->{LOGGER}->fatal( "With LS registration enabled, you need to specify either the service accessPoint for the service or the external_address" );
                return -1;
            }
            $self->{LOGGER}->info( "Setting service access point to http://" . $self->{CONF}->{external_address} . ":" . $self->{PORT} . $self->{ENDPOINT} );
            $self->{CONF}->{"tracerouteMA"}->{"service_accesspoint"} = "http://" . $self->{CONF}->{external_address} . ":" . $self->{PORT} . $self->{ENDPOINT};
        }

        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"service_description"}
            and $self->{CONF}->{"tracerouteMA"}->{"service_description"} )
        {
            my $description = "perfSONAR_PS Traceroute MA";
            if ( $self->{CONF}->{site_name} ) {
                $description .= " at " . $self->{CONF}->{site_name};
            }
            if ( $self->{CONF}->{site_location} ) {
                $description .= " in " . $self->{CONF}->{site_location};
            }
            $self->{CONF}->{"tracerouteMA"}->{"service_description"} = $description;
            $self->{LOGGER}->warn( "Setting 'service_description' to '$description'." );
        }

        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"service_name"}
            and $self->{CONF}->{"tracerouteMA"}->{"service_name"} )
        {
            $self->{CONF}->{"tracerouteMA"}->{"service_name"} = "Traceroute MA";
            $self->{LOGGER}->warn( "Setting 'service_name' to 'Traceroute MA'." );
        }

        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"service_type"}
            and $self->{CONF}->{"tracerouteMA"}->{"service_type"} )
        {
            $self->{CONF}->{"tracerouteMA"}->{"service_type"} = "MA";
            $self->{LOGGER}->warn( "Setting 'service_type' to 'MA'." );
        }
        
        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"}
            and $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"} )
        {
            $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"} = $self->{CONF}->{"ls_key_db"};
            $self->{LOGGER}->warn( "Setting 'ls_key_db' to " . $self->{CONF}->{"ls_key_db"});
        }
        
        #initialize the key database
        if ( not $self->{CONF}->{"ls_key_db"} ) {
            $self->{CONF}->{"ls_key_db"} = '/var/lib/perfsonar/traceroute_ma/lsKey.db';
        }
        unless ( exists $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"}
            and $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"} )
        {
            $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"} = $self->{CONF}->{"ls_key_db"};
            $self->{LOGGER}->warn( "Setting 'ls_key_db' to " . $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"});
        }
        
        #set site parameters
        $self->_mergeSiteConfig('site_project');
        $self->_mergeSiteConfig('site_name');
        $self->_mergeSiteConfig('domain');
        $self->_mergeSiteConfig('city');
        $self->_mergeSiteConfig('region');
        $self->_mergeSiteConfig('country');
        $self->_mergeSiteConfig('zip_code');
        $self->_mergeSiteConfig('latitude');
        $self->_mergeSiteConfig('longitude');
        $self->_mergeSiteConfig('full_name');
        $self->_mergeSiteConfig('administrator_email');
    }
    
    #Register handlers
    $handler->registerMessageHandler( "SetupDataRequest",   $self );
    $handler->registerMessageHandler( "MetadataKeyRequest", $self );
    
    #Initializing database parameters
    my %defaults = (
        DBHOST  => "localhost",
        CONFDIR => $self->{CONF}->{"tracerouteMA"}->{"owmesh"}
    );
    my $conf = new perfSONAR_PS::Config::OWP::Conf( %defaults );
    my $dbtype = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DBTYPE" } );
    my $dbname = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DBNAME" } );
    my $dbhost = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DBHOST" } );
    my $dbuser   = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DBUSER" } );
    my $dbpass   = $self->confHierarchy( { conf => $conf, type => "TRACE", variable => "DBPASS" } );
    my %db_params = (name => $dbtype . ":" . $dbname . ":" . $dbhost,
                     user => $dbuser, 
                     pass => $dbpass);
    $self->{DB_PARAMS} = \%db_params;
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.init.end");
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
    
    return ( $self->{CONF}->{"tracerouteMA"}->{enable_registration} or $self->{CONF}->{enable_registration} );
}

=head2 _chooseLS($self {})

Determines the LS URL to use when registering

=cut
sub _chooseLS {
    my ( $self ) = @_;
    
    if( exists $self->{CONF}->{"tracerouteMA"}->{"ls_instance"}
            and $self->{CONF}->{"tracerouteMA"}->{"ls_instance"} ) {
        $self->{LS_URL} = $self->{CONF}->{"tracerouteMA"}->{"ls_instance"};
    }elsif( defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ) {
        $self->{LS_URL} = $self->{CONF}->{"ls_instance"};
    }else {
        my $ls_bootstrap = SimpleLookupService::Client::Bootstrap->new();
        if($self->{CONF}->{"tracerouteMA"}->{"ls_bootstrap_file"}){
            $ls_bootstrap->init(file => $self->{CONF}->{"tracerouteMA"}->{"ls_bootstrap_file"});
        }else{
            $ls_bootstrap->init();
        }
        $self->{LS_URL} = $ls_bootstrap->register_url();
    }
}

sub registerLS {
    my $self = shift;
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.registerLS.start");
    $self->{NETLOGGER}->info( $nlmsg );
    
    #Query database to build test set
    my $dbh = new perfSONAR_PS::DB::SQL( { name => $self->{DB_PARAMS}->{name}, user => $self->{DB_PARAMS}->{user}, pass => $self->{DB_PARAMS}->{pass} } );
    $dbh->openDB;
    my ($test_set,$interfaces) = $self->buildTestSet(dbh => $dbh);
    $dbh->closeDB;
    
    #Build service registration
    my @event_types_list = ( TRACEROUTE_EVENT_TYPE );
    my @ma_types_list = ( 'traceroute' );
    my $service_params = { 
                      serviceLocator => $self->{CONF}->{"tracerouteMA"}->{"service_accesspoint"}, 
                      serviceType => 'ma', 
     				  serviceName => $self->{CONF}->{"tracerouteMA"}->{"service_name"}, 
     				  eventTypes => \@event_types_list,
     				  maTypes => \@ma_types_list,
 					 };
    $service_params->{'communities'} = $self->{CONF}->{"tracerouteMA"}->{"site_project"} if($self->{CONF}->{"tracerouteMA"}->{"site_project"});
    $service_params->{'site_name'} = $self->{CONF}->{"tracerouteMA"}->{"site_name"} if($self->{CONF}->{"tracerouteMA"}->{"site_name"});
 	$service_params->{'domains'} = $self->{CONF}->{"tracerouteMA"}->{"domain"} if($self->{CONF}->{"tracerouteMA"}->{"domain"});
 	$service_params->{'city'} = $self->{CONF}->{"tracerouteMA"}->{"city"} if($self->{CONF}->{"tracerouteMA"}->{"city"});
 	$service_params->{'region'} = $self->{CONF}->{"tracerouteMA"}->{"region"} if($self->{CONF}->{"tracerouteMA"}->{"region"});
 	$service_params->{'country'} = $self->{CONF}->{"tracerouteMA"}->{"country"} if($self->{CONF}->{"tracerouteMA"}->{"country"});
 	$service_params->{'zip_code'} = $self->{CONF}->{"tracerouteMA"}->{"zip_code"} if($self->{CONF}->{"tracerouteMA"}->{"zip_code"});
 	$service_params->{'latitude'} = $self->{CONF}->{"tracerouteMA"}->{"latitude"} if($self->{CONF}->{"tracerouteMA"}->{"latitude"});
 	$service_params->{'longitude'} = $self->{CONF}->{"tracerouteMA"}->{"longitude"} if($self->{CONF}->{"tracerouteMA"}->{"longitude"});
    #setup administrator
    my $administrator = 0;
    if($self->{CONF}->{"tracerouteMA"}->{"full_name"} ||
        $self->{CONF}->{"tracerouteMA"}->{"administrator_email"}){
        my $name = $self->{CONF}->{"tracerouteMA"}->{"full_name"} ? $self->{CONF}->{"tracerouteMA"}->{"full_name"} : $self->{CONF}->{"tracerouteMA"}->{"administrator_email"};
        $administrator = {
            name => $name,
            email => $self->{CONF}->{"tracerouteMA"}->{"administrator_email"}
        };
    }

    #Register 
    #determine LS
    $self->_chooseLS() if(!defined $self->{LS_URL});
    unless($self->{LS_URL}){
        $self->{LOGGER}->warn("Unable to determine LS, skipping registration for now") unless($self->{LS_URL});
        return 0;
    }
    #handle if array for backward compatibility
    my @ls_array = ();
    my @array = split( /\s+/, $self->{LS_URL} );
    foreach my $l ( @array ) {
        $l =~ s/(\s|\n)*//g;
        push @ls_array, $l if $l;
    }
    #create client
    if(!defined $self->{LS_CLIENT}){
        $self->{LS_CLIENT} = perfSONAR_PS::Utils::MARegistrationManager->new();
        $self->{LS_CLIENT}->init(ls_url => $ls_array[0], ls_key_db => $self->{CONF}->{"tracerouteMA"}->{"ls_key_db"});
    }
    $self->{LS_CLIENT}->register(service_params => $service_params, interfaces => $interfaces, test_set => $test_set, administrator => $administrator);
 
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.registerLS.end");
    $self->{NETLOGGER}->info( $nlmsg );
    
    return 0;
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
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.handleEvent.start", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}});
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
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid event type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid eventType given " . $parameters->{eventType} );
    }
    
    if($parameters->{messageType} eq 'SetupDataRequest'){
        $self->maSetupDataRequest({ output => $parameters->{output},
                                    metadata => $md, 
                                    time_settings => $timeSettings,
                                    message_parameters => $parameters->{messageParameters}
                                 });
    }elsif($parameters->{messageType} eq 'MetadataKeyRequest'){
        $self->maMetaDataKeyRequest({ output => $parameters->{output},
                                    metadata => $md, 
                                    time_settings => $timeSettings,
                                    message_parameters => $parameters->{messageParameters}
                                 });
    }else{
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid message type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid message type given " . $parameters->{messageType} );
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.handleEvent.end", );
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
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maSetupDataRequest.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my $dbh = new perfSONAR_PS::DB::SQL( { name => $self->{DB_PARAMS}->{name}, user => $self->{DB_PARAMS}->{user}, pass => $self->{DB_PARAMS}->{pass} } );
    $dbh->openDB;
    
    #generate metadata
    my ($md_success, $tspec_map, $tspec_keys, $dateList) = $self->buildMetaData({
            output             => $parameters->{output},
            metadata           => $parameters->{metadata},
            time_settings      => $parameters->{time_settings},
            message_parameters => $parameters->{message_parameters},
            dbh => $dbh
    });
    unless($md_success){
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maSetupDataRequest.end", {status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        return;
    }
    
    # get the data
    my $meashops_sql = "";
    my @hops_attrs = ( 'timeValue', 'ttl', 'hop', 'queryNum', 'numBytes', 'value' );
    my $hop_attr_offset = 2;
    my $startTime = $parameters->{time_settings}->{START}->{value};
    my $endTime = $parameters->{time_settings}->{END}->{value};
    for(my $date_i = 0; $date_i < @{$dateList}; $date_i++){
        $meashops_sql .= " UNION " if($date_i > 0);
        $meashops_sql .= "(SELECT m.id, m.testspec_key, m.timestamp, h.ttl, h.addr, h.queryNum, h.numBytes, h.delay";
        $meashops_sql .= " FROM " .  $dateList->[$date_i] . "_HOPS AS h";
        $meashops_sql .= " INNER JOIN " . $dateList->[$date_i] . "_MEASUREMENT AS m ON m.id = h.measurement_id";
        $meashops_sql .= " WHERE m.testspec_key IN ($tspec_keys)";
        $meashops_sql .= " AND m.timestamp >= $startTime" if($startTime);
        $meashops_sql .= " AND m.timestamp <= $endTime" if($endTime);
        $meashops_sql .= " ORDER BY m.id";
        $meashops_sql .= ")";
    }
    
    my $meashops_results = $dbh->query( { query => "$meashops_sql" } );
    my $prev_m_id = '';
    for(my $meas_i= 0; $meas_i < @{$meashops_results}; $meas_i++){
        if($prev_m_id ne $meashops_results->[$meas_i]->[0]){
            endData($parameters->{output}) if($prev_m_id);
            $prev_m_id = '';
        }
        if($prev_m_id eq ''){
            startData($parameters->{output}, 'data.'.$meashops_results->[$meas_i]->[1].'.'.$meas_i, 'meta.'. $meashops_results->[$meas_i]->[1]);
            $prev_m_id = $meashops_results->[$meas_i]->[0];
            $tspec_map->{$meashops_results->[$meas_i]->[1]} = 1;
        }
        my %hopAttrMap = ();
        $hopAttrMap{'timeType'} = 'unix';
        $hopAttrMap{'valueUnits'} = 'ms';
        for (my $hop_attr_i = 0; $hop_attr_i < @hops_attrs; $hop_attr_i++){
            $hopAttrMap{$hops_attrs[$hop_attr_i]} = $meashops_results->[$meas_i]->[$hop_attr_offset+ $hop_attr_i];
        }
        $parameters->{output}->createElement(
                    prefix     => TRACEROUTE_PREFIX,
                    namespace  => TRACEROUTE_EVENT_TYPE,
                    tag        => "datum",
                    attributes => \%hopAttrMap
                );
        
    }
    endData($parameters->{output}) if($prev_m_id);
    
    #create empty data elements for metadata with no results
    foreach my $tspec_map_key(keys %{$tspec_map}){
        if($tspec_map->{$tspec_map_key} == 0){
            my $msg = "Query returned 0 results";
            getResultCodeData( $parameters->{output}, 'data.' . $tspec_map_key . '.empty', 'meta.' . $tspec_map_key, $msg, 1 );
        }
    }
    
    $dbh->closeDB;
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maSetupDataRequest.end");
    $self->{NETLOGGER}->debug( $nlmsg );
}

sub maMetaDataKeyRequest {
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
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maMetaDataKeyRequest.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my $dbh = new perfSONAR_PS::DB::SQL( { name => $self->{DB_PARAMS}->{name}, user => $self->{DB_PARAMS}->{user}, pass => $self->{DB_PARAMS}->{pass} } );
    $dbh->openDB;
    
    #generate metadata
    my ($md_success, $tspec_map, $tspec_keys, $dateList) = $self->buildMetaData({
            output             => $parameters->{output},
            metadata           => $parameters->{metadata},
            time_settings      => $parameters->{time_settings},
            message_parameters => $parameters->{message_parameters},
            dbh => $dbh
    });
    unless($md_success){
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maMetaDataKeyRequest.end", {status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        return;
    }
    
    #use keys to generate data
    foreach my $tspec_key( keys %{$tspec_map} ){
        startData($parameters->{output}, "data.$tspec_key", "meta.$tspec_key");
        $parameters->{output}->startElement(
                    prefix     => NMWG_PREFIX,
                    namespace  => NMWG_NS,
                    tag        => "key"
                );
        startParameters( $parameters->{output}, "params.$tspec_key");
        addParameter($parameters->{output}, 'maKey', $tspec_key);
        addParameter($parameters->{output}, 'startTime',  $parameters->{time_settings}->{START}->{value}) if($parameters->{time_settings}->{START}->{value});
        addParameter($parameters->{output}, 'endTime',  $parameters->{time_settings}->{END}->{value}) if($parameters->{time_settings}->{END}->{value});
        endParameters( $parameters->{output} );
        $parameters->{output}->endElement("key");
        endData($parameters->{output});
    }
    
    $dbh->closeDB;    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.maMetaDataKeyRequest.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    
}

sub buildMetaData{
    my ( $self, @args ) = @_;
    my $METADATA_PARAMS = METADATA_PARAMS();
    my $parameters = validateParams(
        @args,
        {
            output             => 1,
            dbh => 1,
            metadata           => 0,
            time_settings      => 0,
            message_parameters => 0,
            
        }
    );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    #Check the subject and add to where clause
    my $testSpecWhere = "";
    #If given metadata from a query then parse it and build a where clause
    if(exists $parameters->{metadata} && $parameters->{metadata}){
        my $nmwg_key = find( $parameters->{metadata}, "./nmwg:key", 1 );
        my $endPointPair = find( $parameters->{metadata}, "./*[local-name()='subject']/*[local-name()='endPointPair']", 1 );
        if ( $nmwg_key ) {
            my $maKey = extract( find( $nmwg_key, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
            unless ( $maKey ) {
                my $msg = "Key error in metadata storage: cannot find 'maKey' in request message.";
                $self->{LOGGER}->error( $msg );
                $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.end", {status => -1, msg => $msg});
                $self->{NETLOGGER}->debug( $nlmsg );
                throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
                return (0, undef, undef, undef);
            }
            $testSpecWhere .= "WHERE subjKey='$maKey'";
        }elsif( $endPointPair ){
            my $srcDOM = find( $endPointPair, "./*[local-name()='src']", 1 );
            my $src = extract( $srcDOM, 0 );
            my $dstDOM = find( $endPointPair, "./*[local-name()='dst']", 1 );
            my $dst = extract( $dstDOM, 0 );
            $testSpecWhere .= " WHERE" if( $src || $dst );
            $testSpecWhere .= " src='$src'" if( $src );
            $testSpecWhere .= " AND" if( $src && $dst );
            $testSpecWhere .= " dst='$dst'" if( $dst );
            my $hasParam = 0;
            foreach my $req_param(@{ $METADATA_PARAMS }){
                if($parameters->{message_parameters}->{$req_param}){
                    $testSpecWhere .= " AND" if( $src || $dst || $hasParam);
                    $testSpecWhere .= " $req_param='" . $parameters->{message_parameters}->{$req_param} ."'";
                    $hasParam = 1;
                }
            }
        }else{
            my $msg = "Invalid subject given";
            my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.end", { status => -1, msg => $msg });
            $self->{NETLOGGER}->debug( $nlmsg );
            throw perfSONAR_PS::Error_compat( "error.ma.subject_type", $msg );
            return (0, undef, undef, undef);
        }
    }
    
    #Determine the time range
    my @dateList = ();
    my $startTime = 0;
    my $endTime = 0;
    if(exists $parameters->{time_settings} && $parameters->{time_settings}){
        $startTime = $parameters->{time_settings}->{START}->{value};
        $endTime = $parameters->{time_settings}->{END}->{value};
    }
    
    #Begin queries
    my $dateSql = 'SELECT year, month, day FROM DATES';
    $dateSql .= ' WHERE' if($startTime || $endTime);
    if($startTime){
        my @time = gmtime($startTime); 
        my $start_year = $time[5] + 1900;
        my $start_month = $time[4]+1;
        my $start_day = $time[3];
        $dateSql .= " (year > $start_year || (year = $start_year && (month > $start_month || month = $start_month && day >= $start_day)))"; 
    }
    $dateSql .= ' AND' if($startTime && $endTime);
    if($endTime){
        my @time = gmtime($endTime); 
        my $end_year = $time[5] + 1900;
        my $end_month =$time[4]+1;
        my $end_day = $time[3];
        $dateSql .= " (year < $end_year || (year = $end_year && (month < $end_month || month = $end_month && day <= $end_day)))"; 
    }
    
    #get the dates
    my $date_results = $parameters->{dbh}->query( { query => "$dateSql" } );
    if(@{$date_results} == 0){
        my $msg = "No data found in given time range";
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.end", { status => -1, msg => $msg });
        $self->{NETLOGGER}->debug( $nlmsg );
         throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return (0, undef, undef, undef);
    }
    foreach my $date_row(@{$date_results}){
        push @dateList, sprintf "%04d%02d%02d", $date_row->[0], $date_row->[1], $date_row->[2];
    }
    
    # get the test specs.
    
    my $testSpecSQL = "";
    for(my $date_i = 0; $date_i < @dateList; $date_i++){
        $testSpecSQL .= " UNION " if($date_i != 0);
        $testSpecSQL .= "(SELECT id, subjKey, srcType, src, dstType, dst, firstTTL, maxTTL, waitTime, pause, packetSize, numBytes, arguments";
        $testSpecSQL .= " FROM " . $dateList[$date_i] . "_TESTSPEC";
        $testSpecSQL .= " $testSpecWhere )";
    }
    
    my $tspec_results = $parameters->{dbh}->query( { query => "$testSpecSQL" } );
    if(@{$tspec_results} == 0){
        my $msg = "No matching tests found";
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.end", { status => -1, msg => $msg });
        $self->{NETLOGGER}->debug( $nlmsg );
         throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return (0, undef, undef, undef);
    }
    my $tspec_keys = '';
    my %tspec_map = ();
    my $PARAM_OFFSET = 6;
    my %namespaces = ( TRACEROUTE_PREFIX() => TRACEROUTE_EVENT_TYPE, NMWG_PREFIX() => NMWG_NS,  NMWGT_PREFIX() => NMWGT_NS);
    foreach my $tspec_row(@{$tspec_results}){
        #don't print the same metadata more than once
        if(exists $tspec_map{$tspec_row->[1]}){
            next;
        }
        $tspec_keys .= ',' if($tspec_keys);
        $tspec_keys .= "'" . $tspec_row->[1] . "'";
        $tspec_map{$tspec_row->[1]} = 0;
        
        startMetadata($parameters->{output}, 'meta.'.$tspec_row->[1] , undef, \%namespaces);
        my %subjAttrs = ( "id"=> 'subj.'.$tspec_row->[1]);
        $parameters->{output}->startElement(
                    prefix     => TRACEROUTE_PREFIX,
                    namespace  => TRACEROUTE_EVENT_TYPE,
                    tag        => "subject",
                    attributes => \%subjAttrs
                );
        $parameters->{output}->startElement(
                    prefix     => NMWGT_PREFIX,
                    namespace  => NMWGT_NS,
                    tag        => "endPointPair"
                );
        my %srcAttrs = ("type" => $tspec_row->[2], "value" => $tspec_row->[3]);
        $parameters->{output}->createElement(
                    prefix     => NMWGT_PREFIX,
                    namespace  => NMWGT_NS,
                    tag        => "src",
                    attributes => \%srcAttrs
                );
        my %dstAttrs = ("type" => $tspec_row->[4], "value" => $tspec_row->[5]);
        $parameters->{output}->createElement(
                    prefix     => NMWGT_PREFIX,
                    namespace  => NMWGT_NS,
                    tag        => "dst",
                    attributes => \%dstAttrs
                );
        $parameters->{output}->endElement("endPointPair");
        $parameters->{output}->endElement("subject");
        $parameters->{output}->createElement(
                    prefix     => NMWG_PREFIX,
                    namespace  => NMWG_NS,
                    tag        => "eventType",
                    content => TRACEROUTE_EVENT_TYPE
                );
        startParameters( $parameters->{output}, 'params.'.$tspec_row->[1]);
        for(my $param_i = 0; $param_i < @{$METADATA_PARAMS}; $param_i++){
            if(defined $tspec_row->[$param_i+$PARAM_OFFSET] && $tspec_row->[$param_i+$PARAM_OFFSET] ne ''){
                addParameter($parameters->{output}, $METADATA_PARAMS->[$param_i], $tspec_row->[$param_i+$PARAM_OFFSET]);
            }
        }
        endParameters( $parameters->{output});
        endMetadata($parameters->{output});
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildMetaData.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    return (1, \%tspec_map, $tspec_keys, \@dateList);
}

sub buildTestSet{
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            dbh => 1,
            
        }
    );
    
    my %test_set = ();
    my @interfaces = ();
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildTestSet.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    #Determine the time range
    my @dateList = ();
    
    #Begin queries
    my $dateSql = 'SELECT year, month, day FROM DATES';
    #get the dates
    my $date_results = $parameters->{dbh}->query( { query => "$dateSql" } );
    if(@{$date_results} == 0){
        my $msg = "No data found in given time range";
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildTestSet.end", { status => -1, msg => $msg });
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return (\%test_set, \@interfaces);
    }
    foreach my $date_row(@{$date_results}){
        push @dateList, sprintf "%04d%02d%02d", $date_row->[0], $date_row->[1], $date_row->[2];
    }
    
    # get the test specs.
    
    my $testSpecSQL = "";
    for(my $date_i = 0; $date_i < @dateList; $date_i++){
        $testSpecSQL .= " UNION " if($date_i != 0);
        $testSpecSQL .= "(SELECT src, dst FROM " . $dateList[$date_i] . "_TESTSPEC)";
    }
    
    my $tspec_results = $parameters->{dbh}->query( { query => "$testSpecSQL" } );
    if(@{$tspec_results} == 0){
        my $msg = "No matching tests found";
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildTestSet.end", { status => -1, msg => $msg });
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return (\%test_set, \@interfaces);
    }
    
    my %unique_interfaces = ();
    foreach my $tspec_row(@{$tspec_results}){
        $self->{LOGGER}->debug("src: " . $tspec_row->[0] . ", dst: " . $tspec_row->[1]);
        $unique_interfaces{$tspec_row->[0]} = 1;
        $unique_interfaces{$tspec_row->[1]} = 1;
        if(!$test_set{$tspec_row->[0]}){
            $test_set{$tspec_row->[0]} = ();
        }
        if(!$test_set{$tspec_row->[0]}{$tspec_row->[1]}){
            my @tmp = ( TRACEROUTE_EVENT_TYPE );
            $test_set{$tspec_row->[0]}{$tspec_row->[1]} = ( \@tmp );
        }
    }
    @interfaces = keys %unique_interfaces;
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MA.Traceroute.buildTestSet.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    return (\%test_set, \@interfaces);
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

=head2 _mergeSiteConfig($self $param)

Merges global site parameter into traceroute MA configuration if it doesn't exist. May
be able to replace with common mergeConfig, but didn't want to conflict with existing 
setters in init.
=cut
sub _mergeSiteConfig() {
    my ($self, $param) = @_;
    
     unless(exists $self->{CONF}->{"tracerouteMA"}->{"$param"} and 
                $self->{CONF}->{"tracerouteMA"}->{"$param"} ) {
        if ( defined $self->{CONF}->{"$param"} and $self->{CONF}->{"$param"} ) {
            $self->{LOGGER}->debug( "Setting \"$param\" to \"" . $self->{CONF}->{"$param"} . "\"" );
            $self->{CONF}->{"tracerouteMA"}->{"$param"} = $self->{CONF}->{"$param"};
        }
    }
}

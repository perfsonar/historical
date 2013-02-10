package perfSONAR_PS::Services::MA::TracerouteCollector;

use strict;
use warnings;

our $VERSION = 3.3;

use base 'perfSONAR_PS::Services::Base';
use constant TRACEROUTE_EVENT_TYPE => 'http://ggf.org/ns/nmwg/tools/traceroute/2.0';
use constant TRACEROUTE_PREFIX => 'traceroute';
use constant METADATA_PARAMS => ['firstTtl', 'maxTtl', 'waitTime', 'pause', 'packetSize', 'numBytes', 'arguments'];
use constant HOP_DB_MAP => {'ttl' => 'ttl', 'addr' => 'hop', 'queryNum' => 'queryNum', 'delay' => 'value'};
use constant HOP_DB_ERR_VALS => { 'delay' => 0 };
use constant HOP_DB_MAP_OPTIONAL => {'numBytes' =>'numBytes'};
use fields 'LOGGER','NETLOGGER', 'DB_PARAMS';

use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Digest::MD5 qw( md5_hex );
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Config::OWP::Conf;
use perfSONAR_PS::DB::SQL;

sub init {
    my ( $self, $handler ) = @_;
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MA::TracerouteCollector" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.init.start");
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
                $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.init.end", { status => -1, msg => "owmesh not a directory" });
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
         $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.init.end", { status => -1, msg => "owmesh not set" });
                $self->{NETLOGGER}->fatal( $nlmsg );
        return -1;
    }
    
    #Register handlers
    $handler->registerMessageHandler( "RegisterDataRequest",   $self );
    
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
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.init.end");
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
    #return ( $self->{CONF}->{"tracerouteMA"}->{enable_registration} or $self->{CONF}->{enable_registration} );
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
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.handleEvent.start", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}});
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
    #${ $parameters->{doOutputMetadata} } = 0;
    
    $parameters->{eventType} =~ s/\/$//; #remove trailing slashes
    if($parameters->{eventType} ne TRACEROUTE_EVENT_TYPE){
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid event type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid eventType given " . $parameters->{eventType} );
    }
    
    if($parameters->{messageType} eq 'RegisterDataRequest'){
        $self->registerData($parameters);
    }else{
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.handleEvent.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> 'Invalid message type', status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( "Invalid message type given " . $parameters->{messageType} );
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.handleEvent.end", );
    $self->{NETLOGGER}->debug( $nlmsg );
}

sub registerData {
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
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my $hop_db_map = HOP_DB_MAP;
    my $hop_db_err_vals = HOP_DB_ERR_VALS;
    my $hop_db_map_optional = HOP_DB_MAP_OPTIONAL;
    my $dbh = new perfSONAR_PS::DB::SQL( { name => $self->{DB_PARAMS}->{name}, user => $self->{DB_PARAMS}->{user}, pass => $self->{DB_PARAMS}->{pass} } );
    $dbh->openDB;
    
    #generate keys
    my ($src, $srcType, $dst, $dstType, $metadata_key) = $self->generate_key({
            messageParameters => $parameters->{messageParameters},
            subject => $parameters->{subject}[0]
       });
    

    my $datum = find( $parameters->{data}, "./*[local-name()='datum']", 0);
    if((! defined $datum) || $datum->size() == 0){
        my $errMsg = "Data does not contain any datum";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    
    #create tables if needed
    my ($table_prefix, $timestamp) = $self->initTables({ datum => $datum, dbh => $dbh });
    
    #determine if tspec exists
    my $tspec_result = $dbh->query({ query => "SELECT id FROM ${table_prefix}_TESTSPEC WHERE subjKey='$metadata_key'" });
    if($tspec_result == -1){
        my $errMsg = "Error looking for test spec";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    if(@{$tspec_result} == 0){
        my %tspec_values = ();
        $tspec_values{'subjKey'} = $metadata_key;
        $tspec_values{'src'} = $src;
        $tspec_values{'srcType'} = $srcType;
        $tspec_values{'dst'} = $dst;
        $tspec_values{'dstType'} = $dstType;
        foreach my $meta_param(@{ METADATA_PARAMS() }){
            if( defined $parameters->{messageParameters}->{$meta_param} ){
                $tspec_values{$meta_param} = $parameters->{messageParameters}->{$meta_param};
            }
        }
        my $tspec_insert_result = $dbh->insert({table => "${table_prefix}_TESTSPEC", argvalues => \%tspec_values});
        if($tspec_insert_result == -1){
            my $errMsg = "Error inserting metadata into database";
            $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
            $self->{NETLOGGER}->debug( $nlmsg );
            throw perfSONAR_PS::Error_compat( $errMsg );
        }
    }
    
    #create measurement
    my %meas_values = ('testspec_key' => $metadata_key, 'timestamp' => $timestamp);
    my $meas_result =  $dbh->insert({table => "${table_prefix}_MEASUREMENT", argvalues => \%meas_values});
    if($meas_result == -1){
        my $errMsg = "Error inserting measurment into database";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    
    #insert hops
    my $meas_id = $dbh->lastInsertId({table => "${table_prefix}_MEASUREMENT", field => 'id'});
    for(my $datum_i = 0; $datum_i < $datum->size(); $datum_i++){
        my %hop_values = ();
        $hop_values{'measurement_id'} = $meas_id;
        my $datum_elem = $datum->get_node($datum_i);
        #get required attributes
        $hop_values{'addrType'} = $self->getHopType($datum_elem->getAttribute('hop'));
        foreach my $hop_field( keys %{ $hop_db_map } ){
            if($hop_values{'addrType'} eq 'error' && exists $hop_db_err_vals->{$hop_field}){
                $hop_values{$hop_field} = $hop_db_err_vals->{$hop_field};
            }elsif(!defined $datum_elem->getAttribute($hop_db_map->{$hop_field})){
                
                my $errMsg = "Missing required datum attribute " . $hop_db_map->{$hop_field};
                $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
                $self->{NETLOGGER}->debug( $nlmsg );
                throw perfSONAR_PS::Error_compat( $errMsg );
            }else{
                $hop_values{$hop_field} = $datum_elem->getAttribute($hop_db_map->{$hop_field});
            }
        }
        #get optional attributes
        foreach my $hop_field_opt( keys %{ $hop_db_map_optional } ){
            if(defined $datum_elem->getAttribute($hop_db_map_optional->{$hop_field_opt})){
                $hop_values{$hop_field_opt} = $datum_elem->getAttribute($hop_db_map_optional->{$hop_field_opt});
            }
        }
        my $hop_result = $dbh->insert({table => "${table_prefix}_HOPS", argvalues => \%hop_values});
        if($hop_result == -1){
            my $errMsg = "Error inserting hop into database ";
            $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end", {msg=> $errMsg, status => -1});
            $self->{NETLOGGER}->debug( $nlmsg );
            throw perfSONAR_PS::Error_compat( $errMsg );
        }
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.registerData.end");
    $self->{NETLOGGER}->debug( $nlmsg );
}

sub initTables {
    my ($self, @args) = @_;
     my $parameters = validateParams(
        @args,
        {
            datum            => 1,
            dbh              => 1
        }
    );
    
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    #TODO: acquire lock
    
    #Extract time
    my $attrMap = $parameters->{datum}->get_node(0)->attributes();
    if(!$attrMap){
        my $errMsg = "Invalid datum: No attributes";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    
    #TODO: Support ISO type
    if(!$attrMap->getNamedItem('timeValue') || $attrMap->getNamedItem('timeValue')->getValue() !~ /\d+/){
        my $errMsg = "Invalid datum: No time value given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    
    #SELECT from dates
    my $timestamp = $attrMap->getNamedItem('timeValue')->getValue();
    my @time = gmtime( $timestamp );
    my $year = $time[5] + 1900;
    my $month = $time[4]+1;
    my $day = $time[3];
    my $table_prefix = $year . sprintf("%02d", $month) . sprintf("%02d", $day);

    #Create DATE tables if they don't exist
    my $db_create_result = $parameters->{dbh}->execute({ query => "CREATE TABLE IF NOT EXISTS DATES (
        year int NOT NULL,
        month INT NOT NULL, 
        day INT NOT NULL,
        PRIMARY KEY(year, month, day)
    )"});
    if($db_create_result == -1){
        my $err_msg = "Unable to create database table DATES";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $err_msg );
    }
    
   my $date_results = $parameters->{dbh}->query({query=>"SELECT * FROM DATES WHERE year=$year AND month=$month AND day=$day"});
   if($date_results == -1){
        my $err_msg = "Error trying to find date in database";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $err_msg );
    }elsif(@{$date_results} == 0){
        my %date_values = ('year' => $year, 'month' => $month, 'day' => $day);
        $date_results = $parameters->{dbh}->insert({table => "DATES", argvalues => \%date_values});
        if($date_results == -1){
            my $err_msg = "Error trying to insert date into database";
            $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
            $self->{NETLOGGER}->debug( $nlmsg );
            throw perfSONAR_PS::Error_compat( $err_msg );
        }
    }
    
    $db_create_result = $parameters->{dbh}->execute({ query => "CREATE TABLE IF NOT EXISTS ${table_prefix}_TESTSPEC (
        id INT NOT NULL auto_increment,
        subjKey VARCHAR(50) NOT NULL,
        srcType VARCHAR(10) NOT NULL ,
        src VARCHAR(150) NOT NULL,
        dstType VARCHAR(10) NOT NULL,
        dst VARCHAR(150) NOT NULL,
        firstTTL INT,
        maxTTL INT,
        waitTime INT,
        pause INT,
        packetSize INT,
        numBytes INT,
        arguments VARCHAR(20),
        PRIMARY KEY (id),
        INDEX (subjKey),
        INDEX (srcType, src),
        INDEX (dstType, dst),
        INDEX (srcType, src, dst, dstType)
    )"});
    if($db_create_result == -1){
        my $err_msg = "Unable to create database table ${table_prefix}_TESTSPEC";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $err_msg );
    }
    
    $db_create_result =  $parameters->{dbh}->execute({ query => "CREATE TABLE IF NOT EXISTS ${table_prefix}_MEASUREMENT (
        id INT NOT NULL auto_increment,
        testspec_key VARCHAR(50) NOT NULL,
        timestamp INT NOT NULL,
        PRIMARY KEY (id),
        INDEX (testspec_key)
    )" });
    if($db_create_result == -1){
        my $err_msg = "Unable to create database table ${table_prefix}_MEASUREMENT";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $err_msg );
    }
    
    $db_create_result = $parameters->{dbh}->execute({ query => "CREATE TABLE IF NOT EXISTS ${table_prefix}_HOPS (
        id INT NOT NULL auto_increment,
        measurement_id INT NOT NULL,
        ttl INT NOT NULL,
        addrType VARCHAR(10) NOT NULL,
        addr VARCHAR(150) NOT NULL,
        queryNum INT NOT NULL,
        numBytes INT,
        delay FLOAT NOT NULL,
        PRIMARY KEY (id),
        INDEX (measurement_id)
    );" });
    if($db_create_result == -1){
        my $err_msg = "Unable to create database table ${table_prefix}_HOPS";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end", {eventType => $parameters->{eventType}, msgType => $parameters->{messageType}, msg=> $err_msg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $err_msg );
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.initTables.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    return ($table_prefix, $timestamp);
}

sub generate_key{
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            messageParameters => 1,
            subject           => 1
        }
    );
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    my $endPointPair = find( $parameters->{subject}, "./*[local-name()='subject']/*[local-name()='endPointPair']", 1 );
    if(!$endPointPair){
        my $errMsg = "Invalid subject: No endpointPair given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $srcDOM = find( $endPointPair, "./*[local-name()='src']", 1 );
    if(!$srcDOM){
        my $errMsg = "Invalid subject: No source given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $src = extract( $srcDOM, 0 );
    if(!$src){
        my $errMsg = "Invalid subject: Empty source given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $srcType = $srcDOM->getAttribute("type");
    if(!$srcType){
        my $errMsg = "Invalid subject: No source type attribute given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $dstDOM = find( $endPointPair, "./*[local-name()='dst']", 1 );
    if(!$dstDOM){
        my $errMsg = "Invalid subject: No destination given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $dst = extract( $dstDOM, 0 );
    if(!$dst){
        my $errMsg = "Invalid subject: Empty destination given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $dstType = $dstDOM->getAttribute("type");
    if(!$dstType){
        my $errMsg = "Invalid subject: No destination type attribute given";
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", {msg=> $errMsg, status => -1});
        $self->{NETLOGGER}->debug( $nlmsg );
        throw perfSONAR_PS::Error_compat( $errMsg );
    }
    my $md_string = "$src,$dst";
    foreach my $param_key(keys %{$parameters->{messageParameters}}){
        $md_string .= ",$param_key,";
        $md_string .= $parameters->{messageParameters}->{$param_key};
    }
    
    my $key = md5_hex($md_string);
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.generate_key.end", { "key" => $key });
    $self->{NETLOGGER}->debug( $nlmsg );
    return ($src, $srcType, $dst, $dstType, $key);
}

sub getHopType() {
    my ($self, $hop) = @_;
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.getHopType.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my $type = "hostname";
   
    
    if($hop =~ /^error:/){
        $type = "error";
    }elsif( is_ipv4($hop) ){
        $type = "ipv4";
    }elsif( is_ipv6($hop) ){
        $type = "ipv6";
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.Collector.Traceroute.getHopType.end", {hop_type => $type, hop => $hop});
    $self->{NETLOGGER}->debug( $nlmsg );
    return $type;
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

package perfSONAR_PS::Services::MA::Status;

=head1 NAME

perfSONAR_PS::Services::MA::Status - A module that provides methods for a
an L2 Status Measurement Archive. The service can be used to make Link Status
Data available to individuals via webservice interface.

=head1 DESCRIPTION

This module, in conjunction with other parts of the perfSONAR-PS framework,
handles specific messages from interested actors in search of link status data.

There are two major message types that this service can act upon:
 - SetupDataRequest               - Given either metadata or a key regarding a specific
                                      measurement, retrieve data values.
 - MetadataKeyRequest     - Given some metadata about a specific measurement, 
                            request a re-playable 'key' to faster access
                            underlying data.

The module is capable of handling link status data in an E2EMon compatible
fashion, as well as allowing for moving away from the E2EMon-style.
=cut

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'DATA_CLIENT', 'LOGGER', 'DOMAIN', 'LINKS', 'NODES', 'METADATADB', 'E2EMON_METADATADB', 'E2EMON_MAPPING', 'XPATH_CONTEXT';

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;
use English qw( -no_match_vars );

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::DB::Status;
use perfSONAR_PS::Status::Link;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Services::MA::General;

our $VERSION = 0.09;

# Any of the XPath queries used in this module will use one of the following namespaces.
my %status_namespaces = (
    nmwg   => "http://ggf.org/ns/nmwg/base/2.0/",
    select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
    nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
    topoid => "http://ogf.org/schema/network/topology/id/20070828/",
    ifevt  => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
    nmtl2  => "http://ggf.org/ns/nmwg/topology/l2/3.0/",
    nmwgtopo3 => "http://ggf.org/ns/nmwg/topology/base/3.0/",
);

=head1 API

The offered API is not meant for external use as many of the functions are
relied upon by internal aspects of the perfSONAR-PS framework.

=head2 init($self, $handler)
    Called at startup by the daemon when this particular module is loaded into
    the perfSONAR-PS deployment. Checks the configuration file for the
    necessary items and fills in others when needed. Finally the message
    handler loads the appropriate message types and eventTypes for this module.
    Any other 'pre-startup' tasks should be placed in this function.
=cut

sub init {
    my ( $self, $handler ) = @_;

    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MA::Status" );

    # Create an XPath Context that will be used for XPath queries in this module.
    $self->{XPATH_CONTEXT} = XML::LibXML::XPathContext->new();
    foreach my $prefix ( keys %status_namespaces ) {
        $self->{XPATH_CONTEXT}->registerNs( $prefix, $status_namespaces{$prefix} );
    }

    unless ( $self->{CONF}->{"root_hints_url"} ) {
        $self->{CONF}->{"root_hints_url"} = "http://www.perfsonar.net/gls.root.hints";
        $self->{LOGGER}->warn( "gLS Hints file not set, using default at \"http://www.perfsonar.net/gls.root.hints\"." );
    }

    unless ( defined $self->{CONF}->{"status"}->{"enable_registration"} ) {
        $self->{LOGGER}->warn( "Disabling LS registration" );
        $self->{CONF}->{"status"}->{"enable_registration"} = 0;
    }

    if ( $self->{CONF}->{"status"}->{"enable_registration"} ) {
        unless ( exists $self->{CONF}->{"status"}->{"ls_instance"}
            and $self->{CONF}->{"status"}->{"ls_instance"} )
        {
            if ( defined $self->{CONF}->{"ls_instance"}
                and $self->{CONF}->{"ls_instance"} )
            {
                $self->{CONF}->{"status"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
            }
            else {
                $self->{LOGGER}->warn( "No LS instance specified for SNMP service" );
            }
        }

        unless ( exists $self->{CONF}->{"status"}->{"ls_registration_interval"}
            and $self->{CONF}->{"status"}->{"ls_registration_interval"} )
        {
            if ( defined $self->{CONF}->{"ls_registration_interval"}
                and $self->{CONF}->{"ls_registration_interval"} )
            {
                $self->{CONF}->{"status"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
            }
            else {
                $self->{LOGGER}->warn( "Setting registration interval to 4 hours" );
                $self->{CONF}->{"status"}->{"ls_registration_interval"} = 14400;
            }
        }

        if ( not $self->{CONF}->{"status"}->{"service_accesspoint"} ) {
            unless ( $self->{CONF}->{external_address} ) {
                $self->{LOGGER}->error( "With LS registration enabled, you need to specify either the service accessPoint for the service or the external_address" );
                return -1;
            }
            $self->{LOGGER}->info( "Setting service access point to http://" . $self->{CONF}->{external_address} . ":" . $self->{PORT} . $self->{ENDPOINT} );
            $self->{CONF}->{"status"}->{"service_accesspoint"} = "http://" . $self->{CONF}->{external_address} . ":" . $self->{PORT} . $self->{ENDPOINT};
        }

        unless ( exists $self->{CONF}->{"status"}->{"service_description"}
            and $self->{CONF}->{"status"}->{"service_description"} )
        {
            my $description = "perfSONAR_PS SNMP MA";
            if ( $self->{CONF}->{site_name} ) {
                $description .= " at " . $self->{CONF}->{site_name};
            }
            if ( $self->{CONF}->{site_location} ) {
                $description .= " in " . $self->{CONF}->{site_location};
            }
            $self->{CONF}->{"status"}->{"service_description"} = $description;
            $self->{LOGGER}->warn( "Setting 'service_description' to '$description'." );
        }

        unless ( exists $self->{CONF}->{"status"}->{"service_name"}
            and $self->{CONF}->{"status"}->{"service_name"} )
        {
            $self->{CONF}->{"status"}->{"service_name"} = "SNMP MA";
            $self->{LOGGER}->warn( "Setting 'service_name' to 'SNMP MA'." );
        }

        unless ( exists $self->{CONF}->{"status"}->{"service_type"}
            and $self->{CONF}->{"status"}->{"service_type"} )
        {
            $self->{CONF}->{"status"}->{"service_type"} = "MA";
            $self->{LOGGER}->warn( "Setting 'service_type' to 'MA'." );
        }

        my %ls_conf = (
            SERVICE_TYPE        => $self->{CONF}->{"status"}->{"service_type"},
            SERVICE_NAME        => $self->{CONF}->{"status"}->{"service_name"},
            SERVICE_DESCRIPTION => $self->{CONF}->{"status"}->{"service_description"},
            SERVICE_ACCESSPOINT => $self->{CONF}->{"status"}->{"service_accesspoint"},
        );

        my @ls_array = ();
        my @array = split( /\s+/, $self->{CONF}->{"status"}->{"ls_instance"} );
        foreach my $l ( @array ) {
            $l =~ s/(\s|\n)*//g;
            push @ls_array, $l if $l;
        }
        @array = split( /\s+/, $self->{CONF}->{"ls_instance"} );
        foreach my $l ( @array ) {
            $l =~ s/(\s|\n)*//g;
            push @ls_array, $l if $l;
        }

        my @hints_array = ();
        @array = split( /\s+/, $self->{CONF}->{"root_hints_url"} );
        foreach my $h ( @array ) {
            $h =~ s/(\s|\n)*//g;
            push @hints_array, $h if $h;
        }

        $self->{LS_CLIENT} = perfSONAR_PS::Client::LS::Remote->new( \@ls_array, \%ls_conf, \@hints_array );
    }

    if ( not defined $self->{CONF}->{"status"}->{"db_type"} or $self->{CONF}->{"status"}->{"db_type"} eq q{} ) {
        $self->{LOGGER}->error( "No database type specified" );
        return -1;
    }

    my ($dbi_string, $username, $password, $table_prefix);
    $username = $self->{CONF}->{"status"}->{"db_username"};
    $password = $self->{CONF}->{"status"}->{"db_password"};
    $table_prefix = $self->{CONF}->{"status"}->{"db_prefix"};

    if ( lc( $self->{CONF}->{"status"}->{"db_type"} ) eq "sqlite" ) {
        if ( not defined $self->{CONF}->{"status"}->{"db_file"} or $self->{CONF}->{"status"}->{"db_file"} eq q{} ) {
            $self->{LOGGER}->error( "You specified a SQLite Database, but then did not specify a database file(db_file)" );
            return -1;
        }

        my $file = $self->{CONF}->{"status"}->{"db_file"};
        if ( defined $self->{DIRECTORY} ) {
            if ( !( $file =~ "^/" ) ) {
                $file = $self->{DIRECTORY} . "/" . $file;
            }
        }

        $dbi_string = "DBI:SQLite:dbname=" . $file;
    }
    elsif ( lc( $self->{CONF}->{"status"}->{"db_type"} ) eq "mysql" ) {
        $dbi_string = "dbi:mysql";

        if ( not defined $self->{CONF}->{"status"}->{"db_name"} or $self->{CONF}->{"status"}->{"db_name"} eq q{} ) {
            $self->{LOGGER}->error( "You specified a MySQL Database, but did not specify the database (db_name)" );
            return -1;
        }

        $dbi_string .= ":" . $self->{CONF}->{"status"}->{"db_name"};

        if ( not defined $self->{CONF}->{"status"}->{"db_host"} or $self->{CONF}->{"status"}->{"db_host"} eq q{} ) {
            $self->{LOGGER}->error( "You specified a MySQL Database, but did not specify the database host (db_host)" );
            return -1;
        }

        $dbi_string .= ":" . $self->{CONF}->{"status"}->{"db_host"};

        if ( defined $self->{CONF}->{"status"}->{"db_port"} and $self->{CONF}->{"status"}->{"db_port"} ne q{} ) {
            $dbi_string .= ":" . $self->{CONF}->{"status"}->{"db_port"};
        }
    }
    else {
        $self->{LOGGER}->error( "Invalid database type specified" );
        return -1;
    }

	my $data_client = perfSONAR_PS::DB::Status->new();
	unless ($data_client->init({ dbistring => $dbi_string, username => $username, password => $password, table_prefix => $table_prefix})) {
		my $msg = "Problem creating database client";
        $self->{LOGGER}->error($msg);
		return -1;
	}

    my ($status, $res);

    $self->{DATA_CLIENT} = $data_client;
    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open newly created client: $res";
        $self->{LOGGER}->error( $msg );
        return -1;
    }
    $self->{DATA_CLIENT}->closeDB;

    if ( lc( $self->{CONF}->{"status"}->{"enable_e2emon_compatibility"} ) ) {
        if ( $self->{CONF}->{"status"}->{"e2emon_definitions_file"} ) {
            my $file = $self->{CONF}->{"status"}->{"e2emon_definitions_file"};
            if ( defined $self->{DIRECTORY} ) {
                if ( $file !~ "^/" ) {
                    $file = $self->{DIRECTORY} . "/" . $file;
                }
            }

            my ( $status, $domain, $links, $nodes, $dom, $link_mappings );

            ( $status, $domain, $links, $nodes ) = $self->parseCompatCircuitsFile( $file );
            if ( $status != 0 ) {
                my $msg = "Error parsing E2EMon definitions";
                $self->{LOGGER}->error( $msg );
                return -1;
            }

            ( $status, $dom, $link_mappings ) = $self->constructE2EMonMetadataDB( $links, $nodes );
            if ( $status != 0 ) {
                my $msg = "Error parsing E2EMon definitions";
                $self->{LOGGER}->error( $msg );
                return -1;
            }

            $self->{DOMAIN}            = $domain;
            $self->{LINKS}             = $links;
            $self->{NODES}             = $nodes;
            $self->{E2EMON_MAPPING}    = $link_mappings;
            $self->{E2EMON_METADATADB} = $dom;
        }
        else {
            my $msg = "No E2EMon definitions file for E2EMon compatibility";
            $self->{LOGGER}->error( $msg );
            return -1;
        }
    }

    if ( not $self->{CONF}->{"status"}->{"metadata_db_type"} ) {
        $self->{LOGGER}->warn( "No Metadata DB specified, providing direct access" );

        # ignore
    }
    elsif ( $self->{CONF}->{"status"}->{"metadata_db_type"} eq "file" ) {
        my $file = $self->{CONF}->{"status"}->{"metadata_db_file"};
        if ( defined $self->{DIRECTORY} ) {
            if ( $file !~ "^/" ) {
                $file = $self->{DIRECTORY} . "/" . $file;
            }
        }

        my $error;
        $self->{METADATADB} = perfSONAR_PS::DB::File->new( { file => $file } );
        $self->{METADATADB}->openDB( { error => \$error } );
        unless ( $self->{METADATADB} ) {
            $self->{LOGGER}->error( "Couldn't initialize store file: $error" );
            return -1;
        }
    }

    $handler->registerEventHandler( "SetupDataRequest",   "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self );
    $handler->registerEventHandler( "MetadataKeyRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self );

    # E2EMon Compatible
    $handler->registerEventHandler( "SetupDataRequest",   "http://ggf.org/ns/nmwg/topology/l2/3.0/link/status", $self );
    $handler->registerEventHandler( "SetupDataRequest",   "Path.Status",                                        $self );
    $handler->registerEventHandler( "MetadataKeyRequest", "http://ggf.org/ns/nmwg/topology/l2/3.0/link/status", $self );
    $handler->registerEventHandler( "MetadataKeyRequest", "Path.Status",                                        $self );

    return 0;
}

=head2 needLS($self)
    This particular service (Status MA) should register with a lookup service. This
    function simply returns the value set in the configuration file (either yes
    or no, depending on user preference) to let other parts of the framework know
    if LS registration is required.
=cut

sub needLS {
    my ( $self ) = @_;

    return ( $self->{CONF}->{"status"}->{"enable_registration"} );
}

=head2 registerLS($self $sleep_time)
    Given the service information (specified in configuration) and the contents
    of our metadata database, this function contacts the specified LS, and register
    the metadata. The $sleep_time ref can be set to specify how long before the
    perfSONAR-PS daemon should call the function again.
=cut

sub registerLS {
    my ( $self, $sleep_time ) = @_;

    my @mds = ();
    my $ret_mds;

    $ret_mds = $self->getMetadata_compat();
    if ( $ret_mds ) {
        foreach my $md ( @$ret_mds ) {
            push @mds, $md;
        }
    }

    $ret_mds = $self->getMetadata_topoid();
    if ( $ret_mds ) {
        foreach my $md ( @$ret_mds ) {
            push @mds, $md;
        }
    }

    $ret_mds = $self->getMetadata();
    if ( $ret_mds ) {
        foreach my $md ( @$ret_mds ) {
            push @mds, $md;
        }
    }

    my $n = $self->{LS_CLIENT}->registerDynamic( \@mds );

    if ( defined $sleep_time ) {
        ${$sleep_time} = $self->{CONF}->{"status"}->{"ls_registration_interval"};
    }

    return $n;
}

=head2 getMetadata_topoid ($self)

Retrieves the topology identifiers from the backend database and constructs
metadata for each of them. It then returns the values as an array of strings.

=cut

sub getMetadata_topoid {
    my ( $self ) = @_;
    my ( $status, $res );

    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    ( $status, $res ) = $self->{DATA_CLIENT}->get_unique_ids({ });
    if ( $status != 0 ) {
        my $msg = "Couldn't get identifiers from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    my @mds = ();
    my $i   = 0;
    foreach my $id_info ( @{$res} ) {
        my $id = $id_info->{topology_id};

        my $md = q{};

        $md .= "<nmwg:metadata id=\"meta$i\">\n";
        $md .= "<topoid:subject id=\"sub$i\">" . escapeString( $id ) . "</topoid:subject>\n";
        $md .= "<nmwg:eventType>Link.Status</nmwg:eventType>\n";
        $md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/link/status/20070809</nmwg:eventType>\n";
        $md .= "</nmwg:metadata>\n";
        push @mds, $md;
        $i++;
    }

    $self->{DATA_CLIENT}->closeDB;

    return \@mds;
}

=head2 getMetadata_compat ($self)

Builds and returns the E2EMon-compatible metadata as a set of strings, each
containing its own metadata.

=cut

sub getMetadata_compat {
    my ( $self ) = @_;

    return () if ( not $self->{E2EMON_METADATADB} );

    my @mds = ();

    my %output_endpoints = ();

    foreach my $link_name ( keys %{ $self->{LINKS} } ) {
        my $link = $self->{LINKS}->{$link_name};

        foreach my $endpoint ( @{ $link->{"endpoints"} } ) {

            # Skip if it's an external host
            next if ( not defined $self->{NODES}->{ $endpoint->{name} } );

            # Skip if we've already output the node
            next if ( defined $output_endpoints{ $endpoint->{name} } );

            my $output = perfSONAR_PS::XML::Document->new();

            startMetadata( $output, "metadata." . genuid(), q{}, undef );
            $output->startElement( prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub-" . $endpoint->{name} } );
            $self->outputCompatNodeElement( $output, $self->{NODES}->{ $endpoint->{name} } );
            $output->endElement( "subject" );
            endMetadata( $output );

            push @mds, $output->getValue;

            $output_endpoints{ $endpoint->{name} } = 1;
        }

        my $output = perfSONAR_PS::XML::Document->new();
        startMetadata( $output, "metadata." . genuid(), q{}, undef );
        $output->startElement( prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub." . genuid() } );
        $self->outputCompatLinkElement( $output, $link );
        $output->endElement( "subject" );
        endMetadata( $output );

        push @mds, $output->getValue;
    }

    return \@mds;
}

=head2 getMetadata ($self)

Retrieves the metadata from the Metadata Database.

=cut

sub getMetadata {
    my ( $self ) = @_;

    return () if ( not $self->{METADATADB} );

    my ( $status, $res );
    my $ls = q{};

    my $error = q{};
    my @resultsString = $self->{METADATADB}->query( { query => "/nmwg:store/nmwg:metadata", error => \$error } );
    if ( $#resultsString == -1 ) {
        $self->{LOGGER}->error( "No data to register with LS" );
        return -1;
    }

    return \@resultsString;
}

=head2 handleEvent ( $self, { output => 1, messageId => 1, messageType => 1, messageParameters => 1, eventType => 1, subject => 1, filterChain => 1, data => 1, rawRequest => 1, doOutputMetadata  => 1 } )

The main function called by the daemon whenever there is new request. It
multiplexes between the functions for the E2EMon-compatible requests, and those
for other requests.

=cut

sub handleEvent {
    my ( $self, @args ) = @_;
    my $args = validateParams(
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

    my $eventType = $args->{"eventType"};

    if ( $eventType eq "Path.Status" or $eventType = "http://ggf.org/ns/nmwg/topology/l2/3.0/link/status" ) {
        $self->handleCompatEvent( @args );
    }
    else {
        $self->handleNormalEvent( @args );
    }

    return;
}

=head2 handleNormalEvent ( $self, { output => 1, messageId => 1, messageType => 1, messageParameters => 1, eventType => 1, subject => 1, filterChain => 1, data => 1, rawRequest => 1, doOutputMetadata  => 1 } )

    This function is called by the daemon whenever there is a metadata/data
    pair for this instance to handle. This function resolves the select filter
    chain, and then checks which type of "subject" it has. It can be one of a
    key, a topological identifier subject or a "normal" subject. The function
    then dispatches the request to the appropriate function.
=cut

sub handleNormalEvent {
    my ( $self, @args ) = @_;
    my $args = validateParams(
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

    my $output             = $args->{"output"};
    my $messageId          = $args->{"messageId"};
    my $messageType        = $args->{"messageType"};
    my $message_args = $args->{"messageParameters"};
    my $eventType          = $args->{"eventType"};
    my $d                  = $args->{"data"};
    my $raw_request        = $args->{"rawRequest"};
    my @subjects           = @{ $args->{"subject"} };
    my $doOutputMetadata   = $args->{doOutputMetadata};

    my $md = $subjects[0];

    my $metadataId;
    my @filters = @{ $args->{filterChain} };
    my ( $startTime, $endTime ) = $self->resolveSelectChain( $args->{filterChain} );
    if ( $#filters > -1 ) {
        $metadataId = $filters[-1][0]->getAttribute( "id" );
    }
    else {
        $metadataId = $md->getAttribute( "id" );
    }

    my $nmwg_key       = $self->xPathFind( $md, "./nmwg:key",       1 );
    my $topoid_subject = $self->xPathFind( $md, "./topoid:subject", 1 );
    if ( $nmwg_key ) {
        ${$doOutputMetadata} = 1;
        $self->handleRequest_Key(
            {
                output        => $output,
                key           => $nmwg_key,
                metadata_id   => $metadataId,
                message_type  => $messageType,
                start_time    => $startTime,
                end_time      => $endTime,
                event_type    => $eventType,
                output_ranges => 1,
            }
        );
    }
    elsif ( $topoid_subject ) {
        ${$doOutputMetadata} = 1;
        $self->handleRequest_Topoid(
            {
                output       => $output,
                metadata     => $md,
                metadata_id  => $metadataId,
                message_type => $messageType,
                start_time   => $startTime,
                end_time     => $endTime,
                event_type   => $eventType,
            }
        );
    }
    else {
        ${$doOutputMetadata} = 0;
        $self->handleRequest_Metadata(
            {
                output       => $output,
                metadata     => $md,
                metadata_id  => $metadataId,
                message_type => $messageType,
                start_time   => $startTime,
                end_time     => $endTime,
                event_type   => $eventType,
            }
        );
    }

    return;
}

=head2 handleRequest_Metadata ($self, { output=> 1, metadata => 1, metadata_id => 1, message_type => 1, start_time => 1, end_time => 1 })
    This function handles requests that comes in with a subject metadata. It
    then matches the given metadata against the metadata database, and then
    outputs each matching metadata and then either outputs the key directly in
    the case of a MetadataKeyRequest or calls a function to handle querying and
    outputting the data.
=cut

sub handleRequest_Metadata {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output       => 1,
            metadata     => 1,
            metadata_id  => 1,
            message_type => 1,
            start_time   => 1,
            end_time     => 1,
            event_type   => 1,
        }
    );

    my $md_query = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery( { node => $args->{metadata} } ) . "]";
    my $d_query = "/nmwg:store/nmwg:data";

    unless ( $self->{METADATADB} ) {
        my $msg = "Database returned 0 results for search";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    my $md_results = $self->{METADATADB}->querySet( { query => $md_query } );
    my $d_results  = $self->{METADATADB}->querySet( { query => $d_query } );

    my %mds = ();
    foreach my $md ( $md_results->get_nodelist ) {
        my $curr_md_id = $md->getAttribute( "id" );
        next if not $curr_md_id;
        $mds{$curr_md_id} = $md;
    }

    my ( $status, $res);

    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    foreach my $d ( $d_results->get_nodelist ) {
        my $curr_d_mdIdRef = $d->getAttribute( "metadataIdRef" );

        next if ( not $curr_d_mdIdRef or not exists $mds{$curr_d_mdIdRef} );

        my $curr_md = $mds{$curr_d_mdIdRef};

        my $new_md_id = "metadata." . genuid();

        my $md_temp = $curr_md->cloneNode( 1 );
        $md_temp->setAttribute( "metadataIdRef", $args->{metadata_id} );
        $md_temp->setAttribute( "id",            $new_md_id );

        $args->{output}->addExistingXMLElement( $md_temp );

        my @elements = ();
        my $find_res = $self->xPathFind( $d, "./nmwg:key/nmwg:args/nmwg:parameter[\@name=\"element_id\"]", 0 );
        foreach my $id_ref ( $find_res->get_nodelist ) {
            my $id = $id_ref->textContent;
            push @elements, $id;
        }

        if ( $args->{message_type} eq "MetadataKeyRequest" ) {
#            $self->{LOGGER}->debug( "Output: " . Dumper( \@elements ) );

            # need to output the data
            startData( $args->{output}, "data." . genuid(), $new_md_id );
            $self->outputKey( { output => $args->{output}, elements => \@elements, start_time => $args->{start_time}, end_time => $args->{end_time}, event_type => $args->{event_type} } );
            endData( $args->{output} );
        }
        else {
            $self->handleData( { output => $args->{output}, ids => \@elements, start_time => $args->{start_time}, end_time => $args->{end_time}, output_ranges => 1 } );
        }
    }

    $self->{DATA_CLIENT}->closeDB;

    return;
}

=head2 handleRequest_Topoid ($self, { output=> 1, metadata => 1, metadata_id => 1, message_type => 1, start_time => 1, end_time => 1 })
    This function handles requests that comes in with a topology id subject
    metadata. It then queries the database to see if that identifier exists,
    and then returns that identifier.  If so, it outputs the key in the case of
    a MetadataKeyRequest or calls a function to handle querying and outputting
    the data.
=cut

sub handleRequest_Topoid {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output       => 1,
            metadata     => 1,
            metadata_id  => 1,
            message_type => 1,
            start_time   => 1,
            end_time     => 1,
            event_type   => 1,
        }
    );

    my ( $status, $res );

    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    my $topo_id = $self->xPathFindValue( $args->{metadata}, "./topoid:subject" );
    $topo_id =~ s/^\s*//g;
    $topo_id =~ s/\s*$//g;
    $topo_id = unescapeString($topo_id);

    if (not $topo_id) {
        my $msg = "Database returned 0 results for search";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    my $key = $topo_id;

    my @elements = ( $key );

    if ( $args->{message_type} eq "MetadataKeyRequest" ) {
        # need to output the key
        startData( $args->{output}, "data." . genuid(), $args->{metadata_id} );
        $self->outputKey( { output => $args->{output}, elements => \@elements, start_time => $args->{start_time}, end_time => $args->{end_time}, event_type => $args->{event_type} } );
        endData( $args->{output} );
    }
    else {
        $self->handleData( { output => $args->{output}, metadata_id => $args->{metadata_id}, ids => \@elements, start_time => $args->{start_time}, end_time => $args->{end_time}, output_ranges => 1 } );
    }

    $self->{DATA_CLIENT}->closeDB;

    return;
}

=head2 handleRequest_Key ($self, { output=> 1, key => 1, metadata_id => 1, message_type => 1, start_time => 1, end_time => 1, output_metadata => 1 })
    This function handles requests that comes in with a key. It parses the key 
    and then either outputs a new key directly in the case of a
    MetadataKeyRequest or calls a function to handle querying and outputting
    the data for a SetupDataRequest.
=cut

sub handleRequest_Key {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output        => 1,
            key           => 1,
            metadata_id   => 1,
            message_type  => 1,
            start_time    => 1,
            end_time      => 1,
            event_type    => 1,
            output_ranges => 1,
        }
    );

    my ( $status, $res );

    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    my ( $elements, $start_time, $end_time ) = $self->parseKey( $args->{key} );

    if ( not $start_time ) {
        $start_time = $args->{start_time};
    }

    if ( $args->{start_time} and $start_time < $args->{start_time} ) {
        $start_time = $args->{start_time};
    }

    if ( not $end_time ) {
        $end_time = $args->{end_time};
    }

    if ( $args->{end_time} and $end_time > $args->{end_time} ) {
        $start_time = $args->{start_time};
    }

    if ( $start_time and $end_time and $start_time > $end_time ) {
        throw perfSONAR_PS::Error_compat( "error.ma.select", "Ambiguous select args: time requested is out of key's range" );
    }

    if ( $args->{message_type} eq "MetadataKeyRequest" ) {

        # need to output the data
        startData( $args->{output}, "data." . genuid(), $args->{metadata_id} );
        $self->outputKey( { output => $args->{output}, elements => $elements, start_time => $start_time, end_time => $end_time, event_type => $args->{event_type} } );
        endData( $args->{output} );
    }
    else {
        $self->handleData( { output => $args->{output}, metadata_id => $args->{metadata_id}, ids => $elements, start_time => $start_time, end_time => $end_time, output_ranges => $args->{output_ranges} } );
    }

    $self->{DATA_CLIENT}->closeDB;

    return;
}

=head2 handleNormalEvent ( $self, { output => 1, messageId => 1, messageType => 1, messageParameters => 1, eventType => 1, subject => 1, filterChain => 1, data => 1, rawRequest => 1, doOutputMetadata  => 1 } )

    This function is called whenever there is an E2EMon metadata/data pair for
    this instance to handle. This function resolves the select filter chain,
    and then checks which type of "subject" it has, either a key or a "normal"
    subject. The function then dispatches the request to the appropriate
    function.
=cut

sub handleCompatEvent {
    my ( $self, @args ) = @_;
    my $args = validateParams(
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

    my $output             = $args->{"output"};
    my $messageId          = $args->{"messageId"};
    my $messageType        = $args->{"messageType"};
    my $message_args = $args->{"messageParameters"};
    my $eventType          = $args->{"eventType"};
    my $d                  = $args->{"data"};
    my $raw_request        = $args->{"rawRequest"};
    my @subjects           = @{ $args->{"subject"} };
    my $doOutputMetadata   = $args->{doOutputMetadata};

    my $md = $subjects[0];

    my $metadataId;
    my @filters = @{ $args->{filterChain} };
    my ( $startTime, $endTime ) = $self->resolveSelectChain( $args->{filterChain} );
    if ( $#filters > -1 ) {
        $metadataId = $filters[-1][0]->getAttribute( "id" );
    }
    else {
        $metadataId = $md->getAttribute( "id" );
    }

    my $nmwg_key = $self->xPathFind( $md, "./nmwg:key", 1 );
    if ( $nmwg_key ) {
        ${$doOutputMetadata} = 1;
        $self->handleRequest_Key(
            {
                output        => $output,
                key           => $nmwg_key,
                metadata_id   => $metadataId,
                message_type  => $messageType,
                start_time    => $startTime,
                end_time      => $endTime,
                event_type    => $eventType,
                output_ranges => 0,
            }
        );
    }
    else {
        ${$doOutputMetadata} = 0;
        $self->handleCompatRequest_Metadata(
            {
                output       => $output,
                metadata     => $md,
                metadata_id  => $metadataId,
                message_type => $messageType,
                start_time   => $startTime,
                end_time     => $endTime,
                event_type   => $eventType,
            }
        );
    }

    return;
}

=head2 handleCompatRequest_Metadata ($self, { output=> 1, metadata => 1, metadata_id => 1, message_type => 1, start_time => 1, end_time => 1 })
    This function handles E2EMon requests that comes in with a subject
    metadata. It then matches the given metadata against the metadata database,
    and then outputs each matching link and node and then either outputs the
    key directly in the case of a MetadataKeyRequest or calls a function to
    handle querying and outputting the data.
=cut

sub handleCompatRequest_Metadata {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output       => 1,
            metadata     => 1,
            metadata_id  => 1,
            message_type => 1,
            start_time   => 1,
            end_time     => 1,
            event_type   => 1,
        }
    );

    my $md_query = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery( { node => $args->{metadata} } ) . "]";

    $self->{LOGGER}->debug( "Query: " . $md_query );

    unless ( $self->{E2EMON_METADATADB} ) {
        my $msg = "Database returned 0 results for search";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    my ( $status, $res );

    ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
    if ( $status != 0 ) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error( $msg );
        return;
    }

    my $md_results = $self->xPathFind( $self->{E2EMON_METADATADB}, $md_query, 0 );
    if ( $md_results->size() == 0 ) {
        my $msg = "Database returned 0 results for search";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    startParameters( $args->{output}, "params.0" );
    addParameter( $args->{output}, "DomainName", $self->{DOMAIN} );
    endParameters( $args->{output} );

    my %output_endpoints = ();
    my %mds              = ();
    foreach my $md ( $md_results->get_nodelist ) {
        my $curr_md_id = $md->getAttribute( "id" );

        next if ( not $self->{E2EMON_MAPPING}->{$curr_md_id} );
        my $link = $self->{LINKS}->{ $self->{E2EMON_MAPPING}->{$curr_md_id} };
        next if ( not $link );

        foreach my $endpoint ( @{ $link->{"endpoints"} } ) {

            # Skip if it's an external host
            next if ( not defined $self->{NODES}->{ $endpoint->{name} } );

            # Skip if we've already output the node
            next if ( defined $output_endpoints{ $endpoint->{name} } );

            startMetadata( $args->{output}, "metadata." . genuid(), q{}, undef );
            $args->{output}->startElement( prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub-" . $endpoint->{name} } );
            $self->outputCompatNodeElement( $args->{output}, $self->{NODES}->{ $endpoint->{name} } );
            $args->{output}->endElement( "subject" );
            endMetadata( $args->{output} );

            $output_endpoints{ $endpoint->{name} } = 1;
        }

        my $mdId = "metadata." . genuid();

        startMetadata( $args->{output}, $mdId, q{}, undef );
        $args->{output}->startElement( prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub." . genuid() } );
        $self->outputCompatLinkElement( $args->{output}, $link );
        $args->{output}->endElement( "subject" );
        endMetadata( $args->{output} );

        if ( $args->{message_type} eq "MetadataKeyRequest" ) {
            ( $status, $res ) = $self->{DATA_CLIENT}->get_unique_ids({ });
            if ( $status != 0 ) {
                my $msg = "Couldn't get identifiers from database: $res";
                $self->{LOGGER}->error( $msg );
                return;
            }

            # need to output the data
            #$self->{LOGGER}->debug( "Output: " . Dumper( $link->{"subelements"} ) );

            startData( $args->{output}, "data." . genuid(), $mdId );
            $self->outputKey(
                    {
                    output     => $args->{output},
                    elements   => $res,
                    start_time => $args->{start_time},
                    end_time   => $args->{end_time},
                    event_type => $args->{event_type}
                    }
                    );
            endData( $args->{output} );
        }
        else {
            #$self->{LOGGER}->debug( "Link to handle: " . Dumper( $link ) );

            $self->handleData(
                {
                    output        => $args->{output},
                    metadata_id   => $mdId,
                    ids           => $link->{"subelements"},
                    start_time    => $args->{start_time},
                    end_time      => $args->{end_time},
                    output_ranges => 0,
                }
            );
        }
    }

    $self->{DATA_CLIENT}->closeDB;

    return;
}

=head2 resolveSelectChain ($self, $filterChain)
    This function takes the filter chain and tries to resolve it down to a
    single time period. It only searches for chains with "startTime", "endTime"
    or a specific time. This specific time can be "now" in which case the
    returned startTime and endTime are 'undef'.
=cut

sub resolveSelectChain {
    my ( $self, $filterChain ) = @_;

    my ( $startTime, $endTime );

    my @filters = @{$filterChain};

    my $now_flag = 0;

    # got through the filters and load any args with an eye toward
    # producing data as though it had gone through a set of filters.
    foreach my $filter_arr ( @filters ) {
        my @filter_set = @{$filter_arr};
        my $filter     = $filter_set[0];

        my $select_args = $self->xPathFind( $filter, './select:args', 1 );

        if ( not $select_args ) {
            $self->{LOGGER}->debug( "Didn't find any select args" );
            next;
        }

        my $curr_time      = $self->xPathFindValue( $select_args, './select:parameter[@name="time"]' );
        my $curr_startTime = $self->xPathFindValue( $select_args, './select:parameter[@name="startTime"]' );
        my $curr_endTime   = $self->xPathFindValue( $select_args, './select:parameter[@name="endTime"]' );

        if ( $curr_time ) {
            if ( lc( $curr_time ) eq "now" ) {
                if ( $startTime or $endTime ) {
                    throw perfSONAR_PS::Error_compat( "error.ma.select", "Ambiguous select args: 'now' used with a time range" );
                }

                $now_flag = 1;
            }
            else {
                if ( ( $startTime and $curr_time < $startTime ) or ( $endTime and $curr_time > $endTime ) ) {
                    throw perfSONAR_PS::Error_compat( "error.ma.select", "Ambiguous select args: time specified is out of range previously specified" );
                }
                else {
                    $startTime = $curr_time;
                    $endTime   = $curr_time;
                }
            }
        }

        if ( $curr_startTime ) {
            if ( $now_flag ) {
                throw perfSONAR_PS::Error_compat( "error.ma.select", "Ambiguous select args: 'now' used with a time range" );
            }

            if ( not $startTime or $curr_startTime >= $startTime ) {
                $startTime = $curr_startTime;
            }

        }

        if ( $curr_endTime ) {
            if ( $now_flag ) {
                throw perfSONAR_PS::Error_compat( "error.ma.select", "Ambiguous select args: 'now' used with a time range" );
            }

            if ( not $endTime or $curr_endTime < $endTime ) {
                $endTime = $curr_endTime;
            }
        }
    }

    if ( $startTime and $endTime and $startTime > $endTime ) {
        throw perfSONAR_PS::Error_compat( "error.ma.select", "Invalid select args: startTime > endTime" );
    }

    if ( $startTime ) {
        $self->{LOGGER}->debug( "Resolved Filters: Start Time: $startTime" );
    }
    if ( $endTime ) {
        $self->{LOGGER}->debug( "Resolved Filters: End Time: $endTime" );
    }

    return ( $startTime, $endTime );
}

=head2 parseKey ($self, $key)
    Parses the nmwg keys that are generated and handed off to the users. The
    "eventType" is added so that the daemon knows which module to dispatch the
    key to.
=cut

sub parseKey {
    my ( $self, $key ) = @_;

    my $key_params = $self->xPathFind( $key, "./nmwg:args", 1 );
    if ( not $key_params ) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.subject", $msg );
    }

    my $find_res = $self->xPathFind( $key_params, './nmwg:parameter[@name="maKey"]', 0 );
    if ( not $find_res ) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error( $msg );
        throw perfSONAR_PS::Error_compat( "error.ma.subject", $msg );
    }

    my @elements = ();
    foreach my $element_ref ( $find_res->get_nodelist ) {
        my $element = $element_ref->textContent;
        push @elements, unescapeString( $element );
    }

    my $startTime = $self->xPathFindValue( $key_params, './nmwg:parameter[@name="startTime"]' );
    my $endTime   = $self->xPathFindValue( $key_params, './nmwg:parameter[@name="endTime"]' );

    $self->{LOGGER}->debug( "Parsed Key: Start: " . $startTime . " End: " . $endTime . " Elements: " . join( ',', @elements ) );

    return ( \@elements, $startTime, $endTime );
}

=head2 createKey ($self, { output => 1, elements => 1, start_time => 0, end_time => 0, event_type => 0 })
    Outputs a key to the specified XML output module with the specified
    elements, start time, end time and event type.
=cut

sub outputKey {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output     => 1,
            elements   => 1,
            start_time => 0,
            end_time   => 0,
            event_type => 0,
        }
    );

    $args->{output}->startElement( { prefix => "nmwg", tag => "key", namespace => $status_namespaces{"nmwg"} } );
    startParameters( $args->{output}, "params.0" );
    foreach my $element ( @{ $args->{elements} } ) {
        addParameter( $args->{output}, "maKey", escapeString( $element ) );
    }
    addParameter( $args->{output}, "eventType", $args->{event_type} );
    addParameter( $args->{output}, "startTime", $args->{start_time} ) if ( $args->{start_time} );
    addParameter( $args->{output}, "endTime",   $args->{end_time} ) if ( $args->{end_time} );
    endParameters( $args->{output} );
    $args->{output}->endElement( "key" );

    return;
}

=head2 handleData ( $self, { output => 1, metadata_id => 1, ids => 1, data_id => 0, start_time => 0, end_time => 0, output_ranges => 0, } )
    Queries the backend database for the specified elemenets. The data returned
    comes back as time ranges.  It then calls a function to return only those
    ranges where data exists for all the elements. It then goes through those
    common ranges and calculates the status of the combined element. It then
    outputs that data to the specified XML output object. The output_ranges
    parameter is used to ameliorate a difference between the ranged data that
    the database contains, and the single point values E2EMon expects. If
    ranges are not being output, it will output a single datum for the final
    time for a period.
=cut

sub handleData {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            output        => 1,
            metadata_id   => 1,
            ids           => 1,
            data_id       => 0,
            start_time    => 0,
            end_time      => 0,
            output_ranges => 0,
        }
    );

    my $is_now;
    unless ( $args->{start_time} or $args->{end_time} ) {
        $args->{end_time}   = time;
        $args->{start_time} = $args->{end_time} - $self->{CONF}->{status}->{max_recent_age};
        $self->{LOGGER}->debug( "Setting 'now' to " . $args->{start_time} . "-" . $args->{end_time} );

        $is_now = 1;
    }

    if ( not $args->{data_id} ) {
        $args->{data_id} = "data." . genuid();
    }

    my %elements = ();

    foreach my $element (@{ $args->{ids} } ) {
        my ( $status, $res ) = $self->{DATA_CLIENT}->get_element_status( element_ids => [ $element] , start_time => $args->{start_time}, end_time => $args->{end_time} );
        if ( $status != 0 ) {
            my $msg = "Couldn't get information about elements from database: $res";
            $self->{LOGGER}->error( $msg );
            throw perfSONAR_PS::Error_compat( "error.common.storage.fetch", $msg );
        }

        if ($res->{$element}) {
            $elements{$element} = $res->{$element};
        } else {
            my $msg = "Couldn't get information about element $element from database. Assuming unknown";

            my $new_element = perfSONAR_PS::Status::Link->new( $element, $args->{start_time}, $args->{end_time}, "unknown", "unknown" );

            $elements{$element} = [$new_element];
        }
    }

    my @periods       = ();
    my @data_elements = ();

    # Find the periods where there's data from all elements.
    foreach my $id ( @{ $args->{ids} } ) {
        my $first;
        if ( scalar( @periods ) == 0 ) {
            $first = 1;
        }

        my @curr_periods = ();

        foreach my $element_history ( @{ $elements{$id} } ) {
            my %info = ();
            $info{start}        = $element_history->getStartTime;
            $info{end}          = $element_history->getEndTime;
            $info{oper_status}  = [ $element_history->getOperStatus ];
            $info{admin_status} = [ $element_history->getAdminStatus ];

            push @curr_periods, \%info;
        }

        if ( $first ) {
            @periods = @curr_periods;
            $first   = 0;
#            $self->{LOGGER}->debug( "Periods: " . Dumper( \@periods ) );
            next;
        }

        @periods = $self->find_overlap( \@curr_periods, \@periods );
#        $self->{LOGGER}->debug( "Periods: " . Dumper( \@periods ) );
    }

    if ( $is_now ) {

        # get rid of everything except the last period
        my $last_period = $periods[-1];
        my @tmp         = ();
        push @tmp, $last_period;
        @periods = @tmp;
    }

#    $self->{LOGGER}->debug( "Periods: " . Dumper( \@periods ) );

    startData( $args->{output}, $args->{data_id}, $args->{metadata_id}, undef );
    foreach my $period ( @periods ) {
        my $period_oper_status  = "unknown";
        my $period_admin_status = "unknown";

        foreach my $oper_value ( @{ $period->{oper_status} } ) {
            if ( $period_oper_status eq "down" or $oper_value eq "down" ) {
                $period_oper_status = "down";
            }
            elsif ( $period_oper_status eq "degraded" or $oper_value eq "degraded" ) {
                $period_oper_status = "degraded";
            }
            elsif ( $period_oper_status eq "up" or $oper_value eq "up" ) {
                $period_oper_status = "up";
            }
            else {
                $period_oper_status = "unknown";
            }
        }

        foreach my $admin_value ( @{ $period->{admin_status} } ) {
            if ( $period_admin_status eq "maintenance" or $admin_value eq "maintenance" ) {
                $period_admin_status = "maintenance";
            }
            elsif ( $period_admin_status eq "troubleshooting" or $admin_value eq "troubleshooting" ) {
                $period_admin_status = "troubleshooting";
            }
            elsif ( $period_admin_status eq "underrepair" or $admin_value eq "underrepair" ) {
                $period_admin_status = "underrepair";
            }
            elsif ( $period_admin_status eq "normaloperation" or $admin_value eq "normaloperation" ) {
                $period_admin_status = "normaloperation";
            }
            else {
                $period_admin_status = "unknown";
            }
        }

#        $self->{LOGGER}->debug( "Period: " . Dumper( $period ) );

        # if we can output the range, just output one datum with the range
        if ( $args->{output_ranges} ) {
            my %attrs = ();
            $attrs{"timeType"}       = "unix";
            $attrs{"timeValue"}      = $period->{end};
            $attrs{"startTimeType"}  = "unix";
            $attrs{"startTimeValue"} = $period->{start};
            $attrs{"endTimeType"}    = "unix";
            $attrs{"endTimeValue"}   = $period->{end};

            $args->{output}->startElement( prefix => "ifevt", tag => "datum", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", attributes => \%attrs );
            $args->{output}->createElement( prefix => "ifevt", tag => "stateAdmin", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_admin_status );
            $args->{output}->createElement( prefix => "ifevt", tag => "stateOper",  namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_oper_status );
            $args->{output}->endElement( "datum" );
        }
        else {
            my %attrs = ();

            #            $attrs{"timeType"} = "unix";
            #            $attrs{"timeValue"} = $period->{start};
            #            $args->{output}->startElement(prefix => "ifevt", tag => "datum", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", attributes => \%attrs);
            #              $args->{output}->createElement(prefix => "ifevt", tag => "stateAdmin", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_admin_status);
            #              $args->{output}->createElement(prefix => "ifevt", tag => "stateOper", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_oper_status);
            #            $args->{output}->endElement("datum");

            $attrs{"timeType"}  = "unix";
            $attrs{"timeValue"} = $period->{end};
            $args->{output}->startElement( prefix => "ifevt", tag => "datum", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", attributes => \%attrs );
            $args->{output}->createElement( prefix => "ifevt", tag => "stateAdmin", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_admin_status );
            $args->{output}->createElement( prefix => "ifevt", tag => "stateOper",  namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $period_oper_status );
            $args->{output}->endElement( "datum" );
        }
    }
    endData( $args->{output} );

    return;
}

=head2 find_overlap ( $self, $array1, $array2 ) 
    This function takes two arrays containing hashes with elements
    "start_time", "end_time", "oper_status" and "admin_status". The arrays must be
    sorted. The function will then go through and construct a new set of time
    periods corresponding to the overlap between the two arrays. The returned
    array will have a hash for each time period, and this hash will have the
    combined oper_status and admin_status for both arrays.
=cut

sub find_overlap {
    my ( $self, $array1, $array2 ) = @_;

    if ( scalar( @$array1 ) == 0 or scalar( @$array2 ) == 0 ) {
        return ();
    }

    my ( $i, $j );

    $i = 0;
    $j = 0;

    my @ret_periods = ();

    while ( $i < scalar( @$array1 ) and $j < scalar( @$array2 ) ) {
        my $curr_range1 = $array1->[$i];
        my $curr_range2 = $array2->[$j];

        # one of the ranges is completely outside the other, so skip them completely
        if ( $curr_range1->{end} < $curr_range2->{start} ) {
            $i++;
            next;
        }
        if ( $curr_range2->{end} < $curr_range1->{start} ) {
            $j++;
            next;
        }

        my $starts_first = ( $curr_range1->{start} < $curr_range2->{start} ) ? $curr_range1 : $curr_range2;
        my $starts_last  = ( $curr_range1->{start} < $curr_range2->{start} ) ? $curr_range2 : $curr_range1;
        my $ends_first   = ( $curr_range1->{end} < $curr_range2->{end} )     ? $curr_range1 : $curr_range2;
        my $ends_last    = ( $curr_range1->{end} < $curr_range2->{end} )     ? $curr_range2 : $curr_range1;

        # slice away the non-overlapping beginning
        $starts_first->{start} = $starts_last->{start};

        my %new_period = ();
        $new_period{start}        = $starts_last->{start};
        $new_period{end}          = $ends_first->{end};
        $new_period{oper_status}  = ();
        $new_period{admin_status} = ();
        foreach my $array ( $curr_range1, $curr_range2 ) {
            foreach my $status_type ( "oper", "admin" ) {
                foreach my $status ( @{ $array->{ $status_type . "_status" } } ) {
                    push @{ $new_period{ $status_type . "_status" } }, $status;
                }
            }
        }

        push @ret_periods, \%new_period;

        $ends_last->{start} = $new_period{end} + 1;

        $i++ if ( $ends_first == $curr_range1 );
        $j++ if ( $ends_first == $curr_range2 );
    }

    return @ret_periods;
}

=head2 outputCompatNodeElement ( $self, $output, $node )
    Outputs the specified node to the specified XML Output Object in the E2EMon
    compatible format.
=cut

sub outputCompatNodeElement {
    my ( $self, $output, $node ) = @_;

    $output->startElement( prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { id => $node->{"name"} } );
    $output->createElement( prefix => "nmwgtopo3", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => "TopologyPoint" );
    $output->createElement( prefix => "nmwgtopo3", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => $node->{"name"} );
    if ( defined $node->{"city"} and $node->{"city"} ne q{} ) {
        $output->createElement( prefix => "nmwgtopo3", tag => "city", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"city"} );
    }
    if ( defined $node->{"country"} and $node->{"country"} ne q{} ) {
        $output->createElement( prefix => "nmwgtopo3", tag => "country", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"country"} );
    }
    if ( defined $node->{"latitude"} and $node->{"latitude"} ne q{} ) {
        $output->createElement( prefix => "nmwgtopo3", tag => "latitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"latitude"} );
    }
    if ( defined $node->{"longitude"} and $node->{"longitude"} ne q{} ) {
        $output->createElement( prefix => "nmwgtopo3", tag => "longitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"longitude"} );
    }
    if ( defined $node->{"institution"} and $node->{"institution"} ne q{} ) {
        $output->createElement( prefix => "nmwgtopo3", tag => "institution", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/",, content => $node->{"institution"} );
    }
    $output->endElement( "node" );

    return;
}

=head2 outputCompatLinkElement ( $self, $output, $link )
    Outputs the specified link to the specified XML Output Object in the E2EMon
    compatible format.
=cut

sub outputCompatLinkElement {
    my ( $self, $output, $link ) = @_;

    $output->startElement( prefix => "nmtl2", tag => "link", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/" );
    $output->createElement( prefix => "nmtl2", tag => "name",       namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"name"} );
    $output->createElement( prefix => "nmtl2", tag => "globalName", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"globalName"} );
    $output->createElement( prefix => "nmtl2", tag => "type",       namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", content    => $link->{"type"} );
    foreach my $endpoint ( @{ $link->{"endpoints"} } ) {
        $output->startElement( prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $endpoint->{"name"} } );
        $output->createElement( prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $endpoint->{"type"} );
        $output->endElement( "node" );
    }
    $output->endElement( "link" );

    return;
}

=head2 constructE2EMonMetadataDB ( $self, $links, $nodes )
    Takes the links and nodes produced by parseCompatCircuitsFile, and
    constructs the E2EMon Metadata DB file. Due to how the E2EMon protocol
    allows for querying the database, this metadata database does not look like
    what is returned when you query for the entire database. It does not have
    any nodes at the top-level, only links. Each link, instead of having the
    pointers to the nodes as in the response metadata, has the node element
    inside it.
=cut

sub constructE2EMonMetadataDB {
    my ( $self, $links, $nodes ) = @_;

    my %link_mappings = ();

    my $comparison_metadatadb = perfSONAR_PS::XML::Document->new();

    $comparison_metadatadb->startElement( prefix => "nmwg", tag => "store", namespace => "http://ggf.org/ns/nmwg/base/2.0/" );
    foreach my $link_name ( keys %$links ) {
        my $link = $links->{$link_name};
        my $mdId = "metadata." . genuid();
        $link_mappings{$mdId} = $link_name;

        startMetadata( $comparison_metadatadb, $mdId, q{}, undef );
        $comparison_metadatadb->startElement( prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub." . genuid() } );
        $comparison_metadatadb->startElement( prefix => "nmtl2", tag => "link", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/" );
        $comparison_metadatadb->createElement( prefix => "nmtl2", tag => "name",       namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"name"} );
        $comparison_metadatadb->createElement( prefix => "nmtl2", tag => "globalName", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"globalName"} );
        $comparison_metadatadb->createElement( prefix => "nmtl2", tag => "type",       namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", content    => $link->{"type"} );
        foreach my $endpoint ( @{ $link->{"endpoints"} } ) {
            if ( not $nodes->{ $endpoint->{"name"} } ) {
                $comparison_metadatadb->startElement( prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $endpoint->{"name"} } );
                $comparison_metadatadb->createElement( prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $endpoint->{"type"} );
                $comparison_metadatadb->endElement( "node" );
            }
            else {
                $self->outputCompatNodeElement( $comparison_metadatadb, $nodes->{ $endpoint->{"name"} } );
            }
        }
        $comparison_metadatadb->endElement( "link" );
        $comparison_metadatadb->endElement( "subject" );
        $comparison_metadatadb->createElement( prefix => "nmwg", tag => "eventType", namespace => "http://ggf.org/ns/nmwg/base/2.0/", content => "Path.Status" );
        $comparison_metadatadb->createElement( prefix => "nmwg", tag => "eventType", namespace => "http://ggf.org/ns/nmwg/base/2.0/", content => "http://ggf.org/ns/nmwg/topology/l2/3.0/link/status" );
        endMetadata( $comparison_metadatadb );
    }
    $comparison_metadatadb->endElement( "store" );

    my $parser      = XML::LibXML->new();
    my $compare_dom = q{};
    eval { $compare_dom = $parser->parse_string( $comparison_metadatadb->getValue ); };
    if ( $EVAL_ERROR ) {
        my $msg = escapeString( "Parse failed: " . $EVAL_ERROR );

        $self->{LOGGER}->error( $msg );
        return ( -1, undef, undef );
    }

    return ( 0, $compare_dom, \%link_mappings );
}

=head2 parseCompatCircuitsFile ( $self, $file)
    Parses the E2EMon circuits file and returns the domain as a string, and the
    links and nodes as hashes.
=cut

sub parseCompatCircuitsFile {
    my ( $self, $file ) = @_;

    my %nodes = ();
    my %links = ();

    my $parser = XML::LibXML->new();
    my $doc;
    eval { $doc = $parser->parse_file( $file ); };
    if ( $@ or not defined $doc ) {
        my $msg = "Couldn't parse links file $file: $@";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $conf = $doc->documentElement;

    # Grab the domain field
    my $domain = findvalue( $conf, "domain" );
    if ( not defined $domain ) {
        my $msg = "No domain specified in configuration";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    # Grab the set of nodes
    my $find_res;
    $find_res = find( $conf, "./*[local-name()='node']", 0 );
    if ( $find_res ) {
        foreach my $endpoint ( $find_res->get_nodelist ) {
            my $node_name   = $endpoint->getAttribute( "name" );
            my $city        = findvalue( $endpoint, "city" );
            my $country     = findvalue( $endpoint, "country" );
            my $longitude   = findvalue( $endpoint, "longitude" );
            my $institution = findvalue( $endpoint, "institution" );
            my $latitude    = findvalue( $endpoint, "latitude" );

            if ( $node_name !~ /-/ ) {
                $node_name = $domain . "-" . $node_name;
            }

            if ( not defined $node_name or $node_name eq q{} ) {
                my $msg = "Node needs to have a name";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            $node_name =~ s/[^a-zA-Z0-9_-]//g;
            $node_name = uc( $node_name );

            if ( defined $nodes{$node_name} ) {
                my $msg = "Multiple endpoints have the name \"$node_name\"";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            $self->{LOGGER}->debug( "Found '$node_name'" );

            my %tmp      = ();
            my $new_node = \%tmp;

            $new_node->{"name"}        = $node_name   if ( defined $node_name   and $node_name   ne q{} );
            $new_node->{"city"}        = $city        if ( defined $city        and $city        ne q{} );
            $new_node->{"country"}     = $country     if ( defined $country     and $country     ne q{} );
            $new_node->{"longitude"}   = $longitude   if ( defined $longitude   and $longitude   ne q{} );
            $new_node->{"latitude"}    = $latitude    if ( defined $latitude    and $latitude    ne q{} );
            $new_node->{"institution"} = $institution if ( defined $institution and $institution ne q{} );

            $nodes{$node_name} = $new_node;
        }
    }

    # Grab the set of links
    foreach my $type ("link", "circuit") {
    $find_res = find( $conf, "./*[local-name()='$type']", 0 );
    if ( $find_res ) {
        foreach my $link ( $find_res->get_nodelist ) {
            my $global_name = findvalue( $link, "globalName" );
            my $local_name  = findvalue( $link, "localName" );
            my $link_type;

            if ( not defined $global_name or $global_name eq q{} ) {
                my $msg = "Circuit has no global name";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            if ( not defined $local_name or $local_name eq q{} ) {
                $local_name = $global_name;
            }

            my %subelements = ();

            $find_res = find( $link, "./*[local-name()='elementID']", 0 );
            if ( $find_res ) {
                foreach my $topo_id ( $find_res->get_nodelist ) {
                    my $id = $topo_id->textContent;

                    if ( defined $subelements{$id} ) {
                        my $msg = "Segment $id appears multiple times in link $global_name";
                        $self->{LOGGER}->error( $msg );
                        return ( -1, $msg );
                    }

                    $subelements{$id} = q{};
                }
            }

            if ( scalar( keys %subelements ) == 0 ) {
                my $msg = "No elements for link $global_name";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            my @endpoints = ();

            my $num_endpoints = 0;

            my $prev_domain;

            $find_res = find( $link, "./*[local-name()='endpoint']", 0 );
            if ( $find_res ) {
                foreach my $endpoint ( $find_res->get_nodelist ) {
                    my $node_type = $endpoint->getAttribute( "type" );
                    my $node_name = $endpoint->getAttribute( "name" );

                    if ( not defined $node_type or $node_type eq q{} ) {
                        my $msg = "Node with unspecified type found";
                        $self->{LOGGER}->error( $msg );
                        return ( -1, $msg );
                    }

                    if ( not defined $node_name or $node_name eq q{} ) {
                        my $msg = "Endpint needs to specify a node name";
                        $self->{LOGGER}->error( $msg );
                        return ( -1, $msg );
                    }

                    if ( $node_name !~ /-/ ) {
                        $node_name = $domain . "-" . $node_name;
                    }

                    $node_name =~ s/[^a-zA-Z0-9_-]//g;
                    $node_name = uc( $node_name );

                    if ( lc( $node_type ) ne "demarcpoint" and lc( $node_type ) ne "endpoint" ) {
                        my $msg = "Node found with invalid type $node_type. Must be \"DemarcPoint\" or \"EndPoint\"";
                        $self->{LOGGER}->error( $msg );
                        return ( -1, $msg );
                    }

                    my ( $domain, @junk ) = split( /-/, $node_name );
                    if ( not defined $prev_domain ) {
                        $prev_domain = $domain;
                    }
                    elsif ( $domain eq $prev_domain ) {
                        $link_type = "DOMAIN_Link";
                    }
                    else {
                        $link_type = "ID_LinkPartialInfo";
                    }

                    my %new_endpoint = ();

                    $new_endpoint{"type"} = $node_type;
                    $new_endpoint{"name"} = $node_name;

                    push @endpoints, \%new_endpoint;

                    $num_endpoints++;
                }
            }

            if ( $num_endpoints != 2 ) {
                my $msg = "Invalid number of endpoints, $num_endpoints, must be 2";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            my @subelements = keys %subelements;

            my %new_link = ();

            $new_link{"globalName"}  = $global_name;
            $new_link{"name"}        = $local_name;
            $new_link{"subelements"} = \@subelements;
            $new_link{"endpoints"}   = \@endpoints;
            $new_link{"type"}        = $link_type;

            if ( defined $links{$local_name} ) {
                my $msg = "Error: existing link of name $local_name";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }
            else {
                $links{$local_name} = \%new_link;
            }
        }
    }
    }

    $self->{LOGGER}->debug("Links: ".Dumper(\%links));

    return ( 0, $domain, \%links, \%nodes );
}

=head2 xPathFind ($self, $node, $query, $return_first)
    Does the find for this module. It uses the XPath context containing all the
    namespaces that this module knows about. This context is created when the
    module is initialized. If the "$return_first" is set to true, it returns
    the first node of the list.
=cut

sub xPathFind {
    my ( $self, $node, $query, $return_first ) = @_;
    my $res;

    eval { $res = $self->{XPATH_CONTEXT}->find( $query, $node ); };
    if ( $EVAL_ERROR ) {
        $self->{LOGGER}->error( "Error finding value($query): $@" );
        return;
    }

    if ( defined $return_first and $return_first == 1 ) {
        return $res->get_node( 1 );
    }

    return $res;
}

=head2 xPathFindValue ($self, $node, $query)
    This function is analogous to the xPathFind function above. Unlike the
    above, this function returns the text content of the nodes found.
=cut

sub xPathFindValue {
    my ( $self, $node, $xpath ) = @_;

    my $found_node;

    $found_node = $self->xPathFind( $node, $xpath, 1 );

    return if ( not defined $found_node );

    return $found_node->textContent;
}

1;

__END__

=head1 SEE ALSO

L<perfSONAR_PS::Common>,L<perfSONAR_PS::Messages>,L<perfSONAR_PS::Client::LS::Remote>,
L<perfSONAR_PS::DB::Status>,L<perfSONAR_PS::Utils::ParameterValidation>,
L<perfSONAR_PS::Services::MA::General>,

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

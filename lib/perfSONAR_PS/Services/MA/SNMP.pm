package perfSONAR_PS::Services::MA::SNMP;

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'NAMESPACES', 'METADATADB';

use strict;
use warnings;

our $VERSION = 0.07;

=head1 NAME

perfSONAR_PS::Services::MA::SNMP - A module that provides methods for the 
perfSONAR-PS SNMP based Measurement Archive (MA).

=head1 DESCRIPTION

This module, in conjunction with other parts of the perfSONAR-PS framework,
handles specific messages from interested actors in search of SNMP data.  There
are three major message types that this service can act upon:

 - MetadataKeyRequest     - Given some metadata about a specific measurement, 
                            request a re-playable 'key' to faster access
                            underlying data.
 - SetupDataRequest       - Given either metadata or a key regarding a specific
                            measurement, retrieve data values.
 - MetadataStorageRequest - Store data into the archive.
 
The module is capable of dealing with several characteristic and tool based
eventTypes related to the underlying data as well as the aforementioned message
types.  

=cut

use Log::Log4perl qw(get_logger);
use Module::Load;
use Digest::MD5 qw(md5_hex);
use English qw( -no_match_vars );
use Params::Validate qw(:all);

use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Error_compat qw/:try/;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

=head1 API

The offered API is not meant for external use as many of the functions are
relied upon by internal aspects of the perfSONAR-PS framework.

=head2 init($self, $handler)

Called at startup by the daemon when this particular module is loaded into
the perfSONAR-PS deployment.  Checks the configuration file for the necessary
items and fills in others when needed. Initializes the backed metadata storage
(DBXML or a simple XML file) and builds the internal 'key hash' for the 
MetadataKey exchanges.  Finally the message handler loads the appropriate 
message types and eventTypes for this module.  Any other 'pre-startup' tasks
should be placed in this function.

=cut

sub init {
    my ( $self, $handler ) = @_;
    $self->{CONF}->{"snmp"}->{"logger"} =
      get_logger("perfSONAR_PS::Services::MA::SNMP");

    unless ( exists $self->{CONF}->{"snmp"}->{"metadata_db_type"}
        and $self->{CONF}->{"snmp"}->{"metadata_db_type"} )
    {
        $self->{CONF}->{"snmp"}->{"logger"}
          ->error("Value for 'metadata_db_type' is not set.");
        return -1;
    }

    if ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        unless ( exists $self->{CONF}->{"snmp"}->{"metadata_db_file"}
            and $self->{CONF}->{"snmp"}->{"metadata_db_file"} )
        {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Value for 'metadata_db_file' is not set.");
            return -1;
        }
        else {
            if ( defined $self->{DIRECTORY} ) {
                unless ( $self->{CONF}->{"snmp"}->{"metadata_db_file"} =~ "^/" )
                {
                    $self->{CONF}->{"snmp"}->{"metadata_db_file"} =
                        $self->{DIRECTORY} . "/"
                      . $self->{CONF}->{"snmp"}->{"metadata_db_file"};
                }
            }
        }
    }
    elsif ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        eval { load perfSONAR_PS::DB::XMLDB; };
        if ($EVAL_ERROR) {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Couldn't load perfSONAR_PS::DB::XMLDB: $EVAL_ERROR");
            return -1;
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"metadata_db_file"}
            and $self->{CONF}->{"snmp"}->{"metadata_db_file"} )
        {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Value for 'metadata_db_file' is not set.");
            return -1;
        }
        unless ( exists $self->{CONF}->{"snmp"}->{"metadata_db_name"}
            and $self->{CONF}->{"snmp"}->{"metadata_db_name"} )
        {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Value for 'metadata_db_name' is not set.");
            return -1;
        }
        else {
            if ( defined $self->{DIRECTORY} ) {
                unless ( $self->{CONF}->{"snmp"}->{"metadata_db_name"} =~ "^/" )
                {
                    $self->{CONF}->{"snmp"}->{"metadata_db_name"} =
                        $self->{DIRECTORY} . "/"
                      . $self->{CONF}->{"snmp"}->{"metadata_db_name"};
                }
            }
        }
    }
    else {
        $self->{CONF}->{"snmp"}->{"logger"}
          ->error("Wrong value for 'metadata_db_type' set.");
        return -1;
    }

    unless ( exists $self->{CONF}->{"snmp"}->{"rrdtool"}
        and $self->{CONF}->{"snmp"}->{"rrdtool"} )
    {
        $self->{CONF}->{"snmp"}->{"logger"}
          ->error("Value for 'rrdtool' is not set.");
        return -1;
    }

    unless ( exists $self->{CONF}->{"snmp"}->{"default_resolution"}
        and $self->{CONF}->{"snmp"}->{"default_resolution"} )
    {
        $self->{CONF}->{"snmp"}->{"default_resolution"} = "300";
        $self->{CONF}->{"snmp"}->{"logger"}
          ->warn("Setting 'default_resolution' to '300'.");
    }

    unless ( exists $self->{CONF}->{"snmp"}->{"enable_registration"}
        and $self->{CONF}->{"snmp"}->{"enable_registration"} )
    {
        $self->{CONF}->{"snmp"}->{"enable_registration"} = 0;
    }

    if ( $self->{CONF}->{"snmp"}->{"enable_registration"} ) {
        unless ( exists $self->{CONF}->{"snmp"}->{"service_accesspoint"}
            and $self->{CONF}->{"snmp"}->{"service_accesspoint"} )
        {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("No access point specified for SNMP service");
            return -1;
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"ls_instance"}
            and $self->{CONF}->{"snmp"}->{"ls_instance"} )
        {
            if ( defined $self->{CONF}->{"ls_instance"}
                and $self->{CONF}->{"ls_instance"} )
            {
                $self->{CONF}->{"snmp"}->{"ls_instance"} =
                  $self->{CONF}->{"ls_instance"};
            }
            else {
                $self->{CONF}->{"snmp"}->{"logger"}
                  ->error("No LS instance specified for SNMP service");
                return -1;
            }
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"ls_registration_interval"}
            and $self->{CONF}->{"snmp"}->{"ls_registration_interval"} )
        {
            if ( defined $self->{CONF}->{"ls_registration_interval"}
                and $self->{CONF}->{"ls_registration_interval"} )
            {
                $self->{CONF}->{"snmp"}->{"ls_registration_interval"} =
                  $self->{CONF}->{"ls_registration_interval"};
            }
            else {
                $self->{CONF}->{"snmp"}->{"logger"}
                  ->warn("Setting registration interval to 30 minutes");
                $self->{CONF}->{"snmp"}->{"ls_registration_interval"} = 1800;
            }
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"service_accesspoint"}
            and $self->{CONF}->{"snmp"}->{"service_accesspoint"} )
        {
            $self->{CONF}->{"snmp"}->{"service_accesspoint"} =
              "http://localhost:" . $self->{PORT} . "/" . $self->{ENDPOINT};
            $self->{CONF}->{"snmp"}->{"logger"}
              ->warn( "Setting 'service_accesspoint' to 'http://localhost:"
                  . $self->{PORT} . "/"
                  . $self->{ENDPOINT}
                  . "'." );
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"service_description"}
            and $self->{CONF}->{"snmp"}->{"service_description"} )
        {
            $self->{CONF}->{"snmp"}->{"service_description"} =
              "perfSONAR_PS SNMP MA";
            $self->{CONF}->{"snmp"}->{"logger"}->warn(
                "Setting 'service_description' to 'perfSONAR_PS SNMP MA'.");
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"service_name"}
            and $self->{CONF}->{"snmp"}->{"service_name"} )
        {
            $self->{CONF}->{"snmp"}->{"service_name"} = "SNMP MA";
            $self->{CONF}->{"snmp"}->{"logger"}
              ->warn("Setting 'service_name' to 'SNMP MA'.");
        }

        unless ( exists $self->{CONF}->{"snmp"}->{"service_type"}
            and $self->{CONF}->{"snmp"}->{"service_type"} )
        {
            $self->{CONF}->{"snmp"}->{"service_type"} = "MA";
            $self->{CONF}->{"snmp"}->{"logger"}
              ->warn("Setting 'service_type' to 'MA'.");
        }
    }

    my $metadatadb;
    my $error;
    if ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        $metadatadb = new perfSONAR_PS::DB::File(
            $self->{CONF}->{"snmp"}->{"metadata_db_file"} );
    }
    elsif ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        $metadatadb = new perfSONAR_PS::DB::XMLDB(
            $self->{CONF}->{"snmp"}->{"metadata_db_name"},
            $self->{CONF}->{"snmp"}->{"metadata_db_file"},
            \%{ $self->{NAMESPACES} }
        );
    }
    $metadatadb->openDB( \$error );

    if ($error) {
        $self->{CONF}->{"snmp"}->{"logger"}
          ->error("Couldn't initialize store file: $error");
        return -1;
    }

    $self->{METADATADB} = $metadatadb;

    $self->buildHashedKeys;

    $handler->registerMessageHandler( "SetupDataRequest",   $self );
    $handler->registerMessageHandler( "MetadataKeyRequest", $self );

    return 0;
}

=head2 buildHashedKeys($self)

With the backend storage known (i.e. $self->{METADATADB}) we can search through
looking for key structures.  Once we have these in hand each will be examined
and Digest::MD5 will be utilized to create MD5 hex based fingerprints of each
key.  We then map these to the key ids in the metadata database for easy lookup.

=cut

sub buildHashedKeys {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, {} );

    my $queryString = "/nmwg:store/nmwg:data";
    my $error       = q{};
    my $metadatadb  = $self->{METADATADB};

    if ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        my $results = $metadatadb->querySet($queryString);
        if ( $results->size() > 0 ) {
            foreach my $data ( $results->get_nodelist ) {
                if ( $data->getAttribute("id") ) {
                    my $hash = md5_hex( $data->toString );
                    $self->{CONF}->{"snmp"}->{"hashToId"}->{$hash} = $data->getAttribute("id");
                    $self->{CONF}->{"snmp"}->{"idToHash"}->{ $data->getAttribute("id") } = $hash;
                    $self->{CONF}->{"snmp"}->{"logger"}->debug("Key id $hash maps to data element ".$data->getAttribute("id"));
                }
            }
        }
    }
    elsif ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        my @resultsString = ();
        my $dbTr          = $metadatadb->getTransaction( \$error );
        if ( $dbTr and ( not $error ) ) {
            @resultsString = $metadatadb->query( $queryString, $dbTr, \$error );

            $metadatadb->commitTransaction( $dbTr, \$error );
            undef $dbTr;
            if ($error) {
                $self->{CONF}->{"snmp"}->{"logger"}
                  ->error( "Database Error: \"" . $error . "\"." );
                $metadatadb->abortTransaction( $dbTr, \$error ) if $dbTr;
                undef $dbTr;
                return;
            }
        }
        else {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Cound not start database transaction.");
            $metadatadb->abortTransaction( $dbTr, \$error ) if $dbTr;
            undef $dbTr;
            return;
        }

        # do stuff...

    }
    return;
}

=head2 needLS($self)

This particular service (SNMP MA) should register with a lookup service.  This
function simply returns the value set in the configuration file (either yes or
no, depending on user preference) to let other parts of the framework know if
LS registration is required.

=cut

sub needLS {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, {} );

    return ( $self->{CONF}->{"snmp"}->{"enable_registration"} );
}

=head2 registerLS($self)

Given the service information (specified in configuration) and the contents of
our metadata database, we can contact the specified LS and register ourselves.

=cut

sub registerLS {
    my ( $self, $sleep_time ) = validate_pos(@_,
                1,
                { type => SCALARREF },
            );

    my ( $status, $res );
    my $ls = q{};

    if ( !defined $self->{LS_CLIENT} ) {
        my %ls_conf = (
            SERVICE_TYPE => $self->{CONF}->{"snmp"}->{"service_type"},
            SERVICE_NAME => $self->{CONF}->{"snmp"}->{"service_name"},
            SERVICE_DESCRIPTION =>
              $self->{CONF}->{"snmp"}->{"service_description"},
            SERVICE_ACCESSPOINT =>
              $self->{CONF}->{"snmp"}->{"service_accesspoint"},
        );

        $self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote(
            $self->{CONF}->{"snmp"}->{"ls_instance"},
            \%ls_conf, $self->{NAMESPACES} );
    }

    $ls = $self->{LS_CLIENT};

    my $queryString   = "/nmwg:store/nmwg:metadata";
    my $error         = q{};
    my $metadatadb    = $self->{METADATADB};
    my @resultsString = ();

    if ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        @resultsString = $metadatadb->query($queryString);
    }
    elsif ( $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        my $dbTr = $metadatadb->getTransaction( \$error );
        if ( $dbTr and ( not $error ) ) {
            @resultsString = $metadatadb->query( $queryString, $dbTr, \$error );

            $metadatadb->commitTransaction( $dbTr, \$error );
            undef $dbTr;
            if ($error) {
                $self->{CONF}->{"snmp"}->{"logger"}
                  ->error( "Database Error: \"" . $error . "\"." );
                $metadatadb->abortTransaction( $dbTr, \$error ) if $dbTr;
                undef $dbTr;
                return;
            }
        }
        else {
            $self->{CONF}->{"snmp"}->{"logger"}
              ->error("Cound not start database transaction.");
            $metadatadb->abortTransaction( $dbTr, \$error ) if $dbTr;
            undef $dbTr;
            return;
        }
    }

    return $ls->registerStatic( \@resultsString );
}

=head2 handleMessageBegin($self, $ret_message, $messageId, $messageType, 
                          $msgParams, $request, $retMessageType, 
                          $retMessageNamespaces)

Stub function that is currently unused.  Will be used to interact with the 
daemon's message handler.

=cut

sub handleMessageBegin {
    my ( $self, $ret_message, $messageId, $messageType, $msgParams, $request,
        $retMessageType, $retMessageNamespaces )
      = @_;

    #   my ($self, @args) = @_;
    #      my $parameters = validate(@args,
    #            {
    #                ret_message => 1,
    #                messageId => 1,
    #                messageType => 1,
    #                msgParams => 1,
    #                request => 1,
    #                retMessageType => 1,
    #                retMessageNamespaces => 1
    #            });

    return 0;
}

=head2 handleMessageEnd($self, $ret_message, $messageId)

Stub function that is currently unused.  Will be used to interact with the 
daemon's message handler.

=cut

sub handleMessageEnd {
    my ( $self, $ret_message, $messageId ) = @_;

    #   my ($self, @args) = @_;
    #      my $parameters = validate(@args,
    #            {
    #                ret_message => 1,
    #                messageId => 1
    #            });

    return 0;
}

=head2 handleEvent($self, $output, $messageId, $messageType,
                   $message_parameters, $eventType, $md, $d, $raw_request)

Current workaround to the daemon's message handler.  All messages that enter
will be routed based on the message type.  The appropriate solution to this
problem is to route on eventType and message type and will be implemented in
future releases.

=cut

sub handleEvent {
    my ($self, @args) = @_;
      my $parameters = validate(@args,
            {
                output => 1,
                messageId => 1,
                messageType => 1,
                messageParameters => 1,
                eventType => 1,
                subject => 1,
                filterChain => 1,
                data => 1,
                rawRequest => 1,
                doOutputMetadata => 1,
            });

    my $output = $parameters->{"output"};
    my $messageId = $parameters->{"messageId"};
    my $messageType = $parameters->{"messageType"};
    my $message_parameters = $parameters->{"messageParameters"};
    my $eventType = $parameters->{"eventType"};
    my $d = $parameters->{"data"};
    my $raw_request = $parameters->{"rawRequest"};
    my @subjects = @{ $parameters->{"subject"} };
    my @filters = @{ $parameters->{"filterChain"} };

    my $md = $subjects[0];

    my $doOutputMetadata = $parameters->{"doOutputMetadata"};


    # this module outputs its own metadata so it needs to turn off the daemon's
    # metadata output routines.
    ${$doOutputMetadata} = 0;

    my %timeSettings = ();

    # go through the main subject and select filters looking for parameters.
    my $new_timeSettings = $self->getFilterParameters($md, $parameters->{rawRequest}->getNamespaces(), $self->{CONF}->{"snmp"}->{"default_resolution"});

    $timeSettings{"CF"} = $new_timeSettings->{"CF"} if (defined $new_timeSettings->{"CF"});
    $timeSettings{"RESOLUTION"} = $new_timeSettings->{"RESOLUTION"} if (defined $new_timeSettings->{"RESOLUTION"} and $timeSettings{"RESOLUTION_SPECIFIED"});
    $timeSettings{"RESOLUTION_SPECIFIED"} = $new_timeSettings->{"RESOLUTION_SPECIFIED"} if ($new_timeSettings->{"RESOLUTION_SPECIFIED"});
    $timeSettings{"START"} = $new_timeSettings->{"START"} if (defined $new_timeSettings->{"START"});
    $timeSettings{"END"} = $new_timeSettings->{"END"} if (defined $new_timeSettings->{"END"});

    if ($#filters > -1) {
        foreach my $filter_arr (@filters) {
            my @filters = @{ $filter_arr };
            my $filter = $filters[$#filters];

            $new_timeSettings = $self->getFilterParameters($filter, $parameters->{rawRequest}->getNamespaces(), $self->{CONF}->{"snmp"}->{"default_resolution"});

            $timeSettings{"CF"} = $new_timeSettings->{"CF"} if (defined $new_timeSettings->{"CF"});
            $timeSettings{"RESOLUTION"} = $new_timeSettings->{"RESOLUTION"} if (defined $new_timeSettings->{"RESOLUTION"} and $new_timeSettings->{"RESOLUTION_SPECIFIED"});
            $timeSettings{"RESOLUTION_SPECIFIED"} = $new_timeSettings->{"RESOLUTION_SPECIFIED"} if ($new_timeSettings->{"RESOLUTION_SPECIFIED"});

            # we conditionally replace the START/END settings since under the theory of
            # filter, if a later element specifies an earlier start time, the later
            # start time that appears higher in the filter chain would have filtered
            # out all times earlier than itself leaving nothing to exist between the
            # earlier start time and the later start time. XXX I'm not sure how
            # the resolution and the consolidation function should work in this
            # context.

            if (defined $new_timeSettings->{"START"} and (not defined $timeSettings{"START"} or $new_timeSettings->{"START"} > $timeSettings{"START"})) {
                $timeSettings{"START"} = $new_timeSettings->{"START"};
            }

            if (defined $new_timeSettings->{"END"} and (not defined $timeSettings{"END"} or $new_timeSettings->{"END"} < $timeSettings{"END"})) {
                $timeSettings{"END"} = $new_timeSettings->{"END"};
            }
        }
    }

    # If no resolution was listed in the filters, go with the default
    if (not defined $timeSettings{"RESOLUTION"}) {
        $timeSettings{"RESOLUTION"} = $self->{CONF}->{"snmp"}->{"default_resolution"};
        $timeSettings{"RESOLUTION_SPECIFIED"} = 0;
    }

    my $cf = "";
    my $resolution = "";
    my $start = "";
    my $end = "";

    $cf = $timeSettings{"CF"} if ($timeSettings{"CF"});
    $resolution =$timeSettings{"RESOLUTION"} if ($timeSettings{"RESOLUTION"});
    $start = $timeSettings{"START"} if ($timeSettings{"START"});
    $end = $timeSettings{"END"} if ($timeSettings{"END"});

    $self->{CONF}->{"snmp"}->{"logger"}->debug("Request filter parameters: cf: $cf resolution: $resolution start: $start end: $end");

    if ( $messageType eq "MetadataKeyRequest" ) {
        return $self->maMetadataKeyRequest(
            {
                output             => $output,
                metadata           => $md,
                filters            => \@filters,
                time_settings      => \%timeSettings,
                request            => $raw_request,
                message_parameters => $message_parameters
            }
        );
    }
    else {
        return $self->maSetupDataRequest(
            {
                output             => $output,
                metadata           => $md,
                filters            => \@filters,
                time_settings      => \%timeSettings,
                request            => $raw_request,
                message_parameters => $message_parameters
            }
        );
    }
}

=head2 maMetadataKeyRequest($self, $output, $md, $request, $message_parameters)

Main handler of MetadataKeyRequest messages.  Based on contents (i.e. was a
key sent in the request, or not) this will route to one of two functions:

 - metadataKeyRetrieveKey          - Handles all requests that enter with a 
                                     key present.  
 - metadataKeyRetrieveMetadataData - Handles all other requests
 
Chaining operations are handled internally, although chaining will eventually
be moved to the overall message handler as it is an important operation that
all services will need.

The goal of this message type is to return a pointer (i.e. a 'key') to the data
so that the more expensive operation of XPath searching the database is avoided
with a simple hashed key lookup.  The key currently can be replayed repeatedly
currently because it is not time sensitive.  

=cut

sub maMetadataKeyRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            output             => 1,
            metadata           => 1,
            time_settings      => 1,
            filters            => 1,
            request            => 1,
            message_parameters => 1
        }
    );

    my $mdId = q{};
    my $dId  = q{};

    my $metadatadb = $self->{METADATADB};

    my $nmwg_key = find( $parameters->{metadata}, "./nmwg:key", 1 );
    if ( $nmwg_key ) {
        $self->metadataKeyRetrieveKey(
                {
                    metadatadb    => $self->{METADATADB},
                    time_settings => $parameters->{time_settings},
                    key           => $nmwg_key,
                    metadata      => $parameters->{metadata},
                    filters       => $parameters->{filters},
                    request_namespaces => $parameters->{request}->getNamespaces(),
                    output => $parameters->{output}
                }
                );
    } else {
        $self->metadataKeyRetrieveMetadataData(
                {
                    metadatadb    => $self->{METADATADB},
                    time_settings => $parameters->{time_settings},
                    metadata      => $parameters->{metadata},
                    filters       => $parameters->{filters},
                    request_namespaces => $parameters->{request}->getNamespaces(),
                    output => $parameters->{output}
                }
                );

    }

    return;
}

=head2 metadataKeyRetrieveKey($self, $metadatadb, $key, $chain, $id, 
                              $request_namespaces, $output)

Because the request entered with a key, we must handle it in this particular
function.  We first attempt to extract the 'maKey' hash and check for validity.
An invalid or missing key will trigger an error instantly.  If the key is found
we see if any chaining needs to be done (and appropriately 'cook' the key), then
return the response.

=cut

sub metadataKeyRetrieveKey {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            metadatadb         => 1,
            key                => 1,
            time_settings      => 1,
            metadata           => 1,
            filters            => 1,
            request_namespaces => 1,
            output             => 1
        }
    );

    my $mdId = "metadata." . genuid();
    my $dId  = "data." . genuid();

    my $hashKey =
      extract(
        find( $parameters->{key}, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ),
        0 );
    if ($hashKey) {
        my $hashId = $self->{CONF}->{"snmp"}->{"hashToId"}->{$hashKey};
        if ($hashId) {
            if (
                $parameters->{metadatadb}->count(
                    "/nmwg:store/nmwg:data[\@id=\"" . $hashId . "\"]"
                ) != 1
              )
            {
                my $msg = "Key error in metadata storage.";
                $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
                throw perfSONAR_PS::Error_compat( "error.ma.storage_result",
                    $msg );
                return;
            }
        }
        else {
            my $msg = "Key error in metadata storage.";
            $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
            throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
            return;
        }
    }
    else {
        my $msg = "Key error in metadata storage.";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return;
    }

    my $mdIdRef;

    my @filters = @{ $parameters->{filters} };
    if ($#filters > -1) {
        $mdIdRef = $filters[$#filters][0]->getAttribute("id");
    } else {
        $mdIdRef = $parameters->{metadata}->getAttribute("id");
    }

    # Generate 
    createMetadata( $parameters->{output}, $mdId, $mdIdRef, $parameters->{key}->toString, undef );

    my $key2 = $parameters->{key}->cloneNode(1);

    my $params = find($key2, ".//nmwg:parameters", 1);

    $self->addSelectParameters({ parameter_block => $params, filters => $parameters->{filters} });

    createData( $parameters->{output}, $dId, $mdId, $key2->toString, undef );

    return;
}

sub addSelectParameters {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            parameter_block    => 1,
            filters            => 1,
        }
    );

    my $params = $parameters->{parameter_block};
    my @filters = @{ $parameters->{filters} };
    my %paramsByName = ();

    foreach my $p ($params->childNodes) {
        if ($p->localname and $p->localname eq "parameter" and $p->getAttribute("name")) {
            $paramsByName{$p->getAttribute("name")} = $p;
        }
    }

    foreach my $filter_arr (@filters) {
        my @filters = @{ $filter_arr };
        my $filter = $filters[$#filters];

        $self->{CONF}->{"snmp"}->{"logger"}->debug("Filter: ".$filter->toString);

        my $select_params = find($filter, "./select:parameters", 1);
        if ($select_params) {
            foreach my $p ($select_params->childNodes) {
                if ($p->localname and $p->localname eq "parameter" and $p->getAttribute("name")) {
                    my $newChild = $p->cloneNode(1);

                    if ($paramsByName{$p->getAttribute("name")}) {
                        $params->replaceChild($newChild, $paramsByName{$p->getAttribute("name")});
                    } else {
                        $params->addChild($newChild);
                    }

                    $paramsByName{$p->getAttribute("name")} = $newChild;
                }
            }
        }
    }
}

=head2 metadataKeyRetrieveMetadataData($self, $metadatadb, $metadata, $chain,
                                       $id, $request_namespaces, $output)

Similar to 'metadataKeyRetrieveKey' we are looking to return a valid key.  The
input will be partially or fully specified metadata.  If this matches something
in the database we will return a key matching the description (in the form of
an MD5 fingerprint).  If this metadata was a part of a chain the chaining will
be resolved and used to augment (i.e. 'cook') the key.

=cut

sub metadataKeyRetrieveMetadataData {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            metadatadb         => 1,
            time_settings      => 1,
            metadata           => 1,
            filters            => 1,
            request_namespaces => 1,
            output             => 1
        }
    );

    my $mdId = q{};
    my $dId  = q{};

    my $queryString = "/nmwg:store/nmwg:metadata["
      . getMetadataXQuery( $parameters->{metadata}, q{} ) . "]";
    my $results = $parameters->{metadatadb}->querySet($queryString);

    my %et = ();
    my $eventTypes = find( $parameters->{metadata}, "./nmwg:eventType", 0 );
    my $supportedEventTypes = find( $parameters->{metadata}, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0 );
    foreach my $e ( $eventTypes->get_nodelist ) {
        my $value = extract( $e, 0 );
        if ($value) {
            $et{$value} = 1;
        }
    }
    foreach my $se ( $supportedEventTypes->get_nodelist ) {
        my $value = extract( $se, 0 );
        if ($value) {
            $et{$value} = 1;
        }
    }

    $queryString = "/nmwg:store/nmwg:data";
    if ( $eventTypes->size() or $supportedEventTypes->size() ) {
        $queryString = $queryString
          . "[./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"";
        foreach my $e ( sort keys %et ) {
            $queryString =
                $queryString
              . " and \@value=\""
              . $e
              . "\" or text()=\""
              . $e . "\"";
        }
        $queryString = $queryString . "]]";
    }
    my $dataResults = $parameters->{metadatadb}->querySet($queryString);

    if ( $results->size() > 0 and $dataResults->size() > 0 ) {
        my %mds = ();
        foreach my $md ($results->get_nodelist) {
            my $curr_md_id = $md->getAttribute("id");
            next if not $curr_md_id;

            $mds{$curr_md_id} = $md;
        }

        foreach my $d ( $dataResults->get_nodelist ) {
            my $curr_d_mdIdRef = $d->getAttribute("metadataIdRef");
            next if (not $curr_d_mdIdRef or not exists $mds{$curr_d_mdIdRef});
            my $curr_md = $mds{$curr_d_mdIdRef};

            my $dId  = "data." . genuid();
            my $mdId = "metadata." . genuid();

            my $md_temp = $curr_md->cloneNode(1);
            $md_temp->setAttribute( "metadataIdRef", $curr_d_mdIdRef );
            $md_temp->setAttribute( "id",            $mdId );

            $parameters->{output}->addExistingXMLElement($md_temp);

            my $hashId = $d->getAttribute("id");
            my $hashKey = $self->{CONF}->{"snmp"}->{"idToHash"}->{$hashId};

            next if (not defined $hashKey);

            startData($parameters->{output}, $dId, $mdId, undef);
                $parameters->{output}->startElement({ prefix => "nmwg", tag => "key", namespace => "http://ggf.org/ns/nmwg/base/2.0/" });
                    startParameters($parameters->{output}, "params.0");
                        addParameter($parameters->{output}, "maKey", $hashKey);
                        addParameter($parameters->{output}, "startTime", $parameters->{time_settings}->{"START"}) if (defined $parameters->{time_settings}->{"START"});
                        addParameter($parameters->{output}, "endTime", $parameters->{time_settings}->{"END"}) if (defined $parameters->{time_settings}->{"END"});
                        if (defined $parameters->{time_settings}->{"RESOLUTION"} and $parameters->{time_settings}->{"RESOLUTION_SPECIFIED"}) {
                        addParameter($parameters->{output}, "resolution", $parameters->{time_settings}->{"RESOLUTION"});
                        }
                        addParameter($parameters->{output}, "consolidationFunction", $parameters->{time_settings}->{"CF"}) if (defined $parameters->{time_settings}->{"CF"});
                    endParameters($parameters->{output});
                $parameters->{output}->endElement("key");
            endData($parameters->{output});
        }
    }
    else {
        my $msg =
            "Database \""
          . $self->{CONF}->{"snmp"}->{"metadata_db_file"}
          . "\" returned 0 results for search";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }
    return;
}

=head2 maSetupDataRequest($self, $output, $md, $request, $message_parameters)

Main handler of SetupDataRequest messages.  Based on contents (i.e. was a
key sent in the request, or not) this will route to one of two functions:

 - setupDataRetrieveKey          - Handles all requests that enter with a 
                                   key present.  
 - setupDataRetrieveMetadataData - Handles all other requests
 
Chaining operations are handled internally, although chaining will eventually
be moved to the overall message handler as it is an important operation that
all services will need.

The goal of this message type is to return actual data, so after the metadata
section is resolved the appropriate data handler will be called to interact
with the database of choice (i.e. rrdtool, mysql, sqlite).  

=cut

sub maSetupDataRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate(
            @args,
            {
            output             => 1,
            metadata           => 1,
            filters            => 1,
            time_settings      => 1,
            request            => 1,
            message_parameters => 1
            }
            );

    my $mdId = q{};
    my $dId  = q{};

    my $metadatadb = $self->{METADATADB};

    my $nmwg_key = find( $parameters->{metadata}, "./nmwg:key", 1 );
    if ( $nmwg_key ) {
        $self->setupDataRetrieveKey(
                {
                    metadatadb => $metadatadb,
                    metadata   => $nmwg_key,
                    filters    => $parameters->{filters},
                    message_parameters => $parameters->{message_parameters},
                    time_settings => $parameters->{time_settings},
                    request_namespaces => $parameters->{request}->getNamespaces(),
                    output => $parameters->{output}
                }
                );
    }
    else {
        $self->setupDataRetrieveMetadataData(
                {
                    metadatadb => $metadatadb,
                    metadata   => $parameters->{metadata},
                    filters    => $parameters->{filters},
                    time_settings => $parameters->{time_settings},
                    message_parameters => $parameters->{message_parameters},
                    output             => $parameters->{output}
                }
                );
    }

    return;
}

=head2 setupDataRetrieveKey($self, $metadatadb, $metadata, $chain, $id,
                            $message_parameters, $request_namespaces, $output)

Because the request entered with a key, we must handle it in this particular
function.  We first attempt to extract the 'maKey' hash and check for validity.
An invalid or missing key will trigger an error instantly.  If the key is found
we see if any chaining needs to be done.  We finally call the handle data
function, passing along the useful pieces of information from the metadata
database to locate and interact with the backend storage (i.e. rrdtool, mysql, 
sqlite).  

=cut

sub setupDataRetrieveKey {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            metadatadb         => 1,
            metadata           => 1,
            filters            => 1,
            time_settings      => 1,
            message_parameters => 1,
            request_namespaces => 1,
            output             => 1
        }
    );

    my $mdId    = q{};
    my $dId     = q{};
    my $results = q{};

    my $hashKey = extract(
        find(
            $parameters->{metadata}, ".//nmwg:parameter[\@name=\"maKey\"]",
            1
        ),
        0
    );
    if ($hashKey) {
        my $hashId = $self->{CONF}->{"snmp"}->{"hashToId"}->{$hashKey};
        $self->{CONF}->{"snmp"}->{"logger"}->debug("Received hash key $hashKey which maps to $hashId");
        if ($hashId) {
            $results =
              $parameters->{metadatadb}->querySet(
                "/nmwg:store/nmwg:data[\@id=\"" . $hashId . "\"]" );
            if ( $results->size() != 1 ) {
                my $msg = "Key error in metadata storage.";
                $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
                throw perfSONAR_PS::Error_compat( "error.ma.storage_result",
                    $msg );
                return;
            }
        }
        else {
            my $msg = "Key error in metadata storage.";
            $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
            throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
            return;
        }
    }
    else {
        my $msg = "Key error in metadata storage.";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage_result", $msg );
        return;
    }

    my $sentKey      = $parameters->{metadata}->cloneNode(1);
    my $results_temp = $results->get_node(1)->cloneNode(1);
    my $storedKey    = find( $results_temp, "./nmwg:key", 1 );

    my %l_et = ();
    my $l_supportedEventTypes =
      find( $storedKey, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0 );
    foreach my $se ( $l_supportedEventTypes->get_nodelist ) {
        my $value = extract( $se, 0 );
        if ($value) {
            $l_et{$value} = 1;
        }
    }

    $mdId = "metadata." . genuid();
    $dId  = "data." . genuid();

    my $mdIdRef = $parameters->{metadata}->getAttribute("id");

    my @filters = @{ $parameters->{filters} };

    if ($#filters > -1) {
        $self->addSelectParameters({ parameter_block => find($sentKey, ".//nmwg:parameters", 1), filters => \@filters });

        $mdIdRef = $filters[$#filters][0]->getAttribute("id");
    }

    createMetadata( $parameters->{output}, $mdId, $mdIdRef, $sentKey->toString, undef );
    $self->handleData(
        {
            id                 => $mdId,
            data               => $results_temp,
            output             => $parameters->{output},
            time_settings      => $parameters->{time_settings},
            et                 => \%l_et,
            message_parameters => $parameters->{message_parameters}
        }
    );

    return;
}

=head2 setupDataRetrieveMetadataData($self, $metadatadb, $metadata, $id, 
                                     $message_parameters, $output)

Similar to 'setupDataRetrieveKey' we are looking to return data.  The input
will be partially or fully specified metadata.  If this matches something in
the database we will return a data matching the description.  If this metadata
was a part of a chain the chaining will be resolved passed along to the data
handling function.

=cut

sub setupDataRetrieveMetadataData {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            metadatadb         => 1,
            metadata           => 1,
            filters            => 1,
            time_settings      => 1,
            message_parameters => 1,
            output             => 1
        }
    );

    my $mdId = q{};
    my $dId  = q{};

    my $queryString = "/nmwg:store/nmwg:metadata["
      . getMetadataXQuery( $parameters->{metadata}, q{} ) . "]";
    my $results = $parameters->{metadatadb}->querySet($queryString);

    my %et = ();
    my $eventTypes = find( $parameters->{metadata}, "./nmwg:eventType", 0 );
    my $supportedEventTypes = find( $parameters->{metadata},
        ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0 );
    foreach my $e ( $eventTypes->get_nodelist ) {
        my $value = extract( $e, 0 );
        if ($value) {
            $et{$value} = 1;
        }
    }
    foreach my $se ( $supportedEventTypes->get_nodelist ) {
        my $value = extract( $se, 0 );
        if ($value) {
            $et{$value} = 1;
        }
    }

    $queryString = "/nmwg:store/nmwg:data";
    if ( $eventTypes->size() or $supportedEventTypes->size() ) {
        $queryString = $queryString
          . "[./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"";
        foreach my $e ( sort keys %et ) {
            $queryString =
                $queryString
              . " and \@value=\""
              . $e
              . "\" or text()=\""
              . $e . "\"";
        }
        $queryString = $queryString . "]]";
    }
    my $dataResults = $parameters->{metadatadb}->querySet($queryString);

    my %used = ();
    for my $x ( 0 .. $dataResults->size() ) {
        $used{$x} = 0;
    }

    my $base_id = $parameters->{metadata}->getAttribute("id");
    my @filters = @{ $parameters->{filters} };
    if ($#filters > -1) {
        my @filter_arr = @{ $filters[$#filters] };

        $base_id = $filter_arr[0]->getAttribute("id");
    }

    if ( $results->size() > 0 and $dataResults->size() > 0 ) {
        my %mds = ();
        foreach my $md ( $results->get_nodelist ) {
            next if not $md->getAttribute("id");

            my %l_et = ();
            my $l_eventTypes = find( $md, "./nmwg:eventType", 0 );
            my $l_supportedEventTypes = find( $md, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0 );
            foreach my $e ( $l_eventTypes->get_nodelist ) {
                my $value = extract( $e, 0 );
                if ($value) {
                    $l_et{$value} = 1;
                }
            }
            foreach my $se ( $l_supportedEventTypes->get_nodelist ) {
                my $value = extract( $se, 0 );
                if ($value) {
                    $l_et{$value} = 1;
                }
            }

            my %hash = ();
            $hash{"md"} = $md;
            $hash{"et"} = \%l_et;
            $mds{$md->getAttribute("id")} = \%hash;
        }

        foreach my $d ( $dataResults->get_nodelist ) {
            my $idRef = $d->getAttribute("metadataIdRef");

            next if (not defined $idRef or not defined $mds{$idRef});

            my $md_temp = $mds{$idRef}->{"md"}->cloneNode(1);
            my $d_temp = $d->cloneNode(1);
            $mdId = "metadata." . genuid();
            $md_temp->setAttribute( "metadataIdRef", $base_id );
            $md_temp->setAttribute( "id",            $mdId );
            $parameters->{output}->addExistingXMLElement($md_temp);
            $self->handleData(
                    {
                        id                 => $mdId,
                        data               => $d_temp,
                        output             => $parameters->{output},
                        time_settings      => $parameters->{time_settings},
                        et                 => $mds{$idRef}->{"et"},
                        message_parameters => $parameters->{message_parameters}
                    });
        }
    }
    else {
        my $msg =
            "Database \""
          . $self->{CONF}->{"snmp"}->{"metadata_db_file"}
          . "\" returned 0 results for search";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }
    return;
}

=head2 handleData($self, $id, $data, $output, $et, $message_parameters)

Directs the data retrieval operations based on a value found in the metadata
database's representation of the key (i.e. storage 'type').  Current offerings
only interact with rrd files and sql databases.

=cut

sub handleData {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            id                 => 1,
            data               => 1,
            output             => 1,
            et                 => 1,
            time_settings      => 1,
            message_parameters => 1
        }
    );

    my $type = extract(
        find(
            $parameters->{data},
            "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]", 1
        ),
        0
    );
    if ( $type eq "rrd" ) {
        $self->retrieveRRD(
            {
                d                  => $parameters->{data},
                mid                => $parameters->{id},
                output             => $parameters->{output},
                time_settings      => $parameters->{time_settings},
                et                 => $parameters->{et},
                message_parameters => $parameters->{et}
            }

        );
    }
    elsif ( $type eq "sqlite" ) {
        $self->retrieveSQL(

            {
                d                  => $parameters->{data},
                mid                => $parameters->{id},
                output             => $parameters->{output},
                time_settings      => $parameters->{time_settings},
                et                 => $parameters->{et},
                message_parameters => $parameters->{et}
            }
        );
    }
    else {
        my $msg = "Database \"" . $type . "\" is not yet supported";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        getResultCodeData( $parameters->{output}, "data." . genuid(),
            $parameters->{id}, $msg, 1 );
    }
    return;
}

=head2 retrieveSQL($self, $d, $mid, $output, $et, $message_parameters)

Given some 'startup' knowledge such as the name of the database and any
credentials to connect with it, we start a connection and query the database
for given values.  These values are prepared into XML response content and
return in the response message.

=cut

sub retrieveSQL {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            d                  => 1,
            mid                => 1,
            time_settings      => 1,
            output             => 1,
            et                 => 1,
            message_parameters => 1
        }
    );

    my $datumns  = 0;
    my $timeType = q{};

    if (
        defined $parameters->{message_parameters}
        ->{"eventNameSpaceSynchronization"}
        and lc(
            $parameters->{message_parameters}->{"eventNameSpaceSynchronization"}
        ) eq "true"
      )
    {
        $datumns = 1;
    }

    if ( defined $parameters->{message_parameters}->{"timeType"} ) {
        if ( lc( $parameters->{message_parameters}->{"timeType"} ) eq "unix" ) {
            $timeType = "unix";
        }
        elsif ( lc( $parameters->{message_parameters}->{"timeType"} ) eq "iso" )
        {
            $timeType = "iso";
        }
    }

    $self->{CONF}->{"snmp"}->{"logger"}->error("No data element") if (not defined $parameters->{d});

    my $file = extract(find($parameters->{d}, "./nmwg:key//nmwg:parameter[\@name=\"file\"]", 1), 1);
    my $table = extract(find($parameters->{d}, "./nmwg:key//nmwg:parameter[\@name=\"table\"]", 1), 1);

    if (not defined $file or not defined $table) {
        $self->{CONF}->{"snmp"}->{"logger"}->error("Data element ".$parameters->{d}->getAttribute("id")." is missing some SQL elements");
        throw perfSONAR_PS::Error_compat( "error.ma.storage", "Unable to open associated database");
    }

    my @dbSchema = ( "id", "time", "value", "eventtype", "misc" );
    my $result = getDataSQL($self->{DIRECTORY}, $file, $table, $parameters->{time_settings}, \@dbSchema);
    my $id = "data." . genuid();

    if ( $#{$result} == -1 ) {
        my $msg = "Query returned 0 results";
        $self->{CONF}->{"snmp"}->{"logger"}->error($msg);
        getResultCodeData( $parameters->{output}, $id, $parameters->{mid}, $msg,
            1 );
    }
    else {
        my $prefix = "nmwg";
        my $uri    = "http://ggf.org/ns/nmwg/base/2.0";

        if ($datumns) {
            if ( defined $parameters->{et} and $parameters->{et} ne q{} ) {
                foreach my $e ( sort keys %{ $parameters->{et} } ) {
                    next if $e eq "http://ggf.org/ns/nmwg/tools/snmp/2.0";
                    $uri = $e;
                }
            }
            if ( $uri ne "http://ggf.org/ns/nmwg/base/2.0" ) {
                foreach my $r ( sort keys %{ $self->{NAMESPACES} } ) {
                    if ( ( $uri . "/" ) eq $self->{NAMESPACES}->{$r} ) {
                        $prefix = $r;
                        last;
                    }
                }
                if ( !$prefix ) {
                    $prefix = "nmwg";
                    $uri    = "http://ggf.org/ns/nmwg/base/2.0";
                }
            }
        }

        startData( $parameters->{output}, $id, $parameters->{mid}, undef );
        my $len = $#{$result};
        for my $a ( 0 .. $len ) {
            my %attrs = ();
            if ( $timeType eq "iso" ) {
                my (
                    $sec,  $min,  $hour, $mday, $mon,
                    $year, $wday, $yday, $isdst
                ) = gmtime( $result->[$a][1] );
                $attrs{"timeType"} = "ISO";
                $attrs{ $dbSchema[1] . "Value" } =
                  sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ( $year + 1900 ),
                  ( $mon + 1 ), $mday, $hour, $min, $sec;
            }
            else {
                $attrs{"timeType"} = "unix";
                $attrs{ $dbSchema[1] . "Value" } = $result->[$a][1];
            }
            $attrs{ $dbSchema[2] } = $result->[$a][2];

            my @misc = split( /,/xm, $result->[$a][4] );
            foreach my $m (@misc) {
                my @pair = split( /=/xm, $m );
                $attrs{ $pair[0] } = $pair[1];
            }

            $parameters->{output}->createElement(
                prefix     => $prefix,
                namespace  => $uri,
                tag        => "datum",
                attributes => \%attrs
            );
        }
        endData( $parameters->{output} );
    }
    return;
}

=head2 retrieveRRD($self, $d, $mid, $output, $et, $message_parameters)

Given some 'startup' knowledge such as the name of the database and any
credentials to connect with it, we start a connection and query the database
for given values.  These values are prepared into XML response content and
return in the response message.

=cut

sub retrieveRRD {
    my ( $self, @args ) = @_;
    my $parameters = validate(
        @args,
        {
            d                  => 1,
            mid                => 1,
            time_settings      => 1,
            output             => 1,
            et                 => 1,
            message_parameters => 1
        }
    );

    my $timeSettings = $parameters->{time_settings};

    my ( $sec, $frac ) = Time::HiRes::gettimeofday;
    my $datumns  = 0;
    my $timeType = q{};

    if (
        defined $parameters->{message_parameters}
        ->{"eventNameSpaceSynchronization"}
        and lc(
            $parameters->{message_parameters}->{"eventNameSpaceSynchronization"}
        ) eq "true"
      )
    {
        $datumns = 1;
    }

    if ( defined $parameters->{message_parameters}->{"timeType"} ) {
        if ( lc( $parameters->{message_parameters}->{"timeType"} ) eq "unix" ) {
            $timeType = "unix";
        }
        elsif ( lc( $parameters->{message_parameters}->{"timeType"} ) eq "iso" )
        {
            $timeType = "iso";
        }
    }

    my $file_element = find($parameters->{d}, "./nmwg:key//nmwg:parameter[\@name=\"file\"]", 1);

    my $rrd_file = extract($file_element, 1);

    if (not $rrd_file) {
        $self->{CONF}->{"snmp"}->{"logger"}->error("Data element ".$parameters->{d}->getAttribute("id")." is missing some RRD file");
        throw perfSONAR_PS::Error_compat( "error.ma.storage", "Unable to open associated RRD file");
    }

    adjustRRDTime($timeSettings);
    my $id = "data." . genuid();
    my %rrd_result = getDataRRD($self->{DIRECTORY}, $rrd_file, $timeSettings, $self->{CONF}->{"snmp"}->{"rrdtool"} );
    if ( $rrd_result{ERROR} ) {
        $self->{CONF}->{"snmp"}->{"logger"}
          ->error( "RRD error seen: " . $rrd_result{ERROR} );
        getResultCodeData( $parameters->{output}, $id, $parameters->{mid},
            $rrd_result{ERROR}, 1 );
    }
    else {
        my $prefix = "nmwg";
        my $uri    = "http://ggf.org/ns/nmwg/base/2.0";
        if ($datumns) {
            if ( defined $parameters->{et} and $parameters->{et} ne q{} ) {
                foreach my $e ( sort keys %{ $parameters->{et} } ) {
                    next if $e eq "http://ggf.org/ns/nmwg/tools/snmp/2.0";
                    $uri = $e;
                }
            }
            if ( $uri ne "http://ggf.org/ns/nmwg/base/2.0" ) {
                foreach my $r ( sort keys %{ $self->{NAMESPACES} } ) {
                    if ( ( $uri . "/" ) eq $self->{NAMESPACES}->{$r} ) {
                        $prefix = $r;
                        last;
                    }
                }
                if ( !$prefix ) {
                    $prefix = "nmwg";
                    $uri    = "http://ggf.org/ns/nmwg/base/2.0";
                }
            }
        }

        my $dataSource = extract(
            find(
                $parameters->{d},
                "./nmwg:key//nmwg:parameter[\@name=\"dataSource\"]", 1
            ),
            0
        );
        my $valueUnits = extract(
            find(
                $parameters->{d},
                "./nmwg:key//nmwg:parameter[\@name=\"valueUnits\"]", 1
            ),
            0
        );

        startData( $parameters->{output}, $id, $parameters->{mid}, undef );
        foreach my $a ( sort( keys(%rrd_result) ) ) {
            foreach my $b ( sort( keys( %{ $rrd_result{$a} } ) ) ) {
                if ( $b eq $dataSource and $a < $sec ) {

                    my %attrs = ();
                    if ( $timeType eq "iso" ) {
                        my (
                            $sec,  $min,  $hour, $mday, $mon,
                            $year, $wday, $yday, $isdst
                        ) = gmtime($a);
                        $attrs{"timeType"} = "ISO";
                        $attrs{"timeValue"} =
                          sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ\n",
                          ( $year + 1900 ), ( $mon + 1 ), $mday, $hour,
                          $min, $sec;
                    }
                    else {
                        $attrs{"timeType"}  = "unix";
                        $attrs{"timeValue"} = $a;
                    }
                    $attrs{"value"}      = $rrd_result{$a}{$b};
                    $attrs{"valueUnits"} = $valueUnits;

                    $parameters->{output}->createElement(
                        prefix     => $prefix,
                        namespace  => $uri,
                        tag        => "datum",
                        attributes => \%attrs
                    );

                }
            }
        }
        endData( $parameters->{output} );
    }
    return;
}

sub getFilterParameters {
    my($self, $m, $namespaces, $default_resolution) = @_;

    my %time;

    my $prefix = "";
    my $nmwg = $namespaces->{"http://ggf.org/ns/nmwg/base/2.0/"};
    my $tm = $namespaces->{"http://ggf.org/ns/nmwg/time/2.0/"};
    if($namespaces->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
        $prefix = $namespaces->{"http://ggf.org/ns/nmwg/ops/select/2.0/"};
    }
    else {
        $prefix = $namespaces->{"http://ggf.org/ns/nmwg/base/2.0/"};
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"consolidationFunction\"]", 1)) {
        $time{"CF"} = extract(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1)) {
        $time{"CF"} = extract(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1)) {
        $time{"CF"} = extract(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"resolution\"]", 1)) {
        $time{"RESOLUTION"} = extract(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"resolution\"]", 1), 1);
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1)) {
        $time{"RESOLUTION"} = extract(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1), 1);
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1)) {
        $time{"RESOLUTION"} = extract(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1), 1);
    }

    $time{"RESOLUTION_SPECIFIED"} = 0;
    if(!$time{"RESOLUTION"} or
            !($time{"RESOLUTION"} =~ m/^\d+$/)) {
        if(defined $default_resolution) {
            $time{"RESOLUTION"} = $default_resolution;
        }
        else {
            $time{"RESOLUTION"} = 1;
        }
    } else {
        $time{"RESOLUTION_SPECIFIED"} = 1;
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"startTime\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"endTime\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1)) {
        $time{"END"} = parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1)) {
        $time{"START"} = eval(parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$time{"RESOLUTION"});
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1)) {
        $time{"START"} = eval(parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$time{"RESOLUTION"});
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1)) {
        $time{"START"} = eval(parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$time{"RESOLUTION"});
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1)) {
        $time{"END"} = eval(parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$time{"RESOLUTION"});
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1)) {
        $time{"END"} = eval(parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$time{"RESOLUTION"});
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1)) {
        $time{"END"} = eval(parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$time{"RESOLUTION"});
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
        $time{"END"} = $time{"START"};
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
        $time{"END"} = $time{"START"};
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1)) {
        $time{"START"} = parseTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
        $time{"END"} = $time{"START"};
    }

    foreach my $t (keys %time) {
        $time{$t} =~ s/(\n)|(\s+)//g;
    }

    if($time{"START"} and 
            $time{"END"} and 
            $time{"START"} > $time{"END"}) {
        return undef;
    }

    return \%time;
}

sub parseTime {
  my($parameter, $timePrefix, $type) = @_;
  my $logger = get_logger("perfSONAR_PS::Services::MA::General");

  if(defined $parameter and $parameter ne "") {
    if($timePrefix and find($parameter, "./".$timePrefix.":time", 1)) {
      my $timeElement = find($parameter, "./".$timePrefix.":time", 1);
      if($timeElement->getAttribute("type") =~ m/ISO/i) {
        return convertISO(extract($timeElement, 1));
      }
      else {
        return extract($timeElement, 0);
      }
    }
    elsif($timePrefix and $type and find($parameter, "./".$timePrefix.":".$type, 1)) {
      my $timeElement = find($parameter, "./".$timePrefix.":".$type, 1);
      if($timeElement->getAttribute("type") =~ m/ISO/i) {
        return convertISO(extract($timeElement, 1));
      }
      else {
        return extract($timeElement, 1);
      }    
    }
    elsif($parameter->hasChildNodes()) {
      foreach my $p ($parameter->childNodes) {
        if($p->nodeType == 3) {
          (my $value = $p->textContent) =~ s/\s*//g;
          if($value) {
            return $value;
          }
        }
      }
    }  
  }
  else {
    $logger->error("Missing argument.");
  }
  return "";
}


1;

__END__

=head1 SEE ALSO

L<Log::Log4perl>, L<Module::Load>, L<Digest::MD5>, L<English>,
L<Params::Validate>, L<perfSONAR_PS::Services::MA::Base>,
L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Client::LS::Remote>,
L<perfSONAR_PS::Error_compat>, L<perfSONAR_PS::DB::File>,
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

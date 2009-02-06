package perfSONAR_PS::Services::MA::Status;

=head1 NAME

perfSONAR_PS::Services::MA::Status - A module that provides methods for a
an L2 Status Measurement Archive. The service can be used to make Link Status
Data available to individuals via webservice interface.

=head1 DESCRIPTION

This module, in conjunction with other parts of the perfSONAR-PS framework,
handles specific messages from interested actors in search of link status data.

There are two major message types that this service can act upon:
 - MetadataKeyRequest             - Given some metadata about a specific measurement, 
                                      request a re-playable 'key' to faster access
                                      underlying data.
 - SetupDataRequest               - Given either metadata or a key regarding a specific
                                      measurement, retrieve data values.
 - MeasurementArchiveStoreRequest - Given some metadata or a key and some link
                                      status information, updates status
                                      information about a given link.
=cut

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'CLIENT', 'LOGGER', 'DOMAIN', 'CIRCUITS', 'NODES'; 

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use perfSONAR_PS::Time;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Client::Status::SQL;
use perfSONAR_PS::Topology::ID;
use perfSONAR_PS::Utils::ParameterValidation;

our $VERSION = 0.09;

my %status_namespaces = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
    select=>"http://ggf.org/ns/nmwg/ops/select/2.0/",
    nmtopo=>"http://ogf.org/schema/network/topology/base/20070828/",
    topoid=>"http://ogf.org/schema/network/topology/id/20070828/",
    ifevt=>"http://ggf.org/ns/nmwg/event/status/base/2.0/",
    nmtl2=>"http://ggf.org/ns/nmwg/topology/l2/3.0/",
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
    my ($self, $handler) = @_;
    
    $self->{LOGGER} = get_logger("perfSONAR_PS::Services::MA::Status");

    if (not defined $self->{CONF}->{"status"}->{"enable_registration"} or $self->{CONF}->{"status"}->{"enable_registration"} eq q{}) {
        $self->{LOGGER}->warn("Disabling LS registration");
        $self->{CONF}->{"status"}->{"enable_registration"} = 0;
    }

    if ($self->{CONF}->{"status"}->{"enable_registration"}) {
        if (not defined $self->{CONF}->{"status"}->{"service_accesspoint"} or $self->{CONF}->{"status"}->{"service_accesspoint"} eq q{}) {
            $self->{LOGGER}->error("No access point specified for SNMP service");
            return -1;
        }

        if (not defined $self->{CONF}->{"status"}->{"ls_instance"} or $self->{CONF}->{"status"}->{"ls_instance"} eq q{}) {
            if (defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne q{}) {
                $self->{CONF}->{"status"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
            } else {
                $self->{LOGGER}->error("No LS instance specified for SNMP service");
                return -1;
            }
        }

        if (not defined $self->{CONF}->{"status"}->{"ls_registration_interval"} or $self->{CONF}->{"status"}->{"ls_registration_interval"} eq q{}) {
            if (defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne q{}) {
                $self->{CONF}->{"status"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
            } else {
                $self->{LOGGER}->warn("Setting registration interval to 30 minutes");
                $self->{CONF}->{"status"}->{"ls_registration_interval"} = 1800;
            }
        } else {
            # turn the registration interval from minutes to seconds
            $self->{CONF}->{"status"}->{"ls_registration_interval"} *= 60;
        }

        $self->{LOGGER}->debug("Registration interval: ".  $self->{CONF}->{"status"}->{"ls_registration_interval"});

        if(not defined $self->{CONF}->{"status"}->{"service_description"} or
                $self->{CONF}->{"status"}->{"service_description"} eq q{}) {
            $self->{CONF}->{"status"}->{"service_description"} = "perfSONAR_PS Status MA";
            $self->{LOGGER}->warn("Setting 'service_description' to 'perfSONAR_PS Status MA'.");
        }

        if(not defined $self->{CONF}->{"status"}->{"service_name"} or
                $self->{CONF}->{"status"}->{"service_name"} eq q{}) {
            $self->{CONF}->{"status"}->{"service_name"} = "Status MA";
            $self->{LOGGER}->warn("Setting 'service_name' to 'Status MA'.");
        }

        if(not defined $self->{CONF}->{"status"}->{"service_type"} or
                $self->{CONF}->{"status"}->{"service_type"} eq q{}) {
            $self->{CONF}->{"status"}->{"service_type"} = "MA";
            $self->{LOGGER}->warn("Setting 'service_type' to 'MA'.");
        }

        my %ls_conf = (
                SERVICE_TYPE => $self->{CONF}->{"status"}->{"service_type"},
                SERVICE_NAME => $self->{CONF}->{"status"}->{"service_name"},
                SERVICE_DESCRIPTION => $self->{CONF}->{"status"}->{"service_description"},
                SERVICE_ACCESSPOINT => $self->{CONF}->{"status"}->{"service_accesspoint"},
                  );

        $self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"status"}->{"ls_instance"}, \%ls_conf, \%status_namespaces);
    }

    if (not defined $self->{CONF}->{"status"}->{"db_type"} or $self->{CONF}->{"status"}->{"db_type"} eq q{}) {
        $self->{LOGGER}->error("No database type specified");
        return -1;
    }

    if (lc($self->{CONF}->{"status"}->{"db_type"}) eq "sqlite") {
        if (not defined $self->{CONF}->{"status"}->{"db_file"} or $self->{CONF}->{"status"}->{"db_file"} eq q{}) {
            $self->{LOGGER}->error("You specified a SQLite Database, but then did not specify a database file(db_file)");
            return -1;
        }

        my $file = $self->{CONF}->{"status"}->{"db_file"};
        if (defined $self->{DIRECTORY}) {
            if (!($file =~ "^/")) {
                $file = $self->{DIRECTORY}."/".$file;
            }
        }

        my $read_only = 0;

        if (defined $self->{CONF}->{"status"}->{"read_only"} and $self->{CONF}->{"status"}->{"read_only"} == 1) {
            $read_only = 1;
        }

        $self->{CLIENT} = new perfSONAR_PS::Client::Status::SQL("DBI:SQLite:dbname=".$file, q{}, q{}, $self->{CONF}->{"status"}->{"db_table"}, $read_only);
        if (not defined $self->{CLIENT}) {
            my $msg = "No database to dump";
            $self->{LOGGER}->error($msg);
            return -1;
        }
    } elsif (lc($self->{CONF}->{"status"}->{"db_type"}) eq "mysql") {
        my $dbi_string = "dbi:mysql";

        if (not defined $self->{CONF}->{"status"}->{"db_name"} or $self->{CONF}->{"status"}->{"db_name"} eq q{}) {
            $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database (db_name)");
            return -1;
        }

        $dbi_string .= ":".$self->{CONF}->{"status"}->{"db_name"};

        if (not defined $self->{CONF}->{"status"}->{"db_host"} or $self->{CONF}->{"status"}->{"db_host"} eq q{}) {
            $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database host (db_host)");
            return -1;
        }

        $dbi_string .= ":".$self->{CONF}->{"status"}->{"db_host"};

        if (defined $self->{CONF}->{"status"}->{"db_port"} and $self->{CONF}->{"status"}->{"db_port"} ne q{}) {
            $dbi_string .= ":".$self->{CONF}->{"status"}->{"db_port"};
        }

        my $read_only = 0;

        if (defined $self->{CONF}->{"status"}->{"read_only"} and $self->{CONF}->{"status"}->{"read_only"} == 1) {
            $read_only = 1;
        }

        $self->{CLIENT} = new perfSONAR_PS::Client::Status::SQL($dbi_string, $self->{CONF}->{"status"}->{"db_username"}, $self->{CONF}->{"status"}->{"db_password"}, $self->{CONF}->{"status"}->{"db_table"}, $read_only);
        if (not defined $self->{CLIENT}) {
            my $msg = "Couldn't create SQL client";
            $self->{LOGGER}->error($msg);
            return -1;
        }
    } else {
        $self->{LOGGER}->error("Invalid database type specified");
        return -1;
    }

    my ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open newly created client: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    if (lc($self->{CONF}->{"status"}->{"enable_e2emon_compatibility"})) {
        if ($self->{CONF}->{"status"}->{"e2emon_definitions_file"}) {
            my $file = $self->{CONF}->{"status"}->{"e2emon_definitions_file"};
            if (defined $self->{DIRECTORY}) {
                if ($file !~ "^/") {
                    $file = $self->{DIRECTORY}."/".$file;
                }
            }

            $self->parseCompatCircuitsFile($file);
        } else {
            my $msg = "No E2EMon definitions file for E2EMon compatibility";
            $self->{LOGGER}->error($msg);
            return -1;
        }
    }

    $self->{CLIENT}->close;

    $handler->registerEventHandler("MetadataKeyRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
    $handler->registerEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
    $handler->registerEventHandler("MeasurementArchiveStoreRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);

    if (lc($self->{CONF}->{"status"}->{"enable_e2emon_compatibility"})) {
        $handler->registerEventHandler("SetupDataRequest", "Path.Status", $self);
    }

    return 0;
}

=head2 needLS($self)
    This particular service (Status MA) should register with a lookup service. This
    function simply returns the value set in the configuration file (either yes
    or no, depending on user preference) to let other parts of the framework know
    if LS registration is required.
=cut
sub needLS {
    my ($self) = @_;

    return ($self->{CONF}->{"status"}->{"enable_registration"});
}

=head2 registerLS($self $sleep_time)
    Given the service information (specified in configuration) and the contents
    of our backend database, we can contact the specified LS and register
    ourselves. The $sleep_time ref can be set to specify how long before the
    perfSONAR-PS daemon should call the function again.
=cut
sub registerLS {
    my ($self, $sleep_time) = @_;
    my ($status, $res);

    ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open from database: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    ($status, $res) = $self->{CLIENT}->getUniqueIDs;
    if ($status != 0) {
        my $msg = "Couldn't get identifiers from database: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    my @mds = ();
    my $i = 0;
    foreach my $id (@{ $res }) {
        my $md = q{};

        $md .= "<nmwg:metadata id=\"meta$i\">\n";
        $md .= "<nmwg:subject id=\"sub$i\">\n";
        my @ids = idSplit($id, 0, 0);
        if ($ids[0] == 0) {
        $md .= " <nmtopo:".$ids[1]." xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"".escapeString($id)."\" />\n";
        } else {
        $md .= " <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"".escapeString($id)."\" />\n";
        }
        $md .= "</nmwg:subject>\n";
        $md .= "<nmwg:eventType>Link.Status</nmwg:eventType>\n";
        $md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/link/status/20070809</nmwg:eventType>\n";
        $md .= "</nmwg:metadata>\n";
        push @mds, $md;
        $i++;
    }

    $res = q{};

    my $n = $self->{LS_CLIENT}->registerDynamic(\@mds);

    if (defined $sleep_time) {
        ${$sleep_time} = $self->{CONF}->{"status"}->{"ls_registration_interval"};
    }

    return $n;
}

sub handleEvent {
    my ($self, @args) = @_;
    my $parameters = validateParams(@args,
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

    my $eventType = $parameters->{"eventType"};

    if ($eventType eq "Path.Status") {
        $self->handleCompatPathStatus(@args);
    } else {
        $self->handleNonCompatEvent(@args);
    }
}

=head2 handleEvent($self, { output, messageId, messageType, messageParameters, eventType, subject, filterChain, data, rawRequest, doOutputMetadata })

    This function is called by the daemon whenever there is a metadata/data
    pair for this instance to handle. This function calls the subject parsing
    routines that are common to all requests, then calls the filter chaining
    parsing routines which are common to all requests and then passes the
    results onto the specific function depending on the request.
=cut
sub handleNonCompatEvent {
    my ($self, @args) = @_;
    my $parameters = validateParams(@args,
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
    my $doOutputMetadata = $parameters->{doOutputMetadata};

    my $md = $subjects[0];

    my ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    my ($ids, $selectTime, $responseType, $was_key)  = $self->parseSubject($md);

    my $metadataId;
    my @filters = @{ $parameters->{filterChain} };
    $selectTime = $self->resolveSelectChain($md, $parameters->{filterChain}, $selectTime);
    if ($#filters > -1) {
        $metadataId = $filters[-1][0]->getAttribute("id");
    } else {
        $metadataId = $md->getAttribute("id");
    }

    if ($messageType eq "SetupDataRequest") {
        $self->handleLinkStatusRequest($output, $metadataId, $ids, $selectTime, $responseType, $was_key);
    } elsif ($messageType eq "MetadataKeyRequest") {
        $self->handleMetadataKeyRequest($output, $metadataId, $ids, $selectTime, $responseType, $was_key);
    } elsif ($messageType eq "MeasurementArchiveStoreRequest") {
        if ($#filters > -1) {
            throw perfSONAR_PS::Error_compat("error.ma.select", "Can't have a store with select parameters");
        }

        my @ids = @{ $ids };
        if ($#ids > 0) {
            throw perfSONAR_PS::Error_compat("error.ma.subject", "Can't have a store with multiple subject elements");
        }

        my $do_update = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="update"]');
        if (defined $do_update and $do_update ne q{}) {
            if (lc($do_update) eq "yes") {
                $do_update = 1;
            } elsif (lc($do_update) eq "no") {
                $do_update = 0;
            } else {
                throw perfSONAR_PS::Error_compat("error.ma.parameters", "Update parameter must be either 'yes' or 'no'");
            }
        } else {
            $do_update = 0;
        }

        $self->handleStoreRequest($output, $metadataId, $ids[0], $responseType, $do_update, $d);
    }

    $self->{CLIENT}->close;

    return;
}

=head2 parseSubject  ($self, $subject_md)
    There are five possible subject types that are acceptable depending on the
    context: an nmwg key, a topoid subject, an nmwg subject with the old style
    link IDs in them (deprecated). This function calls the relevant parsing
    function depending on the content of the subject metadata.
=cut
sub parseSubject {
    my ($self, $subject_md) = @_;

    my $key;
    my $time;

    # look for any time parameters specified in the key
    my $nmwg_key = find($subject_md, "./*[local-name()='key' and namespace-uri()='".$status_namespaces{"nmwg"}."']", 1);
    my $nmwg_subj = find($subject_md, "./*[local-name()='subject' and namespace-uri()='".$status_namespaces{"nmwg"}."']", 1);
    my $topoid_subj = find($subject_md, './topoid:subject', 1);

    if (($nmwg_key and $nmwg_subj) or ($topoid_subj and $nmwg_subj) or ($nmwg_key and $topoid_subj)) {
        my $msg = "Ambiguous subject";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.subject", $msg);
    }

    if ($nmwg_key) {
        my ($link_id, $time, $responseType) = $self->parseKey($nmwg_key);

        my @tmp = ( "$link_id" );
        return (\@tmp, $time, $responseType, 1);
    }

    if ($topoid_subj) {
        # check for a link expression
        my $ids = $self->lookupIDs($topoid_subj->textContent);

        return ($ids, undef, "topoid", 0);
    }

    if ($nmwg_subj) {
        # we've got the nmwg subject
        my $link_id = findvalue($nmwg_subj, './*[local-name()=\'link\']/@id');
        if ($link_id) {
            my @tmp = ( "$link_id" );
            return (\@tmp, $time, "linkid", 0);
        }
    }

    throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid subject type");
}

=head2 parseKey ($self, $key)
    Parses the nmwg keys that we generate and hand off to the users.
=cut
sub parseKey {
    my ($self, $key) = @_;

    my $key_params = find($key, "./*[local-name()='parameters' and namespace-uri()='".$status_namespaces{"nmwg"}."']", 1);
    if (not $key_params) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.subject", $msg);
    }

    my $link_id = findvalue($key_params, "./nmwg:parameter[\@name=\"maKey\"]");
    $self->{LOGGER}->error("LINK ID: '$link_id'");

    if (not $link_id) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.subject", $msg);
    }

    if (idIsAmbiguous($link_id)) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.subject", $msg);
    }

    my $responseFormat = findvalue($key_params, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"responseFormat\"]");
    if (not $responseFormat or ($responseFormat ne "topoid" and $responseFormat ne "linkid")) {
        my $msg = "Invalid key";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.subject", $msg);
    }

    my $time = findvalue($key_params, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"time\"]");
    my $startTime = findvalue($key_params, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"startTime\"]");
    my $endTime = findvalue($key_params, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"endTime\"]");

    $link_id = unescapeString($link_id);

    unless (defined $time or defined $startTime or defined $endTime) {
        return ($link_id, undef, $responseFormat);
    }

    if (defined $time and (defined $startTime or defined $endTime)) {
        throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid key");
    } 

    if (defined $time) {
        return ($link_id, perfSONAR_PS::Time->new("point", $time), $responseFormat);
    }

    if (not defined $startTime) {
        throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid key");
    } 

    if (not defined $endTime) {
        throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid key");
    } 

    return ($link_id, perfSONAR_PS::Time->new("range", $startTime, $endTime), $responseFormat);
}

=head2 lookupIDs ($self, $topo_exp)
    Takes a topology id expression and matches it with the identifiers in the
    SQL backend.
=cut
sub lookupIDs {
    my ($self, $topo_exp) = @_;

    my $ids;

    $self->{LOGGER}->debug("lookupIDs: '".$topo_exp."'");

    # now we have to look up all the values it could be
    my ($status, $res) = $self->{CLIENT}->getUniqueIDs;
    if ($status != 0) {
        my $msg = "Couldn't get element information from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    $ids = idMatch($res, $topo_exp);

    if (not defined $ids) {
        my $msg = "No circuits or paths match expression: $topo_exp";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
    }

    return $ids;
}

=head2 resolveSelectChain ($self, $subject_md, $filterChain, $selectTime)
    This function takes the filter chain and tries to resolve it down to a
    single point in or range of time. It takes the subject metadata since some
    of the protocol options would take parameters from there, the filter chain
    itself and a $selectTime that is undef in all cases other than keys. In the
    case of a key, it may correspond to a specific time range and in that case,
    $selectTime will have a perfSONAR_PS::Time element with the time
    point/range for the key.
=cut
sub resolveSelectChain {
    my ($self, $subject_md, $filterChain, $selectTime) = @_;

    my ($time, $startTime, $endTime);
    my @filters = @{ $filterChain };

    if ($selectTime) {
        if ($selectTime->getType eq "point") {
            $startTime = $selectTime->getTime;
            $endTime = $selectTime->getTime;
        } else {
            $startTime = $selectTime->getStartTime;
            $endTime = $selectTime->getEndTime;
        }
    }

    my $now_flag = 0;

    # look for any time parameters specified in the parameters of the subject (DEPRECATED)
    my $parameters = find($subject_md, "./*[local-name()='parameters' and namespace-uri()='".$status_namespaces{"nmwg"}."']", 1);
    if (defined $parameters) {
        my $curr_time = findvalue($parameters, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"time\"]");
        if (lc($curr_time) eq "now") {
            if ($startTime or $endTime) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: 'now' used with a time range");
            }

            $now_flag = 1;
        } else {
            if ($startTime and $endTime and ($curr_time < $startTime or $curr_time > $endTime)) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: time specified is out of range previously specified");
            } else {
                $startTime = $curr_time;
                $endTime = $curr_time;
            }
        }
    }

    # got through the filters and load any parameters with an eye toward
    # producing data as though it had gone through a set of filters.
    foreach my $filter_arr (@filters) {
        my @filter_set = @{ $filter_arr };
        my $filter = $filter_set[0];

        my $select_parameters = find($filter, "./*[local-name()='parameters' and namespace-uri()='".$status_namespaces{"select"}."']", 1);
        
        next if (not defined $select_parameters);
    
        my $curr_time = findvalue($select_parameters, "./*[local-name()='parameter' and \@name=\"time\"]");
        my $curr_startTime = findvalue($select_parameters, "./*[local-name()='parameter' and \@name=\"startTime\"]");
        my $curr_endTime = findvalue($select_parameters, "./*[local-name()='parameter' and \@name=\"endTime\"]");
        my $curr_duration = findvalue($select_parameters, "./*[local-name()='parameter' and \@name=\"duration\"]");

        $self->{LOGGER}->debug("Time: $curr_time") if ($curr_time);
        $self->{LOGGER}->debug("Start Time: $curr_startTime") if ($curr_startTime);
        $self->{LOGGER}->debug("End Time: $curr_endTime") if ($curr_endTime);
        $self->{LOGGER}->debug("Duration: $curr_duration") if ($curr_duration);

        if ($curr_time) {
            if (lc($curr_time) eq "now") {
                if ($startTime or $endTime) {
                    throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: 'now' used with a time range");
                }

                $now_flag = 1;
            } else {
                if (($startTime and $curr_time < $startTime) or ($endTime and $curr_time > $endTime)) {
                    throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: time specified is out of range previously specified");
                } else {
                    $startTime = $curr_time;
                    $endTime = $curr_time;
                }
            }
        } elsif ($curr_startTime) {
            if ($now_flag) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: 'now' used with a time range");
            }

            unless ($curr_endTime or $curr_duration) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: startTime but not endTime or duration specified");
            }

            if ($curr_endTime and $curr_duration) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: both endTime and duration specified");
            }

            if (not defined $startTime or $curr_startTime >= $startTime) {
                $startTime = $curr_startTime;
            }

            if ($curr_duration) {
                $curr_endTime = $curr_startTime + $curr_duration;
            }

            if (not defined $endTime or $curr_endTime < $endTime) {
                $endTime = $curr_endTime;
            }
        }

        if ($startTime and $endTime and $startTime > $endTime) {
                throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters: startTime > endTime");
        }
    }

    if (not defined $startTime and not defined $endTime) {
        return;
    }

    $self->{LOGGER}->debug("Start Time: $startTime End Time: $endTime");

    if ($startTime == $endTime) {
        return perfSONAR_PS::Time->new("point", $startTime);
    } else {
        return perfSONAR_PS::Time->new("range", $startTime, $endTime);
    }
}

=head2 handleStoreRequest ($self, $output, $metadataId, $id, $responseType, $do_update, $data)
    This function handles a store request. It pulls the updated information to
    store from the data element, making sure that all the relevant data is
    there.  After that, it updates the link or circuit state in the database
    and then adds a metadata/data pair to show that the store request was
    handled properly.
=cut
sub handleStoreRequest {
    my ($self, $output, $metadataId, $id, $responseType, $do_update, $d) = @_;

    my $time = findvalue($d, './ifevt:datum/@timeValue');
    my $time_type = findvalue($d, './ifevt:datum/@timeType');
    my $adminState = findvalue($d, './ifevt:datum/ifevt:stateAdmin');
    my $operState = findvalue($d, './ifevt:datum/ifevt:stateOper');

    my ($status, $res);

    if (not defined $time or $time eq q{} or not defined $time_type or $time_type eq q{} or not defined $adminState or $adminState eq q{} or not defined $operState or $operState eq q{}) {
        my $msg = "Data block is missing:";
        $msg .= " 'time'" if (not defined $time or $time eq q{});
        $msg .= " 'time type'" if (not defined $time_type or $time_type eq q{});
        $msg .= " 'administrative state'" if (not defined $adminState or $adminState eq q{});
        $msg .= " 'operational state'" if (not defined $operState or $operState eq q{});
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.query.incomplete_data", $msg);
    }

    if ($time_type ne "unix") {
        my $msg = "Time type must be 'unix'";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.ma.query.invalid_timestamp_type", $msg);
    }

    ($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $d, $operState, $adminState, $do_update);
    if ($status != 0) {
        my $msg = "Database update failed: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.update", $msg);
    }

    my $mdID = "metadata.".genuid();
    getResultCodeMetadata($output, $mdID, $metadataId, "success.ma.added");
    getResultCodeData($output, "data.".genuid(), $mdID, "new data element successfully added", 1);

    return;
}

=head2 handleLinkStatusRequest ($self, $output, $metadataId, $ids, $time, $responseType, $was_key)
    This function handles a link status request. First, it checks whether the
    history of a link or circuit should be retrieved or the just the specified
    point/range, calling the appropriate function for each. Next, it must
    output the data. Key requests never have the specific element output,
    just the key. Since the daemon will handle outputting the key for us, we
    can safely not output the metadata in that case. In all other cases, we
    must output the appropriate information. Thus, we check whether the
    incoming request was a key, if so we do nothing, if not, we output the
    appropriate MD depending on the format of the incoming response. Once we've
    done that, we go through and output the resulting status.
=cut
sub handleLinkStatusRequest {
    my ($self, $output, $metadataId, $ids, $time, $responseType, $was_key) = @_;
    my ($status, $res);

    if (defined $time and $time->getType() eq "point" and $time->getTime() == -1) {
        ($status, $res) = $self->{CLIENT}->getLinkHistory($ids);
    } else {
        ($status, $res) = $self->{CLIENT}->getLinkStatus($ids, $time);
    }

    if ($status != 0) {
        my $msg = "Couldn't get information about elements from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.fetch", $msg);
    }

    foreach my $id (@{ $ids }) {
        my $mdID;
        if ($was_key) {
            $mdID = $metadataId;
        } else {
            $mdID  = $self->outputMetadata($output, $id, $metadataId, $responseType);
        }

        my $data_content = q{};

        if (defined $res->{$id}) {
            foreach my $link (@{ $res->{$id} }) {
                if (not defined $time or ($time->getType() eq "point" and $time->getTime() != -1)) {
                    $data_content .= $self->writeoutLinkState($link);
                } else {
                    $data_content .= $self->writeoutLinkState_range($link);
                }
            }
        }
        createData($output, "data.".genuid(), $mdID, $data_content, undef);
    }

    return;
}

=head2 handleMetadataKeyRequest ($self, $output, $metadataId, $ids, $time, $responseType, $was_key)
    This function takes the relevant ids and generates output containing
    the keys associated with those ids. The function is almost identical
    to the handleLinkStatusRequest in its output. It just outputs the key for
    an element instead its associated data.
=cut
sub handleMetadataKeyRequest {
    my ($self, $output, $metadataId, $ids, $time, $responseType, $was_key) = @_;

    my $i = genuid();
    foreach my $id (@{ $ids }) {
        my $mdID;
        if ($was_key) {
            $mdID = $metadataId;
        } else {
            $mdID  = $self->outputMetadata($output, $id, $metadataId, $responseType);
        }

        my $dID = "data$i";
        startData($output, $dID, $mdID, undef);
            $self->createKey($output, $id, $time, $responseType);
        endData($output);
    }

    return;
}

=head2 outputMetadata ($self, $output, $id, $parentMdId, $responseType)
    There are 3 different formats that the metadata in a response can take. The
    'linkid' format is deprecated and kept around for existing software out
    there. However, there is another formats available: topoid.
    Topoid outputs a topoid subject containing the identifier.
=cut
sub outputMetadata {
    my ($self, $output, $id, $parentMdId, $responseType) = @_;

    if ($responseType eq "linkid") {
        return $self->outputLinkIDMetadata($output, $id, $parentMdId);
    } elsif ($responseType eq "topoid") {
        return $self->outputTopoIDMetadata($output, $id, $parentMdId);
    }
}

=head2 outputLinkIDMetadata ($self, $output, $id, $parentMdId)
    Outputs a metadata containing the specified link id in the format expected
    by legacy pS-PS Status MA applications.
=cut
sub outputLinkIDMetadata {
    my ($self, $output, $id, $parentMdId) = @_;

    my $md_content = q{};
    $md_content .= "<nmwg:subject id=\"sub0\">\n";
    $md_content .= "  <nmtopo:link xmlns:nmtopo=\"".$status_namespaces{"nmtopo"}."\" id=\"".escapeString($id)."\" />\n";
    $md_content .= "</nmwg:subject>\n";

    my $mdID = "metadata.".genuid();

    createMetadata($output, $mdID, $parentMdId, $md_content, undef);

    return $mdID;
}

=head2 outputTopoIDMetadata ($self, $output, $id, $parentMdId)
    Outputs a metadata containing the specified id in the new topoid
    format.
=cut
sub outputTopoIDMetadata {
    my ($self, $output, $id, $parentMdId) = @_;

    my $md_content = "<topoid:subject xmlns:topoid=\"".$status_namespaces{"topoid"}."\">".escapeString($id)."</topoid:subject>";

    my $mdID = "metadata.".genuid();

    createMetadata($output, $mdID, $parentMdId, $md_content, undef);

    return $mdID;
}

=head2 createKey ($self, $output, $link_id, $time, $responseType)
    Outputs a key with the relevant time, responseFormat and link id so that a
    client can simply return that key and get the information associated with it.
=cut
sub createKey {
    my ($self, $output, $link_id, $time, $responseType) = @_;

    $output->startElement({ prefix => "nmwg", tag => "key", namespace => $status_namespaces{"nmwg"} });
        startParameters($output, "params.0");
            addParameter($output, "maKey", escapeString($link_id));
            addParameter($output, "eventType", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809");
            addParameter($output, "responseFormat", $responseType);
            if ($time) {
                if ($time->getType eq "range") {
                    addParameter($output, "startTime", $time->getStartTime);
                    addParameter($output, "endTime", $time->getEndTime);
                } elsif ($time->getType eq "point") { 
                    addParameter($output, "time", $time->getTime);
                }
            }
        endParameters($output);
    $output->endElement("key");

    return;
}

=head2 writeoutLinkState_range ($self, $link)
    Writes out the specified perfSONAR_PS::Status::Link element in a format
    backwards compatible with the ifevt standard. It adds four attributes
    to the standard ifevt datum: startTime, startTimeType, endTime and
    endTimeType. These added attributes give the range during which the link
    had the specified state.
=cut
sub writeoutLinkState_range {
    my ($self, $link) = @_;

    return q{} if (not defined $link);

    my $localContent = q{};

    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\"\n";
    $localContent .= "    startTime=\"".$link->getStartTime."\" startTimeType=\"unix\" endTime=\"".$link->getEndTime."\" endTimeType=\"unix\">\n";
    $localContent .= "    <ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
    $localContent .= "    <ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
    $localContent .= "</ifevt:datum>\n";

    return $localContent;
}

=head2 writeoutLinkState_range ($self, $link)
    Writes out the specified perfSONAR_PS::Status::Link element in a format
    compatible with the ifevt standard.
=cut
sub writeoutLinkState {
    my ($self, $link, $time) = @_;

    return q{} if (not defined $link);

    my $localContent = q{};

    if (not defined $time or $time eq q{}) {
    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\">\n";
    } else {
    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" timeType=\"unix\" timeValue=\"$time\">\n";
    }
    $localContent .= "    <ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
    $localContent .= "    <ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
    $localContent .= "</ifevt:datum>\n";

    return $localContent;
}

sub handleCompatPathStatus {
    my ($self, @args) = @_;
    my $parameters = validateParams(@args,
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
    my $doOutputMetadata = $parameters->{doOutputMetadata};

    # Dsiable metadata outputting
    ${ $doOutputMetadata } = 0;

    my ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    my %sublink_ids = ();
    foreach my $circuit_name (keys %{ $self->{CIRCUITS} }) {
        my $circuit = $self->{CIRCUITS}->{$circuit_name};
        foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
            $sublink_ids{$sublink_id} = 1;
        }
    }

    my @ids = keys %sublink_ids;
    
    ($status, $res) = $self->{CLIENT}->getLinkStatus(\@ids, undef);
    if ($status != 0) {
        my $msg = "Couldn't get information about elements from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.fetch", $msg);
    }

    my $link_status = $res;

    my $curr_time = time;

    # Fill in any missing links
    foreach my $circuit_name (keys %{ $self->{CIRCUITS} }) {
        my $circuit = $self->{CIRCUITS}->{$circuit_name};

        foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
            if (not $link_status->{$sublink_id}) {
                my $msg = "Have no information about segment $sublink_id";
                $self->{LOGGER}->warn($msg);

                my $link = perfSONAR_PS::Status::Link->new($sublink_id, "full", $curr_time, $curr_time, "unknown", "unknown");

                $link_status->{$sublink_id} = [ $link ];
            }
        }
    }

    my %circuit_status = ();

    foreach my $circuit_name (keys %{ $self->{CIRCUITS} }) {
        my $circuit = $self->{CIRCUITS}->{$circuit_name};

        my @data_points = ();

        my $circuit_admin_value = "unknown";
        my $circuit_oper_value = "unknown";
        my $circuit_time;

        foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
            foreach my $link_status (@{ $res->{$sublink_id} }) {
                my $oper_value = $link_status->getOperStatus;
                my $admin_value = $link_status->getAdminStatus;
                my $end_time = $link_status->getEndTime;

                $circuit_time = $end_time if (not defined $circuit_time or $end_time > $circuit_time);

                if ($circuit_oper_value eq "down" or $oper_value eq "down")  {
                    $circuit_oper_value = "down";
                } elsif ($circuit_oper_value eq "degraded" or $oper_value eq "degraded")  {
                    $circuit_oper_value = "degraded";
                } elsif ($circuit_oper_value eq "up" or $oper_value eq "up")  {
                    $circuit_oper_value = "up";
                } else {
                    $circuit_oper_value = "unknown";
                }

                if ($circuit_admin_value eq "maintenance" or $admin_value eq "maintenance") {
                    $circuit_admin_value = "maintenance";
                } elsif ($circuit_admin_value eq "troubleshooting" or $admin_value eq "troubleshooting") {
                    $circuit_admin_value = "troubleshooting";
                } elsif ($circuit_admin_value eq "underrepair" or $admin_value eq "underrepair") {
                    $circuit_admin_value = "underrepair";
                } elsif ($circuit_admin_value eq "normaloperation" or $admin_value eq "normaloperation") {
                    $circuit_admin_value = "normaloperation";
                } else {
                    $circuit_admin_value = "unknown";
                }
            }
        }

        if (defined $self->{CONF}->{"status"}->{"max_recent_age"} and $self->{CONF}->{"status"}->{"max_recent_age"} ne q{}) {
            my $curr_time = time;

            if ($curr_time - $circuit_time > $self->{CONF}->{"status"}->{"max_recent_age"}) {
                $self->{LOGGER}->debug("Old link time: $circuit_time Current Time: ".$curr_time.": ".($curr_time - $circuit_time));
                $circuit_time = $curr_time;
                $circuit_oper_value = "unknown";
                $circuit_admin_value = "unknown";
            }
        } else {
            $circuit_time = time;
        }

        $circuit_status{$circuit_name} = perfSONAR_PS::Status::Link->new(q{}, q{}, $circuit_time, $circuit_time, $circuit_oper_value, $circuit_admin_value);
    }

    startParameters($output, "params.0");
     addParameter($output, "DomainName", $self->{DOMAIN});
    endParameters($output);
    $self->outputCompatResults($output, \%circuit_status, undef);

    $self->{CLIENT}->close;

    return;
}

sub outputCompatResults {
    my ($self, $output, $circuit_status, $time) = @_;

    my %output_endpoints = ();
    my $i = 0;

    foreach my $circuit_name (keys %{ $self->{CIRCUITS} }) {
        my $circuit = $self->{CIRCUITS}->{$circuit_name};
        foreach my $endpoint (@{ $circuit->{"endpoints"} }) {
            # Skip if it's an external host
            next if (not defined $self->{NODES}->{$endpoint->{name}});

            # Skip if we've already output the node
            next if (defined $output_endpoints{$endpoint->{name}});

            startMetadata($output, "metadata.".genuid(), q{}, undef);
             $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub-".$endpoint->{name} });
              $self->outputCompatNodeElement($output, $self->{NODES}->{$endpoint->{name}});
             $output->endElement("subject");
            endMetadata($output);

            $output_endpoints{$endpoint->{name}} = 1;
        }

        my $mdid = "metadata.".genuid();

        startMetadata($output, $mdid, q{}, undef);
         $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub$i" });
          $self->outputCompatCircuitElement($output, $circuit);
         $output->endElement("subject");
        endMetadata($output);

        my $datum = $circuit_status->{$circuit_name};

        my %attrs = ();
        $attrs{"timeType"} = "unix";
        $attrs{"timeValue"} = $datum->getEndTime();

        startData($output, "data.$i", $mdid, undef);
          $output->startElement(prefix => "ifevt", tag => "datum", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", attributes => \%attrs);
            $output->createElement(prefix => "ifevt", tag => "stateAdmin", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $datum->getAdminStatus);
            $output->createElement(prefix => "ifevt", tag => "stateOper", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $datum->getOperStatus);
          $output->endElement("datum");
        endData($output);

        $i++;
    }

    return;
}

sub outputCompatNodeElement {
    my ($self, $output, $node) = @_;

    $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { id => $node->{"name"} });
      $output->createElement(prefix => "nmwgtopo3", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => "TopologyPoint");
      $output->createElement(prefix => "nmwgtopo3", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => $node->{"name"});
    if (defined $node->{"city"} and $node->{"city"} ne q{}) {
        $output->createElement(prefix => "nmwgtopo3", tag => "city", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"city"});
    }
    if (defined $node->{"country"} and $node->{"country"} ne q{}) {
        $output->createElement(prefix => "nmwgtopo3", tag => "country", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"country"});
    }
    if (defined $node->{"latitude"} and $node->{"latitude"} ne q{}) {
        $output->createElement(prefix => "nmwgtopo3", tag => "latitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"latitude"});
    }
    if (defined $node->{"longitude"} and $node->{"longitude"} ne q{}) {
        $output->createElement(prefix => "nmwgtopo3", tag => "longitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"longitude"});
    }
    if (defined $node->{"institution"} and $node->{"institution"} ne q{}) {
        $output->createElement(prefix => "nmwgtopo3", tag => "institution", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", , content => $node->{"institution"});
    }
    $output->endElement("node");

    return;
}

sub outputCompatCircuitElement {
    my ($self, $output, $circuit) = @_;

    $output->startElement(prefix => "nmtl2", tag => "link", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/");
      $output->createElement(prefix => "nmtl2", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $circuit->{"name"});
      $output->createElement(prefix => "nmtl2", tag => "globalName", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $circuit->{"globalName"});
      $output->createElement(prefix => "nmtl2", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", content => $circuit->{"type"});
      foreach my $endpoint (@{ $circuit->{"endpoints"} }) {
      $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $endpoint->{"name"} });
      $output->createElement(prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $endpoint->{"type"});
      $output->endElement("node");
      }
#      startParameters($output, "params.0");
#        addParameter($output, "supportedEventType", "Path.Status");
#      endParameters($output);
    $output->endElement("link");

    return;
}

sub parseCompatCircuitsFile {
    my ($self, $file) = @_;

    my %nodes = ();
    my %circuits = ();

    my $parser = XML::LibXML->new();
    my $doc;
    eval {
        $doc = $parser->parse_file($file);
    };
    if ($@ or not defined $doc) {
        my $msg = "Couldn't parse circuits file $file: $@";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
    }

    my $conf = $doc->documentElement;

    # Grab the domain field
    my $domain = findvalue($conf, "domain");
    if (not defined $domain) {
        my $msg = "No domain specified in configuration";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
    }

    $self->{DOMAIN} = $domain;

    # Grab the set of nodes
    my $find_res;
    $find_res = find($conf, "./*[local-name()='node']", 0);
    if ($find_res) {
        foreach my $endpoint ($find_res->get_nodelist) {
            my $node_name = $endpoint->getAttribute("name");
            my $city = findvalue($endpoint, "city");
            my $country = findvalue($endpoint, "country");
            my $longitude = findvalue($endpoint, "longitude");
            my $institution = findvalue($endpoint, "institution");
            my $latitude = findvalue($endpoint, "latitude");

            if ($node_name !~ /-/) {
                $node_name = $domain."-".$node_name;
            }

            if (not defined $node_name or $node_name eq q{}) {
                my $msg = "Node needs to have a name";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            }

            $node_name =~ s/[^a-zA-Z0-9_-]//g;
            $node_name = uc($node_name);

            if (defined $nodes{$node_name}) {
                my $msg = "Multiple endpoints have the name \"$node_name\"";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            }

            $self->{LOGGER}->debug("Found '$node_name'");

            my %tmp = ();
            my $new_node = \%tmp;

            $new_node->{"name"} = $node_name if (defined $node_name and $node_name ne q{});
            $new_node->{"city"} = $city if (defined $city and $city ne q{});
            $new_node->{"country"} = $country if (defined $country and $country ne q{});
            $new_node->{"longitude"} = $longitude if (defined $longitude and $longitude ne q{});
            $new_node->{"latitude"} = $latitude if (defined $latitude and $latitude ne q{});
            $new_node->{"institution"} = $institution if (defined $institution and $institution ne q{});

            $nodes{$node_name} = $new_node;
        }
    }

    $self->{NODES} = \%nodes;

    # Grab the set of links
    $find_res = find($conf, "./*[local-name()='circuit']", 0);
    if ($find_res) {
        foreach my $link ($find_res->get_nodelist) {
            my $global_name = findvalue($link, "globalName");
            my $local_name = findvalue($link, "localName");
            my $link_type;

            if (not defined $global_name or $global_name eq q{}) {
                my $msg = "Circuit has no global name";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            }

            if (not defined $local_name or $local_name eq q{}) {
                $local_name = $global_name;
            }

            my %sublinks = ();

            $find_res = find($link, "./*[local-name()='segmentID']", 0);
            if ($find_res) {
                foreach my $topo_id ($find_res->get_nodelist) {
                    my $id = $topo_id->textContent;

                    if (defined $sublinks{$id}) {
                        my $msg = "Segment $id appears multiple times in link $global_name";
                        $self->{LOGGER}->error($msg);
                        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
                    }

                    $sublinks{$id} = q{};
                }
            }

            my @endpoints = ();

            my $num_endpoints = 0;

            my $prev_domain;

            $find_res = find($link, "./*[local-name()='endpoint']", 0);
            if ($find_res) {
                foreach my $endpoint ($find_res->get_nodelist) {
                    my $node_type = $endpoint->getAttribute("type");
                    my $node_name = $endpoint->getAttribute("name");

                    if (not defined $node_type or $node_type eq q{}) {
                        my $msg = "Node with unspecified type found";
                        $self->{LOGGER}->error($msg);
                        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
                    }

                    if (not defined $node_name or $node_name eq q{}) {
                        my $msg = "Endpint needs to specify a node name";
                        $self->{LOGGER}->error($msg);
                        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
                    }

                    if ($node_name !~ /-/) {
                        $node_name = $self->{DOMAIN}."-".$node_name;
                    }

                    $node_name =~ s/[^a-zA-Z0-9_-]//g;
                    $node_name = uc($node_name);

                    if (lc($node_type) ne "demarcpoint" and lc($node_type) ne "endpoint") {
                        my $msg = "Node found with invalid type $node_type. Must be \"DemarcPoint\" or \"EndPoint\"";
                        $self->{LOGGER}->error($msg);
                        throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
                    }

                    my ($domain, @junk) = split(/-/, $node_name);
                    if (not defined $prev_domain) {
                        $prev_domain = $domain;
                    } elsif ($domain eq $prev_domain) {
                        $link_type = "DOMAIN_Link";
                    } else {
                        $link_type = "ID_Link";
                    }

                    my %new_endpoint = ();

                    $new_endpoint{"type"} = $node_type;
                    $new_endpoint{"name"} = $node_name;

                    push @endpoints, \%new_endpoint;

                    $num_endpoints++;
                }
            }

            if ($num_endpoints != 2) {
                my $msg = "Invalid number of endpoints, $num_endpoints, must be 2";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            }

            my @sublinks = keys %sublinks;

            my %new_link = ();

            $new_link{"globalName"} = $global_name;
            $new_link{"name"} = $local_name;
            $new_link{"sublinks"} = \@sublinks;
            $new_link{"endpoints"} = \@endpoints;
            $new_link{"type"} = $link_type;

            if (defined $circuits{$local_name}) {
                my $msg = "Error: existing link of name $local_name";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            } else {
                $circuits{$local_name} = \%new_link;
            }
        }
    }

    $self->{CIRCUITS} = \%circuits;

    return;
}

1;

__END__
=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Time>, L<perfSONAR_PS::Client::LS::Remote>,
L<perfSONAR_PS::Client::Status::SQL>, L<perfSONAR_PS::Topology::ID>


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

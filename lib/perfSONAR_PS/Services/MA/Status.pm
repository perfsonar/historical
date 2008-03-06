package perfSONAR_PS::Services::MA::Status;

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'CLIENT', 'LOGGER', 'MDOUTPUT', 'LINKSBYID', 'NODESBYNAME', 'ENABLE_COMPAT';

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

our $VERSION = 0.06;

sub init;
sub needLS;
sub registerLS;
sub handleEvent;
sub handleStoreRequest;
sub handleQueryRequest;
sub lookupAllRequest;
sub lookupLinkStatusRequest;
sub writeoutLinkState_range;
sub writeoutLinkState;

my %status_namespaces = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
    select=>"http://ggf.org/ns/nmwg/ops/select/2.0/",
    nmtopo=>"http://ogf.org/schema/network/topology/base/20070828/",
    topoid=>"http://ogf.org/schema/network/topology/id/20070828/",
    ifevt=>"http://ggf.org/ns/nmwg/event/status/base/2.0/",
    nmtl2=>"http://ggf.org/ns/nmwg/topology/l2/3.0/",
);

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

    $self->{ENABLE_COMPAT} = 1;

    if ($self->{CONF}->{"status"}->{"disable_compat_protocol"}) {
        $self->{ENABLE_COMPAT} = 0;
    }

    if ($self->{ENABLE_COMPAT}) {
        if ($self->{CONF}->{"status"}->{"link_description_file"}) {
            my $file = $self->{CONF}->{"status"}->{"link_description_file"};
            if (defined $self->{DIRECTORY}) {
                if (!($file =~ "^/")) {
                    $file = $self->{DIRECTORY}."/".$file;
                }
            }

            $self->parseLinkDefinitionsFile($file);
        } else {
            $self->{LOGGER}->warn("No link description file, disabling compatibility with the SQLMA L2 Status MA");
            $self->{ENABLE_COMPAT} = 0;
        }
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

    $self->{CLIENT}->close;

    $handler->registerEventHandler("MetadataKeyRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
    $handler->registerEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
    $handler->registerEventHandler("MeasurementArchiveStoreRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);

    return 0;
}

sub needLS {
    my ($self) = @_;

    return ($self->{CONF}->{"status"}->{"enable_registration"});
}

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
        my $msg = "Couldn't get link nformation from database: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    my @link_mds = ();
    my $i = 0;
    foreach my $link_id (@{ $res }) {
        my $md = q{};

        $md .= "<nmwg:metadata id=\"meta$i\">\n";
        $md .= "<nmwg:subject id=\"sub$i\">\n";
        $md .= " <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"".escapeString($link_id)."\" />\n";
        $md .= "</nmwg:subject>\n";
        $md .= "<nmwg:eventType>Link.Status</nmwg:eventType>\n";
        $md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/link/status/20070809</nmwg:eventType>\n";
        $md .= "</nmwg:metadata>\n";
        push @link_mds, $md;
        $i++;
    }

    $res = q{};

    my $n = $self->{LS_CLIENT}->registerDynamic(\@link_mds);

    if (defined $sleep_time) {
        ${$sleep_time} = $self->{CONF}->{"status"}->{"ls_registration_interval"};
    }

    return $n;
}

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
    my $doOutputMetadata = $parameters->{doOutputMetadata};

    my $md = $subjects[0];

    my ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    my ($link_ids, $selectTime, $responseType, $was_key)  = $self->parseSubject($md);

    # In the compatability mode, if it's not a key, the module will handle all
    # the output since it needs to output the node and link element metadata
    if ($responseType eq "compat" and not $was_key) {
        ${ $doOutputMetadata } = 0;
    }

    my $metadataId;
    my @filters = @{ $parameters->{filterChain} };
    $selectTime = $self->resolveSelectChain($md, $parameters->{filterChain}, $selectTime);
    if ($#filters > -1) {
        $metadataId = $filters[-1][0]->getAttribute("id");
    } else {
        $metadataId = $md->getAttribute("id");
    }

    if ($messageType eq "SetupDataRequest") {
        $self->handleLinkStatusRequest($output, $metadataId, $link_ids, $selectTime, $responseType, $was_key);
    } elsif ($messageType eq "MetadataKeyRequest") {
        $self->handleMetadataKeyRequest($output, $metadataId, $link_ids, $selectTime, $responseType, $was_key);
    } elsif ($messageType eq "MeasurementArchiveStoreRequest") {
        if ($#filters > -1) {
            throw perfSONAR_PS::Error_compat("error.ma.select", "Can't have a store with select parameters");
        }

        my @link_ids = @{ $link_ids };
        if ($#link_ids > 0) {
            throw perfSONAR_PS::Error_compat("error.ma.subject", "Can't have a store with multiple subject links");
        }

        my $knowledge = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="knowledge"]');

        if (not defined $knowledge or $knowledge eq q{}) {
            $knowledge = "full";
        } else {
            $knowledge = lc($knowledge);
        }

        if ($knowledge ne "full" and $knowledge ne "partial") {
            throw perfSONAR_PS::Error_compat("error.ma.parameters", "Knowledge must be either 'full' or 'partial'");
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

        $self->handleStoreRequest($output, $metadataId, $link_ids[0], $responseType, $knowledge, $do_update, $d);
    }

    return;
}

sub handleStoreRequest {
    my ($self, $output, $metadataId, $link_id, $responseType, $knowledge, $do_update, $d) = @_;

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

    ($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $link_id, $knowledge, $operState, $adminState, $do_update);
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

sub handleLinkStatusRequest {
    my ($self, $output, $metadataId, $linkIds, $time, $responseType, $was_key) = @_;
    my ($status, $res);

    if (defined $time and $time->getType() eq "point" and $time->getTime() == -1) {
        ($status, $res) = $self->{CLIENT}->getLinkHistory($linkIds);
    } else {
        ($status, $res) = $self->{CLIENT}->getLinkStatus($linkIds, $time);
    }

    if ($status != 0) {
        my $msg = "Couldn't get information about links from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.fetch", $msg);
    }

    foreach my $link_id (@{ $linkIds }) {
        my $mdID;
        if ($was_key) {
            $mdID = $metadataId;
        } else {
            $mdID  = $self->outputMetadata($output, $link_id, $metadataId, $responseType);
        }

        my $data_content = q{};

        if (defined $res->{$link_id}) {
            foreach my $link (@{ $res->{$link_id} }) {
                if (defined $time and $time->getType() eq "point" and $time->getTime() != -1) {
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
                if ($curr_time < $startTime or $curr_time > $endTime) {
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

        if ($startTime > $endTime) {
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
        my $link_ids = $self->lookupLinkIDs($topoid_subj->textContent);

        return ($link_ids, undef, "topoid", 0);
    }

    if ($nmwg_subj) {
        # we've got a compat subject
        my $compat_subj = find($nmwg_subj, "./*[local-name()='link' and namespace-uri()='".$status_namespaces{"nmtl2"}."']", 1);
        if ($compat_subj) {
            unless ($self->{ENABLE_COMPAT}) {
                throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid subject type");
            }

            my $link_ids = $self->parseCompatSubject($compat_subj);
            return ($link_ids, undef, "compat", 0);
        }

        # we've got the nmwg subject
        my $link_id = findvalue($nmwg_subj, './*[local-name()=\'link\']/@id');
        if ($link_id) {
            my @tmp = ( "$link_id" );
            return (\@tmp, $time, "linkid", 0);
        }
    }

    if (not defined find($subject_md, './*[local-name()=\'subject\']', 1)) {
        unless ($self->{ENABLE_COMPAT}) {
            throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid subject type");
        }

        my @link_ids = keys %{ $self->{LINKSBYID} };

        return (\@link_ids, undef, "compat", 0);
    }

    throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid subject type");
}

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
    if (not $responseFormat or ($responseFormat ne "topoid" and $responseFormat ne "linkid" and $responseFormat ne "compat")) {
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

sub parseCompatSubject {
    my ($compat_subj) = @_;
    # currently, unimpelemented
    throw perfSONAR_PS::Error_compat("error.ma.subject", "Invalid subject type");
}

sub lookupLinkIDs {
    my ($self, $topo_exp) = @_;

    my $link_ids;

    $self->{LOGGER}->debug("lookupLinkIDs: '".$topo_exp."'");

    if (idIsAmbiguous($topo_exp)) {
        # we've got an ambiguous identifier, so we need to match it with the
        # known set

        # now we have to look up all the values it could be
        my ($status, $res) = $self->{CLIENT}->getUniqueIDs;
        if ($status != 0) {
            my $msg = "Couldn't get link information from database: $res";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
        }

        $self->{LOGGER}->debug("Links: ".Dumper($res));

        $link_ids = idMatch($res, $topo_exp);

        if (not defined $link_ids) {
            my $msg = "No links match expression: $topo_exp";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat( "error.ma.storage", $msg );
        }
    } else {
        # it's a non-ambiguous identifier so it could only match one element
        my @tmp = ( $topo_exp );
        $link_ids = \@tmp;
    }

    return $link_ids;
}

sub handleMetadataKeyRequest {
    my ($self, $output, $metadataId, $link_ids, $time, $responseType, $was_key) = @_;

    my $i = genuid();
    foreach my $link_id (@{ $link_ids }) {
        my $mdID;
        if ($was_key) {
            $mdID = $metadataId;
        } else {
            $mdID  = $self->outputMetadata($output, $link_id, $metadataId, $responseType);
        }

        my $dID = "data$i";
        startData($output, $dID, $mdID, undef);
            $self->createKey($output, $link_id, $time, $responseType);
        endData($output);
    }

    return;
}

sub outputMetadata {
    my ($self, $output, $link_id, $parentMdId, $responseType) = @_;

    if ($responseType eq "linkid") {
        return $self->outputLinkIDMetadata($output, $link_id, $parentMdId);
    } elsif ($responseType eq "topoid") {
        return $self->outputTopoIDMetadata($output, $link_id, $parentMdId);
    } elsif ($responseType eq "compat") {
        return $self->outputCompatMetadata($output, $link_id, $parentMdId);
    }
}

sub outputLinkIDMetadata {
    my ($self, $output, $link_id, $parentMdId) = @_;

    my $md_content = q{};
    $md_content .= "<nmwg:subject id=\"sub0\">\n";
    $md_content .= "  <nmtopo:link xmlns:nmtopo=\"".$status_namespaces{"nmtopo"}."\" id=\"".escapeString($link_id)."\" />\n";
    $md_content .= "</nmwg:subject>\n";

    my $mdID = "metadata.".genuid();

    createMetadata($output, $mdID, $parentMdId, $md_content, undef);

    return $mdID;
}

sub outputTopoIDMetadata {
    my ($self, $output, $link_id, $parentMdId) = @_;

    my $md_content = "<topoid:subject xmlns:topoid=\"".$status_namespaces{"topoid"}."\">".escapeString($link_id)."</topoid:subject>";

    my $mdID = "metadata.".genuid();

    createMetadata($output, $mdID, $parentMdId, $md_content, undef);

    return $mdID;
}

sub outputCompatMetadata {
    my ($self, $output, $link_id, $parentMdId) = @_;

    $self->{LOGGER}->debug("Link ID($link_id): ".Dumper($self->{LINKSBYID}));
    $self->{LOGGER}->debug("Nodes: ".Dumper($self->{NODESBYNAME}));

    return "" if (not defined $self->{LINKSBYID}->{$link_id});

    my $link = $self->{LINKSBYID}->{$link_id};
    my $nodeA = $self->{NODESBYNAME}->{$link->{'nodeA'}->{'name'}};
    my $nodeB = $self->{NODESBYNAME}->{$link->{'nodeB'}->{'name'}};

    my ($link_mdId, $nodeA_mdId, $nodeB_mdId);

    $link_mdId = $link->{'metadataId'};
    $nodeA_mdId = $nodeA->{'metadataId'} if (defined $nodeA);
    $nodeB_mdId = $nodeB->{'metadataId'} if (defined $nodeB);

    if (not defined $self->{MDOUTPUT}) {
        my %hash = ();
        $self->{MDOUTPUT} = \%hash;
    }

    if (defined $nodeA and not defined $self->{MDOUTPUT}->{$nodeA_mdId}) {
        startMetadata($output, $nodeA_mdId, "", undef);
          $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => 'sub-'.$nodeA->{'name'} });
            $self->outputNodeElement($output, $nodeA);
          $output->endElement("subject");
        endMetadata($output);
        $self->{MDOUTPUT}->{$nodeA_mdId} = 1;
    }

    if (defined $nodeB and not defined $self->{MDOUTPUT}->{$nodeB_mdId}) {
        startMetadata($output, $nodeB_mdId, "", undef);
          $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => 'sub-'.$nodeB->{'name'} });
            $self->outputNodeElement($output, $nodeB);
          $output->endElement("subject");
        endMetadata($output);
        $self->{MDOUTPUT}->{$nodeB_mdId} = 1;
    }

    if (not defined $self->{MDOUTPUT}->{$link_mdId}) {
        startMetadata($output, $link_mdId, "", undef);
          $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => 'sub-'.$link->{'name'} });
            $self->outputLinkElement($output, $link);
          $output->endElement("subject");
        endMetadata($output);
        $self->{MDOUTPUT}->{$link_mdId} = 1;
    }

    return $link_mdId;
}

sub outputNodeElement {
    my ($self, $output, $node) = @_;

    $self->{LOGGER}->debug("Outputing node: ".Dumper($node));

    $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { id => $node->{'name'} });
      $output->createElement(prefix => "nmwgtopo3", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => "TopologyPoint");
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

sub outputLinkElement {
    my ($self, $output, $link) = @_;

    $output->startElement(prefix => "nmtl2", tag => "link", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { id => $link->{'name'} });
      $output->createElement(prefix => "nmtl2", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"name"});
      $output->createElement(prefix => "nmtl2", tag => "globalName", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $link->{"globalName"});
      $output->createElement(prefix => "nmtl2", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", content => $link->{"type"});
      $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $link->{'nodeA'}->{"name"} });
      $output->createElement(prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $link->{'nodeA'}->{"type"});
      $output->endElement("node");
      $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $link->{'nodeB'}->{"name"} });
      $output->createElement(prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $link->{'nodeB'}->{"type"});
      $output->endElement("node");
      startParameters($output, "params.0");
        addParameter($output, "supportedEventType", "Path.Status");
      endParameters($output);
    $output->endElement("link");

    return;
}

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

sub writeoutLinkState_range {
    my ($self, $link) = @_;

    return q{} if (not defined $link);

    my $localContent = q{};

    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\" knowledge=\"".$link->getKnowledge."\"\n";
    $localContent .= "    startTime=\"".$link->getStartTime."\" startTimeType=\"unix\" endTime=\"".$link->getEndTime."\" endTimeType=\"unix\">\n";
    $localContent .= "    <ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
    $localContent .= "    <ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
    $localContent .= "</ifevt:datum>\n";

    return $localContent;
}

sub writeoutLinkState {
    my ($self, $link, $time) = @_;

    return q{} if (not defined $link);

    my $localContent = q{};

    if (not defined $time or $time eq q{}) {
    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\">\n";
    } else {
    $localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"$time\">\n";
    }
    $localContent .= "    <ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
    $localContent .= "    <ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
    $localContent .= "</ifevt:datum>\n";

    return $localContent;
}

sub parseLinkDefinitionsFile {
    my ($self, $file) = @_;

    my %nodes = ();
    my %links = ();

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

        if (not defined $node_name or $node_name eq q{}) {
            my $msg = "Node needs to have a name";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
        }

        if (defined $nodes{$node_name}) {
            my $msg = "Multiple endpoints have the name \"$node_name\"";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
        }

        my %tmp = ();
        my $new_node = \%tmp;

        $new_node->{"name"} = $node_name;
        $new_node->{"city"} = $city if (defined $city and $city ne q{});
        $new_node->{"country"} = $country if (defined $country and $country ne q{});
        $new_node->{"longitude"} = $longitude if (defined $longitude and $longitude ne q{});
        $new_node->{"latitude"} = $latitude if (defined $latitude and $latitude ne q{});
        $new_node->{"institution"} = $institution if (defined $institution and $institution ne q{});
        $new_node->{'metadataId'} = "metadata.".$node_name.".".genuid();

        $nodes{$node_name} = $new_node;
    }
    }

    $find_res = find($conf, "./*[local-name()='link']", 0);
    if ($find_res) {
    foreach my $link ($find_res->get_nodelist) {
        my $global_name = findvalue($link, "globalName");
        my $local_name = findvalue($link, "localName");
        my $link_id = findvalue($link, "linkID");
        my $knowledge = $link->getAttribute("knowledge");
        my $link_type;

        if (not defined $global_name or $global_name eq q{}) {
            my $msg = "Link has no global name";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
        }

        if (not defined $knowledge or $knowledge eq q{}) {
            $self->{LOGGER}->warn("Don't know the knowledge level of link \"$global_name\". Assuming full");
            $knowledge = "full";
        } else {
            $knowledge = lc($knowledge);
        }

        if (not defined $local_name or $local_name eq q{}) {
            $local_name = $global_name;
        }

        my $prev_domain;
        my ($nodeA, $nodeB);

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
                if ($knowledge eq "full") {
                    $link_type = "ID_Link";
                } else {
                    $link_type = "ID_LinkPartialInfo";
                }
            }

            my %new_endpoint = ();

            $new_endpoint{"type"} = $node_type;
            $new_endpoint{"name"} = $node_name;

            if (not defined $nodeA) {
                $nodeA = \%new_endpoint;
            } elsif (not defined $nodeB) {
                $nodeB = \%new_endpoint;
            } else {
                my $msg = "Invalid number of endpoints on link $global_name must be 2";
                $self->{LOGGER}->error($msg);
                throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
            }
        }
        }

        my %new_link = ();

        $new_link{"globalName"} = $global_name;
        $new_link{"name"} = $local_name;
        $new_link{"link"} = $link_id;
        $new_link{"nodeA"} = $nodeA;
        $new_link{"nodeB"} = $nodeB;
        $new_link{"type"} = $link_type;
        $new_link{'metadataId'} = "metadata.".$global_name.".".genuid();

        if (defined $links{$link_id}) {
            my $msg = "Error: existing circuit of name $local_name";
            $self->{LOGGER}->error($msg);
            throw perfSONAR_PS::Error_compat ("error.configuration", $msg);
        }

        $links{$link_id} = \%new_link;
    }
    }

    $self->{NODESBYNAME} = \%nodes;
    $self->{LINKSBYID} = \%links;

    return 0;
}

1;

__END__
=head1 NAME

perfSONAR_PS::Services::MA::Status - A module that provides methods for the Status MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::Services::MA::Status;

my %conf = readConfiguration();

my %ns = (
        nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
        ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
        nmtopo => "http://ogf.org/schema/network/topology/base/20070707/",
     );

my $ma = perfSONAR_PS::Services::MA::Status->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::Services::MA::Status->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

if ($ma->init != 0) {
    print "Error: couldn't initialize measurement archive\n";
    exit(-1);
}

$ma->registerLS;

while(1) {
    my $request = $ma->receive;
    $ma->handleRequest($request);
}

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive.

=head2 init 

       Initializes the MA and validates or fills in entries in the
    configuration file. Returns 0 on success and -1 on failure.

=head2 registerLS($self)

    Reads the information contained in the database and registers it with
    the specified LS.

=head2 receive($self)

    Grabs an incoming message from transport object to begin processing. It
    completes the processing if the message was handled by a lower layer.
    If not, it returns the Request structure.

=head2 handleRequest($self, $request)

    Handles the specified request returned from receive()

=head2 __handleRequest($self)

    Validates that the message is one that we can handle, calls the
    appropriate function for the message type and builds the response
    message. 

=head2 parseStoreRequest($self, $request)

    Goes through each metadata/data pair, extracting the eventType and
    calling the function associated with that eventType.

=head2 handleStoreRequest($self, $link_id, $knowledge, $time, $operState, $adminState, $do_update)

    Stores the new link information into the database. If an update is to
    be performed, the function reads in the most recent data for the
    specified link and updates it.

=head2 parseQueryRequest($self, $request)

    Goes through each metadata/data pair, extracting the eventType and
    any other relevant information calling the function associated with
    that eventType.

=head2 lookupAllRequest($self, $metadata, $data)

    Reads all link information from the database and constructs the
    metadata/data pairs for the response.

=head2 lookupLinkStatusRequest($self, $link_id, $time)

    Looks up the requested link information from the database and
    returns the results.

=head2 writeoutLinkState_range($self, $link)

    Writes out the requested link in a format slightly different than the
    normal ifevt. The ifevt schema has only the concept of events at a
    single point in time. This output is compatible with applications
    expecting the normal ifevt output, but also contains a start time and
    an end time during which the status was the same.

=head2 writeoutLinkState($self, $link, $time)

    Writes out the requested link according to the ifevt schema. If time is
    empty, it simply uses the end time of the given range as the time for
    the event.

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Client::LS::Remote>,
L<perfSONAR_PS::Client::Status::SQL>


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
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

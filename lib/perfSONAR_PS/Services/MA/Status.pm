package perfSONAR_PS::Services::MA::Status;

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'CLIENT', 'LOGGER';

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::Time;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Client::Status::SQL;

our $VERSION = 0.06;

sub init;
sub needLS;
sub registerLS;
sub handleEvent;
sub handleStoreRequest;
sub __handleStoreRequest;
sub handleQueryRequest;
sub lookupAllRequest;
sub lookupLinkStatusRequest;
sub writeoutLinkState_range;
sub writeoutLinkState;

my %status_namespaces = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
    select=>"http://ggf.org/ns/nmwg/ops/select/2.0/",
    nmtopo=>"http://ogf.org/schema/network/topology/base/20070828/",
    ifevt=>"http://ggf.org/ns/nmwg/event/status/base/2.0/",
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

    $handler->registerEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
    $handler->registerEventHandler("SetupDataRequest", "Database.Dump", $self);
    $handler->registerEventHandler_Regex("SetupDataRequest", ".*select.*", $self);
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
        exit(-1);
    }

    ($status, $res) = $self->{CLIENT}->getUniqueIDs;
    if ($status != 0) {
        my $msg = "Couldn't get link nformation from database: $res";
        $self->{LOGGER}->error($msg);
        exit(-1);
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
    			mergeChain => 1,
    			filterChain => 1,
    			data => 1,
    			rawRequest => 1
    		});

    my $output = $parameters->{"output"};
    my $messageId = $parameters->{"messageId"};
    my $messageType = $parameters->{"messageType"};
    my $message_parameters = $parameters->{"messageParameters"};
    my $eventType = $parameters->{"eventType"};
    my $d = $parameters->{"data"};
    my $raw_request = $parameters->{"rawRequest"};
    my $md = shift(@{ $parameters->{"mergeChain"} });

    if ($messageType eq "MeasurementArchiveStoreRequest") {
        return $self->handleStoreRequest($output, $md, $d);
    } elsif ($messageType eq "SetupDataRequest") {
        my $selectTime;

        my $metadataId;
        my @filter = @{ $parameters->{filterChain} };
        if ($#filter > -1) {
            $selectTime = $self->resolveSelectChain($parameters->{filterChain});
            my $curr_md = shift(@{ $filter[$#filter] });
            $self->{LOGGER}->debug("MD: ".$curr_md->toString);
            $metadataId = $curr_md->getAttribute("id");
        } else {
            $selectTime = $self->resolveCompatTime($md);
            $metadataId = $md->getAttribute("id");
        }

        return $self->handleQueryRequest($output, $metadataId, $md, $selectTime);
    }
}

sub resolveCompatTime {
    my ($self, $md) = @_;

    my $ret_time;
    my $time = findvalue($md, "./*[local-name()='parameters' and namespace-uri()='".$status_namespaces{"nmwg"}."' and \@name=\"time\"]");
    if (defined $time) {
        if (lc($time) eq "all") {
            $ret_time = perfSONAR_PS::Time->new("point", -1);
        } elsif (lc($time) ne "now" and $time ne q{}) {
            $ret_time = perfSONAR_PS::Time->new("point", $time);
        }
    }

    return $ret_time;
}

sub resolveSelectChain {
    my ($self, $filterChain) = @_;

    my ($time, $startTime, $endTime, $duration);

    foreach my $filter_arr (@{ $filterChain }) {
        my @filters = @{ $filter_arr };
        my $filter = $filters[$#filters];
        my $select_subject = find($filter, "./*[local-name()='subject' and namespace-uri()='".$status_namespaces{"select"}."']", 1);

        if (not defined $select_subject) {
            # we definitely have a subject in this message, we just don't understand it
            throw perfSONAR_PS::Error_compat("error.ma.unsupported_filter_type", "This Status MA only supports select filters and metadata ".$filter->getAttribute("id")." does not contain a select subject");
        }

        $self->{LOGGER}->debug("Filter: ".$filter->toString);

        my $select_parameters = find($select_subject, "./*[local-name()='parameters' and namespace-uri()='".$status_namespaces{"select"}."']", 1);
        
        next if (not defined $select_parameters);
    
        my $curr_time = findvalue($select_parameters, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"select"}."' and \@name=\"time\"]");
        my $curr_startTime = findvalue($select_parameters, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"select"}."' and \@name=\"startTime\"]");
        my $curr_endTime = findvalue($select_parameters, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"select"}."' and \@name=\"endTime\"]");
        my $curr_duration = findvalue($select_parameters, "./*[local-name()='parameter' and namespace-uri()='".$status_namespaces{"select"}."' and \@name=\"duration\"]");

        $time = $curr_time if ($curr_time);
        $duration = $curr_duration if ($curr_duration);
        if ($curr_startTime) {
            $startTime = $curr_startTime if (not defined $startTime or $curr_startTime > $startTime);
        }

        if ($curr_endTime) {
            $endTime = $curr_endTime if (not defined $endTime or $curr_endTime > $endTime);
        }
    }

    if (defined $time and (defined $startTime or defined $endTime or defined $duration)) {
        throw perfSONAR_PS::Error_compat("error.ma.select", "Ambiguous select parameters");
    }

    if (defined $time) {
        if (lc($time) eq "now") {
            return undef;
        }
        return perfSONAR_PS::Time->new("point", $time);
    }

    if (not defined $startTime) {
        throw perfSONAR_PS::Error_compat("error.ma.select", "No start time specified");
    } elsif (not defined $endTime and not defined $duration) {
        throw perfSONAR_PS::Error_compat("error.ma.select", "No end time specified");
    } elsif (defined $endTime) {
        return perfSONAR_PS::Time->new("range", $startTime, $endTime);
    } else {
        return perfSONAR_PS::Time->new("duration", $startTime, $duration);
    }
}

sub handleStoreRequest {
    my ($self, $output, $md, $d) = @_;

    my ($status, $res);
    my $link_id = findvalue($md, './nmwg:subject/*[local-name()=\'link\']/@id');
    my $knowledge = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="knowledge"]');
    my $do_update = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="update"]');
    my $time = findvalue($d, './ifevt:datum/@timeValue');
    my $time_type = findvalue($d, './ifevt:datum/@timeType');
    my $adminState = findvalue($d, './ifevt:datum/ifevt:stateAdmin');
    my $operState = findvalue($d, './ifevt:datum/ifevt:stateOper');

    if (not defined $knowledge or $knowledge eq q{}) {
        $knowledge = "full";
    } else {
        $knowledge = lc($knowledge);
    }

    if (defined $do_update and $do_update ne q{}) {
        if (lc($do_update) eq "yes") {
            $do_update = 1;
        } elsif (lc($do_update) eq "no") {
            $do_update = 0;
        }
    } else {
        $do_update = 0;
    }

    if (not defined $link_id or $link_id eq q{}) {
        $status = "error.ma.query.incomplete_metadata";
        $res = "Metadata ".$md->getAttribute("id")." is missing the link id";
        $self->{LOGGER}->error($res);
        throw perfSONAR_PS::Error_compat($status, $res);
    }

    if ($knowledge ne "full" and $knowledge ne "partial") {
        $status = "error.ma.query.invalid_knowledge_level";
        $res = "Invalid knowledge level specified, \"$knowledge\", must be either 'full' or 'partial'";
        $self->{LOGGER}->error($res);
        throw perfSONAR_PS::Error_compat($status, $res);
    }

    if (not defined $time or $time eq q{} or not defined $time_type or $time_type eq q{} or not defined $adminState or $adminState eq q{} or not defined $operState or $operState eq q{}) {
        $status = "error.ma.query.incomplete_data";
        $res = "Data block is missing:";
        $res .= " 'time'" if (not defined $time or $time eq q{});
        $res .= " 'time type'" if (not defined $time_type or $time_type eq q{});
        $res .= " 'administrative state'" if (not defined $adminState or $adminState eq q{});
        $res .= " 'operational state'" if (not defined $operState or $operState eq q{});
        $self->{LOGGER}->error($res);
        throw perfSONAR_PS::Error_compat($status, $res);
    }

    if ($time_type ne "unix") {
        $status = "error.ma.query.invalid_timestamp_type";
        $res = "Time type must be 'unix'";
        $self->{LOGGER}->error($res);
        throw perfSONAR_PS::Error_compat($status, $res);
    }

    if (not defined $do_update) {
        $status = "error.ma.query.invalid_update_parameter";
        $res = "The update parameter, if included, must be 'yes' or 'no', not '$do_update'";
        $self->{LOGGER}->error($res);
        throw perfSONAR_PS::Error_compat($status, $res);
    }

    ($status, $res) = $self->__handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update);

    my $mdID = "metadata.".genuid();

    my $subID = "sub0";
    my $md_content = q{};
    $md_content .= "<nmwg:subject id=\"$subID\">\n";
    $md_content .= "  <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"".escapeString($link_id)."\" />\n";
    $md_content .= "</nmwg:subject>\n";
    $md_content .= "<nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/link/status/20070809</nmwg:eventType>\n";
    createMetadata($output, $md->getAttribute("id"), "", $md_content, undef);
    getResultCodeMetadata($output, $mdID, $md->getAttribute("id"), "success.ma.added");
    getResultCodeData($output, "data.".genuid(), $mdID, "new data element successfully added", 1);

    return;
}

sub __handleStoreRequest {
    my ($self, $link_id, $knowledge, $time, $operState, $adminState, $do_update) = @_;
    my ($status, $res);

    $self->{LOGGER}->debug("handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update)");

    ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    ($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $link_id, $knowledge, $operState, $adminState, $do_update);
    if ($status != 0) {
        my $msg = "Database update failed: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.update", $msg);
    }

    return;
}

sub handleQueryRequest {
    my ($self, $output, $metadataId, $subject_md, $time) = @_;
    my ($status, $res);

    my $eventType = findvalue($subject_md, "./nmwg:eventType");

    if ($eventType eq "Database.Dump") {
        $self->lookupAllRequest($output, $metadataId, $subject_md);
    } elsif ($eventType eq "Link.Status" or
            $eventType eq "http://ggf.org/ns/nmwg/characteristic/link/status/20070809") {
        $self->lookupLinkStatusRequest($output, $metadataId, $subject_md, $time);
    } else {
        throw perfSONAR_PS::Error_compat("error.ma.event_type", "\'$eventType\' is not supported");
    }

    return;
}


sub lookupAllRequest {
    my ($self, $output, $metadataId, $subject_md) = @_;
    my $localContent = q{};
    my ($status, $res);

    $self->{LOGGER}->debug("lookupAllRequest()");

    my $mdID = $subject_md->getAttribute("id");

    ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    ($status, $res) = $self->{CLIENT}->getAll;
    if ($status != 0) {
        my $msg = "Couldn't get information from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.fetch", $msg);
    }

    my %links = %{ $res };

    my $i = genuid();
    foreach my $link_id (keys %links) {
        my $mdID = "meta$i";
        my $subID = "sub$i";
        my $md_content = q{};
        $md_content .= "<nmwg:subject id=\"sub$i\">\n";
        $md_content .= "  <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"".escapeString($link_id)."\" />\n";
        $md_content .= "</nmwg:subject>\n";
        createMetadata($output, $mdID, $metadataId, $md_content, undef);
        my $data_content = q{};
        foreach my $link (@{ $links{$link_id} }) {
            $data_content .= $self->writeoutLinkState_range($link);
        }
        createData($output, "data.".$i, $mdID, $data_content, undef);
        $i++;
    }

    return;
}

sub lookupLinkStatusRequest {
    my($self, $output, $metadataId, $md, $time) = @_;
    my ($status, $res);

    $self->{LOGGER}->debug("lookupLinkStatusRequest()");

    my $link_id = findvalue($md, './nmwg:subject/*[local-name()=\'link\']/@id');

    if (not defined $link_id or $link_id eq q{}) {
        throw perfSONAR_PS::Error_compat("error.ma.status.no_link_id", "No link id specified in request");
    }

    ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.open", $msg);
    }

    my @tmp_array = ( $link_id );

    if (defined $time and $time->getType() eq "point" and $time->getTime() == -1) {
        ($status, $res) = $self->{CLIENT}->getLinkHistory(\@tmp_array);
    } else {
        ($status, $res) = $self->{CLIENT}->getLinkStatus(\@tmp_array, $time);
    }

    if ($status != 0) {
        my $msg = "Couldn't get information about link $link_id from database: $res";
        $self->{LOGGER}->error($msg);
        throw perfSONAR_PS::Error_compat("error.common.storage.fetch", $msg);
    }

    my $data_content = q{};
    foreach my $link (@{ $res->{$link_id} }) {
        if (defined $time and $time->getType() eq "point" and $time->getTime() != -1) {
            $data_content .= $self->writeoutLinkState($link);
        } else {
            $data_content .= $self->writeoutLinkState_range($link);
        }
    }
    createData($output, "data.".genuid(), $metadataId, $data_content, undef);

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

package perfSONAR_PS::Services::MA::Status;

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'CLIENT';

our $VERSION = 0.03;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Client::Status::SQL;

sub init($$);
sub needLS($);
sub registerLS($$);
sub handleEvent($$$$$$$$$);
sub handleStoreRequest($$$$);
sub __handleStoreRequest($$$$$$);
sub handleQueryRequest($$$$$);
sub lookupAllRequest($$$$);
sub lookupLinkStatusRequest($$$$);
sub writeoutLinkState_range($$$);
sub writeoutLinkState($$$);

my %namespaces = (
	select=>"http://ggf.org/ns/nmwg/ops/select/2.0/",
	nmtopo=>"http://ogf.org/schema/network/topology/base/20070828/",
	ifevt=>"http://ggf.org/ns/nmwg/event/status/base/2.0/",
);

sub init($$) {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	if (!defined $self->{CONF}->{"status"}->{"enable_registration"} or $self->{CONF}->{"status"}->{"enable_registration"} eq "") {
		$logger->warn("Disabling LS registration");
		$self->{CONF}->{"status"}->{"enable_registration"} = 0;
	}

	if ($self->{CONF}->{"status"}->{"enable_registration"}) {
		if (!defined $self->{CONF}->{"status"}->{"service_accesspoint"} or $self->{CONF}->{"status"}->{"service_accesspoint"} eq "") {
			$logger->error("No access point specified for SNMP service");
			return -1;
		}

		if (!defined $self->{CONF}->{"status"}->{"ls_instance"} or $self->{CONF}->{"status"}->{"ls_instance"} eq "") {
			if (defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne "") {
				$self->{CONF}->{"status"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
			} else {
				$logger->error("No LS instance specified for SNMP service");
				return -1;
			}
		}

		if (!defined $self->{CONF}->{"status"}->{"ls_registration_interval"} or $self->{CONF}->{"status"}->{"ls_registration_interval"} eq "") {
			if (defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne "") {
				$self->{CONF}->{"status"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
			} else {
				$logger->warn("Setting registration interval to 30 minutes");
				$self->{CONF}->{"status"}->{"ls_registration_interval"} = 1800;
			}
		} else {
			# turn the registration interval from minutes to seconds
			$self->{CONF}->{"status"}->{"ls_registration_interval"} *= 60;
		}

		$logger->debug("Registration interval: ".  $self->{CONF}->{"status"}->{"ls_registration_interval"});

		if(!defined $self->{CONF}->{"status"}->{"service_description"} or
				$self->{CONF}->{"status"}->{"service_description"} eq "") {
			$self->{CONF}->{"status"}->{"service_description"} = "perfSONAR_PS Status MA";
			$logger->warn("Setting 'service_description' to 'perfSONAR_PS Status MA'.");
		}

		if(!defined $self->{CONF}->{"status"}->{"service_name"} or
				$self->{CONF}->{"status"}->{"service_name"} eq "") {
			$self->{CONF}->{"status"}->{"service_name"} = "Status MA";
			$logger->warn("Setting 'service_name' to 'Status MA'.");
		}

		if(!defined $self->{CONF}->{"status"}->{"service_type"} or
				$self->{CONF}->{"status"}->{"service_type"} eq "") {
			$self->{CONF}->{"status"}->{"service_type"} = "MA";
			$logger->warn("Setting 'service_type' to 'MA'.");
		}

		my %ls_conf = (
				SERVICE_TYPE => $self->{CONF}->{"status"}->{"service_type"},
				SERVICE_NAME => $self->{CONF}->{"status"}->{"service_name"},
				SERVICE_DESCRIPTION => $self->{CONF}->{"status"}->{"service_description"},
				SERVICE_ACCESSPOINT => $self->{CONF}->{"status"}->{"service_accesspoint"},
			      );

		$self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"status"}->{"ls_instance"}, \%ls_conf, \%namespaces);
	}


	if (!defined $self->{CONF}->{"status"}->{"db_type"} or $self->{CONF}->{"status"}->{"db_type"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if (lc($self->{CONF}->{"status"}->{"db_type"}) eq "sqlite") {
		if (!defined $self->{CONF}->{"status"}->{"db_file"} or $self->{CONF}->{"status"}->{"db_file"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(db_file)");
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

		$self->{CLIENT} = new perfSONAR_PS::Client::Status::SQL("DBI:SQLite:dbname=".$file, "", "", $self->{CONF}->{"status"}->{"db_table"}, $read_only);
		if (!defined $self->{CLIENT}) {
			my $msg = "No database to dump";
			$logger->error($msg);
			return (-1, $msg);
		}
	} elsif (lc($self->{CONF}->{"status"}->{"db_type"}) eq "mysql") {
		my $dbi_string = "dbi:mysql";

		if (!defined $self->{CONF}->{"status"}->{"db_name"} or $self->{CONF}->{"status"}->{"db_name"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database (db_name)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"status"}->{"db_name"};

		if (!defined $self->{CONF}->{"status"}->{"db_host"} or $self->{CONF}->{"status"}->{"db_host"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database host (db_host)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"status"}->{"db_host"};

		if (defined $self->{CONF}->{"status"}->{"db_port"} and $self->{CONF}->{"status"}->{"db_port"} ne "") {
			$dbi_string .= ":".$self->{CONF}->{"status"}->{"db_port"};
		}

		my $read_only = 0;

		if (defined $self->{CONF}->{"status"}->{"read_only"} and $self->{CONF}->{"status"}->{"read_only"} == 1) {
			$read_only = 1;
		}

		$self->{CLIENT} = new perfSONAR_PS::Client::Status::SQL($dbi_string, $self->{CONF}->{"status"}->{"db_username"}, $self->{CONF}->{"status"}->{"db_password"}, $self->{CONF}->{"status"}->{"db_table"}, $read_only);
		if (!defined $self->{CLIENT}) {
			my $msg = "Couldn't create SQL client";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	my ($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open newly created client: $res";
		$logger->error($msg);
		return -1;
	}

	$self->{CLIENT}->close;

	$handler->addEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);
	$handler->addEventHandler_Regex("SetupDataRequest", ".*select.*", $self);
	$handler->addEventHandler("MeasurementArchiveStoreRequest", "http://ggf.org/ns/nmwg/characteristic/link/status/20070809", $self);

	return 0;
}

sub needLS($) {
	my ($self) = @_;

	return ($self->{CONF}->{"status"}->{"enable_registration"});
}

sub registerLS($$) {
	my ($self, $sleep_time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");
	my ($status, $res);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open from database: $res";
		$logger->error($msg);
		exit(-1);
	}

	($status, $res) = $self->{CLIENT}->getUniqueIDs;
	if ($status != 0) {
		my $msg = "Couldn't get link nformation from database: $res";
		$logger->error($msg);
		exit(-1);
	}

	my @link_mds = ();
	my $i = 0;
	foreach my $link_id (@{ $res }) {
		my $md = "";

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

	$res = "";

	my $n = $self->{LS_CLIENT}->registerDynamic(\@link_mds);

	if (defined $sleep_time) {
		$$sleep_time = $self->{CONF}->{"status"}->{"ls_registration_interval"};
	}

	return $n;
}

sub handleEvent($$$$$$$$$) {
	my ($self, $output, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	if ($messageType eq "MeasurementArchiveStoreRequest") {
		return $self->handleStoreRequest($output, $md, $d);
	} elsif ($messageType eq "SetupDataRequest") {
		my ($status, $res1, $res2) = $self->resolveSelectChain($md, $raw_request);
		if ($status ne "") {
			return ($status, $res1);
		}

		my $selectTime = $res1;
		my $subject_md = $res2;

		return $self->handleQueryRequest($output, $subject_md, $selectTime);
	}
}

sub resolveSelectChain($$$) {
	my ($self, $md, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	if (!$request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
		$logger->debug("No select namespace means there is no select chain");
	}

	if (!find($md, "./select:subject", 1)) {
		$logger->debug("No select subject means there is no select chain");
	}

	if ($request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and find($md, "./select:subject", 1)) {
		my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".find($md, "./select:subject", 1)->getAttribute("metadataIdRef")."\"]", 1);
		if(!$other_md) {
			return ("error.ma.chaining", "Cannot resolve supposed subject chain in metadata.");
		}

		if (!find($md, "./select:subject/select:parameters", 1)) {
			return ("error.ma.select", "No select parameters specified in given chain.");
		}

		my $time = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"time\"]");
		my $startTime = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"startTime\"]");
		my $endTime = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"endTime\"]");
		my $duration = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"duration\"]");

		if (defined $time and (defined $startTime or defined $endTime or defined $duration)) {
			return ("error.ma.select", "Ambiguous select parameters");
		}

		if (defined $time) {
			return ("", perfSONAR_PS::Time->new("point", $time), $other_md);
		}

		if (!defined $startTime) {
			return ("error.ma.select", "No start time specified");
		} elsif (!defined $endTime and !defined $duration) {
			return ("error.ma.select", "No end time specified");
		} elsif (defined $endTime) {
			return ("", perfSONAR_PS::Time->new("range", $startTime, $endTime), $other_md);
		} else {
			return ("", perfSONAR_PS::Time->new("duration", $startTime, $duration), $other_md);
		}
	} else {
		# No select subject means they didn't specify one which results in "now"
		$logger->debug("No select chain");

		my $ret_time;
		my $time = findvalue($md, "./nmwg:parameters/nmwg:parameter[\@name=\"time\"]");
		if (defined $time and lc($time) ne "now" and $time ne "") {
			$ret_time = perfSONAR_PS::Time->new("point", $time);
		}

		return ("", $ret_time, $md);
	}
}

sub handleStoreRequest($$$$) {
	my ($self, $output, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	my ($status, $res);
	my $link_id = findvalue($md, './nmwg:subject/*[local-name()=\'link\']/@id');
	my $knowledge = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="knowledge"]');
	my $do_update = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="update"]');
	my $time = findvalue($d, './ifevt:datum/@timeValue');
	my $time_type = findvalue($d, './ifevt:datum/@timeType');
	my $adminState = findvalue($d, './ifevt:datum/ifevt:stateAdmin');
	my $operState = findvalue($d, './ifevt:datum/ifevt:stateOper');

	if (!defined $knowledge or $knowledge eq "") {
		$knowledge = "full";
	} else {
		$knowledge = lc($knowledge);
	}

	if (defined $do_update and $do_update ne "") {
		if (lc($do_update) eq "yes") {
			$do_update = 1;
		} elsif (lc($do_update) eq "no") {
			$do_update = 0;
		}
	} else {
		$do_update = 0;
	}

	if (!defined $link_id or $link_id eq "") {
		$status = "error.ma.query.incomplete_metadata";
		$res = "Metadata ".$md->getAttribute("id")." is missing the link id";
		$logger->error($res);
	} elsif ($knowledge ne "full" and $knowledge ne "partial") {
		$status = "error.ma.query.invalid_knowledge_level";
		$res = "Invalid knowledge level specified, \"$knowledge\", must be either 'full' or 'partial'";
		$logger->error($res);
	} elsif (!defined $time or $time eq "" or !defined $time_type or $time_type eq "" or !defined $adminState or $adminState eq "" or !defined $operState or $operState eq "") {
		$status = "error.ma.query.incomplete_data";
		$res = "Data block is missing:";
		$res .= " 'time'" if (!defined $time or $time eq "");
		$res .= " 'time type'" if (!defined $time_type or $time_type eq "");
		$res .= " 'administrative state'" if (!defined $adminState or $adminState eq "");
		$res .= " 'operational state'" if (!defined $operState or $operState eq "");
		$logger->error($res);
	} elsif ($time_type ne "unix") {
		$status = "error.ma.query.invalid_timestamp_type";
		$res = "Time type must be 'unix'";
		$logger->error($res);
	} elsif (!defined $do_update) {
		$status = "error.ma.query.invalid_update_parameter";
		$res = "The update parameter, if included, must be 'yes' or 'no', not '$do_update'";
		$logger->error($res);
	} else {
		($status, $res) = $self->__handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update);
	}

	if ($status ne "") {
		return ($status, $res);
	} else {
		my $mdID = "metadata.".genuid();

		$output->addExistingXMLElement($md);
		getResultCodeMetadata($output, $mdID, $md->getAttribute("id"), "success.ma.added");
		getResultCodeData($output, "data.".genuid(), $mdID, "new data element successfully added", 1);

		return ("", "");
	}
}

sub __handleStoreRequest($$$$$$) {
	my ($self, $link_id, $knowledge, $time, $operState, $adminState, $do_update) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");
	my ($status, $res);

	$logger->debug("handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update)");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $link_id, $knowledge, $operState, $adminState, $do_update);
	if ($status != 0) {
		my $msg = "Database update failed: $res";
		$logger->error($msg);
		return ("error.common.storage.update", $msg);
	}

	return ("", "");
}

sub handleQueryRequest($$$$$) {
	my ($self, $output, $eventType, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	my ($status, $res);

	if ($eventType eq "Database.Dump") {
		($status, $res) = $self->lookupAllRequest($md, $d);
	} elsif ($eventType eq "Link.Status" or
			$eventType eq "http://ggf.org/ns/nmwg/characteristic/link/status/20070809") {
		($status, $res) = $self->lookupLinkStatusRequest($output, $md, $d);
	} else {
		$status = "error.ma.event_type";
		$res = "No supported event types";
	}

	return ($status, $res);
}


sub lookupAllRequest($$$$) {
	my ($self, $output, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");
	my $localContent = "";
	my ($status, $res);

	my $mdID = $md->getAttribute("id");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->getAll;
	if ($status != 0) {
		my $msg = "Couldn't get information from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	my %links = %{ $res };

	my $i = genuid();
	foreach my $link_id (keys %links) {
		my $mdID = "meta$i";
		my $subID = "sub$i";
		my $md_content = "";
		$md_content .= "<nmwg:subject id=\"sub$i\">\n";
		$md_content .= "  <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"$link_id\" />\n";
		$md_content .= "</nmwg:subject>\n";
		createMetadata($output, $mdID, $md->getAttribute("id"), $md_content, undef);
		my $data_content = "";
		foreach my $link (@{ $links{$link_id} }) {
			$data_content .= $self->writeoutLinkState_range($link);
		}
		createData($output, "data.".$i, $mdID, $data_content, undef);
		$i++;
	}

	return ("", "");
}

sub lookupLinkStatusRequest($$$$) {
	my($self, $output, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");
	my $localContent = "";
	my ($status, $res);

	my $link_id = findvalue($md, './nmwg:subject/*[local-name()=\'link\']/@id');
	my $time = findvalue($md, './nmwg:parameters/nmwg:parameter[@name="time"]');

	if (!defined $time or $time eq "now") {
		# no time simply grabs the most recent information
		$time = "";
	}

	if (!defined $link_id or $link_id eq "") {
		return ("error.ma.status.no_link_id", "No link id specified in request");
	}

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	my @tmp_array = ( $link_id );

	if ($time eq "all") {
		($status, $res) = $self->{CLIENT}->getLinkHistory(\@tmp_array);
	} else {
		($status, $res) = $self->{CLIENT}->getLinkStatus(\@tmp_array, $time);
	}

	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	$output->addExistingXMLElement($md);

	my $data_content = "";
	foreach my $link (@{ $res->{$link_id} }) {
		if ($time eq "all") {
			$data_content .= $self->writeoutLinkState_range($link);
		} else {
			$data_content .= $self->writeoutLinkState($link, $time);
		}
	}
	createData($output, "data.".genuid(), $md->getAttribute("id"), $data_content, undef);

	return ("", "");
}

sub writeoutLinkState_range($$$) {
	my ($self, $link) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	return "" if (!defined $link);

	my $localContent = "";

	$localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\" knowledge=\"".$link->getKnowledge."\"\n";
	$localContent .= "	startTime=\"".$link->getStartTime."\" startTimeType=\"unix\" endTime=\"".$link->getEndTime."\" endTimeType=\"unix\">\n";
	$localContent .= "	<ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
	$localContent .= "	<ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
	$localContent .= "</ifevt:datum>\n";

	return $localContent;
}

sub writeoutLinkState($$$) {
	my ($self, $link, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Status");

	return "" if (!defined $link);

	my $localContent = "";

	if (!defined $time or $time eq "") {
	$localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\">\n";
	} else {
	$localContent .= "<ifevt:datum xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\" knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"$time\">\n";
	}
	$localContent .= "	<ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
	$localContent .= "	<ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
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

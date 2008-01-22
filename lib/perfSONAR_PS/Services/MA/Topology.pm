package perfSONAR_PS::Services::MA::Topology;

use base 'perfSONAR_PS::Services::Base';

use fields 'CLIENT', 'LS_CLIENT';

our $VERSION = 0.06;

use warnings;
use strict;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Topology::Common;
use perfSONAR_PS::Client::Topology::XMLDB;
use perfSONAR_PS::Client::LS::Remote;

sub init($$) {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");

	if (!defined $self->{CONF}->{"topology"}->{"db_type"} or $self->{CONF}->{"topology"}->{"db_type"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}


	if (lc($self->{CONF}->{"topology"}->{"db_type"}) eq "xml") {
		if (!defined $self->{CONF}->{"topology"}->{"db_file"} or $self->{CONF}->{"topology"}->{"db_file"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file (db_file)");
			return -1;
		}

		if (!defined $self->{CONF}->{"topology"}->{"db_environment"} or $self->{CONF}->{"topology"}->{"db_environment"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name (db_environment)");
			return -1;
		}

		my $environment = $self->{CONF}->{"topology"}->{"db_environment"};
		if (defined $self->{DIRECTORY}) {
			if (!($environment =~ "^/")) {
				$environment = $self->{DIRECTORY}."/".$environment;
			}
		}

		my $read_only = 0;

		if (defined $self->{CONF}->{"topology"}->{"read_only"} and $self->{CONF}->{"topology"}->{"read_only"} == 1) {
			$read_only = 1;
		}

		my $file = $self->{CONF}->{"topology"}->{"db_file"};
		my %ns = getTopologyNamespaces();

		$self->{CLIENT}= new perfSONAR_PS::Client::Topology::XMLDB($environment, $file, \%ns, $read_only);
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	if ($self->{CONF}->{"topology"}->{"enable_registration"}) {
		if (!defined $self->{CONF}->{"topology"}->{"service_accesspoint"} or $self->{CONF}->{"topology"}->{"service_accesspoint"} eq "") {
			$logger->error("No access point specified for SNMP service");
			return -1;
		}

		if (!defined $self->{CONF}->{"topology"}->{"ls_instance"} or $self->{CONF}->{"topology"}->{"ls_instance"} eq "") {
			if (defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne "") {
				$self->{CONF}->{"topology"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
			} else {
				$logger->error("No LS instance specified for SNMP service");
				return -1;
			}
		}

		if (!defined $self->{CONF}->{"topology"}->{"ls_registration_interval"} or $self->{CONF}->{"topology"}->{"ls_registration_interval"} eq "") {
			if (defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne "") {
				$self->{CONF}->{"topology"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
			} else {
				$logger->warn("Setting registration interval to 30 minutes");
				$self->{CONF}->{"topology"}->{"ls_registration_interval"} = 1800;
			}
		} else {
			# turn the registration interval from minutes to seconds
			$self->{CONF}->{"topology"}->{"ls_registration_interval"} *= 60;
		}

		if(!defined $self->{CONF}->{"topology"}->{"service_description"} or
				$self->{CONF}->{"topology"}->{"service_description"} eq "") {
			$self->{CONF}->{"topology"}->{"service_description"} = "perfSONAR_PS Topology MA";
			$logger->warn("Setting 'service_description' to 'perfSONAR_PS Topology MA'.");
		}

		if(!defined $self->{CONF}->{"topology"}->{"service_name"} or
				$self->{CONF}->{"topology"}->{"service_name"} eq "") {
			$self->{CONF}->{"topology"}->{"service_name"} = "Topology MA";
			$logger->warn("Setting 'service_name' to 'Topology MA'.");
		}

		if(!defined $self->{CONF}->{"topology"}->{"service_type"} or
				$self->{CONF}->{"topology"}->{"service_type"} eq "") {
			$self->{CONF}->{"topology"}->{"service_type"} = "MA";
			$logger->warn("Setting 'service_type' to 'MA'.");
		}
	}

	$handler->addEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/topology/query/xquery/20070809", $self);
	$handler->addEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/topology/query/all/20070809", $self);
	$handler->addEventHandler("TopologyChangeRequest", "http://ggf.org/ns/nmwg/topology/change/add/20070809", $self);
	$handler->addEventHandler("TopologyChangeRequest", "http://ggf.org/ns/nmwg/topology/change/update/20070809", $self);
	$handler->addEventHandler("TopologyChangeRequest", "http://ggf.org/ns/nmwg/topology/change/replace/20070809", $self);

	return 0;
}

sub needLS($) {
	my ($self) = @_;

	return ($self->{CONF}->{"topology"}->{"enable_registration"});
}

sub registerLS($$) {
	my ($self, $sleep_time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");
	my ($status, $res1);

	if (!defined $self->{LS_CLIENT}) {
		my %ls_conf = (
				LS_INSTANCE => $self->{CONF}->{"topology"}->{"ls_instance"},
				SERVICE_TYPE => $self->{CONF}->{"topology"}->{"service_type"},
				SERVICE_NAME => $self->{CONF}->{"topology"}->{"service_name"},
				SERVICE_DESCRIPTION => $self->{CONF}->{"topology"}->{"service_description"},
				SERVICE_ACCESSPOINT => $self->{CONF}->{"topology"}->{"service_accesspoint"},
				LS_REGISTRATION_INTERVAL => $self->{CONF}->{"topology"}->{"registration_interval"},
			      );

		my %ns = getTopologyNamespaces();
		$self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"topology"}->{"ls_instance"}, \%ls_conf, \%ns);
	}

	($status, $res1) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open from database: $res1";
		$logger->error($msg);
		exit(-1);
	}

	($status, $res1) = $self->{CLIENT}->getUniqueIDs;
	if ($status != 0) {
		my $msg = "Couldn't get link nformation from database: $res1";
		$logger->error($msg);
		exit(-1);
	}

	my @mds = ();
	my @md_ids = ();

	foreach my $info (@{ $res1 }) {
		my ($md, $md_id) = buildLSMetadata($info->{id}, $info->{type}, $info->{prefix}, $info->{uri});
		push @mds, $md;
	}

	$res1 = "";

	my $n = $self->{LS_CLIENT}->registerDynamic(\@mds);

	if (defined $sleep_time) {
		$$sleep_time = $self->{CONF}->{"topology"}->{"ls_registration_interval"};
	}

	return $n;
}

sub buildLSMetadata($$$$) {
	my ($id, $type, $prefix, $uri) = @_;
	my $md = "";
	my $md_id = "meta".genuid();

	$md .= "<nmwg:metadata id=\"$md_id\">\n";
	$md .= "<nmwg:subject id=\"sub0\">\n";
	if (!defined $prefix or $prefix eq "") {
	$md .= " <$type xmlns=\"$uri\" id=\"$id\" />\n";
	} else {
	$md .= " <$prefix:$type xmlns:$prefix=\"$uri\" id=\"$id\" />\n";
	}
	$md .= "</nmwg:subject>\n";
	$md .= "<nmwg:eventType>topology</nmwg:eventType>\n";
	$md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/topology/query/all/20070809</nmwg:eventType>\n";
	$md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/topology/query/xquery/20070809</nmwg:eventType>\n";
	$md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/add/20070809</nmwg:eventType>\n";
	$md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/update/20070809</nmwg:eventType>\n";
	$md .= "<nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/replace/20070809</nmwg:eventType>\n";
	$md .= "</nmwg:metadata>\n";
}

sub handleEvent($$$$) {
	my ($self, $output, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message) = @_;

	my $retMetadata;
	my $retData;
	my $mdID = "metadata.".genuid();
	my $msg = "The echo request has passed.";

	if ($eventType eq "http://ggf.org/ns/nmwg/topology/query/xquery/20070809") {
		return $self->queryTopology($output, $eventType, $md, $d);
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/query/all/20070809") {
		return $self->queryTopology($output, $eventType, $md, $d);
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/change/add/20070809") {
		return $self->changeTopology($output, $eventType, $md, $d);
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/change/update/20070809") {
		return $self->changeTopology($output, $eventType, $md, $d);
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/change/replace/20070809") {
		return $self->changeTopology($output, $eventType, $md, $d);
	}
}

sub queryTopology($$) {
	my ($self, $output, $eventType, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");
	my ($status, $res);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my ($status, $res);
		$status = "error.topology.ma";
		$res = "Couldn't open database";
		$logger->error($res);
	} else {
		if ($eventType eq "http://ggf.org/ns/nmwg/topology/query/all/20070809") {
			($status, $res) = $self->queryAllRequest();
		} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/query/xquery/20070809") {
			my $query = findvalue($m, "./xquery:subject");
	
			if (!defined $query or $query eq "") {
				$status = "error.topology.query.query_not_found";
				$res =  "No query given in request";
			} else {
				($status, $res) = $self->queryXqueryRequest($query);
			}
		}
	}

	if ($status ne "") {
		throw perfSONAR_PS::Error_compat($status, $res);
	} else {
		$output->addExistingXMLElement($m);
		createData($output, "data.".genuid(), $m->getAttribute("id"), $res, undef);
	}

	return ("", "");
}

sub changeTopology($$$$$) {
	my ($self, $output, $eventType, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");
	my $changeType;

	if ($eventType eq "http://ggf.org/ns/nmwg/topology/change/add/20070809") {
		$changeType = "add";
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/change/update/20070809") {
		$changeType = "update";
	} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/change/replace/20070809") {
		$changeType = "replace";
	}

	my $topology = find($d, "./*[local-name()='topology']", 1);

	my ($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my ($status, $res);
		$status = "error.topology.ma";
		$res = "Couldn't open database";
	} elsif (!defined $topology) {
		$status = "error.topology.query.topology_not_found";
		$res = "No topology defined in change topology request for metadata: ".$m->getAttribute("id");
	} else {
		($status, $res) = $self->changeRequest($changeType, $topology);
	}

	if ($status ne "") {
		$logger->error("Couldn't handle requested metadata: $res");

		my $mdID = "metadata.".genuid();

		getResultCodeMetadata($output, $mdID, $m->getAttribute("id"), $status);
		getResultCodeData($output, "data.".genuid(), $mdID, $res, 1);
	} else {
		my $changeDesc;
		my $mdID = "metadata.".genuid();

		if ($changeType eq "add") {
			$changeDesc = "added";
		} elsif ($changeType eq "replace") {
			$changeDesc = "replaced";
		} elsif ($changeType eq "update") {
			$changeDesc = "updated";
		}

		$output->addExistingXMLElement($m);
		getResultCodeMetadata($output, $mdID, $m->getAttribute("id"), "success.ma.".$changeDesc);
		getResultCodeData($output, "data.".genuid(), $mdID, "data element(s) successfully $changeDesc", 1);
	}

	return ("", "");
}

sub changeRequest($$$) {
	my($self, $changeType, $topology) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");
	my ($status, $res);
	my $localContent = "";

	$logger->debug("Topology: ".$topology->toString);

	($status, $res) = topologyNormalize($topology);
	if ($status != 0) {
		$logger->error("Couldn't normalize topology");
		return ("error.topology.invalid_topology", $res);
	}

	($status, $res) = $self->{CLIENT}->changeTopology($changeType, $topology);
	if ($status != 0) {
		$logger->error("Error handling topology request");
		return ("error.topology.ma", $res);
	}

	return ("", "");
}

sub queryAllRequest($) {
	my ($self) = @_;
	my ($status, $res);
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->getAll;
	if ($status != 0) {
		my $msg = "Database dump failed: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	return ("", $res->toString);
}

sub queryXqueryRequest($$) {
	my ($self, $xquery) = @_;
	my ($status, $res);
	my $logger = get_logger("perfSONAR_PS::Services::MA::Topology");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->xQuery($xquery);
	if ($status != 0) {
		my $msg = "Database query failed: $res";
		$logger->error($msg);
		return ("error.common.storage.query", $msg);
	}

	return ("", $res);
}


1;

__END__
=head1 NAME

perfSONAR_PS::Services::MA::Topology - A module that provides methods for the Topology MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::Services::MA::Topology;

my %conf = readConfiguration();

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
	 );

my $ma = perfSONAR_PS::Services::MA::Topology->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::Services::MA::Topology->new;
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

The offered API is simple, but offers the key functions needed in a measurement archive.

=head2 init

       Initializes the MA and validates the entries in the
       configuration file. Returns 0 on success and -1 on failure.

=head2 registerLS($self)

	Registers the data contained in the MA with the configured LS.

=head2 receive($self)

	Grabs an incoming message from transport object to begin processing. It
	completes the processing if the message was handled by a lower layer.
	If not, it returns the Request structure.

=head2 handleMessage($self, $messageType, $message)
	Handles the specific message. This should entail iterating through the
	metadata/data pairs and handling each one.

=head2 handleMetadataPair($$$$) {
	Handles a specific metadata/data request.


=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Client::LS::Remote>


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

#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology;

use warnings;
use strict;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::Client::XMLDB;
use perfSONAR_PS::LS::Register;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	if ($self->SUPER::init != 0) {
		$logger->error("Couldn't initialize parent class");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPO_DB_TYPE"} or $self->{CONF}->{"TOPO_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XML") {
		if (!defined $self->{CONF}->{"TOPO_DB_FILE"} or $self->{CONF}->{"TOPO_DB_FILE"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file(TOPO_DB_FILE)");
			return -1;
		}

		if (!defined $self->{CONF}->{"TOPO_DB_ENVIRONMENT"} or $self->{CONF}->{"TOPO_DB_ENVIRONMENT"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name(TOPO_DB_ENVIRONMENT)");
			return -1;
		}

		my $environment = $self->{CONF}->{"TOPO_DB_ENVIRONMENT"};
		if (defined $self->{DIRECTORY}) {
			if (!($environment =~ "^/")) {
				$environment = $self->{DIRECTORY}."/".$environment;
			}
		}

		my $read_only = 0;

		if (defined $self->{CONF}->{"READ_ONLY"} and $self->{CONF}->{"READ_ONLY"} == 1) {
			$read_only = 1;
		}

		my $file = $self->{CONF}->{"TOPO_DB_FILE"};
		my %ns = getTopologyNamespaces();

		$self->{CLIENT}= new perfSONAR_PS::MA::Topology::Client::XMLDB($environment, $file, \%ns, $read_only);
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	return 0;
}

sub registerLS($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $ls = new perfSONAR_PS::LS::Register($self->{CONF}, $self->{NAMESPACES});
	my ($status, $res1);

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
		$logger->debug("ID: \"".$info->{type}.":".$info->{id}."\"");
		my ($md, $md_id) = buildLSMetadata($info->{id}, $info->{type}, $info->{prefix}, $info->{uri});
		push @mds, $md;
	}

	$res1 = "";

	return $ls->register_withData(\@mds);
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

sub receive($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $n;
	my $request;
	my $error;

	do {
		$request = undef;

		$n = $self->{LISTENER}->acceptCall(\$request, \$error);
		if ($n == 0) {
			$logger->debug("Received 'shadow' request from below; no action required.");
			$request->finish;
		}

		if (defined $error and $error ne "") {
			$logger->error("Error in accept call: $error");
		}
	} while ($n == 0);

	return $request;
}

sub handleRequest($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	$logger->debug("Handling request");

	eval {
 		local $SIG{ALRM} = sub{ die "Request lasted too long\n" };
		alarm($self->{CONF}->{"MAX_WORKER_LIFETIME"}) if (defined $self->{CONF}->{"MAX_WORKER_LIFETIME"} and $self->{CONF}->{"MAX_WORKER_LIFETIME"} > 0);
		__handleRequest($self, $request);
 	};

	# disable the alarm after the eval is done
	alarm(0);

	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		$request->setResponse(getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred"));
	}

	$request->finish;

	return;
}

sub __handleRequest($$) {
	my($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $messageIdReturn = genuid();
	my $messageId = $request->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $request->getRequestDOM()->getDocumentElement->getAttribute("type");

	$self->{REQUESTNAMESPACES} = $request->getNamespaces();

	my ($status, $response);

	if($messageType eq "SetupDataRequest") {
		($status, $response) = $self->queryTopology($request->getRequestDOM()->documentElement);
	} elsif ($messageType eq "TopologyChangeRequest") {
		($status, $response) = $self->changeTopology($request->getRequestDOM()->documentElemenet);
	} else {
		$status = "error.ma.message.type";
		$response = "Message type \"".$messageType."\" is not yet supported";
		$logger->error($response);
	}

	if ($status ne "") {
		$logger->error("Unable to handle topology request: $status/$response");
		$request->setResponse(getResultCodeMessage($messageIdReturn, $messageId, "", $messageType."Response", $status, $response, 1));
	} else {
		my %all_namespaces = ();

		my $request_namespaces = $request->getNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$request->setResponse(getResultMessage($messageIdReturn, $messageId, $messageType, $response, \%all_namespaces));
	}
}

sub queryTopology($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	my $found_match = 0;

	foreach my $d ($request->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = findvalue($m, "./nmwg:eventType");

				$found_match = 1;

				my ($status, $res);

				if (!defined $eventType or $eventType eq "") {
					$status = "error.ma.no_eventtype";
					$res = "No event type specified for metadata: ".$m->getAttribute("id");
				} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/query/all/20070809") {
					($status, $res) = $self->queryAllRequest();
				} elsif ($eventType eq "http://ggf.org/ns/nmwg/topology/query/xquery/20070809") {
					my $query = findvalue($m, "./xquery:subject");

					if (!defined $query or $query eq "") {
						$status = "error.topology.query.query_not_found";
						$res =  "No query given in request";
					} else {
						($status, $res) = $self->queryXqueryRequest($query);
					}
				} else {
					$status = "error.topology.query.invalid_event_type";
					$res =  "No query given in request";
				}

				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");
					my $mdID = "metadata.".genuid();
					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
				} else {
					$localContent .= $m->toString;
					$localContent .= createData("data.".genuid(), $m->getAttribute("id"), $res);
				}
			}
		}
	}

	if ($found_match == 0) {
		my $status = "error.ma.no_metadata_data_pair";
		my $res = "There was no data/metadata pair found";

		my $mdID = "metadata.".genuid();

		$localContent .= getResultCodeMetadata($mdID, "", $status);
		$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
	}

	return ("", $localContent);
}

sub changeTopology($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $transaction;

	my $localContent = "";

	my ($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my ($status, $res);
		$status = "error.topology.ma";
		$res = "Couldn't open database";
		$logger->error($res);
		return ($status, $res);
	}

	my $found_match = 0;

	foreach my $data ($request->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $md ($request->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $md->getAttribute("id")) {
				my $eventType = findvalue($md, "nmwg:eventType");
				my $changeType;
				my $topology = find($data, "./*[local-name()='topology']", 1);

				if (defined $eventType and $eventType ne "") {
					if ($changeType eq "http://ggf.org/ns/nmwg/topology/change/add/20070809") {
						$changeType = "add";
					} elsif ($changeType eq "http://ggf.org/ns/nmwg/topology/change/update/20070809") {
						$changeType = "update";
					} elsif ($changeType eq "http://ggf.org/ns/nmwg/topology/change/replace/20070809") {
						$changeType = "replace";
					}
				}

				my ($status, $res);

				if (!defined $eventType or $eventType eq "") {
					$status = "error.ma.no_eventtype";
					$res = "No event type specified for metadata: ".$md->getAttribute("id");
				} elsif (!defined $changeType) {
					$status = "error.topology.invalid_change_type";
					$res = "Invalid change type: \"$eventType\"";
				} elsif (!defined $topology) {
					$status = "error.topology.query.topology_not_found";
					$res = "No topology defined in change topology request for metadata: ".$md->getAttribute("id");
				} else {
					($status, $res) = $self->changeRequest($changeType, $topology);
				}

				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");

					my $mdID = "metadata.".genuid();

					$localContent .= getResultCodeMetadata($mdID, $md->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
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

					$localContent .= $md->toString;
					$localContent .= getResultCodeMetadata($mdID, $md->getAttribute("id"), "success.ma.".$changeDesc);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, "data element(s) successfully $changeDesc", 1);

				}
			}
		}
	}

	if ($found_match == 0) {
		my $status = "error.ma.no_metadata_data_pair";
		my $res = "There was no data/metadata pair found";

		my $mdID = "metadata.".genuid();

		$localContent .= getResultCodeMetadata($mdID, "", $status);
		$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
	}

	return ("", $localContent);
}

sub changeRequest($$$) {
	my($self, $changeType, $topology) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my ($status, $res);
	my $localContent = "";

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
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

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
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

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

perfSONAR_PS::MA::Topology - A module that provides methods for the Topology MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::MA::Topology;

my %conf = readConfiguration();

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
	 );

my $ma = perfSONAR_PS::MA::Topology->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Topology->new;
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

       Initializes the MP and validates or fills in entries in the
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

=head2 parseLookupRequest($self, $request)

	Goes through each metadata/data pair, extracting the eventType and
	any other relevant information calling the function associated with
	that eventType.

=head2 lookupAllRequest($self, $metadata, $data)

	Reads all link information from the database and constructs the
	metadata/data pairs for the response.

=head2 lookupLinkStatusRequest($self, $metadata, $data, $link_id, $time)

	Looks up the requested link information from the database and
	constructs the metadata/data pairs for the response.

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

=head2 buildLSMetadata($id, $type, $prefix, $uri)

	Writes out the metadata for the given element. It takes the topology
	id, the element type(e.g. domain, path, etc), the prefix (nmtopo, ipv4,
	nmtl3, etc) and the uri associated with that prefix. It then returns a
	metadata block made up of those elements.

=head2 queryTopology($self, $request)

	Goes through each metadata/data pair, extracting the eventType and
	calling the function associated with that eventType.

=head2 changeTopology($self, $request)

	Goes through each metadata/data pair, extracting the eventType and
	calling the function associated with that eventType.

=head2 changeRequest($self, $type, $topology)

	Normalizes the topology from the request and tries to insert it into
	the database.

=head2 queryAllRequest($self)

	Performs the getAll query on the database and returns the results.

=head2 queryXqueryRequest($self, $xquery)

	Performs an xQuery query on the database and returns the results.

=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::LS::Register>,
L<perfSONAR_PS::MA::Status::Client::SQL>


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

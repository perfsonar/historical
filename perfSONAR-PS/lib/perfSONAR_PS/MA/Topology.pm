#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology;

use warnings;
use strict;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	$self->SUPER::init;

	if (!defined $self->{CONF}->{"TOPO_DB_TYPE"} or $self->{CONF}->{"TOPO_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "SQLite") {
		if (!defined $self->{CONF}->{"TOPO_DB_FILE"} or $self->{CONF}->{"TOPO_DB_FILE"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(TOPO_DB_FILE)");
			return -1;
		}

		$self->{DATADB} = new perfSONAR_PS::DB::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"TOPO_DB_FILE"});
	} elsif ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XML") {
		my %ns = (
				nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
				netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
				nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
				snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
				nmtopo=>"http://ggf.org/ns/nmwg/topology/base/3.0/",
			 );

		if (!defined $self->{CONF}->{"TOPO_DB_FILE"} or $self->{CONF}->{"TOPO_DB_FILE"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file(TOPO_DB_FILE)");
			return -1;
		}

		if (!defined $self->{CONF}->{"TOPO_DB_NAME"} or $self->{CONF}->{"TOPO_DB_NAME"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name(TOPO_DB_NAME)");
			return -1;
		}

		$self->{DATADB}= new perfSONAR_PS::DB::XMLDB($self->{CONF}->{"TOPO_DB_NAME"}, $self->{CONF}->{"TOPO_DB_FILE"}, \%ns);
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	return 0;
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $readValue = $self->{LISTENER}->acceptCall;
	if($readValue == 0) {
		$logger->debug("Received 'shadow' request from below; no action required.");
		$self->{RESPONSE} = $self->{LISTENER}->getResponse();
	} elsif($readValue == 1) {
		$logger->debug("Received request to act on.");
		handleRequest($self);
	} else {
		my $msg = "Sent Request was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
		$logger->error($msg);
		$self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg);
	}
	return;
}

sub handleRequest {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	delete $self->{RESPONSE};
	my $messageIdReturn = genuid();
	my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");

	$self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling topology request.");
		my ($status, $response) = $self->parseRequest($self->{LISTENER}->getRequestDOM());
		if ($status != 0) {
			$logger->error("Unable to handle topology request");
			$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.content", $response);
		} else {
			$self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "SetupDataRequest", $response);
		}
	} elsif ($messageType eq "ChangeTopology") {
		$logger->debug("Handling ChangeTopology Request");
		
		my ($status, $response) = $self->changeTopology($self->{LISTENER}->getRequestDOM());
	} else {
		my $msg = "Message type \"".$messageType."\" is not yet supported";
		$logger->error($msg);
		$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.type", $msg);
	}

	return $self->{RESPONSE};
}


sub parseRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				if ($eventType eq "Path.Status") {
					my ($status, $res) = $self->pathStatusRequest($m, $d);
					if ($status != 0) {
						$logger->error("Couldn't dump topology information");
						return ($status, $res);
					}

					$localContent .= $res;
				} else {
					$logger->error("Unknown event type: ".$eventType);
					return ( -1, "Unknown event type: ".$eventType )
				}
			}
		}
	}

	return (0, $localContent);
}

sub changeTopology {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	foreach my $data ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $md ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $md->getAttribute("id")) {
				my $eventType = $md->findvalue("nmwg:eventType");

				$self->normalizeTopology($data);

				my ($status, $res);

				if ($eventType eq "updateTopology") {
					($status, $res) = $self->changeXMLDB("update", $data);
				} elsif ($eventType eq "addTopology") {
					($status, $res) = $self->changeXMLDB("add", $data);
				} elsif ($eventType eq "removeTopology") {
					($status, $res) = $self->changeXMLDB("remove", $data);
				} else {
					$status = -1;
					$res = "Unknown topology modification type: $eventType";
				}

				if ($status != 0) {
					$logger->error("Error handling topology request");
					# this should undo any previous changes.
				}

				$localContent .= $res;
			}
		}
	}

	# commit the transaction

	return (0, $localContent);
}

sub changeXMLDB($$$) {
	my ($self, $modification, $root) = @_;

	foreach my $node ($root->getChildrenByTagName("nmtopo:node")) {
		
	}

	foreach my $link ($root->getChildrenByTagName("nmtopo:node")) {
		
	}

	return (0, "");
}

sub changeTopologyRequest($$$) {
	my ($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";

	$localContent .= $m->toString();

	$self->normalizeTopology($m);

	return (0, $localContent);
}

sub pathStatusRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";

#	$localContent .= "<nmwg:parameters id=\"storeId\"><nmwg:parameter name=\"DomainName\">";
#	if (defined $self->{CONF}->{"domain"}) {
#		$localContent .= $self->{CONF}->{"domain"};
#	} else {
#		$localContent .= "UNKNOWN";
#	}
#	$localContent .= "</nmwg:parameter></nmwg:parameters>";

	$localContent .= $m->toString();

	$localContent .= "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
	my ($status, $res) = $self->dumpDatabase;
	if ($status == 0) {
		$localContent .= $res;
	} else {
		$logger->error("Couldn't dump topology structure: $res");
		return ($status, $res);
	}
	$localContent .= "  </nmwg:data>\n";

	open(OUTPUT, ">results");
	print OUTPUT $localContent;
	close(OUTPUT);

	return (0, $localContent);
}

sub dumpDatabase {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my ($status, $res);

	if (!defined $self->{DATADB}) {
		my $msg = "No database to dump";
		$logger->error($msg);
		return (-1, $msg);
	}

	$status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open topology database";
		$logger->error($msg);
		return (-1, $msg);
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "SQLite") {
		($status, $res) = $self->dumpSQLDatabase;
	} elsif ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XML") {
		($status, $res) = $self->dumpXMLDatabase;
	} else {
		my $msg = "Unknown topology database type: ".$self->{CONF}->{"TOPO_DB_TYPE"};
		$logger->error($msg);
		$self->{DATADB}->closeDB;
		return (-1, $msg);
	}

	$self->{DATADB}->closeDB;

	return ($status, $res);
}

sub dumpXMLDatabase($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $content = "";

	my @nodes = $self->{DATADB}->query("/nmtopo:node");
	if ($#nodes == -1) {
		my $msg = "Couldn't find list of nodes in DB";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @nodes);

	my @links = $self->{DATADB}->query("/nmtopo:link");
	if ($#links == -1) {
		my $msg = "Couldn't find list of links in DB";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @links);

	return (0, $content);
}

sub addXMLDatabase {
	return (-1, "XML Databases unsupported");
}

# The goal of normalization is to bring all first class entities: nodes,
# interfaces and links to the top level. These entities can be defined inside
# of other entities, so we must grot through the DOM finding instances where
# people have declared entities inside of other entities(for example, an
# interface defined inside of a node). When we find an instance, we pull the
# entity up to the top-level and replace it with a node containing simply an
# IdRef to keep the meaning the same.
#
# e.g.
#    <nmtopo:link id="link1">
#        <nmtopo:link id="sublink1">
#            <nmtopo:interface interfaceIdRef="node1iface1" />
#            <nmtopo:interface id="node2iface1" nodeIdRef="node2">
#        </nmtopo:link>
#    </nmtopo:link>
#    <nmtopo:node id="node1">
#        <nmtopo:interface id="node1iface1" />
#    </nmtopo:node>
#    <nmtopo:node id="node2" />
# 
#  would become
#    <nmtopo:link id="link1>
#        <nmtopo:link linkIdRef="sublink1">
#    </nmtopo:link>
#    <nmtopo:link id="link1>
#        <nmtopo:interface interfaceIdRef="node1iface1" />
#        <nmtopo:interface interfaceIdRef="node2iface1" />
#    </nmtopo:link>
#    <nmtopo:node id="node1">
#        <nmtopo:interface interfaceIdRef="node1iface1" />
#    </nmtopo:node>
#    <nmtopo:node id="node2">
#        <nmtopo:interface interfaceIdRef="node2iface1" />
#    </nmtopo:node>
#    <nmtopo:interface id="node1iface1" />
#    <nmtopo:interface id="node2iface1" />

sub normalizeTopology($$) {
	my ($self, $root) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $link ($root->getChildrenByTagName("nmtopo:link")) {
		normalizeLink("", $root, $link);
	}

	foreach my $node ($root->getChildrenByTagName("nmtopo:node")) {
		normalizeNode("", $root, $node);
	}
}

sub normalizeNode($$$) {
	my ($self, $root, $node) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $interface ($node->getChildrenByTagName("nmtopo:interface")) {
		if (defined $interface->getAttribute("id")) {
			# it's a new interface, pull it to the top level
			if (!defined $interface->getAttribute("nodeIdRef")) {
				$interface->setAttribute("nodeIdRef", $node->getAttribute("id"));
			}
			my $new_node = $node->addNewChild("", "nmtopo:interface");
			$new_node->setAttribute("interfaceIdRef", $interface->getAttribute("id"));
			$node->removeChild($interface);
			$root->appendChild($interface);
		} elsif (!defined $interface->getAttribute("interfaceIdRef")) {
			# XXX Complain
		}
	}
}

sub normalizeLink($$$) {
	my ($self, $root, $link) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $interface ($link->getChildrenByTagName("nmtopo:interface")) {
		if (defined $interface->getAttribute("id") and !defined $interface->getAttribute("nodeIdRef")) {
			# XXX Complain
		} elsif (defined $interface->getAttribute("id")) {
			# it's a new interface, pull it to the top level
			my $new_node = $link->addNewChild("", "nmtopo:interface");
			$new_node->setAttribute("interfaceIdRef", $interface->getAttribute("id"));
			$link->removeChild($interface);
			$root->appendChild($interface);
		} elsif (!defined $interface->getAttribute("interfaceIdRef")) {
			# XXX Complain
		}
	}

	foreach my $sublink ($link->getChildrenByTagName("nmtopo:link")) {
		if (defined $sublink->getAttribute("id")) {
			# remove the sublink and replace it with a reference
			my $new_node = $sublink->addNewChild("", "nmtopo:link");
			$new_node->setAttribute("linkIdRef", $link->getAttribute("id"));
			$link->removeChild($sublink);
			$root->appendChild($sublink);

			my ($status, $res) = $self->normalizeLinkTopology($root, $sublink);
		} elsif (!defined $sublink->getAttribute("linkIdRef")) {
			# XXX Complain
		}
	}

	return (0, "");
}

sub dumpSQLDatabase {
	my ($self, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $nodes = $self->{DATADB}->query("select id, name, country, city, institution, latitude, longitude from nodes");
	if ($nodes == -1) {
		$logger->error("Couldn't grab list of nodes");
		return (-1, "Couldn't grab list of nodes");
	}

	my $localContent = "";

	foreach my $node_ref (@{ $nodes }) {
		my @node = @{ $node_ref };

		# dump the node information in XML format

		$localContent .= "<nmwgt:node id=\"".$node[0]."\">\n";
		$localContent .= "	<nmwgt:type>TopologyPoint</nmwgt:type>\n";
  		$localContent .= "	<nmwgt:name type=\"logical\">".$node[1]."</nmwgt:name>\n";
  		$localContent .= "	<nmwgt:country>".$node[2]."</nmwgt:country>\n";
  		$localContent .= "	<nmwgt:city>".$node[3]."</nmwgt:city>\n";
  		$localContent .= "	<nmwgt:institution>".$node[4]."</nmwgt:institution>\n";
  		$localContent .= "	<nmwgt:latitude>".$node[5]."</nmwgt:latitude>\n";
  		$localContent .= "	<nmwgt:longitude>".$node[6]."</nmwgt:longitude>\n";

		my $ifs = $self->{DATADB}->query("select name, type, capacity from interfaces where node_id=\'".$node[0]."\'");
		if ($ifs == -1) {
			$logger->error("Couldn't grab list of interfaces for node ".$node[0]);
			return (-1, "Couldn't grab list of interfaces for node ".$node[0]);
		}

		foreach my $if_ref (@{ $ifs }) {
			my @if = @{ $if_ref };

			$localContent .= "	<nmwgt:interface id=\"".$if[0]."\">\n";
			$localContent .= "		<nmwgt:type>".$if[1]."</nmwgt:type>\n";
			$localContent .= "		<nmwgt:capacity>".$if[2]."</nmwgt:capacity>\n";
			$localContent .= "	</nmwgt:interface>\n";
		}

		$localContent .= "</nmwgt:node>\n";
	}

	my $links = $self->{DATADB}->query("select id, name, globalName, type from links");
	if ($links == -1) {
		$logger->error("Couldn't grab list of links");
		return (-1, "Couldn't grab list of links");
	}

	foreach my $link_ref (@{ $links }) {
		my @link = @{ $link_ref };

		my $link_node_query = "select node_id, interface, role, link_index from link_nodes where link_id=\'".$link[0]."\'";
		if (defined $time and $time ne "") {
			$link_node_query .= " and start_time <= $time and end_time >= $time";
		}

		my $nodes = $self->{DATADB}->query($link_node_query);
		if ($nodes == -1) {
			$logger->error("Couldn't grab list of nodes associated with link ".$link[0]);
			return (-1, "Couldn't grab list of nodes associated with link " . $link[0]);
		}

		# dump the link information in XML format
		$localContent .= "<nmwgt:link id=\"".$link[0]."\">\n";
  		$localContent .= "	<nmwgt:name type=\"logical\">".$link[1]."</nmwgt:name>\n";
  		$localContent .= "	<nmwgt:globalName type=\"logical\">".$link[2]."</nmwgt:globalName>\n";
		$localContent .= "	<nmwgt:type>".$link[3]."</nmwgt:type>\n";

		foreach my $node_ref (@{ $nodes }) {
			my @node = @{ $node_ref };
			$localContent .= "	<nmwgt:node nodeIdRef=\"".$node[0]."\">\n";
			$localContent .= "		<nmwgt:interface>".$node[1]."</nmwgt:interface>\n";
			$localContent .= "		<nmwgt:role>".$node[2]."</nmwgt:role>\n";
			$localContent .= "		<nmwgt:link_index>".$node[3]."</nmwgt:link_index>\n";
			$localContent .= "	</nmwgt:node>\n";
		}

		$localContent .= "</nmwgt:link>\n";
	}

	return (0, $localContent);
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

my %conf = ();
$conf{"METADATA_DB_TYPE"} = "xmldb";
$conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Topology/xmldb";
$conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
$conf{"PING"} = "/bin/ping";

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
		select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
	 );

my $ma = perfSONAR_PS::MA::Topology->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Topology->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

$ma->init;
while(1) {
	$ma->receive;
	$ma->respond;
}


=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed nn an MA.
Additional logic is needed to address issues such as different backend storage facilities.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive.

=head2 receive($self)

	Grabs message from transport object to begin processing.

=head2 handleRequest($self)

	Functions as the 'gatekeeper' the the MA.  Will either reject or accept
	requets.  will also 'do nothing' in the event that a request has been
	acted on by the lower layer.

=head2 parseRequest($self, $messageId, $messageIdRef, $type)

	Processes both the the MetadataKeyRequest and SetupDataRequest messages, which
	preturn either metadata or data to the user.

=head2 setupDataKeyRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

	Runs the specific needs of a SetupDataRequest when a key is presented to
	the service.

=head2 setupDataRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

	Runs the specific needs of a SetupDataRequest when a key is NOT presented to
	the service.

=head2 handleData($self, $id, $dataString, $localContent)

	Helper function to extract data from the backed storage.

=head2 retrieveSQL($did)

	The data is extracted from the backed storage (in this case SQL).

=head2 retrieveRRD($did)

	The data is extracted from the backed storage (in this case RRD).

	=head1 SEE ALSO

	L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
	L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>,
	L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::RRD>

	To join the 'perfSONAR-PS' mailing list, please visit:

	https://mail.internet2.edu/wws/info/i2-perfsonar

	The perfSONAR-PS subversion repository is located at:

	https://svn.internet2.edu/svn/perfSONAR-PS

	Questions and comments can be directed to the author, or the mailing list.

	=head1 VERSION

	$Id: Topology.pm 242 2007-06-19 21:22:24Z zurawski $

	=head1 AUTHOR

	Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

	=head1 COPYRIGHT AND LICENSE

	Copyright (C) 2007 by Internet2

	This library is free software; you can redistribute it and/or modify
	it under the same terms as Perl itself, either Perl version 5.8.8 or,
	at your option, any later version of Perl 5 you may have available.

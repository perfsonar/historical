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

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	$self->SUPER::init;

	if (!defined $self->{CONF}->{"TOPO_DB_TYPE"} or $self->{CONF}->{"TOPO_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XML") {
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
		my ($status, $response) = $self->queryTopology($self->{LISTENER}->getRequestDOM());
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


sub queryTopology {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				my ($status, $res) = $self->queryRequest($eventType, $m, $d);
				if ($status != 0) {
					$logger->error("Couldn't dump topology information");
					return ($status, $res);
				}

				$localContent .= $res;
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

				my $topology = $data->find("nmtopo:topology");
				if (!defined $topology) {
					my $msg = "No topology defined";
					$logger->error($msg);
					return (-1, $msg);
				}

				normalizeTopology($topology);

				my ($status, $res) = $self->changeXMLDB($eventType, $topology);
				if ($status != 0) {
					$logger->error("Error handling topology request");
					# this should undo any previous changes.
					return ($status, $res);
				}

				$localContent .= $res;
			}
		}
	}

	# commit the transaction

	return (0, $localContent);
}

sub changeXMLDB($$$) {
	my ($self, $type, $topology) = @_;

	if ($type eq "topology.change.replace") {
		
	} elsif ($type eq "topology.change.update") {

	} elsif ($type eq "topology.change.add") {

	} elsif ($type eq "topology.change.remove") {

	}
	return (0, "");
}

sub changeTopologyRequest($$$) {
	my ($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";

	$localContent .= $m->toString();

#	$self->normalizeTopology($m);

	return (0, $localContent);
}



sub queryRequest($$$$) {
	my($self, $type, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";

	$localContent .= $m->toString();
	$localContent .= "\n";

	my $md_id = $m->getAttribute("id");
	my $d_id = $d->getAttribute("id");
	if (!defined $d_id) {
		$d_id = genuid();
	}

	$localContent .= "<nmwg:data id=\"$d_id\" metadataIdRef=\"$md_id\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$localContent .= "<nmtopo:topology xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topo/base/2.0\">\n";
	if ($type eq "topology.lookup.all") {
		my ($status, $res) = $self->queryDatabase_dump;
		if ($status == 0) {
			$localContent .= $res;
		} else {
			$logger->error("Couldn't dump topology structure: $res");
			return ($status, $res);
		}
	} elsif ($type eq "topology.lookup.xquery") {
		my ($status, $res) = $self->queryDatabase_xQuery($m);
		if ($status == 0) {
			$localContent .= $res;
		} else {
			$logger->error("Couldn't query topology: $res");
			return ($status, $res);
		}

	}

	$localContent .= "</nmtopo:topology>\n";
	$localContent .= "</nmwg:data>\n";

	return (0, $localContent);
}

sub queryDatabase_xQuery($$) {
	my($self, $m) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";

	$logger->debug("queryDatabase_xQuery()");

	if ($self->{CONF}->{"TOPO_DB_TYPE"} ne "XML") {
		my $msg = "xQuery unsupported for database type: ".$self->{CONF}->{"TOPO_DB_TYPE"};
		$logger->error($msg);
		return (-1, $msg);
	}

	my $query = extract($m->find("./xquery:subject")->get_node(1));
	if (!defined $query or $query eq "") {
		return (-1, "No query given in request");
	}

	$query =~ s/\s{1}\// collection('CHANGEME')\//g;

	if ($self->{DATADB}->openDB != 0) {
		my $msg = "Couldn't open database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $queryResults = $self->{DATADB}->xQuery($query);
	if ($queryResults == -1) {
		$logger->error("Couldn't query database");
		return (-1, "Couldn't query database");
	}

	foreach my $line (@{ $queryResults }) {
		$localContent .= $line;
	}

	return (0, $localContent);
}

sub queryDatabase_dump {
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

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XML") {
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

	my @results = $self->{DATADB}->query("/*:network");
	if ($#results == -1) {
		my $msg = "Couldn't find list of nodes in DB";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	return (0, $content);
}

sub topologyNormalize($) {
	my ($root) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my %topology = ();
	$topology{"networks"} = ();
	$topology{"nodes"} = ();
	$topology{"links"} = ();
	$topology{"ports"} = ();

	my ($status, $res);

	($status, $res) = topologyNormalize_networks($root, \%topology);
	if ($status != 0) {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_nodes($root, \%topology, "");
	if ($status != 0) {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_ports($root, \%topology, "");
	if ($status != 0) {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_links($root, \%topology, "");
	if ($status != 0) {
		return ($status, $res);
	}
}

sub topologyNormalize_networks($$) {
	my ($root, $topology) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $network ($root->getChildrenByLocalName("network")) {
		my $id = $network->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			my $msg = "No id for specified network";
			 $logger->error($msg);
			return (-1, $msg);
		}

		if (idIsFQ($id) == 0) {
			$id = idConstruct($id);

			$network->setAttribute("id", $id);
		}		

		$logger->debug("Adding $id");

		$topology->{"networks"}->{$id} = $network;
	}

	return (0, "");
}

sub topologyNormalize_nodes($$) {
	my ($root, $topology, $uri) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $network ($root->getChildrenByLocalName("network")) {
		my $fqid = $network->getAttribute("id");
		my ($status, $res) = topologyNormalize_nodes($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByLocalName("node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			if (defined $node->getAttribute("nodeIdRef")) {
				next;
			} else {
				my $msg = "Node has no id";
				$logger->error($msg);
				return (-1, $msg);
			}
		}

		if (idIsFQ($id) == 0) {
			if ($uri eq "") {
				my $msg = "Node $id has no parent and is not fully qualified";
				$logger->error($msg);
				return (-1, $msg);
			}

			$fqid = idAddLevel($uri, $id);

		} else {
			$fqid = idSanitize($id);

			if ($uri ne "") {
				# compare the uri with the FQ id
			}

			my $network_id = idRemoveLevel($fqid);
			my $network = $topology->{"networks"}->{$network_id};

			if (!defined $network) {
				my $msg = "Node $fqid references non-existent network: $network_id";
				$logger->error($msg);
				return (-1, $msg);
			}

			$logger->debug("Moving $fqid to $network_id");

			# remove the node from $root and add it to the network
			$root->removeChild($node);
			networkReplaceChild($network, $node, $fqid);
			$node->setAttribute("id", idBaseLevel($fqid));
		}

		$logger->debug("Adding $fqid");
		$topology->{"nodes"}->{$fqid} = $node;
	}
}

sub topologyNormalize_ports($$) {
	my ($root, $topology, $uri) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $network ($root->getChildrenByLocalName("network")) {
		my $fqid = $network->getAttribute("id");
		my ($status, $res) = topologyNormalize_ports($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByLocalName("node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		my ($status, $res) = topologyNormalize_ports($node, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByLocalName("port")) {
		my $id = $port->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			if (defined $port->getAttribute("portIdRef")) {
				next;
			} else {
				my $msg = "Port has no id";
				$logger->error($msg);
				return (-1, $msg);
			}
		}

		if (idIsFQ($id) == 0) {
			if ($uri eq "") {
				my $msg = "Port $id has no parent and is not fully qualified";
				$logger->error($msg);
				return (-1, $msg);
			}

			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);

			if ($uri ne "") {
				# compare the uri with the FQ id
			} 

			my $node_id = idRemoveLevel($fqid);
			my $node = $topology->{"nodes"}->{$node_id};

			if (!defined $node) {
				my $msg = "Port $fqid references non-existent node: $node_id";
				$logger->error($msg);
				return (-1, $msg);
			}

			# remove the port from $root and add it to the node
			$root->removeChild($port);
			nodeReplaceChild($node, $port, $fqid);
			$port->setAttribute("id", idBaseLevel($fqid));
		}

		$logger->debug("Adding $fqid");
		$topology->{"ports"}->{$fqid} = $port;
		$port->setAttribute("id", idBaseLevel($fqid));
	}
}

sub topologyNormalize_links($$) {
	my ($root, $topology, $uri) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $network ($root->getChildrenByLocalName("network")) {
		my $fqid = $network->getAttribute("id");
		my ($status, $res) = topologyNormalize_links($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByLocalName("node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		my ($status, $res) = topologyNormalize_links($node, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByLocalName("port")) {
		my $id = $port->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		my ($status, $res) = topologyNormalize_links($port, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $link ($root->getChildrenByLocalName("link")) {
		my $id = $link->getAttribute("id");
		my $fqid;

		$logger->debug("Handling $id");

		if (!defined $id) {
			if (!defined $link->getAttribute("link") and defined $link->getAttribute("linkIdRef")) {
				$logger->debug("Link appears to be a pointer, skipping");
				next;
			} else {
				my $msg = "Link has no id";
				$logger->error($msg);
				return (-1, $msg);
			}
		}

		if (idIsFQ($id) == 0) {
			$logger->debug("$id not qualified: ".$root->localname."");

			next if ($root->localname eq "port");

			my $num_ports = 0;

			foreach my $port ($link->getChildrenByLocalName("port")) {
				my $idref = $port->getAttribute("portIdRef");

				$logger->debug("Got port ref: ".$idref."");
				if (!defined $idref or $idref eq "") {
					my $msg = "Link $id refers to port with no portIdRef";
					$logger->error($msg);
					return (-1, $msg);
				}

				$idref = idSanitize($idref);
				my $new_link = $link->cloneNode(1);
				my $new_link_fqid = idAddLevel($idref, $id);
				my $port = $topology->{"ports"}->{$idref};

				if (!defined $port) {
					my $msg = "Link $id refers to non-existent port $idref";
					$logger->error($msg);
					return (-1, $msg);
				}

				my $link_element = $port->find("./*[local-name()='link']")->get_node(1);

				if (defined $link_element) {
					my $link_idref = $link_element->getAttribute("linkIdRef");
					if (!defined $link_idref or idSanitize($link_idref) ne $new_link_fqid) {
						my $msg = "$new_link_fqid slated to replace existing link";
						$logger->error($msg);
						return (-1, $msg);
					}

					$logger->debug("Replacing child");
					$link_element->replaceNode($new_link);
				} else {
					$logger->debug("Appending child");
					$port->appendChild($new_link);
				}

				$logger->debug("Adding $new_link_fqid");
				$topology->{"links"}->{$new_link_fqid} = $new_link;
				$num_ports++;
			}

			if ($num_ports == 0) {
				my $msg = "Link $id has no port to attach to";
				$logger->error($msg);
				return (-1, $msg);
			}

			$root->removeChild($link);

			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);

			if ($uri ne "") {
				# compare the uri with the FQ id
			}

			my $port_id = idRemoveLevel($fqid);
			my $port = $topology->{"ports"}->{$port_id};

			if (!defined $port) {
				my $msg = "Link $fqid references non-existent port: $port_id";
				$logger->error($msg);
				return (-1, $msg);
			}

			# remove the link from $root and add it to the port
			$root->removeChild($link);
			portReplaceChild($port, $link, $fqid);
			$logger->debug("Adding $fqid");
			$topology->{"links"}->{$fqid} = $link;
			$link->setAttribute("id", idBaseLevel($fqid));
		}
	}
}

# XXX ReplaceChild may need to merge the new node and the replaced node
sub networkReplaceChild($$$) {
	my ($network, $new_node, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $node ($network->getChildrenByLocalName("node")) {
		my $id = $node->getAttribute("nodeIdRef"); 
		next if (!defined $id or $id eq "");
		$id = idSanitize($id);
		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$network->removeChild($node);
		}
	}

	$network->addChild($new_node);
}

sub nodeReplaceChild($$$) {
	my ($node, $new_port, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $port ($node->getChildrenByLocalName("port")) {
		my $id = $port->getAttribute("portIdRef"); 
		next if (!defined $id or $id eq "");
		$id = idSanitize($id);
		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$node->removeChild($port);
		}
	}

	$node->addChild($new_port);
}

sub portReplaceChild($$$) {
	my ($port, $new_link, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	foreach my $link ($port->getChildrenByLocalName("link")) {
		my $id = $port->getAttribute("linkIdRef"); 
		next if (!defined $id or $id eq "");
		$id = idSanitize($id);
		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$port->removeChild($link);
		}
	}

	$port->addChild($new_link);
}

sub idConstruct {
	my ($domain, $node, $interface, $link) = @_;

	my $id = "";

	return $id if (!defined $domain);

	$id .= "http://$domain/";

	return $id if (!defined $node);

	$id .= "$node/";

	return $id if (!defined $interface);

	$id .= "$interface/";

	return $id if (!defined $link);

	$id .= "$link/";

	return $id;
}

sub idIsFQ($) {
	my ($id) = @_;

	return 1 if ($id =~ /^http:\/\//);

	return 0;
}

sub idAddLevel($) {
	my ($id, $new_level) = @_;
	if ($id =~ /\/$/) {
		$id .= $new_level . "/";
	} else {
		$id .= "/".$new_level . "/";
	}

	return $id;
}

sub idRemoveLevel($) {
	my ($id) = @_;
	my $i = rindex($id, "/");

	if ($id =~ /(http:\/\/.*\/)[^\/]+\/$/) {
		return $1;
	} else {
		return $id;
	}
}

sub idSanitize($) {
	my ($id) = @_;

	return $id if ($id =~ /\/$/);

	return $id."/";
}

sub idBaseLevel($) {
	my ($id) = @_;

	if ($id =~ /http:\/\/.*\/([^\/]+)\/$/) {
		return $1;
	} else {
		return $id;
	}
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

=head2 queryTopology($self, $messageId, $messageIdRef, $type)

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

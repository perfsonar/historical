#!/usr/bin/perl -w

package perfSONAR_PS::MA::CircuitStatus;

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

use perfSONAR_PS::MA::Status::Client::MA;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	$self->SUPER::init;

	if (!defined $self->{CONF}->{"STATUS_MA"} or $self->{CONF}->{"STATUS_MA"} eq "") {
		$logger->error("No status MA URI specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPOLOGY_MA_HOST"} or $self->{CONF}->{"TOPOLOGY_MA_HOST"} eq "") {
		$logger->error("No topology MA port specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPOLOGY_MA_PORT"} or $self->{CONF}->{"TOPOLOGY_MA_PORT"} eq "") {
		$logger->error("No topology MA port specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPOLOGY_MA_ENDPOINT"} or $self->{CONF}->{"TOPOLOGY_MA_ENDPOINT"} eq "") {
		$logger->error("No topology MA endpoint specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"LINK_FILE_TYPE"} or $self->{CONF}->{"LINK_FILE_TYPE"} eq "") {
		$logger->error("No link file type specified");
		return -1;
	}

	if($self->{CONF}->{"LINK_FILE_TYPE"} eq "file") {
		if (!defined $self->{CONF}->{"LINK_FILE"} or $self->{CONF}->{"LINK_FILE"} eq "") {
			$logger->error("No link file specified");
			return -1;
		}

		my ($status, $res1, $res2, $res3) = parseLinkFile($self->{CONF}->{"LINK_FILE"});
		if ($status ne "") {
			my $msg = "Error parsing link file: $res1";
			$logger->error($msg);
			return -1;
		}

		$self->{DOMAIN} = $res1;
		$self->{LINKS} = $res2;
		$self->{NODES} = $res3;
	} else {
		$logger->error("Invalid link file type specified: ".$self->{CONF}=>{"LINK_FILE_TYPE"});
		return -1;
	}

	return 0;
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

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
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	delete $self->{RESPONSE};
	my $messageIdReturn = genuid();
	my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");

	$self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();

	my ($status, $response);

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling status request.");
		($status, $response) = $self->parseRequest($self->{LISTENER}->getRequestDOM());
	} else {
		$status = "error.ma.message.type";
		$response ="Message type \"".$messageType."\" is not yet supported";

		$logger->error($response);
	}

	if ($status ne "") {
		$logger->error("Error handling request: $status/$response");

		$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", $status, $response);
	} else {
		my %all_namespaces = ();

		my $request_namespaces = $self->{LISTENER}->getRequestNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, $messageType."Response", $response, \%all_namespaces);
	}

	return $self->{RESPONSE};
}

sub parseRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				if ($eventType eq "Path.Status") {

					$logger->debug("Path.Status found");

					my ($status, $res) = $self->handlePathStatusRequest;
					if ($status ne "") {
						$logger->error("Couldn't dump status information");
						return ($status, $res);
					}

					$localContent .= $res;
				} else {
					$logger->error("Unknown event type: ".$eventType);
					return ( "error.ma.message.event_type", "Unknown event type: ".$eventType )
				}
			}
		}
	}

	return ("", $localContent);
}

sub handlePathStatusRequest($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my $topology_request = buildTopologyRequest();

	my ($status, $res) = consultArchive($self->{CONF}->{TOPOLOGY_MA_HOST}, $self->{CONF}->{TOPOLOGY_MA_PORT}, $self->{CONF}->{TOPOLOGY_MA_ENDPOINT}, $topology_request);
	if ($status != 0) {
		my $msg = "Error consulting topology archive: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $topo_msg = $res;

	foreach my $data ($topo_msg->getElementsByLocalName("data")) {
		foreach my $metadata ($topo_msg->getElementsByLocalName("metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
				my $eventType = $metadata->findvalue("nmwg:eventType");
				if ($eventType ne "topology.lookup.all") {
					my $msg = "Invalid response eventType received: $eventType";
					$logger->error($msg);
					return ("error.ma", $msg);
				}

				my $topology = $data->find("nmtopo:topology")->get_node(1);
				if (!defined $topology) {
					my $msg = "No topology defined in change topology response";
					$logger->error($msg);
					return ("error.ma", $msg);
				}

				my ($status, $res) = parseTopology($topology, $self->{NODES}, $self->{DOMAIN});
				if ($status ne "") {
					my $msg = "Error parsing topology: $res";
					$logger->error($msg);
					return ("error.ma", $msg);
				}
			}
		}
	}

	my $status_client = new perfSONAR_PS::MA::Status::Client::MA($self->{CONF}->{STATUS_MA});
	if (!defined $status_client) {
		my $msg = "Problem creating client for status MA";
		$logger->error($msg);
		return ("error.ma", $msg);
	}

	($status, $res) = $status_client->open;
	if ($status != 0) {
		my $msg = "Problem opening status MA: $res";
		$logger->error($msg);
		return ("error.ma", $msg);
	}

	my @link_ids = ();
	foreach my $link_id (keys %{ $self->{LINKS} }) {
		push @link_ids, $self->{LINKS}->{$link_id}->{"archiveId"};
	}

	($status, $res) = $status_client->getLastLinkStatus(\@link_ids);
	if ($status != 0) {
		my $msg = "Error getting link status: $res";
		$logger->error($msg);
		return ("error.ma", $msg);
	}

	foreach my $id (%{ $res }) {
		my $link = pop(@{ $res->{$id} });

		$logger->debug("Got information on link $id");

		if (!defined $self->{LINKS}->{$id}) {
			$logger->warn("Response from server contains a link we didn't ask for");
			next;
		}

		my $prev_domain = "";
		my $link_type = "BROKEN";

		foreach my $node (@{ $self->{LINKS}->{$id}->{"endpoints"} }) {
			my ($domain, @junk) = split(/-/, $node->{"node"}->{"name"});
			$logger->debug("DOMAIN: ". $domain . " NAME: ".$node->{"node"}->{"name"});
			if ($prev_domain ne "") {
				if ($domain eq $prev_domain) {
					$link_type = "DOMAIN_Link";
				} else {
					if ($link->getKnowledge eq "full") {
						$link_type = "ID_Link";
					} else {
						$link_type = "ID_LinkPartialInfo";
					}
				}
			} else {
				$prev_domain = $domain;
			}
		}

		$self->{LINKS}->{$id}->{"mdid"} = genuid();
		$self->{LINKS}->{$id}->{"time"} = $link->getEndTime;
		$self->{LINKS}->{$id}->{"type"} = $link_type;
		$self->{LINKS}->{$id}->{"operStatus"} = $link->getOperStatus;
		$self->{LINKS}->{$id}->{"adminStatus"} = $link->getAdminStatus;
	}

	foreach my $link_id (keys %{ $self->{LINKS} }) {
		if (!defined $self->{LINKS}->{$link_id}->{"time"}) {
			my $msg = "Did not receive any information about link $link_id";
			$logger->error($msg);
			return ("error.ma", $msg);
		}
	}

	my $localContent = "";

	$localContent .= outputNodes($self->{NODES});
	$localContent .= outputLinks($self->{LINKS});

	return ("", $localContent);
}

sub idBaseLevel($) {
	my ($id) = @_;

	if ($id =~ /urn:nmtopo:.*\/([^\/]+)$/) {
		return $1;
	} else {
		return $id;
	}
}

sub buildTopologyRequest($) {
	my ($nodes, $links) = @_;

	my $topology_request = <<EOR
		<nmwg:message type="SetupDataRequest" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
		<nmwg:metadata id="meta1">
		<nmwg:eventType>topology.lookup.all</nmwg:eventType>
		</nmwg:metadata>

		<nmwg:data id="data1" metadataIdRef="meta1"/>
		</nmwg:message>
EOR
		;

	return $topology_request;
}

sub outputNodes($) {
	my ($nodes) = @_;

	my $content = "";

	foreach my $id (keys %{ $nodes }) {
		$content .= "<nmwg:metadata id=\"".$nodes->{$id}->{"mdid"}."\">\n";
		$content .= "  <nmwg:subject id=\"sub-".$nodes->{$id}->{"name"}."\">\n";
		$content .= "    <nmwgtopo3:node id=\"".$nodes->{$id}->{"name"}."\" xmlns:nmwgtopo3=\"http://ggf.org/ns/nmwg/topology/base/3.0/\">\n";
		$content .= "      <nmwgtopo3:type>TopologyPoint</nmwgtopo3:type>\n";
		$content .= "      <nmwgtopo3:name type=\"logical\">".$nodes->{$id}->{"name"}."</nmwgtopo3:name>\n";
		$content .= "      <nmwgtopo3:city>".$nodes->{$id}->{"city"}."</nmwgtopo3:city>\n" if (defined $nodes->{$id}->{"city"});
		$content .= "      <nmwgtopo3:country>".$nodes->{$id}->{"country"}."</nmwgtopo3:country>\n" if (defined $nodes->{$id}->{"country"});
		$content .= "      <nmwgtopo3:latitude>".$nodes->{$id}->{"latitude"}."</nmwgtopo3:latitude>\n" if (defined $nodes->{$id}->{"latitude"});
		$content .= "      <nmwgtopo3:longitude>".$nodes->{$id}->{"longitude"}."</nmwgtopo3:longitude>\n" if (defined $nodes->{$id}->{"longitude"});
		$content .= "    </nmwgtopo3:node>\n";
		$content .= "  </nmwg:subject>\n";
		$content .= "</nmwg:metadata>\n";
	}

	return $content;
}

sub outputLinks($) {
	my ($links, $nodes) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my $content = "";

	my $i = 0;

	foreach my $link_id (keys %{ $links }) {
		my $link = $links->{$link_id};
		$content .= "<nmwg:metadata id=\"".$link->{"mdid"}."\">\n";
		$content .= "  <nmwg:subject id=\"sub$i\">\n";
		$content .= "    <nmtl2:link xmlns:nmtl2=\"http://ggf.org/ns/nmwg/topology/l2/3.0/\">\n";
		$content .= "      <nmtl2:name type=\"logical\">".$link->{"name"}."</nmtl2:name>\n";
		$content .= "      <nmtl2:globalName type=\"logical\">".$link->{"globalName"}."</nmtl2:globalName>\n";
		$content .= "      <nmtl2:type>".$link->{"type"}."</nmtl2:type>\n";
		foreach my $endpoint (@{ $link->{"endpoints"} }) {
			$content .= "      <nmwgtopo3:node nodeIdRef=\"".$endpoint->{"node"}->{"name"}."\" xmlns:nmwgtopo3=\"http://ggf.org/ns/nmwg/topology/base/3.0/\">\n";
			$content .= "        <nmwgtopo3:role>".$endpoint->{"type"}."</nmwgtopo3:role>\n";
			$content .= "      </nmwgtopo3:node>\n";
		}
		$content .= "    </nmtl2:link>\n";
		$content .= "  </nmwg:subject>\n";
		$content .= "</nmwg:metadata>\n";

		$content .= "<nmwg:data id=\"data$i\" metadataIdRef=\"".$link->{"mdid"}."\">\n";
		$content .= "  <ifevt:datum timeType=\"unix\" timeValue=\"".$link->{"time"}."\">\n";
		$content .= "    <ifevt:stateAdmin>".$link->{"adminStatus"}."</ifevt:stateAdmin>\n";
		$content .= "    <ifevt:operAdmin>".$link->{"operStatus"}."</ifevt:operAdmin>\n";
		$content .= "  </ifevt:datum>\n";
		$content .= "</nmwg:data>\n";
		$i++;
	}

	return $content;
}

sub parseLinkFile($) {
	my ($file) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my %topology_ids = ();
	my %links = ();

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_file($file);
	if (!defined $doc) {
		my $msg = "Couldn't parse $file";
		$logger->error($msg);
		return ("error.configuration", $msg);
	}

	my $conf = $doc->documentElement;

	my $domain = $conf->findvalue("domain");
	if (!defined $domain) {
		my $msg = "No domain specified in configuration";
		$logger->error($msg);
		return ("error.configuration", $msg);
	}

	foreach my $link ($conf->getChildrenByLocalName("link")) {
		my $global_name = $link->findvalue("globalName");
		my $ma_name = $link->findvalue("archiveId");
		my $local_name = $link->findvalue("localName");

		if (!defined $global_name) {
			my $msg = "Link has no global name";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (!defined $ma_name) {
			my $msg = "Link has no archive id";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (!defined $local_name or $local_name eq "") {
			$local_name = $ma_name;
			$local_name =~ s/[^a-zA-Z0-9_]//g;
		}

		my @endpoints = ();

		my $num_endpoints = 0;

		my $prev_endpoint;

		foreach my $endpoint ($link->getChildrenByLocalName("endpoint")) {
			my $node_id = $endpoint->getAttribute("id");
			my $node_type = $endpoint->getAttribute("type");
			my $node_name = $endpoint->getAttribute("name");

			if (!defined $node_type) {
				my $msg = "Node with unspecified type found";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if (!defined $node_id and !defined $node_name) {
				my $msg = "Node needs to have either a topology id or a name";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if (lc($node_type) ne "demarcpoint" and lc($node_type) ne "endpoint") {
				my $msg = "Node found with invalid type $node_type. Must be \"DemarcPoint\" or \"EndPoint\"";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			my $new_node;
			if (!defined $node_id) {
				my %tmp = ();
				$new_node = \%tmp;
			} elsif (!defined $topology_ids{"$node_id"}) {
				my %tmp = ();
				$topology_ids{"$node_id"} = \%tmp;
				$new_node = \%tmp;
			} else {
				$new_node = $topology_ids{"$node_id"};
			}

			$new_node->{"id"} = $node_id if defined $node_id;
			$new_node->{"name"} = $node_name if defined $node_name;

			my %new_endpoint = ();

			$new_endpoint{"type"} = $node_type if defined $node_type;
			$new_endpoint{"node"} = $new_node;

			push @endpoints, \%new_endpoint;

			$num_endpoints++;
		}

		if ($num_endpoints != 2) {
			my $msg = "Invalid number of endpoints, $num_endpoints, must be 2";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		my %new_link = ();

		$new_link{"globalName"} = $global_name;
		$new_link{"name"} = $local_name;
		$new_link{"archiveId"} = $ma_name;
		$new_link{"endpoints"} = \@endpoints;

		$links{$ma_name} = \%new_link;
	}

	return ("", $domain, \%links, \%topology_ids);
}

sub parseTopology($$$) {
	my ($topology, $topology_ids, $domain_name) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	my %ids = ();

	$logger->debug("parseTopology()");

	foreach my $domain ($topology->getChildrenByLocalName("domain")) {
		$logger->debug("domain: ".$domain->getAttribute("id"));
		foreach my $node ($domain->getChildrenByLocalName("node")) {
			my $id = $node->getAttribute("id");
			$logger->debug("node: ".$id);

			next if !defined $topology_ids->{$id};

			$logger->debug("found node ".$id." in here");

			my $longitude = $node->findvalue("./*[local-name()='longitude']");
			$logger->debug("searched for longitude");
			my $latitude = $node->findvalue("./*[local-name()='latitude']");
			$logger->debug("searched for latitude");
			my $city = $node->findvalue("./*[local-name()='city']");
			$logger->debug("searched for city");
			my $country = $node->findvalue("./*[local-name()='country']");
			$logger->debug("searched for country");
			my $name = $node->findvalue("./*[local-name()='name']");
			$logger->debug("searched for name");

			$topology_ids->{$id}->{"mdid"} = genuid();
			$topology_ids->{$id}->{"type"} = "TopologyPoint";

			if (!defined $name and !defined $topology_ids->{$id}->{"name"}) {
				my $msg = "No name for node $id";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if (!defined $topology_ids->{$id}->{"name"}) {
				my $new_name = uc($name);
				$new_name =~ s/[^A-Z0-9_]//g;
				$topology_ids->{$id}->{"name"} = $domain_name."-".$new_name;
			}

			if (defined $longitude) {
				# conversions may need to be made
				$topology_ids->{$id}->{"longitude"} = $longitude;
			}

			if (defined $latitude) {
				# conversions may need to be made
				$topology_ids->{$id}->{"latitude"} = $latitude;
			}

			$topology_ids->{$id}->{"city"} = $city if defined $city;
			$topology_ids->{$id}->{"country"} = $country if defined $country;
		}
	}

	foreach my $id (keys %{ $topology_ids }) {
		if (!defined $topology_ids->{$id}->{"name"}) {
			my $msg = "Lookup failed for node $id";
			$logger->error($msg);
			return ("error.ma", $msg);
		}
	}

	return ("", "");
}

sub parseLinkStatusOutput($$) {
	my ($output, $links) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");


	return ("", "");
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::CircuitStatus - A module that provides methods for the Status MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::MA::CircuitStatus;

my %conf = ();
$conf{"METADATA_DB_TYPE"} = "xmldb";
$conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Status/xmldb";
$conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
$conf{"PING"} = "/bin/ping";

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
		select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
	 );

my $ma = perfSONAR_PS::MA::CircuitStatus->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::CircuitStatus->new;
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

	$Id: Status.pm 242 2007-06-19 21:22:24Z zurawski $

	=head1 AUTHOR

	Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

	=head1 COPYRIGHT AND LICENSE

	Copyright (C) 2007 by Internet2

	This library is free software; you can redistribute it and/or modify
	it under the same terms as Perl itself, either Perl version 5.8.8 or,
	at your option, any later version of Perl 5 you may have available.

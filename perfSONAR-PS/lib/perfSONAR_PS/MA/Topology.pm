#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology;

use warnings;
use strict;
use Carp qw( carp cluck );
use Exporter;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::MA::Topology::ID;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::Client::XMLDB;
use perfSONAR_PS::LS::Register;

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
		if (!defined $self->{CONF}->{"TOPO_DB_FILE"} or $self->{CONF}->{"TOPO_DB_FILE"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file(TOPO_DB_FILE)");
			return -1;
		}

		if (!defined $self->{CONF}->{"TOPO_DB_NAME"} or $self->{CONF}->{"TOPO_DB_NAME"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name(TOPO_DB_NAME)");
			return -1;
		}

		my %ns = (
			nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
			netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
			nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
			snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
			nmtopo=>"http://ggf.org/ns/nmwg/topology/base/3.0/",
		 );

		$self->{CLIENT}= new perfSONAR_PS::MA::Topology::Client::XMLDB($self->{CONF}->{"TOPO_DB_NAME"}, $self->{CONF}->{"TOPO_DB_FILE"}, \%ns);
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	if (defined $self->{CONF}->{"LS_INSTANCE"} and $self->{CONF}->{"LS_INSTANCE"} ne "") {
		if (!defined $self->{CONF}->{"SERVICE_ACCESSPOINT"} or $self->{CONF}->{"SERVICE_ACCESSPOINT"} eq "") {
			my $msg = "You specified to specify a SERVICE_ACCESSPOINT so that people consulting the LS know how to get to this service.";
			$logger->error($msg);
			return -1;
		}

		# fill in sane defaults if the user does not

		if (!defined $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} or $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} eq "") {
			$self->{CONF}->{"LS_REGISTRATION_INTERVAL"} = 5; # 5 minutes
		}

		if (!defined $self->{CONF}->{SERVICE_TYPE} or $self->{CONF}->{SERVICE_TYPE}) {
			$self->{CONF}->{SERVICE_TYPE} = "MA";
		}

		if (!defined $self->{CONF}->{SERVICE_DESCRIPTION} or $self->{CONF}->{SERVICE_DESCRIPTION}) {
			$self->{CONF}->{SERVICE_DESCRIPTION} = "Link Status Measurement Archive";
		}

		my $reg_pid = fork();
		if ($reg_pid == 0) {
			$self->registerLS();
			exit(0);
		} elsif ($reg_pid < 0) {
			$logger->error("Couldn't start LS registration process");
			return -1;
		}
	}

	return 0;
}

sub registerLS {
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
		$logger->info("ID: \"".$info->{type}.":".$info->{id}."\"");
		my ($md, $md_id) = buildLSMetadata($info->{id}, $info->{type}, $info->{prefix}, $info->{uri});
		push @mds, $md;
	}

	$res1 = "";

	$logger->info(Dumper(@mds));

	while(1) {
		$ls->register_withData(\@mds);
		sleep($self->{CONF}->{"LS_REGISTRATION_INTERVAL"} * 60);
	}
}

# XXX prefix!

sub buildLSMetadata($$$$) {
	my ($id, $type, $prefix, $uri) = @_;
	my $md = "";
	my $md_id = "meta".genuid();

	$md .= "<nmwg:metadata id=\"$md_id\">\n";
	$md .= "<nmwg:subject id=\"sub0\">\n";
	$md .= " <$prefix:$type xmlns:$prefix=\"$uri\" id=\"$id\" />\n";
	$md .= "</nmwg:subject>\n";
	$md .= "<nmwg:eventType>topology</nmwg:eventType>\n";
	$md .= "</nmwg:metadata>\n";
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	eval {
		my $readValue = $self->{LISTENER}->acceptCall;
		if($readValue == 0) {
			$logger->debug("Received 'shadow' request from below; no action required.");
			$self->{RESPONSE} = $self->{LISTENER}->getResponse();
		} elsif($readValue == 1) {
			$logger->debug("Received request to act on.");
			handleRequest($self);
		}
	};
	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		$self->{RESPONSE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred");  

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

	my ($status, $response);

	if($messageType eq "SetupDataRequest") {
		($status, $response) = $self->queryTopology($self->{LISTENER}->getRequestDOM());
	} elsif ($messageType eq "TopologyChangeRequest") {
		($status, $response) = $self->changeTopology($self->{LISTENER}->getRequestDOM());
	} else {
		$status = "error.ma.message.type";
		$response = "Message type \"".$messageType."\" is not yet supported";
		$logger->error($response);
	}

	if ($status ne "") {
		$logger->error("Unable to handle topology request: $status/$response");
		$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "", $messageType."Response", $status, $response);
	} else {
		my %all_namespaces = ();

		my $request_namespaces = $self->{LISTENER}->getRequestNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, $messageType, $response, \%all_namespaces);
	}

	return $self->{RESPONSE};
}


sub queryTopology {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	my %ns = (
			nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
			nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
			nmtopo=>"http://ggf.org/ns/nmwg/topology/base/3.0/",
		 );

	$self->{DATADB} = new perfSONAR_PS::DB::XMLDB($self->{CONF}->{"TOPO_DB_NAME"}, $self->{CONF}->{"TOPO_DB_FILE"}, \%ns);

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		$logger->debug("Data id: ".$d->getAttribute("id")." ref: ".$d->getAttribute("metadataIdRef"));
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				$logger->debug("Found corresponding metadata id");

				my $eventType = $m->findvalue("nmwg:eventType");

				my ($status, $res) = $self->queryRequest($eventType, $m, $d);
				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");

					my $mdID = "metadata.".genuid();

					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res);
				} else {
					$localContent .= $res;
				}
			}
		}
	}

	return ("", $localContent);
}

sub changeTopology {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $transaction;

	my $localContent = "";

	my %ns = (
			nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
			netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
			nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
			snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
			nmtopo=>"http://ggf.org/ns/nmwg/topology/base/3.0/",
		 );

	$self->{DATADB}= new perfSONAR_PS::DB::XMLDB($self->{CONF}->{"TOPO_DB_NAME"}, $self->{CONF}->{"TOPO_DB_FILE"}, \%ns);

	if ($self->{DATADB}->openDB != 0) {
		my ($status, $res);
		$status = "error.topology.ma";
		$res = "Couldn't open database";
		$logger->error($res);
		return ($status, $res);
	}

	$transaction = $self->{DATADB}->startTransaction;

	foreach my $data ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $md ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $md->getAttribute("id")) {
				my $eventType = $md->findvalue("nmwg:eventType");
				my ($status, $res);

				my $topology = $data->find("nmtopo:topology")->get_node(1);
				if (!defined $topology) {
					my $msg = "No topology defined in change topology request";
					$logger->error($msg);
					$self->{DATADB}->abortTransaction($transaction);
					return ("error.topology.query.topology_not_found", $msg);
				}

				($status, $res) = topologyNormalize($topology);
				if ($status ne "") {
					$logger->error("Couldn't normalize topology");
					$self->{DATADB}->abortTransaction($transaction);
					return ($status, $res);
				}

				$localContent .= $md->toString();
				$localContent .= "\n";

				my $md_id = $md->getAttribute("id");
				my $d_id = $data->getAttribute("id");
				if (!defined $d_id) {
					$d_id = genuid();
				}

				$localContent .= "<nmwg:data id=\"$d_id\" metadataIdRef=\"$md_id\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
				$localContent .= "<nmtopo:topology xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topo/base/2.0\">\n";

				($status, $res) = $self->changeXMLDB($eventType, $topology);
				if ($status ne "") {
					$logger->error("Error handling topology request: aborting all changes");
					# this should undo any previous changes.
					$self->{DATADB}->abortTransaction($transaction);
					return ($status, $res);
				}

				$localContent .= $res;
				$localContent .= "</nmtopo:topology>\n";
				$localContent .= "</nmwg:data>\n";
			}
		}
	}

	$self->{DATADB}->commitTransaction($transaction);

	return ("", $localContent);
}

sub lookupDomain($$$) {
	my ($self, $id, $domains) = @_;

	if (idIsFQ($id) != 0) {
		$id = idBaseLevel($id);
	}

	if (!defined $domains->{$id}) {
		my ($status, $doc) = $self->{DATADB}->getDocumentByName($id);

		if ($status != 0) {
			return undef;
		}

		my $parser = XML::LibXML->new();
		my $pdoc = $parser->parse_string($doc);
		my $domain = $pdoc->getDocumentElement;

		$domains->{$id} = $domain;

		return $domain;
	} else {
		# use the cache'd copy
		return $domains->{$id};
	}
}

sub lookupNode($$$) {
	my ($self, $domain, $id, $nodes) = @_;

	return $nodes->{$id} if (defined $nodes->{$id});

	my $node_basename = idBaseLevel($id);

	return $domain->find("./*[local-name()=\'node\' and \@id='$node_basename']")->get_node(1);
}

sub lookupPort($$$) {
	my ($self, $node, $id, $ports) = @_;

	return $ports->{$id} if (defined $ports->{$id});

	my $port_basename = idBaseLevel($id);

	return $node->find("./*[local-name()=\'port\' and \@id='$port_basename']")->get_node(1);
}

sub changeXMLDB($$$) {
	my ($self, $type, $topology, $transaction) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";

	my %comparison_attrs = {
		'link' => { id => '' },
		'node' => { id => '' },
		'port' => { id => '' },
		'domain' => { id => '' },
	};

	if ($type eq "topology.change.update" or $type eq "topology.change.replace" or $type eq "topology.change.add" or $type eq "topology.change.remove") {
		my @namespaces = $topology->getNamespaces();

		my %domains = ();
		my %nodes = ();
		my %ports = ();
		my %links = ();
		my %domains_to_delete = ();

		foreach my $domain ($topology->getChildrenByTagNameNS("*", "domain")) {
			my $id = $domain->getAttribute("id");
			my $fqid;

			if (!defined $id or $id eq "") {
				my $msg = "Domain with no id found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			if (idIsFQ($id) != 0) {
				$id = idBaseLevel($id);
				$fqid = $id;
			} else {
				$fqid = idConstruct($id);
			}

			my $new_domain;
			my $old_domain = $self->lookupDomain($id, \%domains);

			if ($type eq "topology.change.update") {
				if (!defined $old_domain) {
					my $msg = "Domain $id to update, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_domain = mergeNodes_general($old_domain, $domain, \%comparison_attrs);
			} elsif ($type eq "topology.change.replace") {
				$new_domain = $domain->cloneNode(1);
			} elsif ($type eq "topology.change.add") {
				if (defined $old_domain) {
					my $msg = "Domain $id already exists";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}
			} elsif ($type eq "topology.change.remove") {
				if (!defined $old_domain) {
					my $msg = "Domain $id to remove, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$domains_to_delete{$fqid} = "";
			}

			$domains{$fqid} = $new_domain;
		}

		foreach my $node ($topology->getChildrenByTagNameNS("*", "node")) {
			my $id = $node->getAttribute("id");
			if (!defined $id or $id eq "") {
				my $msg = "Node with no id found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			if (idIsFQ($id) == 0) {
				my $msg = "Node with non-fully qualified id, $id, is specified at top-level";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}



			my $domain_id = idRemoveLevel($id);

			my $domain = $self->lookupDomain($domain_id, \%domains);
			if (!defined $domain) {
				my $msg = "Domain $domain_id for node $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $basename = idBaseLevel($id);

			my $new_node;
			my $old_node = $domain->find("./*[local-name()=\'node\' and \@id='$basename']")->get_node(1);

			if ($type eq "topology.change.update") {
				if (!defined $old_node) {
					my $msg = "Node $id to update, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_node = mergeNodes_general($old_node, $node, \%comparison_attrs);
			} elsif ($type eq "topology.change.replace") {
				$new_node = $node->cloneNode(1);
			} elsif ($type eq "topology.change.add") {
				if (defined $old_node) {
					my $msg = "Node $id already exists";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_node = $node->cloneNode(1);
			} elsif ($type eq "topology.change.remove") {
				if (!defined $old_node) {
					my $msg = "Node $id to remove, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_node = undef;

				$domain->removeChild($old_node);
			}

			if (defined $new_node) {
				$new_node->setAttribute("id", $basename);

				if (defined $old_node) {
					$old_node->replaceNode($new_node);
				} else {
					domainReplaceChild($domain, $new_node, $id);
				}
			}

			$nodes{$id} = $new_node;
		}

		foreach my $port ($topology->getChildrenByTagNameNS("*", "port")) {
			my $id = $port->getAttribute("id");
			if (!defined $id or $id eq "") {
				my $msg = "Port with no id found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			if (idIsFQ($id) == 0) {
				my $msg = "Port with non-fully qualified id, $id, is specified at top-level";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}


			my $node_id = idRemoveLevel($id);
			my $domain_id = idRemoveLevel($node_id);

			my $domain = $self->lookupDomain($domain_id, \%domains);
			if (!defined $domain) {
				my $msg = "Domain $domain_id for node $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $node = $self->lookupNodes($domain, $node_id, \%nodes);

			if (!defined $node) {
				my $msg = "Node $node_id for port $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $basename = idBaseLevel($id);

			my $new_port = $port->cloneNode(1);
			my $old_port = $node->find("./*[local-name()=\'port\' and \@id='$basename']")->get_node(1);

			if ($type eq "topology.change.update") {
				if (!defined $old_port) {
					my $msg = "Node $id to update, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_port = mergeNodes_general($old_port, $port, \%comparison_attrs);
			} elsif ($type eq "topology.change.replace") {
				$new_port = $port->cloneNode(1);
			} elsif ($type eq "topology.change.add") {
				if (defined $old_port) {
					my $msg = "Port $id already exists";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_port = $port->cloneNode(1);
			} elsif ($type eq "topology.change.remove") {
				if (!defined $old_port) {
					my $msg = "Port $id to remove, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_port = undef;

				$node->removeChild($old_port);
			}

			if (defined $new_port) {
				$new_port->setAttribute("id", $basename);

				if (defined $old_port) {
					$old_port->replaceNode($new_port);
				} else {
					nodeReplaceChild($node, $new_port, $id);
				}
			}

			$ports{$id} = $new_port;
		}

		foreach my $link ($topology->getChildrenByTagNameNS("*", "link")) {
			my $id = $link->getAttribute("id");
			if (!defined $id or $id eq "") {
				my $msg = "Link with no id found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			if (idIsFQ($id) == 0) {
				my $msg = "Link with non-fully qualified id, $id, is specified at top-level";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}


			my $port_id = idRemoveLevel($id);
			my $node_id = idRemoveLevel($id);
			my $domain_id = idRemoveLevel($node_id);

			my $domain = $self->lookupDomain($domain_id, \%domains);
			if (!defined $domain) {
				my $msg = "Domain $domain_id for node $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $node = $self->lookupNode($domain, $node_id, \%nodes);
			if (!defined $node) {
				my $msg = "Node $node_id for link $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $port = $self->lookupPort($node, $port_id, \%ports);
			if (!defined $port) {
				my $msg = "Port $port_id for link $id not found";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			my $basename = idBaseLevel($id);

			my $new_link;
			my $old_link = $link->find("./*[local-name()=\'link\' and \@id='$basename']")->get_node(1);

			if ($type eq "topology.change.update") {
				if (!defined $old_link) {
					my $msg = "Link $id to update, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_link = mergeNodes_general($old_link, $link, \%comparison_attrs);
			} elsif ($type eq "topology.change.replace") {
				$new_link = $link->cloneNode(1);
			} elsif ($type eq "topology.change.add") {
				if (defined $old_link) {
					my $msg = "Link $id already exists";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_link = $link->cloneNode(1);
			} elsif ($type eq "topology.change.remove") {
				if (!defined $old_link) {
					my $msg = "Link $id to remove, but not found";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$new_link = undef;

				$port->removeChild($old_link);
			}

			if (defined $new_link) {
				$new_link->setAttribute("id", $basename);

				if (defined $old_link) {
					$old_link->replaceNode($new_link);
				} else {
					portReplaceChild($port, $new_link, $id);
				}
			}

			$links{$id} = $new_link;
		}

		# we only pulled in domains if something changed, so update
		# any domain we have
		foreach my $fq_domain_id (keys %domains) {
			my $id = idBaseLevel($fq_domain_id);

			$self->{DATADB}->remove($id);

			if ($self->{DATADB}->insertIntoContainer($domains{$fq_domain_id}->toString, $id) != 0) {
				my $msg = "Error updating $fq_domain_id";
				$logger->error($msg);
				return ("error.topology.ma", $msg);
			}
		}
	} else {
		my $msg = "Invalid change type specified $type";
		$logger->error($msg);
		return ("error.topology.change.invalid_change_type", $msg);
	}

	return ("", $localContent);
}

sub queryRequest($$$$) {
	my($self, $type, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";
	my ($status, $res);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	my $dataContent;
	if ($type eq "topology.lookup.all") {
		($status, $res) = $self->{CLIENT}->getAll;
		if ($status != 0) {
			my $msg = "Database dump failed: $res";
			$logger->error($msg);
			return ("error.common.storage.fetch", $msg);
		}

		$dataContent = $res->toString;
	} elsif ($type eq "topology.lookup.xquery") {
		my $query = extract($m->find("./xquery:subject")->get_node(1));
		if (!defined $query or $query eq "") {
			return ("error.topology.query.query_not_found", "No query given in request");
		}

		($status, $res) = $self->{CLIENT}->xQuery($query);
		if ($status != 0) {
			my $msg = "Database query failed: $res";
			$logger->error($msg);
			return ("error.common.storage.query", $msg);
		}

		$dataContent .= "<nmtopo:topology>\n";
		$dataContent .= $res;
		$dataContent .= "</nmtopo:topology>\n";
	} else {
		my $msg = "Unknown event type: $type";
		$logger->error($msg);
		return ("error.ma.eventtype_not_supported", $msg);
	}

	$localContent .= $m->toString();
	$localContent .= "\n";

	my $md_id = $m->getAttribute("id");
	my $d_id = $d->getAttribute("id");
	if (!defined $d_id) {
		$d_id = genuid();
	}

	$localContent .= "<nmwg:data id=\"$d_id\" metadataIdRef=\"$md_id\">\n";
	$localContent .= $dataContent;
	$localContent .= "</nmwg:data>\n";

	return ("", $localContent);
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

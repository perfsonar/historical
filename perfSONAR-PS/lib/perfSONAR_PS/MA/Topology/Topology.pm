package perfSONAR_PS::MA::Topology::Topology;

use perfSONAR_PS::MA::Topology::ID;
use Log::Log4perl qw(get_logger :levels);
use Exporter;

@ISA  = ('Exporter');
@EXPORT = ('topologyNormalize', 'validateDomain', 'validateNode', 'validatePort', 'validateLink', 'domainReplaceChild', 'nodeReplaceChild', 'portReplaceChild');

sub mergeNodes_general($$$);
sub domainReplaceChild($$$);
sub nodeReplaceChild($$$);
sub portReplaceChild($$$);
sub topologyNormalize_links($$$$);
sub topologyNormalize_ports($$$$);
sub topologyNormalize_nodes($$$$);
sub topologyNormalize_domains($$);
sub topologyNormalize($);

sub mergeNodes_general($$$) {
	my ($old_node, $new_node, $attrs) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	my $node = $old_node->cloneNode;

	my @new_attributes = $new_node->getAttributes();

	foreach my $attribute (@new_attributes) {
		$node->setAttribute($attribute->getName, $attribute->getValue);
	}


	my %elements = ();

	foreach my $elem ($node->getChildNodes) {
		$elements{$elem->localname} = $elem;
	}

	foreach my $elem ($new_node->getChildNodes) {
		my $is_equal;

		if (defined $attrs->{$elem->localname} and defined $elements{$elem->localname}) {
			$is_equal = 1;

			foreach my $attr (keys %{ $attrs->{$elem->localname} }) {
				my $old_attr = $elements{$elem->localname}->getAttributes($attr);
				my $new_attr = $elem->getAttributes($attr);

				if (defined $old_attr and defined $new_attr) {
					# if the attribute exists in both the old node and the new node, compare them
					if ($old_attr->getValue ne $new_attr->getValue) {
						$is_equal = 0;
					}
				} elsif (defined $old_attr or defined $new_attr) {
					# if the attribute exists in one or the other, obviously they cannot be equal
					$is_equal = 0;
				}
			}
		} elsif (defined $elements{$elem->localname}) {
			$is_equal = 1;
		} else {
			$is_equal = 0;
		}

		my $new_child;
		if ($elem->hasChildNodes) {
			if ($is_equal) {
				$new_child = mergeNodes_general($elements{$elem->localname}, $elem, $attrs);
			} else {
				$new_child = $elem->cloneNode(1);
			}
		} else {
			$new_child = $elem->cloneNode(1);
		}

		if ($is_equal) {
			$node->removeChild($elements{$elem->localname});
		}

		$node->appendChild($new_child);
	}

	return $node;
}

sub domainReplaceChild($$$) {
	my ($domain, $new_node, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	foreach my $node ($domain->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("nodeIdRef"); 
		next if (!defined $id or $id eq "");

		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$domain->removeChild($node);
		}
	}

	$domain->addChild($new_node);
}

sub nodeReplaceChild($$$) {
	my ($node, $new_port, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	foreach my $port ($node->getChildrenByTagNameNS("*", "port")) {
		my $id = $port->getAttribute("portIdRef"); 
		next if (!defined $id or $id eq "");

		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$node->removeChild($port);
		}
	}

	$node->addChild($new_port);
}

sub portReplaceChild($$$) {
	my ($port, $new_link, $fqid) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	foreach my $link ($port->getChildrenByTagNameNS("*", "link")) {
		my $id = $port->getAttribute("linkIdRef"); 
		next if (!defined $id or $id eq "");

		$logger->debug("comparing $id to $fqid");
		if ($id eq $fqid) {
			$port->removeChild($link);
		}
	}

	$port->addChild($new_link);
}

sub topologyNormalize_links($$$$) {
	my ($root, $topology, $uri, $top_level) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("normalizing links");

	foreach my $domain ($root->getChildrenByTagNameNS("*", "domain")) {
		my $fqid = $domain->getAttribute("id");
		my ($status, $res) = topologyNormalize_links($domain, $topology, $fqid, $top_level);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		my $n = idIsFQ($id, "node");
		if ($n == 0) {
			$fqid = idAddLevel($uri, $id);
		} elsif ($n == -1) {
			my $msg = "Node $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} else {
			$fqid = $id;
		}

		my ($status, $res) = topologyNormalize_links($node, $topology, $fqid, $top_level);
		if ($status ne "") {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByTagNameNS("*", "port")) {
		my $id = $port->getAttribute("id");
		my $fqid;

		my $n = idIsFQ($id, "port");
		if ($n == 0) {
			$fqid = idAddLevel($uri, $id);
		} elsif ($n == -1) {
			my $msg = "Port $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} else {
			$fqid = $id;
		}

		my ($status, $res) = topologyNormalize_links($port, $topology, $fqid, $top_level);
		if ($status ne "") {
			return ($status, $res);
		}
	}

	foreach my $link ($root->getChildrenByTagNameNS("*", "link")) {
		my $id = $link->getAttribute("id");
		my $fqid;

		$logger->debug("Handling link $id");

		if (!defined $id) {
			if (!defined $link->getAttribute("link") and defined $link->getAttribute("linkIdRef")) {
				$logger->debug("Link appears to be a pointer, skipping");
				next;
			} else {
				my $msg = "Link has no id";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}
		}

		my $n = idIsFQ($id, "link");
		if ($n == -1) {
			my $msg = "Link $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} elsif ($n == 0) {
			$logger->debug("$id not qualified: ".$root->localname."");

			if ($root->localname eq "port") {
				my $port_id = $root->getAttribute("id");
				my $fqid = idAddLevel($port_id, $id);
				$link->setAttribute("id", $fqid);
				next;
			}

			my $num_ports = 0;

			foreach my $port ($link->getChildrenByTagNameNS("*", "port")) {
				my $idref = $port->getAttribute("portIdRef");

				$logger->debug("Got port ref: ".$idref."");
				if (!defined $idref or $idref eq "") {
					my $msg = "Link $id refers to port with no portIdRef";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				$idref = $idref;
				my $new_link = $link->cloneNode(1);
				my $new_link_fqid = idAddLevel($idref, $id);
				my $port = $topology->{"ports"}->{$idref};

				if (!defined $port) {
					my $msg = "Link $id refers to non-existent port $idref";
					$logger->error($msg);
					return ("error.topology.invalid_topology", $msg);
				}

				my $link_element = $port->find("./*[local-name()='link']")->get_node(1);

				if (defined $link_element) {
					my $link_idref = $link_element->getAttribute("linkIdRef");
					if (!defined $link_idref or idSanitize($link_idref) ne $new_link_fqid) {
						my $msg = "$new_link_fqid slated to replace existing link";
						$logger->error($msg);
						return ("error.topology.invalid_topology", $msg);
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
				return ("error.topology.invalid_topology", $msg);
			}

			$root->removeChild($link);

			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = $id;

			my $port_id = idRemoveLevel($fqid);
			my $port = $topology->{"ports"}->{$port_id};

			if (!defined $port) {
				# move it to the top level
				$root->removeChild($link);
				$top_level->appendChild($link);
			} else {
				# remove the link from $root and add it to the port
				$root->removeChild($link);
				portReplaceChild($port, $link, $fqid);
			}
			$logger->debug("Adding $fqid");
			$topology->{"links"}->{$fqid} = $link;
			$link->setAttribute("id", $fqid);
		}
	}
}

sub topologyNormalize_ports($$$$) {
	my ($root, $topology, $uri, $top_level) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("normalizing ports");

	foreach my $domain ($root->getChildrenByTagNameNS("*", "domain")) {
		my $fqid = $domain->getAttribute("id");
		my ($status, $res) = topologyNormalize_ports($domain, $topology, $fqid, $top_level);
		if ($status ne "") {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		my $n = idIsFQ($id, "node");
		if ($n == 0) {
			$fqid = idAddLevel($uri, $id);
		} elsif ($n == -1) {
			my $msg = "Node $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} else {
			$fqid = $id;
		}

		my ($status, $res) = topologyNormalize_ports($node, $topology, $fqid, $top_level);
		if ($status ne "") {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByTagNameNS("*", "port")) {
		my $id = $port->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			if (defined $port->getAttribute("portIdRef")) {
				next;
			} else {
				my $msg = "Port has no id";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}
		}

		my $n = idIsFQ($id, "port");
		if ($n == 0) {
			if ($uri eq "") {
				my $msg = "Port $id has no parent and is not fully qualified";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			$fqid = idAddLevel($uri, $id);
		} elsif ($n == -1) {
			my $msg = "Port $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} else {
			$fqid = $id;

			my $node_id = idRemoveLevel($fqid);
			my $node = $topology->{"nodes"}->{$node_id};

			if (!defined $node) {
				# move it to the top level
				$root->removeChild($port);
				$top_level->appendChild($port);
			} else {
				# remove the port from $root and add it to the node
				$root->removeChild($port);
				nodeReplaceChild($node, $port, $fqid);
			}
		}

		$logger->debug("Adding $fqid");
		$topology->{"ports"}->{$fqid} = $port;
		$port->setAttribute("id", $fqid);
	}
}

sub topologyNormalize_nodes($$$$) {
	my ($root, $topology, $uri, $top_level) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("normalizing nodes");

	foreach my $domain ($root->getChildrenByTagNameNS("*", "domain")) {
		my $fqid = $domain->getAttribute("id");
		$logger->debug("Found domain: $fqid");
		my ($status, $res) = topologyNormalize_nodes($domain, $topology, $fqid, $top_level);
		if ($status ne "") {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			if (defined $node->getAttribute("nodeIdRef")) {
				next;
			} else {
				my $msg = "Node has no id";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}
		}

		$logger->debug("Found node: $id");

		my $n = idIsFQ($id, "node");
		if ($n == 0) {
			if ($uri eq "") {
				my $msg = "Node $id has no parent and is not fully qualified";
				$logger->error($msg);
				return ("error.topology.invalid_topology", $msg);
			}

			$fqid = idAddLevel($uri, $id);
		} elsif ($n == -1) {
			my $msg = "Node $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} else {
			$fqid = $id;

			my $domain_id = idRemoveLevel($fqid);
			my $domain = $topology->{"domains"}->{$domain_id};

			if (!defined $domain) {
				my $msg = "Node $fqid references non-existent domain $domain_id, moving to top-level";
				$logger->debug($msg);

				$root->removeChild($node);
				$top_level->appendChild($node);
			} else {
				$logger->debug("Moving $fqid to $domain_id");

				# remove the node from $root and add it to the domain
				$root->removeChild($node);
				domainReplaceChild($domain, $node, $fqid);
			}
		}

		$node->setAttribute("id", $fqid);
		$logger->debug("Adding $fqid");
		$topology->{"nodes"}->{$fqid} = $node;
	}
}

sub topologyNormalize_domains($$) {
	my ($root, $topology) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("normalizing domains");

	foreach my $domain ($root->getChildrenByTagNameNS("*", "domain")) {
		my $id = $domain->getAttribute("id");
		my $fqid;

		if (!defined $id) {
			my $msg = "No id for specified domain";
			 $logger->error($msg);
			return ("error.topology.invalid_topology", $msg);
		}

		my $n = idIsFQ($id, "domain");
		if ($n == -1) {
			my $msg = "Domain $id has an invalid fully-qualified id";
			$logger->error($msg);
			return (-1, $msg);
		} elsif ($n == 0) {
			$id = idConstruct($id);

			$domain->setAttribute("id", $id);
		}

		$logger->debug("Adding $id");

		$topology->{"domains"}->{$id} = $domain;
	}

	return ("", "");
}

sub topologyNormalize($) {
	my ($root) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	my %topology = ();
	$topology{"domains"} = ();
	$topology{"nodes"} = ();
	$topology{"links"} = ();
	$topology{"ports"} = ();

	my ($status, $res);

	($status, $res) = topologyNormalize_domains($root, \%topology);
	if ($status ne "") {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_nodes($root, \%topology, "", $root);
	if ($status ne "") {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_ports($root, \%topology, "", $root);
	if ($status ne "") {
		return ($status, $res);
	}

	($status, $res) = topologyNormalize_links($root, \%topology, "", $root);
	if ($status ne "") {
		return ($status, $res);
	}
}

sub validateDomain($) {
	my ($domain) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("Validating domain");

	my $id = $domain->getAttribute("id");
	if (!defined $id or $id eq "") {
		my $msg = "Domain has no id";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (idIsFQ($id, "domain") != 1) {
		my $msg = "Domain has non-properly qualified id: $id";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $node ($domain->getChildrenByTagNameNS("*", "node")) {
		my ($status, $res) = validateNode($node);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $other_domain($domain->getChildrenByTagNameNS("*", "domain")) {
		my $msg = "Found domain with domain in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $link ($domain->getChildrenByTagNameNS("*", "link")) {
		my $msg = "Found domain with link in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $path ($domain->getChildrenByTagNameNS("*", "path")) {
		my $msg = "Found domain with path in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $network ($domain->getChildrenByTagNameNS("*", "network")) {
		my $msg = "Found domain with network in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, "");
}

sub validateNode($) {
	my ($node) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("Validating node");

	my $id = $node->getAttribute("id");
	if (!defined $id or $id eq "") {
		my $msg = "Node has no id";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (idIsFQ($id, "node") != 1) {
		my $msg = "Node has non-properly qualified id: $id";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $port ($node->getChildrenByTagNameNS("*", "port")) {
		my ($status, $res) = validatePort($port);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $other_node ($node->getChildrenByTagNameNS("*", "node")) {
		my $msg = "Found node with node in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $link ($node->getChildrenByTagNameNS("*", "link")) {
		my $msg = "Found node with link in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $path ($node->getChildrenByTagNameNS("*", "path")) {
		my $msg = "Found node with path in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $network ($node->getChildrenByTagNameNS("*", "network")) {
		my $msg = "Found node with network in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $domain ($node->getChildrenByTagNameNS("*", "domain")) {
		my $msg = "Found node with domain in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, "");
}

sub validatePort($) {
	my ($port) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("Validating port");

	my $id = $port->getAttribute("id");
	if (!defined $id or $id eq "") {
		my $msg = "Port has no id";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (idIsFQ($id, "port") != 1) {
		my $msg = "Port has non-properly qualified id: $id";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $link ($port->getChildrenByTagNameNS("*", "link")) {
		my ($status, $res) = validateLink($link);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $other_port ($port->getChildrenByTagNameNS("*", "port")) {
		my $msg = "Found port with port in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $node ($port->getChildrenByTagNameNS("*", "node")) {
		my $msg = "Found port with node in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $path ($port->getChildrenByTagNameNS("*", "path")) {
		my $msg = "Found port with path in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $network ($port->getChildrenByTagNameNS("*", "network")) {
		my $msg = "Found port with network in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $domain ($port->getChildrenByTagNameNS("*", "domain")) {
		my $msg = "Found port with domain in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, "");
}

sub validateLink($) {
	my ($link) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Topology");

	$logger->info("Validating link");

	my $id = $link->getAttribute("id");
	if (!defined $id or $id eq "") {
		my $msg = "Link has no id";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (idIsFQ($id, "link") != 1) {
		my $msg = "Link has non-properly qualified id: $id";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $other_link ($link->getChildrenByTagNameNS("*", "link")) {
		my $msg = "Found link with link in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $node ($link->getChildrenByTagNameNS("*", "node")) {
		my $msg = "Found link with node in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $path ($link->getChildrenByTagNameNS("*", "path")) {
		my $msg = "Found link with path in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $network ($link->getChildrenByTagNameNS("*", "network")) {
		my $msg = "Found link with network in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $domain ($link->getChildrenByTagNameNS("*", "domain")) {
		my $msg = "Found link with domain in it";
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, "");
}

1;

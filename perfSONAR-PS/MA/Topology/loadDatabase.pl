#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		loadDatabase.pl                    #
# Author:	Aaron Brown                        #
# Contact:	aaron@internet2.edu                #
# Args:		$ifile = Input File                #
#               $XMLDBENV = XML DB environment     #
#               $XMLDBCONT = XML DB Container      #
#               $doc_name = Document Name          #
#               $ofile = Output File (not required)#
# Purpose:	Load the XML DB with toplogy       #
#               information                        #
#                                                  #
# ################################################ #

use XML::LibXML;
use strict;
use Data::Dumper;
use perfSONAR_PS::DB::XMLDB;
use Log::Log4perl qw(get_logger :levels);

Log::Log4perl->init("logger.conf");

my $ifile = shift;
my $xmldbenv = shift;
my $xmldbcontainer = shift;
my $doc_name = shift;
my $ofile = shift;
my $logger = get_logger("perfSONAR_PS::MA::Topology");

if (!defined $ifile or !defined $xmldbenv or !defined $xmldbcontainer or !defined $doc_name) {
	$logger->debug("Error: need to specify input file, xml db environment, xml db container and the document name. Also, if you want a file to output the munged XML into");
	exit(-1);
}

my $parser = XML::LibXML->new();
my $doc = $parser->parse_file($ifile);
my ($status, $res) = topologyNormalize($doc->documentElement());
if ($status != 0) {
	$logger->debug("Error parsing topology: $res");
	exit(-1);
}

my %ns = (
                nmtopo=>"http://ggf.org/ns/nmwg/topology/base/3.0/"
	);

my $db = new perfSONAR_PS::DB::XMLDB($xmldbenv, $xmldbcontainer, \%ns);
if ($db->openDB != 0) {
	$logger->debug("Error: couldn't open requested database");
	exit(-1);
}

if ($db->insertIntoContainer($doc->toString, $doc_name) != 0) {
	$logger->debug("Error: couldn't insert data into database");
	exit(-1);
}

if (defined $ofile) {
	$doc->toFile($ofile);
}

exit(0);

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

	foreach my $network ($root->getChildrenByTagName("nmtopo:network")) {
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

	foreach my $network ($root->getChildrenByTagName("nmtopo:network")) {
		my $fqid = $network->getAttribute("id");
		($status, $res) = topologyNormalize_nodes($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagName("nmtopo:node")) {
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

	foreach my $network ($root->getChildrenByTagName("nmtopo:network")) {
		my $fqid = $network->getAttribute("id");
		($status, $res) = topologyNormalize_ports($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagName("nmtopo:node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		($status, $res) = topologyNormalize_ports($node, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByTagName("nmtopo:port")) {
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

	foreach my $network ($root->getChildrenByTagName("nmtopo:network")) {
		my $fqid = $network->getAttribute("id");
		($status, $res) = topologyNormalize_links($network, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $node ($root->getChildrenByTagName("nmtopo:node")) {
		my $id = $node->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		($status, $res) = topologyNormalize_links($node, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $port ($root->getChildrenByTagName("nmtopo:port")) {
		my $id = $port->getAttribute("id");
		my $fqid;

		if (idIsFQ($id) == 0) {
			$fqid = idAddLevel($uri, $id);
		} else {
			$fqid = idSanitize($id);
		}

		($status, $res) = topologyNormalize_links($port, $topology, $fqid);
		if ($status != 0) {
			return ($status, $res);
		}
	}

	foreach my $link ($root->getChildrenByTagName("nmtopo:link")) {
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

			foreach my $port ($link->getChildrenByTagName("nmtopo:port")) {
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

				my $link_element = $port->find("./nmtopo:link")->get_node(1);

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

	foreach my $node ($network->getChildrenByTagName("nmtopo:node")) {
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

	foreach my $port ($node->getChildrenByTagName("nmtopo:port")) {
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

	foreach my $link ($port->getChildrenByTagName("nmtopo:link")) {
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

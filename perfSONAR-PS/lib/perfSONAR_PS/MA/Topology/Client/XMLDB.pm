#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology::Client::XMLDB;

use strict;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::DB::XMLDB;
use Data::Dumper;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::ID;

sub new {
	my ($package, $db_container, $db_file, $ns) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Client::XMLDB");

	my %hash;

	if (defined $db_container and $db_container ne "") {
		$hash{"DB_CONTAINER"} = $db_container;
	}

	if (defined $db_file and $db_file ne "") {
		$hash{"DB_FILE"} = $db_file;
	}

	if (defined $ns and $ns ne "") {
		$hash{"DB_NAMESPACES"} = $ns;
	}

	$hash{"DB_OPEN"} = 0;
	$hash{"DATADB"} = "";

	bless \%hash => $package;
}

sub open($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Client::XMLDB");

	return (0, "") if ($self->{DB_OPEN} != 0);

	$self->{DATADB} = new perfSONAR_PS::DB::XMLDB($self->{DB_CONTAINER}, $self->{DB_FILE}, $self->{DB_NAMESPACES});
	if (!defined $self->{DATADB}) {
		my $msg = "Couldn't open specified database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open status database";
		$logger->error($msg);
		return (-1, $msg);
	}

	$self->{DB_OPEN} = 1;

	return (0, "");
}

sub close($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return 0 if ($self->{DB_OPEN} == 0);

	$self->{DB_OPEN} = 0;

	return $self->{DATADB}->closeDB;
}

sub setDBContainer($$) {
	my ($self, $container) = @_;

	$self->{DB_CONTAINER} = $container;
	$self->close;
}

sub setDBFile($$) {
	my ($self, $file) = @_;

	$self->{DB_FILE} = $file;
	$self->close;
}

sub setDBNamespaces($$) {
	my ($self, $namespaces) = @_;

	$self->{DB_NAMESPACES} = $namespaces;

	if ($self->{DB_OPEN}) {
		$self->{DATADB}->setNamespaces($namespaces);
	}
}

sub xQuery($$) {
	my($self, $xquery) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";
	my $error;

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	$xquery =~ s/\s{1}\// collection('CHANGEME')\//g;

	my @queryResults = $self->{DATADB}->xQuery($xquery, \$error);
	if ($error ne "") {
		$logger->error("Couldn't query database");
		return (-1, "Couldn't query database: $error");
	}

	$localContent .= "<nmtopo:topology>\n";
	$localContent .= join("", @queryResults);
	$localContent .= "</nmtopo:topology>\n";

	return (0, $localContent);
}

sub getAll {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my @results;
	my $error;

	return (-1, "Database not open") if ($self->{DB_OPEN} == 0);

	my $content = "";

	$content .= "<nmtopo:topology";
	foreach my $ns (keys %{ $self->{DB_NAMESPACES} }) {
		$content .= " xmlns:$ns=\"".$self->{DB_NAMESPACES}->{$ns}."\"";
	}
	$content .= ">";

	@results = $self->{DATADB}->query("/*:domain", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of domains from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	@results = $self->{DATADB}->query("/*:node", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of nodes from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	@results = $self->{DATADB}->query("/*:port", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of ports from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	@results = $self->{DATADB}->query("/*:link", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of links from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	@results = $self->{DATADB}->query("/*:network", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of networks from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	@results = $self->{DATADB}->query("/*:path", \$error);
	if ($error ne "") {
		my $msg = "Couldn't get list of paths from database: $error";
		$logger->error($msg);
		return (-1, $msg);
	}

	$content .= join("", @results);

	$content .= "</nmtopo:topology>";

	my $topology;

	eval {
		my $parser = XML::LibXML->new();
		my $pdoc = $parser->parse_string($content);
		$topology = $pdoc->getDocumentElement;
	};
	if ($@) {
		my $msg = "Couldn't parse resulting database dump: ".$@;
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, $topology);
}

sub getUniqueIDs($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Client::XMLDB");
	my $error;
	my (@domain_ids, @network_ids, @path_ids);

	return (-1, "Database not open") if ($self->{DB_OPEN} == 0);

	my ($status, $results) = $self->getAll();
	if ($status != 0) {
		return ($status, $results);
	}

	my @ids = ();

	foreach my $node ($results->getChildrenByLocalName("domain")) {
		my $id = $node->getAttribute("id");
		my $uri = $node->namespaceURI();
		my $prefix = $node->prefix;

		my %info = (
			type => 'domain',
			id => $id,
			prefix => $prefix,
			uri => $uri,
		);

		push @ids, \%info;
	}

	foreach my $node ($results->getChildrenByLocalName("network")) {
		my $id = $node->getAttribute("id");
		my $uri = $node->namespaceURI();
		my $prefix = $node->prefix;

		my %info = (
			type => 'network',
			id => $id,
			prefix => $prefix,
			uri => $uri,
		);

		push @ids, \%info;
	}

	foreach my $node ($results->getChildrenByLocalName("path")) {
		my $id = $node->getAttribute("id");
		my $uri = $node->namespaceURI();
		my $prefix = $node->prefix;

		my %info = (
			type => 'path',
			id => $id,
			prefix => $prefix,
			uri => $uri,
		);

		push @ids, \%info;
	}

	return (0, \@ids);
}

sub changeTopology($$) {
	my ($self, $type, $topology) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Client::XMLDB");
	my ($status, $res);

	return (-1, "Database not open") if ($self->{DB_OPEN} == 0);

	my %comparison_attrs = (
		link => ( id => '' ),
		node => ( id => '' ),
		port => ( id => '' ),
		domain => ( id => '' ),
	);

	if ($type ne "update" and $type ne "replace" and $type ne "add") {
		my $msg = "Invalid topology change specified: $type";
		$logger->error($msg);
		return (-1, $msg);
	}

	my @namespaces = $topology->getNamespaces();

	my %domains = ();
	my %nodes = ();
	my %ports = ();
	my %links = ();

	foreach my $domain ($topology->getChildrenByTagNameNS("*", "domain")) {
		my $id = $domain->getAttribute("id");

		if (!defined $id or $id eq "") {
			my $msg = "Domain with no id found";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (idIsFQ($id, "domain") == 0) {
			my $msg = "Domain with non-fully qualified id, $id, is specified";
			$logger->error($msg);
			return (-1, $msg);
		}

		my ($status, $res) = validateDomain($domain);
		if ($status != 0) {
			my $msg = "Invalid domain, $id, specified: $res";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $new_domain;
		my $old_domain;

		($status, $res) = $self->lookupElement($id, \%domains, \%nodes, \%ports, \%links);
		$old_domain = $res if ($status == 0);

		if ($type eq "update") {
			if (!defined $old_domain) {
				my $msg = "Domain $id to update, but not found";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_domain = mergeNodes_general($old_domain, $domain, \%comparison_attrs);
		} elsif ($type eq "replace") {
			$new_domain = $domain->cloneNode(1);
		} elsif ($type eq "add") {
			if (defined $old_domain) {
				my $msg = "Domain $id already exists";
				$logger->error($msg);
				return (-1, $msg);
			}
		}

		$domains{$id} = $new_domain;
	}

	foreach my $node ($topology->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("id");

		if (!defined $id or $id eq "") {
			my $msg = "Node with no id found";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (idIsFQ($id, "node") == 0) {
			my $msg = "Node with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}

		my ($status, $res) = validateNode($node);
		if ($status != 0) {
			my $msg = "Invalid node , $id, specified: $res";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $domain;
		my $new_node;
		my $old_node;

		($status, $res) = $self->lookupElement(idRemoveLevel($id), \%domains, \%nodes, \%ports, \%links);
		$domain = $res if ($status == 0);

		($status, $res) = $self->lookupElement($id, \%domains, \%nodes, \%ports, \%links);
		$old_node = $res if ($status == 0);

		if ($type eq "update") {
			if (!defined $old_node) {
				my $msg = "Node $id to update, but not found";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_node = mergeNodes_general($old_node, $node, \%comparison_attrs);
		} elsif ($type eq "replace") {
			$new_node = $node->cloneNode(1);
		} elsif ($type eq "add") {
			if (defined $old_node) {
				my $msg = "Node $id already exists";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_node = $node->cloneNode(1);
		}

		if (defined $domain) {
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
			return (-1, $msg);
		}

		if (idIsFQ($id, "port") == 0) {
			my $msg = "Port with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}

		my ($status, $res) = validatePort($port);
		if ($status != 0) {
			my $msg = "Invalid port , $id, specified: $res";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $node;
		my $old_port;
		my $new_port;

		($status, $res) = $self->lookupElement(idRemoveLevel($id), \%domains, \%nodes, \%ports, \%links);
		$node = $res if ($status == 0);

		($status, $res) = $self->lookupElement($id, \%domains, \%nodes, \%ports, \%links);
		$old_port = $res if ($status == 0);


		if ($type eq "update") {
			if (!defined $old_port) {
				my $msg = "Port $id to update, but not found";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_port = mergeNodes_general($old_port, $port, \%comparison_attrs);
		} elsif ($type eq "replace") {
			$new_port = $port->cloneNode(1);
		} elsif ($type eq "add") {
			if (defined $old_port) {
				my $msg = "Port $id already exists";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_port = $port->cloneNode(1);
		}

		if (defined $node) {
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
			return (-1, $msg);
		}

		if (idIsFQ($id, "link") == 0) {
			my $msg = "Link with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}

		my ($status, $res) = validateLink($link);
		if ($status != 0) {
			my $msg = "Invalid link , $id, specified: $res";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $port;
		my $old_link;
		my $new_link;

		($status, $res) = $self->lookupElement(idRemoveLevel($id), \%domains, \%nodes, \%ports, \%links);
		$port = $res if ($status == 0);

		($status, $res) = $self->lookupElement($id, \%domains, \%nodes, \%ports, \%links);
		$old_link = $res if ($status == 0);

		if ($type eq "update") {
			if (!defined $old_link) {
				my $msg = "Link $id to update, but not found";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_link = mergeNodes_general($old_link, $link, \%comparison_attrs);
		} elsif ($type eq "replace") {
			$new_link = $link->cloneNode(1);
		} elsif ($type eq "add") {
			if (defined $old_link) {
				my $msg = "Link $id already exists";
				$logger->error($msg);
				return (-1, $msg);
			}

			$new_link = $link->cloneNode(1);
		}

		if (defined $port) {
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
	foreach my $domain_id (keys %domains) {
		my $id = "domain_".$domain_id;

		# This is a hack to force the namespace declaration into the
		# node we're going to insert. A better solution would be to
		# have each node declare its namespace, but I'm not sure how to
		# finagle libxml into doing that.
		$domains{$domain_id}->unbindNode;
		$domains{$domain_id}->setNamespace($domains{$domain_id}->namespaceURI(), $domains{$domain_id}->prefix, 1);

		$self->{DATADB}->remove($id);

		if ($self->{DATADB}->insertIntoContainer($domains{$domain_id}->toString, $id) != 0) {
			my $msg = "Error updating $domain_id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	foreach my $node_id (keys %nodes) {
		my $id = "node_".$node_id;

		next if (defined $nodes{$node_id}->parentNode->parentNode);

		# if the element is top-level, it's parent is a document of
		# some type, but it's parent doesn't have a parent.
		$self->{DATADB}->remove($id);

		$nodes{$node_id}->unbindNode;
		$nodes{$node_id}->setNamespace($nodes{$node_id}->namespaceURI(), $nodes{$node_id}->prefix, 1);

		if ($self->{DATADB}->insertIntoContainer($nodes{$node_id}->toString, $id) != 0) {
			my $msg = "Error updating $node_id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	foreach my $port_id (keys %ports) {
		my $id = "port_".$port_id;

		next if (defined $ports{$port_id}->parentNode->parentNode);

		$ports{$port_id}->unbindNode;
		$ports{$port_id}->setNamespace($ports{$port_id}->namespaceURI(), $ports{$port_id}->prefix, 1);

		$self->{DATADB}->remove($id);

		if ($self->{DATADB}->insertIntoContainer($ports{$port_id}->toString, $id) != 0) {
			my $msg = "Error updating $port_id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	foreach my $link_id (keys %links) {
		my $id = "link_".$link_id;

		next if (defined $links{$link_id}->parentNode->parentNode);

		$self->{DATADB}->remove($id);

		$links{$link_id}->unbindNode;
		$links{$link_id}->setNamespace($links{$link_id}->namespaceURI(), $links{$link_id}->prefix, 1);

		if ($self->{DATADB}->insertIntoContainer($links{$link_id}->toString, $id) != 0) {
			my $msg = "Error updating $link_id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	foreach my $path ($topology->getChildrenByTagNameNS("*", "path")) {
		my $id = $path->getAttribute("id");
		if (!defined $id) {
			my $msg = "Error, no path id specified in given path";
			$logger->error($msg);
			return ("error.topology.invalid_topology", $msg);
		}

		$id = "path_".$id;

		$self->{DATADB}->remove($id);

		$path->unbindNode;
		$path->setNamespace($path->namespaceURI(), $path->prefix, 1);

		if ($self->{DATADB}->insertIntoContainer($path->toString, $id) != 0) {
			my $msg = "Error updating $id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	foreach my $network ($topology->getChildrenByTagNameNS("*", "network")) {
		my $id = $network->getAttribute("id");
		if (!defined $id) {
			my $msg = "Error, no network id specified in given network";
			$logger->error($msg);
			return ("error.topology.invalid_topology", $msg);
		}

		$id = "network_".$id;

		$self->{DATADB}->remove($id);

		$network->unbindNode;
		$network->setNamespace($network->namespaceURI(), $network->prefix, 1);

		if ($self->{DATADB}->insertIntoContainer($network->toString, $id) != 0) {
			my $msg = "Error updating $id";
			$logger->error($msg);
			return (-1, $msg);
		}
	}

	return (0, "");
}

sub lookupElement($$$$$$) {
        my ($self, $id, $domains, $nodes, $ports, $links) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology::Client::XMLDB");

	$logger->debug("Looking up element \"$id\"");

	my ($status, $domain_id, $node_id, $port_id, $link_id) = idSplit($id, 1);
	if ($status != 0) {
		my $msg = "Invalid id: $id";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (defined $link_id) {
		if (defined $links->{$link_id}) {
			return (0, $links->{$link_id});
		} else {
			my ($status, $res) = $self->lookupElement($port_id, $domains, $nodes, $ports, $links);
			my $link;
			if ($status != 0) {
				my $error;
				my $doc = $self->{DATADB}->getDocumentByName("link_".$link_id, \$error);
				if ($error ne "") {
					my $msg = "Link $link_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 

				my $parser = XML::LibXML->new();
				my $pdoc = $parser->parse_string($doc);
				$link = $pdoc->getDocumentElement;
			} else {
				my $parent = $res;

				foreach my $curr_link ($parent->getChildrenByTagNameNS("*", "link")) {
					if ($curr_link->getAttribute("id") eq $link_id) {
						$link = $curr_link;
						last;
					}
				}

				if (!defined $link) {
					my $msg = "Link $link_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 
			}

			$links->{$link_id} = $link;

			return (0, $link);
		}
	}

	if (defined $port_id) {
		if (defined $ports->{$port_id}) {
			return (0, $ports->{$port_id});
		} else {
			my ($status, $res) = $self->lookupElement($node_id, $domains, $nodes, $ports, $links);
			my $port;
			if ($status != 0) {
				my $error;
				my $doc = $self->{DATADB}->getDocumentByName("port_".$port_id, \$error);

				if ($error ne "") {
					my $msg = "Port $port_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 

				my $parser = XML::LibXML->new();
				my $pdoc = $parser->parse_string($doc);
				$port = $pdoc->getDocumentElement;
			} else {
				my $parent = $res;

				foreach my $curr_port ($parent->getChildrenByTagNameNS("*", "port")) {
					if ($curr_port->getAttribute("id") eq $port_id) {
						$port = $curr_port;
						last;
					}
				}

				if (!defined $port) {
					my $msg = "Port $port_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 

			}

			$ports->{$port_id} = $port;

			return (0, $port);
		}
	}

	if (defined $node_id) {
		if (defined $nodes->{$node_id}) {
			return (0, $nodes->{$node_id});
		} else {
			my ($status, $res) = $self->lookupElement($domain_id, $domains, $nodes, $ports, $links);
			my $node;
			if ($status != 0) {
				my $error;
				my $doc = $self->{DATADB}->getDocumentByName("node_".$node_id, \$error);

				if ($error ne "") {
					my $msg = "Node $node_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 

				my $parser = XML::LibXML->new();
				my $pdoc = $parser->parse_string($doc);
				$node = $pdoc->getDocumentElement;
			} else {
				my $parent = $res;

				foreach my $curr_node ($parent->getChildrenByTagNameNS("*", "node")) {
					if ($curr_node->getAttribute("id") eq $node_id) {
						$node = $curr_node;
						last;
					}
				}

				if (!defined $node) {
					my $msg = "Node $node_id not found";
					$logger->error($msg);
					return (-1, $msg);
				} 
			}

			$nodes->{$node_id} = $node;

			return (0, $node);
		}
	}

	if (defined $domain_id) {
		if (defined $domains->{$domain_id}) {
			return (0, $domains->{$domain_id});
		} else {
			my $error;
			my $doc = $self->{DATADB}->getDocumentByName("domain_".$domain_id, \$error);

			if ($error ne "") {
				my $msg = "Domain $domain_id not found";
				$logger->error($msg);
				return (-1, $msg);
			} 

			my $parser = XML::LibXML->new();
			my $pdoc = $parser->parse_string($doc);
			my $domain = $pdoc->getDocumentElement;

			$domains->{$domain_id} = $domain;

			return (0, $domain);
		}
	}

	return (-1, "It should never get here");
}

1;

__END__

=head1 NAME

perfSONAR_PS::MA::Topology::Client::XMLDB - A module that provides methods for
interacting with a Topology MA database directly.

=head1 DESCRIPTION

This module allows one to interact with the Topology MA XMLDB Backend directly
using a standard set of methods.  interface. The API provided is identical to
the API for interacting with the MAs via its Web Serviecs interface. Thus, a
client written to read from or update a Topology MA can be easily modified to
interact directly with its underlying database allowing more efficient
interactions if required.

The module is to be treated as an object, where each instance of the object
represents a connection to a single database. Each method may then be invoked
on the object for the specific database.  

=head1 SYNOPSIS

=head1 DETAILS

=head1 API

The API for perfSONAR_PS::MA::Topology::Client::MA is rather simple and greatly
resembles the messages types received by the server. It is also identical to
the perfSONAR_PS::MA::Topology::Client::SQL API allowing easy construction of
programs that can interface via the MA server or directly with the database.

=head2 new($package, $uri_string)

The new function takes a URI connection string as its first argument. This
specifies which MA to interact with.

=head2 open($self)

The open function could be used to open a persistent connection to the MA.
However, currently, it is simply a stub function.

=head2 close($self)

The close function could close a persistent connection to the MA. However,
currently, it is simply a stub function.

=head2 setURIString($self, $uri_string)

The setURIString function changes the MA that the instance uses.

=head2 dbIsOpen($self)

This function is a stub function that always returns 1.

=head2 getURIString($)

The getURIString function returns the current URI string

=head2 getAll($self)

The getAll function gets the full contents of the database. It returns the
results as a ref to a LibXML element pointing to the <nmtopo:topology>
structure containing the contents of the database. 

=head2 xQuery($self, $xquery)

The xQuery function performs an xquery on the specified database. It returns
the results as a string.

=head1 SEE ALSO

L<perfSONAR_PS::MA::Topology::Client::MA>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=


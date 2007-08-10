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
		return ("error.topology.ma", "Couldn't query database: $error");
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
		my $fqid;

		if (!defined $id or $id eq "") {
			my $msg = "Domain with no id found";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (idIsFQ($id) != 0) {
			$id = idBaseLevel($id);
			$fqid = $id;
		} else {
			$fqid = idConstruct($id);
		}

		my $new_domain;
		my $old_domain = $self->lookupDomain($id, \%domains);

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

		$domains{$fqid} = $new_domain;
	}

	foreach my $node ($topology->getChildrenByTagNameNS("*", "node")) {
		my $id = $node->getAttribute("id");
		if (!defined $id or $id eq "") {
			my $msg = "Node with no id found";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (idIsFQ($id) == 0) {
			my $msg = "Node with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}



		my $domain_id = idRemoveLevel($id);

		my $domain = $self->lookupDomain($domain_id, \%domains);
		if (!defined $domain) {
			my $msg = "Domain $domain_id for node $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $basename = idBaseLevel($id);

		my $new_node;
		my $old_node = $domain->find("./*[local-name()=\'node\' and \@id='$basename']")->get_node(1);

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
			return (-1, $msg);
		}

		if (idIsFQ($id) == 0) {
			my $msg = "Port with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}


		my $node_id = idRemoveLevel($id);
		my $domain_id = idRemoveLevel($node_id);

		my $domain = $self->lookupDomain($domain_id, \%domains);
		if (!defined $domain) {
			my $msg = "Domain $domain_id for node $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $node = $self->lookupNode($domain, $node_id, \%nodes);

		if (!defined $node) {
			my $msg = "Node $node_id for port $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $basename = idBaseLevel($id);

		my $new_port = $port->cloneNode(1);
		my $old_port = $node->find("./*[local-name()=\'port\' and \@id='$basename']")->get_node(1);

		if ($type eq "update") {
			if (!defined $old_port) {
				my $msg = "Node $id to update, but not found";
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
			return (-1, $msg);
		}

		if (idIsFQ($id) == 0) {
			my $msg = "Link with non-fully qualified id, $id, is specified at top-level";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $port_id = idRemoveLevel($id);
		my $node_id = idRemoveLevel($id);
		my $domain_id = idRemoveLevel($node_id);

		my $domain = $self->lookupDomain($domain_id, \%domains);
		if (!defined $domain) {
			my $msg = "Domain $domain_id for node $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $node = $self->lookupNode($domain, $node_id, \%nodes);
		if (!defined $node) {
			my $msg = "Node $node_id for link $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $port = $self->lookupPort($node, $port_id, \%ports);
		if (!defined $port) {
			my $msg = "Port $port_id for link $id not found";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $basename = idBaseLevel($id);

		my $new_link;
		my $old_link = $link->find("./*[local-name()=\'link\' and \@id='$basename']")->get_node(1);

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
		my $id = "domain_".idBaseLevel($fq_domain_id);

		$self->{DATADB}->remove($id);

		if ($self->{DATADB}->insertIntoContainer($domains{$fq_domain_id}->toString, $id) != 0) {
			my $msg = "Error updating $fq_domain_id";
			$logger->error($msg);
			return ("error.topology.ma", $msg);
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

		if ($self->{DATADB}->insertIntoContainer($path->toString, $id) != 0) {
			my $msg = "Error updating $id";
			$logger->error($msg);
			return ("error.topology.ma", $msg);
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

		if ($self->{DATADB}->insertIntoContainer($network->toString, $id) != 0) {
			my $msg = "Error updating $id";
			$logger->error($msg);
			return ("error.topology.ma", $msg);
		}
	}

	return (0, "");
}

sub lookupDomain($$$) {
        my ($self, $id, $domains) = @_;

        if (idIsFQ($id) != 0) {
                $id = idBaseLevel($id);
        }

        if (!defined $domains->{$id}) {
                my ($status, $doc) = $self->{DATADB}->getDocumentByName("domain_".$id);

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


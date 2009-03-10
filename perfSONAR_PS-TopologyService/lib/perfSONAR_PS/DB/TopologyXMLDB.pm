package perfSONAR_PS::DB::TopologyXMLDB;

use strict;
use warnings;

use fields 'READ_ONLY', 'DB_OPEN', 'DB_NAMESPACES', 'DB_FILE', 'DB_CONTAINER', 'DATADB', 'LOGGER', 'INITIALIZED';

=head1 NAME

perfSONAR_PS::DB::TopologyXMLDB - A module that provides methods for querying
and modifying a topology database.

=head1 DESCRIPTION

This module provides methods to interact with a topology database. This allows
querying as well as updating the database. 

interacting with the Sleepycat [Oracle] XML database.  The module is to be
treated as an object, where each instance of the object represents a direct
connection to a single database and collection. Each method may then be
invoked on the object for the specific database.  

=cut
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::Common;
use perfSONAR_PS::Topology::Common;
use perfSONAR_PS::Topology::ID;

our $VERSION = 0.09;

sub new {
    my ($class) = @_;

    my $self = fields::new($package);

    $self->{LOGGER} = get_logger($class);

    return $self;
}

sub init {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { directory => 1, file => 1, namespaces => 0, read_only => 0 } );

    my $db_container = $parameters->{directory};
    my $db_file = $parameters->{file};
    my $ns = $parameters->{namespaces};
    my $read_only = $parameters->{read_only};

    if ($read_only) {
        $self->{READ_ONLY} = 1;
    } else {
        $self->{READ_ONLY} = 0;
    }

    if ($db_container) {
        $self->{DB_CONTAINER} = $db_container;
    }

    if ($db_file) {
        $self->{DB_FILE} = $db_file;
    }

    if ($ns) {
        $self->{DB_NAMESPACES} = $ns;
    } else {
        my %ns = getTopologyNamespaces();
        $self->{DB_NAMESPACES} = \%ns;
    }

    $self->{DB_OPEN} = 0;
    $self->{DATADB} = "";
    $self->{INITIALIZED} = 1;

    return $self;
}

sub open {
    my ($self) = @_;

    return (-1, "Database not initialized") unless ($self->{INITIALIZED});

    return (0, "") if ($self->{DB_OPEN} != 0);

    $self->{DATADB} = perfSONAR_PS::DB::XMLDB->new({  env => $self->{DB_CONTAINER}, cont => $self->{DB_FILE}, ns => $self->{DB_NAMESPACES} });
    unless ($self->{DATADB}) {
        my $msg = "Couldn't open specified database";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $error;
    my $status = $self->{DATADB}->openDB({ txn => undef, error => \$error });
    if ($status == -1) {
        my $msg = "Couldn't open specified database: $error";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    $self->{DB_OPEN} = 1;

    return (0, "");
}

sub close {
    my ($self) = @_;

    return 0 if ($self->{DB_OPEN} == 0);

    $self->{DB_OPEN} = 0;

    return $self->{DATADB}->closeDB;
}

sub dbIsOpen {
    my ($self) = @_;

    return $self->{DB_OPEN};
}

sub setDBContainer {
    my ($self, $container) = @_;

    $self->{DB_CONTAINER} = $container;
    $self->close;

    return;
}

sub setDBFile {
    my ($self, $file) = @_;

    $self->{DB_FILE} = $file;
    $self->close;

    return;
}

sub setDBNamespaces {
    my ($self, $namespaces) = @_;

    $self->{DB_NAMESPACES} = $namespaces;

    if ($self->{DB_OPEN}) {
        $self->{DATADB}->setNamespaces({ ns => $namespaces });
    }

    return;
}

sub xQuery {
    my($self, $xquery) = @_;
    my $localContent = "";
    my $error;

    return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

    $xquery =~ s/\s{1}\// collection('CHANGEME')\//g;

    my @queryResults = $self->{DATADB}->query({ query => $xquery, txn => undef, error => \$error });
    if ($error ne "") {
        $self->{LOGGER}->error("Couldn't query database");
        return (-1, "Couldn't query database: $error");
    }

    $localContent .= "<nmtopo:topology xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20080828/\">\n";
    $localContent .= join("", @queryResults);
    $localContent .= "</nmtopo:topology>\n";

    return (0, $localContent);
}

sub getAll {
    my($self) = @_;
    my @results;
    my $error;

    return (-1, "Database not open") if ($self->{DB_OPEN} == 0);

    @results = $self->{DATADB}->query({ query => "//*", txn => undef, error => \$error });
    if ($error ne "") {
        my $msg = "Couldn't get list of domains from database: $error";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $content = "";

    $content .= "<nmtopo:topology xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20080828/\">\n";

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
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    return (0, $topology);
}

sub changeTopology {
    my ($self, $type, $topology) = @_;
    my ($status, $res);

    $self->{LOGGER}->debug("Topology: ".$topology->toString);

    return (-1, "Database not open") if ($self->{DB_OPEN} == 0);

    return (-1, "Database is Read-Only") if ($self->{READ_ONLY} == 1);

    my %comparison_attrs = (
            link => ( id => '' ),
            node => ( id => '' ),
            port => ( id => '' ),
            domain => ( id => '' ),
            path => ( id => '' ),
            network => ( id => '' ),
            );

    if ($type ne "update" and $type ne "replace" and $type ne "add") {
        my $msg = "Invalid topology change specified: $type";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my @namespaces = $topology->getNamespaces();

    my %elements = ();

    my %domain_ids = ();

    my $find_res;

    $find_res = find($topology, "./*[local-name()='domain']", 0);
    if ($find_res) {
        foreach my $domain ($find_res->get_nodelist) {
            my $id = $domain->getAttribute("id");

            $self->{LOGGER}->debug("Got a request for domain: $id");

            if (not defined $id or $id eq "") {
                my $msg = "Domain with no id found";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            if (idIsFQ($id, "domain") == 0) {
                my $msg = "Domain with non-fully qualified id, $id, is specified";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my ($status, $res) = validateDomain($domain, \%domain_ids);
            if ($status != 0) {
                my $msg = "Invalid domain, $id, specified: $res";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my $new_domain;
            my $old_domain;

            ($status, $res) = $self->lookupElement($id, \%elements);
            $old_domain = $res if ($status == 0);

            if ($type eq "update") {
                if (not defined $old_domain) {
                    my $msg = "Domain $id to update, but not found";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_domain = mergeNodes_general($old_domain, $domain, \%comparison_attrs);
            } elsif ($type eq "replace") {
                $new_domain = $domain->cloneNode(1);
            } elsif ($type eq "add") {
                if (defined $old_domain) {
                    my $msg = "Domain $id already exists";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_domain = $domain->cloneNode(1);
            }

            $elements{$id} = $new_domain;
        }
    }

    my %node_ids = ();

    $find_res = find($topology, "./*[local-name()='node']", 0);
    if ($find_res) {
        foreach my $node ($find_res->get_nodelist) {
            my $id = $node->getAttribute("id");

            if (not defined $id or $id eq "") {
                my $msg = "Node with no id found";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            if (idIsFQ($id, "node") == 0) {
                my $msg = "Node with non-fully qualified id, $id, is specified at top-level";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my ($status, $res) = validateNode($node, \%node_ids, "");
            if ($status != 0) {
                my $msg = "Invalid node , $id, specified: $res";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my $domain;
            my $new_node;
            my $old_node;

            ($status, $res) = $self->lookupElement(idRemoveLevel($id, ""), \%elements);
            $domain = $res if ($status == 0);

            ($status, $res) = $self->lookupElement($id, \%elements);
            $old_node = $res if ($status == 0);

            if ($type eq "update") {
                if (not defined $old_node) {
                    my $msg = "Node $id to update, but not found";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_node = mergeNodes_general($old_node, $node, \%comparison_attrs);
            } elsif ($type eq "replace") {
                $new_node = $node->cloneNode(1);
            } elsif ($type eq "add") {
                if (defined $old_node) {
                    my $msg = "Node $id already exists";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_node = $node->cloneNode(1);
            }

            if (defined $domain) {
                if (defined $old_node) {
                    $old_node->replaceNode($new_node);
                } else {
                    replaceChild($domain, "domain", $new_node, $id);
                }
            }

            $elements{$id} = $new_node;
        }
    }

    my %port_ids = ();

    $find_res = find($topology, "./*[local-name()='port']", 0);
    if ($find_res) {
        foreach my $port ($find_res->get_nodelist) {
            my $id = $port->getAttribute("id");

            if (not defined $id or $id eq "") {
                my $msg = "Port with no id found";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            if (idIsFQ($id, "port") == 0) {
                my $msg = "Port with non-fully qualified id, $id, is specified at top-level";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my ($status, $res) = validatePort($port, \%port_ids, "");
            if ($status != 0) {
                my $msg = "Invalid port , $id, specified: $res";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my $node;
            my $old_port;
            my $new_port;

            ($status, $res) = $self->lookupElement(idRemoveLevel($id, ""), \%elements);
            $node = $res if ($status == 0);

            ($status, $res) = $self->lookupElement($id, \%elements);
            $old_port = $res if ($status == 0);


            if ($type eq "update") {
                if (not defined $old_port) {
                    my $msg = "Port $id to update, but not found";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_port = mergeNodes_general($old_port, $port, \%comparison_attrs);
            } elsif ($type eq "replace") {
                $new_port = $port->cloneNode(1);
            } elsif ($type eq "add") {
                if (defined $old_port) {
                    my $msg = "Port $id already exists";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_port = $port->cloneNode(1);
            }

            if (defined $node) {
                if (defined $old_port) {
                    $old_port->replaceNode($new_port);
                } else {
                    replaceChild($node, "node", $new_port, $id);
                }
            }

            $elements{$id} = $new_port;
        }
    }

    my %link_ids = ();

    $find_res = find($topology, "./*[local-name()='link']", 0);
    if ($find_res) {
        foreach my $link ($find_res->get_nodelist) {
            my $id = $link->getAttribute("id");
            if (not defined $id or $id eq "") {
                my $msg = "Link with no id found";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            if (idIsFQ($id, "link") == 0) {
                my $msg = "Link with non-fully qualified id, $id, is specified at top-level";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my ($status, $res) = validateLink($link, \%link_ids, "");
            if ($status != 0) {
                my $msg = "Invalid link , $id, specified: $res";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            my $port;
            my $old_link;
            my $new_link;

            ($status, $res) = $self->lookupElement(idRemoveLevel($id, ""), \%elements);
            $port = $res if ($status == 0);

            ($status, $res) = $self->lookupElement($id, \%elements);
            $old_link = $res if ($status == 0);

            if ($type eq "update") {
                if (not defined $old_link) {
                    my $msg = "Link $id to update, but not found";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_link = mergeNodes_general($old_link, $link, \%comparison_attrs);
            } elsif ($type eq "replace") {
                $new_link = $link->cloneNode(1);
            } elsif ($type eq "add") {
                if (defined $old_link) {
                    my $msg = "Link $id already exists";
                    $self->{LOGGER}->error($msg);
                    return (-1, $msg);
                }

                $new_link = $link->cloneNode(1);
            }

            if (defined $port) {
                if (defined $old_link) {
                    $old_link->replaceNode($new_link);
                } else {
                    replaceChild($port, "port", $new_link, $id);
                }
            }

            $elements{$id} = $new_link;
        }
    }

    $self->{LOGGER}->debug("Elements: ".Dumper(\%elements));

    my $error;

    my $dbTr = $self->{DATADB}->getTransaction( { error => \$error } );
    unless ($dbTr) {
        my $msg = "Cound not start database transaction, database responded with \"" . $error . "\".";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    # update everything that is sitting at the top-level
    foreach my $id (keys %elements) {
        next if (defined $elements{$id}->parentNode->parentNode);

        $self->{LOGGER}->debug("Inserting $id");

        # This is a hack to force the namespace declaration into the
        # node we're going to insert. A better solution would be to
        # have each node declare its namespace, but I'm not sure how to
        # finagle libxml into doing that.
        $elements{$id}->unbindNode;
        $elements{$id}->setNamespace($elements{$id}->namespaceURI(), $elements{$id}->prefix, 1);

        $self->{DATADB}->remove({ name => $id });

        if ($self->{DATADB}->insertIntoContainer({ content => $elements{$id}->toString, name => $id, txn => $dbTr, error => \$error }) != 0) {
            $self->{DATADB}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            $self->{DATADB}->checkpoint( { error => \$error } );
            $self->{DATADB}->closeDB( { error => \$error } );

            my $msg = "Error updating $id: $error";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }
    }

    $status = $self->{DATADB}->commitTransaction( { txn => $dbTr, error => \$error } );
    if ( $status != 0 ) {
        $self->{DATADB}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        $self->{DATADB}->checkpoint( { error => \$error } );
        $self->{DATADB}->closeDB( { error => \$error } );

        my $msg = "Database Error: \"" . $error . "\".";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    $self->{DATADB}->checkpoint( { error => \$error } );
    $self->{DATADB}->closeDB( { error => \$error } );

    return (0, "");
}

sub lookupElement {
    my ($self, $id, $elements) = @_;

    $self->{LOGGER}->debug("Looking up element \"$id\"");

    my @res = idSplit($id, 1, 0);
    if ($res[0] != 0) {
        my $msg = "Invalid id: $id";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $base_type = $res[1];
    my $base_id = $res[3];
    my $parent_id = $res[5];

    if (defined $elements->{$base_id}) {
        return (0, $elements->{$base_id});
    }

    my $parent;

    if (defined $parent_id) {
        my ($status, $res) = $self->lookupElement($parent_id, $elements);
        if ($status == 0) {
            $parent = $res;
        }
    }

    if (not defined $parent_id or not defined $parent) {
        my $error;
        if (not defined $parent_id) {
            $self->{LOGGER}->debug("Parent not found");
        } else {
            $self->{LOGGER}->debug("Parent '$parent_id' Not Found");
        }

        my $doc = $self->{DATADB}->getDocumentByName({ name => $base_id, txn => undef, error => \$error });
        if ($error ne "" or $doc eq "") {
            my $msg = "Element ".$base_id." not found";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $parser = XML::LibXML->new();
        my $pdoc = $parser->parse_string($doc);
        my $elm = $pdoc->getDocumentElement;

        $elements->{$base_id} = $elm;

        return (0, $elm);
    } else {
        $self->{LOGGER}->debug("Parent: $parent_id Found");

        my $find_res = find($parent, "./*[local-name()='$base_type']", 0);
        if ($find_res) {
            foreach my $curr_elm ($find_res->get_nodelist) {
                if ($curr_elm->getAttribute("id") eq $base_id) {
                    $elements->{$base_id} = $curr_elm;

                    return (0, $curr_elm);
                }
            }
        }

        my $msg = "Element ".$base_id." not found";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    return (-1, "It should never get here");
}

1;

__END__

=head1 NAME

perfSONAR_PS::DB::TopologyXMLDB - A module that provides methods for
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

The API for perfSONAR_PS::Client::Topology::MA is rather simple and greatly
resembles the messages types received by the server. It is also identical to
the perfSONAR_PS::Client::Topology::SQL API allowing easy construction of
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

    L<perfSONAR_PS::Client::Topology::MA>, L<Log::Log4perl>

    To join the 'perfSONAR-PS' mailing list, please visit:

    https://mail.internet2.edu/wws/info/i2-perfsonar

    The perfSONAR-PS subversion repository is located at:

    https://svn.internet2.edu/svn/perfSONAR-PS 

    Questions and comments can be directed to the author, or the mailing list. 

    =head1 VERSION

    $Id$

    =head1 AUTHOR

    Aaron Brown, aaron@internet2.edu

    =head1 LICENSE

    You should have received a copy of the Internet2 Intellectual Property Framework along
    with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

    =head1 COPYRIGHT

    Copyright (c) 2004-2009, Internet2 and the University of Delaware

    All rights reserved.

    =cut

# vim: expandtab shiftwidth=4 tabstop=4

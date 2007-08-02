#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology::Client::XMLDB;

use strict;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::DB::XMLDB;
use Data::Dumper;

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


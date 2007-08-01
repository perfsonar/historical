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

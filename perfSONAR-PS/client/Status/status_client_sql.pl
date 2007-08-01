#!/usr/bin/perl -w -I ../lib

use strict;
use Log::Log4perl qw(get_logger :levels);

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");
$logger->level($DEBUG);

use perfSONAR_PS::MA::Status::Client::SQL;

my $status_client = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=status.db");
if (!defined $status_client) {
	print "Problem creating client for status MA\n";
	exit(-1);
}

my ($status, $res) = $status_client->open;
if ($status != 0) {
	print "Problem opening status MA: $res\n";
	exit(-1);
}

($status, $res) = $status_client->getAll();
if ($status != 0) {
	print "Problem getting complete database: $res\n";
	exit(-1);
}

my @links = (); 

foreach my $id (keys %{ $res }) {
	print "Link ID: $id\n";

	foreach my $link ( @{ $res->{$id} }) {
		print "\t" . $link->getStartTime . " - " . $link->getEndTime . "\n";
		print "\t-Knowledge Level: " . $link->getKnowledge . "\n";
		print "\t-operStatus: " . $link->getOperStatus . "\n";
		print "\t-adminStatus: " . $link->getAdminStatus . "\n";
	}

	push @links, $id;
}

($status, $res) = $status_client->getLastLinkStatus(\@links);
if ($status != 0) {
	print "Problem obtaining most recent link status: $res\n";
	exit(-1);
}

foreach my $id (keys %{ $res }) {
	print "Link ID: $id\n";

	foreach my $link ( @{ $res->{$id} }) {
		print "-operStatus: " . $link->getOperStatus . "\n";
		print "-adminStatus: " . $link->getAdminStatus . "\n";
	}
}

($status, $res) = $status_client->getLinkHistory(\@links);
if ($status != 0) {
	print "Problem obtaining link history: $res\n";
	exit(-1);
}

foreach my $id (keys %{ $res }) {
	print "Link ID: $id\n";

	foreach my $link ( @{ $res->{$id} }) {
		print "-operStatus: " . $link->getOperStatus . "\n";
		print "-adminStatus: " . $link->getAdminStatus . "\n";
	}
}

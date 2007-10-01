#!/usr/bin/perl -w

use strict;
use Log::Log4perl qw(get_logger :levels);
use File::Basename;

my $dirname;
my $libdir;

# we need to figure out what the library is at compile time so that "use lib"
# doesn't fail. To do this, we enclose the calculation of it in a BEGIN block.
BEGIN {
	$dirname = dirname($0);
	$libdir = $dirname."/../lib";
}

use lib "$libdir";
use perfSONAR_PS::MA::Status::Client::SQL;

Log::Log4perl->init($dirname."/../logger.conf");
my $logger = get_logger("perfSONAR_PS");
$logger->level($DEBUG);

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
	$logger->info("Link ID: $id");

	foreach my $link ( @{ $res->{$id} }) {
		$logger->info("\t" . $link->getStartTime . " - " . $link->getEndTime . "");
		$logger->info("\t-Knowledge Level: " . $link->getKnowledge . "");
		$logger->info("\t-operStatus: " . $link->getOperStatus . "");
		$logger->info("\t-adminStatus: " . $link->getAdminStatus . "");
	}

	push @links, $id;
}

($status, $res) = $status_client->getLinkStatus(\@links, "");
if ($status != 0) {
	$logger->info("Problem obtaining most recent link status: $res");
	exit(-1);
}

foreach my $id (keys %{ $res }) {
	$logger->info("Link ID: $id");

	foreach my $link ( @{ $res->{$id} }) {
		$logger->info("-operStatus: " . $link->getOperStatus . "");
		$logger->info("-adminStatus: " . $link->getAdminStatus . "");
	}
}

($status, $res) = $status_client->getLinkHistory(\@links);
if ($status != 0) {
	$logger->info("Problem obtaining link history: $res");
	exit(-1);
}

my $min = 0;
my $max = 0;

foreach my $id (keys %{ $res }) {
	$logger->info("Link ID: $id");

	foreach my $link ( @{ $res->{$id} }) {
		$min = $link->getStartTime if ($link->getStartTime < $min or $min == 0);
		$max = $link->getEndTime if ($link->getStartTime < $min or $max == 0);

		$logger->info("-operStatus: " . $link->getOperStatus . "");
		$logger->info("-adminStatus: " . $link->getAdminStatus . "");
	}
}

my $time = int($min + ($max - $min) / 2);

($status, $res) = $status_client->getLinkStatus(\@links, $time);
if ($status != 0) {
	$logger->info("Problem obtaining link history: $res");
	exit(-1);
}

foreach my $id (keys %{ $res }) {
	$logger->info("Link ID: $id($time)");

	foreach my $link ( @{ $res->{$id} }) {
		$logger->info("-Range: ".$link->getStartTime."-".$link->getEndTime."");
		$logger->info("-operStatus: " . $link->getOperStatus . "");
		$logger->info("-adminStatus: " . $link->getAdminStatus . "");
	}
}

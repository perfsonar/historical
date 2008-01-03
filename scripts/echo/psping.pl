#!/usr/bin/perl

use Time::HiRes qw( gettimeofday tv_interval );

use perfSONAR_PS::Client::Echo;

my $uri = shift;
my $eventType = shift;

if (!defined $uri or $uri eq "-h") {
	print "Usage: psping [-h] SERVICE_URI [ECHO_EVENT_TYPE]\n";
	exit(-1);
}

my $echo_client = perfSONAR_PS::Client::Echo->new($uri, $eventType);
if (!defined $echo_client) {
	print "Problem creating echo client for service\n";
	exit(-1);
}

my ($stime, $etime);

$stime = [gettimeofday];

my ($status, $res) = $echo_client->ping();
if ($status != 0) {
	print "Service $uri is down: $res\n";
	exit(-1);
}

$etime = [gettimeofday];

$elapsed = tv_interval($stime, $etime);

print "Service $uri is up\n";
print "-Time to make request: $elapsed\n";

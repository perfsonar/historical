use Time::HiRes qw( gettimeofday tv_interval );

use perfSONAR_PS::Client::Echo;

my $uri = shift;

my $echo_client = new perfSONAR_PS::Client::Echo($uri);
if (!defined $echo_client) {
	print "Problem creating echo client for service\n";
	exit(-1);
}

my ($stime, $etime);

$stime = [gettimeofday];

my ($status, $res) = $echo_client->ping;
if ($status != 0) {
	print "Service $uri is down: $res\n";
	exit(-1);
}

$etime = [gettimeofday];

$elapsed = tv_interval($stime, $etime);

print "Service $uri is up\n";
print "-Time to make request: $elapsed\n";

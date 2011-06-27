#!/usr/bin/perl

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Services::MP::TracerouteTest;
use perfSONAR_PS::Services::MP::TracerouteSender;

my $tr = perfSONAR_PS::Services::MP::TracerouteTest->new(600, '/var/lib/perfsonar/traceroute_ma',
                {"max_ttl" => 40, "host" => $ARGV[0], 'source_address' => '198.129.226.155',
                "timeout" => 15 , "protocol" => "udp"});

$tr->run();

my @ma_urls = ('http://localhost:8081/perfSONAR_PS/services/tracerouteCollector');
my $tr_send = perfSONAR_PS::Services::MP::TracerouteSender->new(\@ma_urls, 10, '/var/lib/perfsonar/traceroute_ma');
$tr_send->run();
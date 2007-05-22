#!/bin/env perl

use gmaps::MA::RRDMA;

my $ma = $ARGV[0];
my $port = $ARGV[1];
my $endpoint = $ARGV[2];
my $event = $ARGV[3];

if ( ! defined $ma ) {
print "usage:  <server> <port> <endpoint> <eventType>\n";
exit;
}


my $routers = &gmaps::MA::RRDMA::getAllRouters( 
		$ma, $port, $endpoint, $event );
		
foreach my $r ( @$routers ) {
	print "$r\n";
}

exit;

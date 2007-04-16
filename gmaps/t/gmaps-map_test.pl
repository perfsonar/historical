#!/usr/bin/perl -I ../cgi/

use gmaps;

# get from raw
my $in = "@ARGV";

my $routers = gmaps::getRouters( undef, $in );

foreach $r ( @$routers ) {
	print "ROUTER: $r\n";
}

my $marks = &gmaps::getCoords( $routers );

foreach my $m ( @marks ) {
	print $m->{ip} . ": " . $m->{lat} . ',' . $m->{long} . "\n";
}

my $out = gmaps::createXml( undef, @$routers );

print $out;

1;
#!/bin/env perl

use gmaps::Topology;


my ( $ip, $dns ) = gmaps::Topology::getDNS( $ARGV[0] );

print "$ARGV[0] -> $ip, $dns\n";

1;
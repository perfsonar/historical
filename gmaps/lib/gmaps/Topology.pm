#!/bin/env perl

#######################################################################
# Topology module to get topology information
#######################################################################
use gmaps::Topology::GeoIP;
use gmaps::Topology::DNSLoc;

package gmaps::Topology;

use Socket;
use strict;


sub getDNS
{
	my $ip = shift;
	my $dns = undef;

	# ip is actual ip, get the dns
	if ( &isIpAddress( $ip ) ) {
		$dns = gethostbyaddr(inet_aton($ip), AF_INET);
		if ( ! defined $dns ) {
			return ( $ip, undef );
		}
	}
	# ip is dns, get the ip
	else {
		$dns = $ip;
		my $i = inet_aton($dns);

		if ( $i ne '' ) {
			$ip = inet_ntoa( $i );
		}
		else {
			warn "DUNNO! $dns, $i\n";
			return ( undef, $dns );
		}
	}

	return ( $ip, $dns );
}

sub isIpAddress
{
	my $ip = shift;
	if ( $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
		$ip = $1 . '.' . $2 . '.'  .$3 . '.' . $4;
		return undef if  ( $1 > 255 || $2 > 255 || $3 > 255 || $4 > 255 );
		return $ip;
	}
	return undef;
}


# determines the coordinates fo the routers provided
sub getCoords
{
	my $routers = shift;
	my $loc = shift;
	
	my @marks = ();
	my %seen = ();

	# find out the lat longs for each router
	for( my $i=0; $i<scalar(@$routers); $i++ )
	{
	
		# find out lat and long for router
		my $ip = undef;
		my $dns = undef;
		
		my $long = undef;
		my $lat = undef;

		( $ip, $dns ) = &getDNS( $routers->[$i] );

		next if ! defined $ip;

  			if ( $loc ne '' ) {
				my $module = 'gmaps::Topology::' . $loc . '::getLatLong';		
				( $lat, $long ) = &$module( $dns );
			}
			else {
				# try the dnslocators, if failed, use geoiptool
				( $lat, $long ) = &gmaps::Topology::DNSLoc::getLatLong( $dns );
			
				if ( ! defined $long && ! defined $lat ) {
					( $lat, $long ) = &gmaps::Topology::GeoIP::getLatLong( $ip );
				}
				
				# if no lat long exists, set it inside of the bermuda triangel :)
				if ( ! defined $long && ! defined $lat ) {
					$lat = '26.511129';
					$long = '-71.48186';
				}
			}
		
		#print $routers->[$i] . "/$ip/$dns/$i = LAT: $lat, LONG: $long\n";
		
		my %mark = (
				'dns'  => $dns,
				'ip'   => $ip,
				'lat'  => $lat,
				'long' => $long,
			);
		
		# keep a tally of same coords, keep an array of which ones by index
		my $coords = $lat . ',' . $long;
		push @{$seen{$coords}}, $i;
	
		# add to list
		push @marks, \%mark;
		
	} # foreach router

	# lets make sure that we don't overlap any nodes by checking the lat longs
	# for each.
	# use the indexes as reference to the node in the future for modifcations
	# and create a circle of the nodes around the epicenter of the coords

	# radius factor controls the distance from epicenter
	my $radius = 0.001;
	foreach my $c (keys %seen)
	{
		my @indexes = @{$seen{$c}};
		my $nodesAtSameCoords = scalar @indexes;

		next if $nodesAtSameCoords == 1;
		next if $c eq ',';
		
		my $n = 1;
		foreach my $i (@indexes) {
			# create a cirle around the coords, with each node at 360/$nodesAtSameCoords degrees
			# from each other
			my $angle = 360 / ( $nodesAtSameCoords / $n );
			$marks[$i]->{lat} = $marks[$i]->{lat} + ($radius * sin( $angle ));
			$marks[$i]->{long} = $marks[$i]->{long} + ($radius * cos( $angle ));
			$n++;
		}
	}

	return \@marks;
}


sub markOkay
{
	my $thisMark = shift;
	if ( $thisMark->{'lat'} =~ /^26.51/ && $thisMark->{'long'} =~ /^-71.48/ ) {
		return 0;
	}
	return 1;
}

sub getLines
{
	my $marks = shift;
	
	my @lines = ();
	
	my $prevMark = undef;
	
	foreach my $thisMark (@$marks) {
		if ( defined $prevMark && &markOkay( $thisMark ) ) {
			my $line = {
						'descr'  => $prevMark->{'ip'} . '-' . $thisMark->{'ip'},
						'srclat' => $prevMark->{'lat'},
						'srclng' => $prevMark->{'long'},
						'dstlat' => $thisMark->{'lat'},
						'dstlng' => $thisMark->{'long'}
						};
			push( @lines, $line );
			$prevMark = $thisMark;
		}
		# $lat = '26.511129';
		# $long = '-71.48186';
		# ignore all marks in the bermuda triangle
		elsif( ! defined $prevMark && &markOkay( $thisMark ) ) {
			$prevMark = $thisMark;		
		} else {
			$prevMark = undef;
		}

	}

	return \@lines;
}

1;

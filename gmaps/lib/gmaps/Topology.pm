#!/bin/env perl

#######################################################################
# Topology module to get topology information
#######################################################################
use gmaps::Topology::GeoIP;
use gmaps::Topology::DNSLoc;

use threads;
use Thread::Queue;


package gmaps::Topology;

use Socket;
use strict;

# number of max parallel threads for lookup
our $concurrentLookups = 7;


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


sub getLatLong
{
	my $router = shift;
	my $loc = shift;

	# find out lat and long for router
    my $ip = undef;
        my $dns = undef;

        my $long = undef;
        my $lat = undef;

        ( $ip, $dns ) = &getDNS( $router );

        #warn "Looking at $ip ($dns)\n";

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
        }
        # if no lat long exists, set it inside of the bermuda triangel :)
        if ( ! defined $long && ! defined $lat ) {
        	$lat = '26.511129';
                $long = '-71.48186';
        }
        
        #print $routers->[$i] . "/$ip/$dns/$i = LAT: $lat, LONG: $long\n";

	if($ip eq "64.57.28.243") {
	  $lat = "33.750000";
	  $long = "-84.418944";
	}
	elsif($ip eq "64.57.28.241") {
	  $lat = "41.889867";
	  $long = "-87.621278";
	}
	elsif($ip eq "64.57.28.242") {
	  $lat = "40.737306";
	  $long = "-73.916028";
	}
	elsif($ip eq "64.57.28.249") {
	  $lat = "38.902583";
	  $long = "-77.003167";
	}

	return ( $ip, $dns, $lat, $long );

}

# uses the two queues, one for a list of routers to query (queue) and another
# for a list of results to store those queries into (marks).
sub threadWrapper
{
	my $queue = shift;
	my $marks = shift;
	my $loc = shift;

	while( $queue->pending ) {

		my $router = $queue->dequeue;

		# lock num threads
		# get the lat long
		my ( $ip, $dns, $lat, $long )  = &getLatLong( $router, $loc );
		#warn '[' . threads->self->tid() . "] found $ip ($dns) @ $lat,$long\n";
		# queeus' only support scalars!! argh!
		my $ans = $ip . '==' . $dns . '==' . $lat . '==' . $long;
		#warn "      $ans\n";
		$marks->enqueue( $ans );

	}
	return undef;

}


# determines the coordinates fo the routers provided
sub getCoords
{
	my $routers = shift;
	my $loc = shift;
	
	my $marks : shared;
	$marks = new Thread::Queue;
	my %seen = ();

	# enqueue list of routers in shared queue
	my $queue : shared;
	$queue =  new Thread::Queue;
	for my $r ( @$routers ) {
		$queue->enqueue( $r );
	}

	my @thread = ();

	# find out the lat longs for each router
	# spawn off a series of threads to run 
	for my $i ( 0..$concurrentLookups-1 ) {
		push @thread, threads->new( \&threadWrapper, $queue, $marks, $loc );
	} # foreach thread

	# sync results
	for my $i ( 0.. $concurrentLookups-1 ) {
		$thread[$i]->join;
	}

	# need to stick an undef at the end of the marks to ensure that we do not block forever
	$marks->enqueue( undef );

	# dequeue the results
	my @marks = ();
	my $i = 0;
	while ( my $info = $marks->dequeue ) {
		#warn "MARK: $info\n";
		
		my %mark = ();
		( $mark{ip}, $mark{dns}, $mark{lat}, $mark{long} ) = split /==/, $info;
		
		#warn "GOT: $mark{ip} ($mark{dns}) @ $mark{lat},$mark{long}\n";
                
		# keep a tally of same coords, keep an array of which ones by index
		my $coords = $mark{lat} . ',' . $mark{long};
		
		push @{$seen{$coords}}, $i;
		push( @marks, \%mark );
		
		$i++;
	}

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

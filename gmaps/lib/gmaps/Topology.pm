#!/bin/env perl

#######################################################################
# Topology module to get topology information
#######################################################################
use gmaps::Topology::GeoIP;
use gmaps::Topology::DNSLoc;

use threads;
use Thread::Queue;
use Log::Log4perl qw(get_logger);


package gmaps::Topology;

use Socket;
use Data::Dumper;

our $logger = Log::Log4perl->get_logger("gmaps::MA::RRDMA");


# number of max parallel threads for lookup
our $concurrentLookups = 7;


sub getDNS
{
	my $ip = shift;
	my $dns = undef;

	$logger->info( "IN: ip: $ip, dns: $dns");
	# ip is actual ip, get the dns
	if ( &isIpAddress( $ip ) ) {
		$logger->info( "Fetching dns for ip $ip" );
		$dns = gethostbyaddr(inet_aton($ip), AF_INET)
			unless $ip eq '172.16.12.1';	# blatant hack to reduce time for fnal lookup
	}
	# ip is dns, get the ip
	else {
		$dns = $ip;
		$logger->info("Fetching ip for dns $dns" );
		my $i = inet_aton($dns);

		if ( $i ne '' ) {
			$ip = inet_ntoa( $i );
		}
		else {
			$logger->warn( "unknown dns for ip $ip\n" );
		}
	}

	$logger->info( "OUT: ip: $ip, dns: $dns" );
	undef $dns if $dns eq '';
	undef $ip if $ip eq '';
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

		$logger->info( "looking at $router");
        ( $ip, $dns ) = &getDNS( $router );

		if ( ! defined $dns) {
			$dns = $ip;
		}

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
		$logger->info($ans);
		$marks->enqueue( $ans );

	}
	return undef;

}


# determines the coordinates fo the routers provided
# routers{ip:ifname}
sub getCoords
{
	my $metadata = shift; # array of metadata hash refs
	my $loc = shift;
		
	$logger->info( "Getting coordinates..." );

	my $marks : shared;
	$marks = new Thread::Queue;

	# enqueue list of routers in shared queue
	my $queue : shared;
	$queue =  new Thread::Queue;
	my %seenip = ();
	foreach my $md ( @$metadata ) {
		my $ip = $md->{ifAddress};
		next if $seenip{$ip}++;		
		$logger->info( "enqueuing $ip");
		$queue->enqueue( $ip );
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

	my @tempmarks = ();
	while ( my $info = $marks->dequeue ) {
		#warn "MARK: $info\n";
		
		my %mark = ();
		( $mark{ip}, $mark{dns}, $mark{lat}, $mark{long} ) = split /==/, $info;
		
		push( @tempmarks, \%mark );	
	}

	# we use this counter to see how many points we have that in total
	my %seen = ();

	# so now we have all the routers in @tempmarks with teh ip/dns/lat/long
	my @marks = ();
		
	# lets make sure that we include all interfaces (ifnames) for each node
	# so we add a new mark for each; make use of seenip
    foreach my $m ( @tempmarks ) {
    	
    	$logger->info( "looking at " . $m->{ip});
    	
    	# if we have more than one interface on ip, then make sure we expand on 
    	# the interfaecs into marks
   	$logger->info( $m->{ip} . " has " . $seenip{$m->{ip}}  . " entries");

    	if ( $seenip{$m->{ip}} > 1 ) {
    		
		foreach my $md ( @$metadata ) {
			$logger->info( "looking at " . $md->{ifAddress} );
			if ( $md->{ifAddress} eq $m->{ip} ) {
				# keep a tally of same coords, keep an array of which ones by index
#				my $coords = $m->{lat} . ',' . $m->{long};
#				push @{$seen{$coords}}, $md->{id};
				&setInfo( $md, $m, \%seen );
				$logger->info( "  adding as " . $md->{'gmapsLabel'} );
			}
		}
    	} 
    	else {
		foreach my $md ( @$metadata ) { 
		
			next unless $md->{ifAddress} eq $m->{ip};
 #			my $coords = $m->{lat} . ',' . $m->{long};
#			push @{$seen{$coords}}, $md->{id};
			&setInfo( $md, $m, \%seen );
			$logger->info( "  adding as " . $md->{'gmapsLabel'} );
		}
    	}
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
		foreach my $id (@indexes) {

			$logger->info( "adding jitter to $id 's location" );

			# create a cirle around the coords, with each node at 360/$nodesAtSameCoords degrees
			# from each other
			my $angle = 360 / ( $nodesAtSameCoords / $n );
			foreach my $md ( @$metadata ) {
				next unless $md->{id} eq $id;
				$md->{latitude} = $md->{latitude} + ($radius * sin( $angle ));
				$md->{longitude} = $md->{longitude} + ($radius * cos( $angle ));
			}
			$n++;
		}
	}

	return $metadata;
}


sub setInfo
{
	my $md = shift;
	my $m = shift;
	my $seen = shift;

	my $name = $md->{hostName};
        
	if ( defined $m ) {
        	$name = $m->{dns} if ! $name;
		$md->{latitude} = $m->{lat};
        	$md->{longitude} = $m->{long};
        	# keep a tally of same coords, keep an array of which ones by index
        	my $coords = $m->{lat} . ',' . $m->{long};
        	push @{$seen->{$coords}}, $md->{id} if defined $seen;
	}
        
	# set the label for the item
	$name .= '@' . $md->{authRealm} if exists $md->{authRealm};
	$md->{'gmapsLabel'} = $name;
	$md->{'gmapsLabel'} .= ':' . $md->{ifName} if exists $md->{ifName};

	return;
}

sub markOkay
{
	my $thisMark = shift;
	#$logger->info( Dumper $thisMark );
	if ( $thisMark->{'latitude'} =~ /^26.51/ && $thisMark->{'longitude'} =~ /^-71.48/ ) {
		$logger->info("false");
		return 0;
	}
	$logger->info("true");
	return 1;
}

sub getLines
{
	my $marks = shift; # array of metadata hash refs
	
	my @lines = ();
	
	my $prevMark = undef;
	
	foreach my $thisMark ( @$marks) {

#		$logger->info( "looking at " . Dumper $thisMark );

		if ( defined $prevMark && &markOkay( $thisMark ) ) {
			my $line = {
						'descr'  => $prevMark->{'gmapsLabel'} . '-' . $thisMark->{'gmapsLabel'},
						'srclat' => $prevMark->{'latitude'},
						'srclng' => $prevMark->{'longitude'},
						'dstlat' => $thisMark->{'latitude'},
						'dstlng' => $thisMark->{'longitude'}
						};
			$logger->info( "Adding line " . $line->{'descr'} );
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

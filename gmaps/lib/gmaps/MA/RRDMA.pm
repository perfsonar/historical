#!/bin/env perl

#######################################################################
# 
#######################################################################

use gmaps::gmap;
use gmaps::Transport;
use gmaps::Topology;
use Template;
use File::Temp qw( tempfile );
use utils::rrd;
use Log::Log4perl qw(get_logger);

package gmaps::MA::RRDMA;

use Data::Dumper;
use strict;

our $logger = Log::Log4perl->get_logger("gmaps::MA::RRDMA");



sub processTemplate
{
	my $requestXML = shift;
	my $vars = shift;

	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	

	# store xml in memory as out
	# for some unknown reason, writing directly to the variable output
	# process( blah, blah, $request ) causes the request to fail (even though
	# the output looks fine ); therefore we hack it up and use a temp file
	
	my ( undef, $filename) = &File::Temp::tempfile( UNLINK => 1 );	
	$tt->process( $requestXML, $vars, $filename )
        || die $tt->error;

	my $out = &perfSONAR_PS::Common::readXML( $filename );
	unlink $filename or warn "Could not unlink $filename.\n";

	return $out;
	
}

###
# returns the xpath object of the response from the ma
###
sub get
{
	my $maHost = shift;
	my $maPort = shift;
	my $maEndpoint = shift;
	
	my $ip = shift;
	my $eventType = shift;
	my $ifname = shift;
	
	unless ( &gmaps::Topology::isIpAddress( $ip ) ) {
		die "ip address needs to be supplied.";
	}

	my $request = ${gmaps::gmap::templatePath} . 'rrdma_xml.tt2';

	my $vars = {
			'router' => $ip,
			'ifName' => $ifname,
			'eventType' => $eventType,
		};
	my $request = &processTemplate( $request, $vars );
	#print "REQ: $request\n";

	my $response = &gmaps::Transport::getString( 
				$maHost, $maPort, $maEndpoint, 
				$request );

	# usie the xpath statement if necessary
   	return XML::XPath->new( xml => $response );
}

sub getGraph
{
	my $xp = shift;# output of getUtilization
	my $metadata = shift;
	
	# retrieve the meta data info if necessary
	if ( $metadata eq '' ) {
		$metadata = &getMetadata( $xp )
	}

#	$logger->info( "xp" );
#	my $nodeset = $xp->find( '/' );
#	foreach my $node ( $nodeset->get_nodelist ) {
#		$logger->info( XML::XPath::XMLParser::as_string( $node ) );
#	}

	$logger->info( "metadata: " . Dumper $metadata );
	
	my $inMetaId = undef;
	my $outMetaId = undef;
	
	# determine metadataids for in and out
	foreach my $id ( keys %$metadata ) {
		if ( $metadata->{$id}->{direction} eq 'in' ) {
			$inMetaId = $id;
		} elsif ( $metadata->{$id}->{direction} eq 'out' ) {
			$outMetaId = $id;
		}
	}

	$logger->info("Found metadata ids: in=$inMetaId, out=$outMetaId" );
	my $data = undef;
	
	# now we need to fetch the data from the xpath xml structure
	$data = &mergeUtilizationData(
				&getUtilizationData( $xp, $inMetaId ),
				&getUtilizationData( $xp, $outMetaId )
			);
	
	return &createRRDGraph( $data );
	
}


sub createRRDGraph
{
	my $data = shift;

	# beginning time
	my @times = sort {$a <=> $b} keys %$data;
	my $start = $times[0];
	my $end = $times[$#times];

	# entries
	my $entries = scalar( @times );
	#print "TIMES: @times\n";
	if ( $entries eq 0 ) {
		return undef;
	}

	# create temp rrd
	my ( undef, $rrdFile ) = &File::Temp::tempfile( UNLINK => 1 );	
	my $rrd = utils::rrd->new( $rrdFile, $start, $entries );

	# add the data into the rrd
	my $prev = undef;
	my $realStart = undef;
	my $realEnd = undef;

	foreach my $t ( @times )
	{
		next if $t <= $prev;

		next if $t == 10;

		$realStart = $t if $t < $realStart || ! defined $realStart;

		if ( $data->{$t}->{'in'} ne '' 
				&& $data->{$t}->{'out'} ne '' ) {
			$rrd->add( $t, 'in:out', $data->{$t}->{'in'}, $data->{$t}->{'out'} );
		}
		elsif ( $data->{$t}->{'in'} ne ''
				&& $data->{$t}->{'out'} eq '' ) {
			$rrd->add( $t, 'in', $data->{$t}->{'in'} );
		}
		elsif ( $data->{$t}->{'in'} eq ''
				&& $data->{$t}->{'out'} ne '' ) {
			$rrd->add( $t, 'out', $data->{$t}->{'out'} );
		}
		
		$realEnd = $t if $t > $realEnd || ! defined $realEnd;

		$prev = $t;
	}
	
	# now get the graph from the rrd
	my ( undef, $pngFilename ) = &File::Temp::tempfile( UNLINK => 1 );		
	#warn( "START: $realStart, END: $realEnd\n" );	
	# ref to scalar
	my $graph = $rrd->getGraph( $pngFilename, $realStart, $realEnd );

	# clean up
#	unlink $pngFilename or warn "Could not unlink $pngFilename.\n";;
	undef $rrd;

	return $graph;	
}




sub mergeUtilizationData
{
	my $in = shift;
	my $out = shift;
	
	my %data = ();
	
	foreach my $i ( @$in ) {
		my ( $inTime, $inValue ) = split /:/, $i;
		$data{$inTime}{in} = $inValue;
	}

	foreach my $o ( @$out) {
		my ( $outTime, $outValue ) = split /:/, $o;
		$data{$outTime}{out} = $outValue;
	}

	return \%data;
}


sub getUtilizationData
{
	my $xp = shift;
	my $metadataIdRef = shift;
	
	$logger->info( "Looking for $metadataIdRef" );
	my $dataset = $xp->find( '//nmwg:data[@metadataIdRef="' . $metadataIdRef . '"]/nmwg:datum' );
	
	my @tuples = ();
				
	foreach my $data ( $dataset->get_nodelist ) {
		
		my $time = $data->getAttribute('timeValue');
		if ( ! $time ) {
			$time = $data->getAttribute('time');
		}
		next unless $time =~ /^\d+$/;
		my $value = $data->getAttribute('value');

		next if $value eq 'nan';

		$logger->debug( "TIME: $time, $value" );
		push( @tuples, $time . ':' . $value );
	
	}

	return ( \@tuples );
}

sub commify {
    local($_) = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;
    return $_;
} 

# returns hash of metadata info for the utilisation provided
sub getMetadata
{
	my $xp = shift; # output of getUtilization

	# lets keep a hash of meta{id}{$tag} = $info
    my %meta = ();

	# first get all the metadata's
    my $nodeset = $xp->find( '//nmwg:metadata[@id]' );
    
    foreach my $node ($nodeset->get_nodelist) {
    	
    	# find out it's id value
    	my $id = $node->getAttribute('id');
    	    	
    	# search underneath to get the actual info
    	my $subnodeset = $xp->find( './netutil:subject/nmwgt:interface/*', $node );
    	
    	foreach my $subnode ( $subnodeset->get_nodelist )
    	{	    	
		my $tag = $subnode->getLocalName();
		my $info = $subnode->string_value();

		if ( $tag eq 'capacity' ) {
			$info = &commify( $info ) . ' bit/sec';
		}
   
	   	$meta{$id}{$tag} = $info;
    	}

   }
    
	return \%meta;

}


sub sendTemplate2XPath
{
	my $maHost = shift;
	my $maPort = shift;
	my $maEndpoint = shift;
	
	my $requestTemplate = shift;
	my $vars = shift;
	
	my $request = &processTemplate( $requestTemplate, $vars );
	my $response = &gmaps::Transport::getString( $maHost, $maPort, $maEndpoint, 
		$request );

	# usie the xpath statement if necessary
   	my $xp = XML::XPath->new( xml => $response );

	return $xp;	
}

sub sendTemplate2Array
{
	my $maHost = shift;
	my $maPort = shift;
	my $maEndpoint = shift;
	
	my $requestTemplate = shift;
	my $vars = shift;
	my $xpathFilter = shift;
	
	#print "FILTER: " . $xpathFilter . "\n";
	
	my $request = &processTemplate( $requestTemplate, $vars );
	
	$logger->info( " request: $request\n" );
	
	my $response = &gmaps::Transport::getArray( 
						$maHost, $maPort, $maEndpoint, 
						$request, $xpathFilter );

	$logger->info( "response: @$response\n" );


	return $response;
}




###
# queries the MA directly to determine what meta data is stored and returns the ip's for those routers
###
sub getAllRouters
{
	my $maHost = shift;
	my $maPort = shift;
	my $maEndpoint = shift;
	
	my $eventType = shift;
	
	my $vars = { 'eventType'	=> $eventType	};

	# sendt he template and parse output
	my $metakeys = sendTemplate2XPath( 
						$maHost, $maPort, $maEndpoint,
						${gmaps::gmap::templatePath} . 'rrdma_all-routers-ip-address_xml.tt2',
						$vars
					);

	# we now want to grab the router list and its ifName
#  <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
#    <nmwgt:ifAddress type="ipv4">198.124.252.110</nmwgt:ifAddress>
#    <nmwgt:hostName>fnal-mr1.es.net</nmwgt:hostName>
#    <nmwgt:ifName>Vlan1805</nmwgt:ifName>
#    <nmwgt:ifDescription>fnal-mr1->fnal-pt1:10ge(vlan)::show:intracloud</nmwgt:ifDescription>
#    <nmwgt:capacity>10000000000</nmwgt:capacity>
#    <nmwgt:direction>in</nmwgt:direction>
#    <nmwgt:authRealm>ESnet-Public</nmwgt:authRealm>
#  </nmwgt:interface>

	my $metadatas = &getMetadata( $metakeys );

	my @array = ();
	foreach my $meta ( keys %$metadatas ) {
		$logger->info( "Found $meta\n" . Dumper $metadatas->{$meta} );		
		$metadatas->{$meta}->{id} = $meta;
		push @array, $metadatas->{$meta};
	}

	return \@array;
}


1;


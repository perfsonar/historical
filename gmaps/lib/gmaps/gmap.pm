#!/bin/env perl

#######################################################################
# simple cgi frontend to perfsonar services; spits out html, pngs and 
# kml files
#######################################################################

use gmaps::MA::RRDMA;
use gmaps::Topology;
use gmaps::LookupService;
use gmaps::LookupService::StaticLS;
use gmaps::KML;
use gmaps::gmap;

use Template;


package gmaps::gmap;

our $templatePath = '/u/sf/ytl/Work/perfSONAR/gmaps/trunk/lib/gmaps/templates/';
our $server = 'http://134.79.24.133:8080/cgi-bin/gmaps.pl';
our $googlemapKey = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBSCiUxZOw432i6dgwL13ERiRlaSNRS5laPT7HkzCJQupyaoW8s87EsHmQ';

use CGI::Application;
use base 'CGI::Application';

#use strict;

# setup for mode switching
sub setup {
    my($self) = @_;
    
    $self->start_mode('enter');
    
    $self->mode_param('mode');
    
    $self->run_modes(
		     'graph'	=> 'rrdmaUtilizationGraph',	# returns the rrdma utilization graph
		     'enter'	=> 'enterNodes',			# form to process router/domain info
		     'info'		=> 'rrdmaInfoXml',			# returns info about a router
		     'xml'		=> 'createXml',				# returns an xml of long lats and nodes
		     'map'		=> 'mapFromXml',			# returns the googlemap with async. xml of nodes (createXml)
		     'mapInline'	=> 'mapWithInlineJavascript',	# returns googlemap with inline javascript of ndoes
		     'kml'		=> 'createKml',				# returns a kml file of nodes
		     'routers'		=> 'testRouters',		# returns the parsed output
		     'wait'		=> 'waitGraphic',			# wait graphic
		     'ma'		=> 'ma'						# info about ma
		   );

	return undef;    
}

sub teardown {
    my $self = shift;
    
    # Disconnect when we're done
}


#######################################################################
# utility functions
#######################################################################

# utility function to grab all the routers inputted form teh get statment
sub getRouters 
{
	my $self = shift;
	my $in = shift;
	
	my @routers = ();
	
	if ( defined $in ) {
		@routers = &parseRouters( $in );
	}
	
	elsif ( defined $self ) {
		my $q = $self->query();
		
		# get ips dierct from input
		@routers = $q->param('ip');
		
		# grep from teh raw input
		# if not routers defined, then check for string (from enter sub)
		if ( scalar( @routers ) == 0 
				&& defined $q->param('raw'))
		{
			my $raw = $q->param('raw');
			if ( $raw =~ /ARRAY/ ) {
				$raw = "@$raw";
			}
			@routers = &parseRouters( $raw );
		}
		
		# process domain (do a fetch on the MA for all registered routers)
		my @domainRouters = $q->param('domain');
		foreach my $d ( @domainRouters ) {
			my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( $d );
			my $nodes = &gmaps::MA::RRDMA::getAllRouters( $host, $port, $endpoint, $eventType );
			push( @routers, @$nodes );
		}
		
	}
	return \@routers;
}

# grab all the ip/dns entries from text
sub parseRouters
{
	my $raw = shift;
	
	my @nodes = split /\s+/, $raw;
	my @nodes2 = ();

	
	foreach my $n (@nodes) {
		# make sure we have a separator
		next unless $n =~ m/\.(\w+)\./;
		
		# strip brackets of traceroute ips
		if ( $n =~ m/(\d+\.\d+\.\d+\.\d+)/ ) {
			$n = $1;
			next unless &gmaps::Topology::isIpAddress( $n );
		}
		push( @nodes2, $n );
	}
	
	my @final = ();
	my %seen = ();
	# make sure we don't have duplicates ()ip and dns also)
	foreach my $n ( @nodes2 ) {
		
		my ( $ip, $dns ) = &gmaps::Topology::getDNS( $n );
		push( @final, $ip ) unless $seen{$ip}++;

	}


	return @final;
}

# push the arguments to other script
sub passArgs
{
	my $self = shift;
	my @other = shift;
	
	my @ip = ();
	my @domain = ();
	if ( defined $self ) {
		my $q = $self->query();
		@ip = $q->param('ip');
	#	print "IP; @ip\n";
		@domain = $q->param('domain');
	#	print "DOMAIN: @domain\n";
		my @rawIps = &parseRouters( $q->param('raw') );
	#	print "RAW: @rawIps\n";
		push( @ip, @rawIps )
	}
	
	foreach my $i (@ip) {
		$i = 'ip=' . $i;
	}
	foreach my $d (@domain) {
		$d = 'domain=' . $d;
	}
	
	my $args = join '&', @ip;
	if ( scalar @domain ) {
		$args .= join '&', @domain;
	}
	
	#print "<p>OUT: $args<p>";
	
	return $args;	
}

# simply outputs the routers to screen
sub testRouters
{
	my $self = shift;
	$routers = &getRouters( $self, @_);

	$self->header_add(  -type => "text/html" ); 

	my $output = undef;
	foreach my $r ( @$routers ) {
		$output .= "$r<br>";
	}

	return $output;
}

#######################################################################
# access functions
#######################################################################

# returns the wait/loading graphic
sub waitGraphic
{
	my $self = shift;
	
	$self->header_add( -type => "image/gif", -expires => '+24h' ); 
	return &catFile( $templatePath . '/spinner.gif' );
}

# enter the nodes in a form
sub enterNodes
{

	my $self = shift;
	
	my @domains = sort &gmaps::LookupService::StaticLS::getDomains();
	
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $vars = {
      			'cgi'  => $server,
      			'mapMode' => 'map',
      			'domains' => \@domains
				};	
	my $file = $templatePath . '/gmaps_enterNodes_html.tt2';
	my $output = '';
	$tt->process( $file, $vars, \$output )
        || die $tt->error;

	$self->header_add(  -type => "text/html" ); 
	return $output;
}


# outputs a kml file
sub createKML
{
	my $self = shift;
	my $routers = &getRouters( $self, @_ );
	
	# create the kml file from nodes
	my $kml = gmaps::KML->new( );

	foreach my $ip (@$routers) {

		my ( $long, $lat ) = &gmaps::Topology::GeoIP::getLatLong( $ip );
		
		next if ( $lat eq undef || $long eq undef );
	
		# get the ip address and dns
		my ( $ip2, $dns ) = gmaps::Topology::getDNS( $ip );
	
		# get the descr
		my $desc = &gmaps::gmap::getDescr( undef, $ip );
	
		# add the placemark
		$kml->addPlacemark( $dns, $long, $lat, $desc );

	}
	
	my $markup = $kml->getKML();
	
	return $$markup;
}	

# returns an xml of the markers
sub createXmlFull
{
	my $self = shift;
	my $routers = &getRouters( $self, @_ );
	
	my $marks = &gmaps::Topology::getCoords( $routers );
	
	# create template object
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $file = undef;
	my $vars = {};
	
	# add the extra panel info
	foreach my $m (@$marks)
	{
			
		# get the utilization tab html		
		$vars = {
				'dns'	=> $m->{'dns'},
				'ip'	=> $m->{'ip'},
				'cgi' 	=> $server . '?mode=graph&ip=' . $m->{'ip'}
				};
		$file = $templatePath. '/gmaps-utilization_html.tt2';
		$tt->process( $file, $vars, \$m->{'utilTab'} )
        	|| die $tt->error;
        $m->{'utilTab'} = &escapeString( $m->{'utilTab'} );
	
		# info tab
		# get ma info
		
		# TODO: do i care?
		$vars = {
				'ma'		=> $m->{'dns'},
				'hostName'	=> $m->{'ip'},
				'ifName' 	=> $server . '?mode=graph&ip=' . $m->{'ip'},
			};
		$file = $templatePath. '/gmaps-info_html.tt2';
		$tt->process( $file, $vars, \$m->{'infoTab'} )
        	|| die $tt->error;
        $m->{'infoTab'} = &escapeString( $m->{'infoTab'} );


	}
	
	# final xml
	if ( defined $self ) {
		$self->header_add(  -type => "text/xml" ); 
	}
	
	my $out = '';
	$vars = {
      			'marks'  => $marks
			};	
	$file = $templatePath . '/gmaps_xml.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;
	
	return $out;
}


# returns an xml of the markers
sub createXml
{
	my $self = shift;
	my $routers = &getRouters( $self, @_ );

	# get the coords of routers
	my $marks = &gmaps::Topology::getCoords( $routers );
	
	# get the interconnecting lines
	my $lines = &gmaps::Topology::getLines( $marks );
	
	# create template object
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $file = undef;
	my $vars = {};
		
	my $out = '';
	$vars = {
      			'marks'  => $marks,
      			'lines'  => $lines
			};	
	$file = $templatePath . '/gmaps_xml.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;
	
	# final xml
	if ( defined $self ) {
		$self->header_add(  -type => "text/xml" ); 
	}
		
	return $out;
}


# creates a web page with a ref to get teh XML file for plotting
sub mapFromXml
{
	my $self = shift;

	my $args = &passArgs( $self, @_ );

	# write the output to return to the client
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
	my $vars = {
					'cgi'	=> $server,
					'args'	=> $args,
					'xmlMode' => 'xml',
					'infoMode' => 'info',
					'graphMode' => 'graph',
					'googlemapKey' => $googlemapKey,
				};
	my $file = $templatePath . '/gmaps_html.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;
	
	$self->header_add(  -type => "text/html" ); 		
	return $out;
}

# return a map with the nodes inlined as javascript
sub mapWithInlineJavascript
{
	my $self = shift;
	my $routers = &getRouters( $self, @_ );

	my @marks = ();
	my %seen = ();
	
	my $marks = &gmaps::Topology::getCoords( $routers );
	
	# write the output to return to the client
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
	my $vars = {
					'graphUri'	=> $server . '?mode=graph&ip=',
					'infoUri'	=> $server . '?mode=info&ip=',
      				'marks'  => \@marks,
				};
	my $file = $templatePath . '/gmaps_html-inline.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;
	
	
	undef @marks;
	undef $file;
	
	return $out;

}

# simply cats the output to a variable reference (good for returning pics)
sub catFile
{
	my $file = shift;
	open ( DATA, '<' . $file );
	my $png = undef;
	while( <DATA>) {
		$png .= $_;	
	}
	close DATA;
	return $png;	
}



#######################################################################
# rrd ma stuff
#######################################################################

# spits out meta data in xml formatted html
sub rrdmaInfoXml
{
	my $self = shift;
	
	my $ip = gmaps::Topology::isIpAddress( $self->query()->param( 'ip' ) );
 	my ( $routerInfo, $meta, $ma, $eventType ) = &rrdmaFetch( $ip );
 
	if ( ! defined $meta ) {
		$ma = 'unknown';
		$eventType = 'unknown';
	}

 	# this need to be xml due to reparsing as xml by the httpxml reader
 	$self->header_add( -type => "text/xml" );
 	
	my @metaRefs = keys %$meta;
	$meta = $meta->{$metaRefs[0]};
	
	my $output = '';
	my $vars = {
			'ma'		=> $ma,
			'eventType' => $eventType,
			'hostName'	=> $meta->{'hostName'},
			'ifName' 	=> $meta->{'ifName'},
			'ifAddress'	=> $meta->{'ifAddress'},
			'capacity'	=> $meta->{'capacity'},
			'ifDescription'	=> $meta->{'ifDescription'}
		};
	my $file = $templatePath. '/gmaps-info_html.tt2';
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
	$tt->process( $file, $vars, \$output )
        	|| die $tt->error;

	return $output;
}

# plots graph
sub rrdmaUtilizationGraph
{
	my $self = shift;

	my $ip = gmaps::Topology::isIpAddress( $self->query()->param( 'ip' ) );
	if ( ! defined $ip ) {
		( $ip, undef ) = gmaps::Topology::getDNS( $self->query()->param( 'ip' ) );
	}
	
	my ( $routerInfo, $meta, undef, undef ) = &rrdmaFetch( $ip );
	#warn "$ip :: info: $routerInfo, meta: $meta\n";

	# output is always a graph/png	
	$self->header_add( -type => "image/png", -expires => 'now' ); 

	# error if no ma matched
	unless( defined $routerInfo && defined $meta ) {
		return &catFile( $templatePath . '/noma.png' );
	} 	

	# dereference graph	
	my $png = &gmaps::MA::RRDMA::getGraph( $routerInfo, $meta );
	
	if ( ! defined $png ) {
		return &catFile( $templatePath . '/nodata.png' );
	}
	
	return $$png;
}


# fetch info for the router
sub rrdmaFetch
{
	my $router = shift;
	
	# the ma needs the dns entry to work, so get dns name of router
	my ( $ip, $dns ) = gmaps::Topology::getDNS( $router );
 	my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( $dns );
 	if ( ! defined $host or $host eq '' ) {
 		return ( undef, undef, undef, undef ); 
 	}
 	
	my $data = &gmaps::MA::RRDMA::get(  
						$host,
						$port,
						$endpoint,						
						$ip,
						$eventType );

	my $meta = &gmaps::MA::RRDMA::getMetadata( $data );

	return ( $data, $meta, 'http://' . $host . ':' . $port . '/' . $endpoint, $eventType );
}

# displays the MA configuration set for the routers
sub ma
{
	my $self = shift;

	my $routers = &getRouters( $self, @_ );

	my $output = '';
	
	foreach my $router ( @$routers ) 
	{
		my ( $ip, $dns ) = gmaps::Topology::getDNS( $router );	
	 	my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( $dns );
	
		my $ma = 'http://' . $host . ':' . $port . '/' . $endpoint;
		
		if ( ! defined $host ) {
			$ma = 'unknown';
			$eventType = 'unknown';
		}
		
		my $this = '';
		my $vars = {
						'input'	=> $router,
						'ip'	=> $ip,
						'dns'	=> $dns,
						'ma'	=> $ma,
						'eventType' => $eventType
					};
		my $file = $templatePath. '/gmaps-ma_html.tt2';
		my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
		$tt->process( $file, $vars, \$this )
	        	|| die $tt->error;
	        	
	    $output .= $this;
	}
	$self->header_add( -type => "text/html", -expires => '+3m' ); 	
	return $output;
}


1;

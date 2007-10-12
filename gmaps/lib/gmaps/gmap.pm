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

use Data::Dumper;

use Log::Log4perl qw(get_logger :levels);

our $templatePath = '/usr/local/perfSONAR-PS/www/gmaps/templates/';
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
	'enter'	=> 'enterNodes',			# form to process router/domain info

	'map'		=> 'mapFromXml',		# returns the googlemap with async. xml of nodes (createXml)
	'mapInline'	=> 'mapWithInlineJavascript',	# returns googlemap with inline javascript of ndoes
	
	'graph'		=> 'rrdmaUtilizationGraph',	# returns the rrdma utilization graph
	'list' 		=> 'rrdmaUtilizationGraphList',
	
	'info'		=> 'rrdmaInfoXml',		# returns info about a router
	'ma'		=> 'measurementArchiveInfo',			# info about ma
#	'geo'		=> 'geoInfo',

	'xml'		=> 'createXml',			# returns an xml of long lats and nodes
	'kml'		=> 'createKml',			# returns a kml file of nodes

	'routers'	=> 'testRouters',		# returns the parsed output

	#logo
	'spinner'	=> 'spinnerGraphic',		# wait graphic
	'slac_logo'	=> 'slacGraphic',		# slac logo
	'perfsonar_logo'	=> 'perfsonarGraphic',	# perfsonar logo
	'internet2_logo'	=> 'internet2Graphic',	# perfsonar logo
   );

   return undef;    
}



# run these before calling runbmode
# set up db and templates
sub cgiapp_prerun
{
	my $self = shift;
     
	my $conf = $templatePath . '/gmaps.conf';
	if ( -e $conf ) {
	  Log::Log4perl->init( $conf );
	} else {
	  Log::Log4perl->easy_init($ERROR);
	}
	$self->param( 'logger' => &get_logger("gmaps") );

	#$self->param('logger')->info( "Entering run mode '' with " . Dumper $self->query() );

}




sub teardown {
    my $self = shift;
    
    # Disconnect when we're done
}


#######################################################################
# utility functions
#######################################################################

sub createIf
{
	my $in = shift; # from parseIf
	my $id = shift;
	my $md = ();
	( $md->{ifAddress}, $md->{ifName} ) = &splitIf( $in );
	if ( defined $id ) {
		$md->{id} = $id;
	}
	
	return $md;
}

# utility function to grab all the routers inputted form teh get statment
# returns an array of hashes with ifAddress, ifName etc
sub getRouters 
{
	my $self = shift;
	my $in = shift;
		
	my @metadata = ();
	
	my $id = 0;

	if ( defined $in ) {
		$self->param('logger')->debug( "in='" . $in . "'" );
		foreach my $if ( &parseIf( $in ) ) {
			#next if ! gmaps::utils::IP::isAnIP( $r );
			push @metadata, &createIf( $if, $id ); 
			$id++;
		}
	}
	
	elsif ( defined $self ) {
		$self->param('logger')->debug("self call" . Dumper $self );
		# get ips dierct from input
		my @ifs = $self->query()->param('if');
		foreach my $if ( @ifs ) {
			$self->param('logger')->debug( "Found in param if: $if" );
			push @metadata, &createIf( $if, $id );
			$id++;
		}	
		# grep from teh raw input
		# if not routers defined, then check for string (from enter sub)
		if ( defined $self->query()->param('raw') )
		{
			my @raws = $self->query()->param('raw');
			foreach my $raw ( @raws ) {
			    $self->param("logger")->debug( "Found raw statement $raw" );
			    foreach my $if ( &parseIf( $raw ) ) {
				next if ( $if =~ /^\(.*\)$/ );
				push @metadata, &createIf( $if, $id );
				$id++;
			   }
			}
		}
		
		# process domain (do a fetch on the MA for all registered routers)
		my @domainRouters = $self->query()->param('domain');
		foreach my $d ( @domainRouters ) {
			$self->param('logger')->info("Looking for domain $d");
			my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( undef, $d );
			my $data = &gmaps::MA::RRDMA::getAllRouters( $host, $port, $endpoint, $eventType );
		
			
			push @metadata, @$data;
		}
		
	}

	$self->param("logger")->debug( "Final nodes: " . Dumper \@metadata );

	return \@metadata;
}


# returns an array of ifAddress:ifName from the raw text input
sub parseIf
{
	my $raw = shift;

	my @nodes = split /\s+/, $raw;
	my @nodes2 = ();
	
	# get all the ip addresses
        foreach my $n (@nodes) {

                # make sure we have a separator
                next unless $n =~ m/\.(\w+)\./;

		# if we have a dns supplied, map it to an ip address for lookup purposes
		# if we have an associated if with teh node, strip it
		my $node = undef;
		my $if = undef;
		( $node, $if ) = split /\:/, $n;
		if ( ! &gmaps::Topology::isIpAddress( $node ) ) {
			( $node, undef ) =  &gmaps::Topology::getDNS( $node );
		}

		# reconstruct it to add to list
		my $final = $node;
		$final .= ':' . $if if defined $if;

                push( @nodes2, $final );
        }

	return @nodes2;
}

# splits the ifAddress:ifNAme from parseInterfaces
sub splitIf
{
	my $in = shift;
	my $ip = undef;
	my $if = undef;
	if ( $in =~ /\:/ ) {
		( $ip, $if ) = split /\:/, $in;
	} else {
		$ip = $in;
	}
	return ( $ip, $if );
}

# push the arguments to other script
sub passArgs
{
	my $self = shift;	
	my $q = $self->query();

	my @if = $q->param('if');
	my @domain = $q->param('domain');
	
	foreach my $i (@if) {
		$i = 'if=' . $i;
	}
	foreach my $d (@domain) {
		$d = 'domain=' . $d;
	}
	
	my $other = $self->getRouters();
	my @raw = ();
	foreach my $r (@$other) {
		push ( @raw, 'if=' . $r->{ifAddress} );
	}
	
	my $args = undef;
	if ( scalar @domain ) {
		$args = join '&', @domain;
	} elsif ( scalar @if ) {
		$args = join '&', @if;
	} else {
		$args = join '&', @raw;
	}

	return $args;	
}

sub passGraphArgs
{
	my $self = shift;
	my $q = $self->query();

	my $args = undef;
        # add graph settings
        if ( $q->param('period') ) {
                $args .= '&period='. $q->param( 'period' )
        }
        if ( $q->param('cf') ) {
                $args .= '&period=' . $q->param( 'cf' )
        }
        if ( $q->param('resolution') ) {
                $args .= '&resolution=' . $q->param( 'resolution' )
        }
	if ( $q->param('refresh') ) {
                $args .= '&refresh=' . $q->param( 'refresh' )
        }


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

###
# spits out graphics for logos etc (not the best use of cgi...)
###

# returns the wait/loading graphic
sub spinnerGraphic
{
	my $self = shift;
	
	$self->header_add( -type => "image/gif", -expires => '+24h' ); 
	return &catFile( $templatePath . '/spinner.gif' );
}

# returns the wait/loading graphic
sub slacGraphic
{
	my $self = shift;
	
	$self->header_add( -type => "image/png", -expires => '+24h' ); 
	return &catFile( $templatePath . '/slac_logo_small.png' );
}

# returns the wait/loading graphic
sub perfsonarGraphic
{
	my $self = shift;
	
	$self->header_add( -type => "image/png", -expires => '+24h' ); 
	return &catFile( $templatePath . '/perfsonar_logo_small.png' );
}

# returns the internet2 graphic
sub internet2Graphic
{
       my $self = shift;

       $self->header_add( -type => "image/png", -expires => '+24h' ); 
       return &catFile( $templatePath . '/i2-clear.png' );
}
 

	
# enter the nodes in a form
sub enterNodes
{

	my $self = shift;
	
	$self->param('logger')->info("enterNodes");
	
	my @domains = sort &gmaps::LookupService::StaticLS::getDomains();
	
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $vars = {
      			'cgi'  => $server,
      			'mapMode' => 'map',
      			'listMode' => 'list',
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
		my ( $ip2, $dns ) = &gmaps::Topology::getDNS( $ip );
	
		# get the descr
		my $desc = &gmaps::gmap::getDescr( undef, $ip );
	
		# add the placemark
		$kml->addPlacemark( $dns, $long, $lat, $desc );

	}
	
	my $markup = $kml->getKML();
	
	return $$markup;
}	

# returns an xml of the markers
sub createXml
{
	my $self = shift;

	$self->param('logger')->debug( Dumper $self );

	my $metadata = $self->getRouters( @_ ); # returns array of metadata's 
	
	# get the coords of routers
	&gmaps::Topology::getCoords( $metadata );
	
	$self->param("logger")->debug( "Fetching list of nodes for " . Dumper $metadata );

	# get the interconnecting lines
	my $lines = &gmaps::Topology::getLines( $metadata );

	# create template object
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $file = undef;
	my $vars = {};

	$self->param('logger')->info("processing template");

	my $out = '';
	$vars = {
      			'marks'  => $metadata,
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

	$self->param('logger')->info("  returning: \n$out");
	
	return $out;
}


# creates a web page with a ref to get teh XML file for plotting
sub mapFromXml
{
	my $self = shift;

	$self->param('logger')->info("Generating google map page");

	# write the output to return to the client
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
	my $vars = {
			'cgi'		=> $server,
			'args'		=> $self->passArgs( ),
			'graphArgs'	=> $self->passGraphArgs( ),
			'xmlMode' 	=> 'xml',
			'infoMode' 	=> 'info',
			'graphMode' 	=> 'graph',
			'googlemapKey' 	=> $googlemapKey,
		};
	if ( $self->query()->param('refresh') ) {
		$vars->{'REFRESHINTERVAL'} = $self->query()->param('refresh');
	}
	my $file = $templatePath . '/gmaps_html.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;
	
	$self->header_add(  -type => "text/html" ); 		
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
	
	my $interface =  $self->query()->param( 'if' );
	my ( $ip, $if ) = &splitIf( $interface );

 	my ( $routerInfo, $meta, $ma, $eventType ) = &rrdmaFetch( $ip, $if );
 
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
	my $q = $self->query();

	my $interface = $q->param( 'if' );
	my ( $ip, $ifname ) = &splitIf( $interface );

	$self->param('logger')->info( "Looking for $ip, interface $ifname (from $interface)");

	if ( ! defined $ip ) {
		$self->param('logger')->fatal("Why is no IP defined?!");
	}

	my ( $data, $meta, undef, undef ) = &rrdmaFetch( $ip, $ifname, $q->param( 'period' ), $q->param( 'cf' ), $q->param( 'resolution' ) );

	# output is always a graph/png	
	$self->header_add( -type => "image/png", -expires => 'now' ); 

	# error if no ma matched
	unless( defined $data && defined $meta ) {
		return &catFile( $templatePath . '/noma.png' );
	} 	

	# dereference graph	
	my $png = &gmaps::MA::RRDMA::getGraph( $data, $meta );
	
	if ( ! defined $png ) {
		return &catFile( $templatePath . '/nodata.png' );
	}
	
	return $$png;
}

# returns a html of the util grpah, refresh automatically
sub rrdmaUtilizationGraphList
{
	my $self = shift;
	my $metadata = &getRouters( $self, @_ );
	
	# get dns for each
	my @hosts = ();
	foreach my $r ( @$metadata ) {
		$self->param('logger')->info("Found " . Dumper $r );
		my $coords = {};
		( $r->{ifAddress}, $r->{hostName} ) = &gmaps::Topology::getDNS( $r->{ifAddress} );
		&gmaps::Topology::setInfo( $r );
		push @hosts, $r;
	}
	
	# create template object
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );		
	my $file = undef;
	my $vars = {};
		
	my $out = '';
	$vars = {
      			'routers'  => \@hosts,
      			'graphMode'  => 'graph',
      			'cgi'		=> $server,
			'graphArgs'	=> $self->passGraphArgs(),
			};
	if ( $self->query()->param('refresh') ) {
		$vars->{'REFRESHINTERVAL'} = $self->query()->param('refresh') ;
	}	
	$file = $templatePath . '/gmaps-graph_html.tt2';
	
	my $out = '';
	$tt->process( $file, $vars, \$out )
        || $self->param('logger')->logdie( "template error " . $tt->error );
	
	# final xml
	if ( defined $self ) {
		$self->header_add(  -type => "text/html" ); 
	}
		
	return $out;

}


# fetch info for the router
sub rrdmaFetch
{
	my $router = shift;
	my $ifname = shift;
	
	my $period = shift;
	my $cf = shift;
	my $resolution = shift;


	# the ma needs the dns entry to work, so get dns name of router
	my ( $ip, $dns ) = gmaps::Topology::getDNS( $router );
 	my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( $ip, $dns );


 	if ( ! defined $host or $host eq '' ) {
 		return ( undef, undef, undef, undef ); 
 	}
 	
	my $data = &gmaps::MA::RRDMA::get( 	$host, $port, $endpoint,
						$ip, $eventType, $ifname,
						$period, $cf, $resolution				
					 );

	my $meta = &gmaps::MA::RRDMA::getMetadata( $data );

	return ( $data, $meta, 'http://' . $host . ':' . $port . '/' . $endpoint, $eventType );
}

# displays the MA configuration set for the routers
sub measurementArchiveInfo
{
	my $self = shift;

	my $routers = $self->getRouters( @_ );
	my $output = '';
	
	foreach my $router ( @$routers ) 
	{

		$self->param('logger')->info( "Looking at " . $router->{ifAddress} . ':' . $router->{ifName} );

		my ( $ip, $dns ) = gmaps::Topology::getDNS( $router->{ifAddress} );	
	 	my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::StaticLS::getMA( $ip, $dns );
	
		my $ma = 'http://' . $host . ':' . $port . '/' . $endpoint;
		
		if ( ! defined $host ) {
			$ma = 'unknown';
			$eventType = 'unknown';
		}
		
		my $this = '';
		my $vars = {
						'ip'	=> $ip,
						'dns'	=> $dns,
						'ma'	=> $ma,
						'eventType' => $eventType
					};
		if ( exists $router->{ifName} ) {
			$vars->{ifName} = $router->{ifName}
		}
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

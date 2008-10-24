=head1 NAME

gmaps::Interface::web - An google maps based interface to interact with 
perfsonar services  

=head1 DESCRIPTION

This module provides functions to query a remote perfsonar measurement point
or measurement archive. Inherited classes should overload the appropiate
methods to provide customised access to the service in question.

=head1 SYNOPSIS

    use gmaps::Interface::web;
    
    # create a new service
    my $service = gmaps::Interface::web->new();
  
    # get a list of all urn's available on a perfsonar service endpoint
	my $list = $service->discover( 'http://localhost:8080/endpoint' );
	
	foreach my $urn ( @$list ) {
		print "$urn\n";
	}
	
	# get a data table of the values for the service
	my $table = $service->fetch( 'http://localhost:8080/endpoint', 
						'urn:ogf:network:domain=localdomain:host=localhost');

	# graph the data table (also does a fetch)
	my $png = $service->graph( 'http://localhost:8080/endpoint', 
						'urn:ogf:network:domain=localdomain:host=localhost');
	# if you already have the data you can also
	# my $png = $service->getGraph( $table );
	
	
	

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=cut

package gmaps::Interface::web;

use CGI::Application;
use gmaps::Interface;

BEGIN{
	@ISA = ( 'CGI::Application', 'gmaps::Interface' );
}

use CGI::Application::Plugin::TT;

# logging
use Log::Log4perl qw( get_logger );
our $logger = Log::Log4perl::get_logger( 'gmaps::web');

use strict;


#######################################################################
# pre stuff
#######################################################################

###
# setup for mode switching
###
sub setup {
    my($self) = @_;
    
    $self->start_mode('map');
    $self->mode_param('mode');
    $self->run_modes(
		
		'services'  => 'getServices', # returns an xml of the service endpoints from teh given gLS
		
		'topology'	=> 'topology',	# does the actual perfsonar topology discovery from a service

		'map'		=> 'map',		# returns the googlemap with async. xml of nodes (createXml)

		'graph'		=> 'graph',	# returns the rrdma utilization graph

   	);

   return undef;    
}



# run these before calling runbmode
# set up db and templates
sub cgiapp_prerun
{
	my $self = shift;
	$logger->debug( "Using template path '${gmaps::paths::templatePath}'");
    $self->tt_include_path( ${gmaps::paths::templatePath} );
    $self->tt_config(
              TEMPLATE_OPTIONS => {
                        INCLUDE_PATH => ${gmaps::paths::templatePath},
              } );
	return;     
}


###
# overrides parents
###
sub processTemplate
{
	my $self = shift;
	my $xml = shift;
	my $vars = shift;

	$logger->debug( "Processing template '$xml' using $vars");

	return $self->tt_process( $xml, $vars )
		or $logger->logdie( "Could not process template '$xml': " . $self->param( 'tt' )->error() );
}


#######################################################################
# html frontends
#######################################################################


###
# returns the map
###
sub map
{
	my $self = shift;
	
	my $vars = {
		'GOOGLEMAPKEY' => ${gmaps::paths::googleMapKey},
	};
	
	my $template = 'web/map_html.tt2';
	return $self->processTemplate( $template, $vars );
}


sub topology
{
	my $self = shift;
	
	my $using = $self->query()->param('using');
	lc( $using );
	
	my $uri = $self->query()->param('uri');
	my $urn = $self->query()->param('urn');

	my $markers = $self->SUPER::topology( $uri, $using, $urn );
	
	return $self->getMarkers( $markers );
}



###
# given a list of hashes representing the nodes,
# spit out the relevant xml for it
###
sub getMarkers
{
	my $self = shift;
	my $data = shift;
	
	my $vars = {
		'NODES' => $data,
	};
	$logger->info( "Found " . scalar @{$vars->{'NODES'}}  );
	
	my $template = 'web/markers_xml.tt2';
	return $self->processTemplate( $template, $vars );
	
}



=head2 getServices

=cut
sub getServices
{
    my $self = shift;
	my $uri = $self->query()->param('gLS');
    
    my $services = $self->SUPER::getServices( $uri );
    
    my @list = ();
    
    foreach my $service ( @$services ) {
        my $hash = utils::urn::toHash( $service );
        push @list, $hash; 
    }
    
    my $vars = {
        'SERVICES' => \@list,
    };
    my $template = 'web/services_xml.tt2';
    return $self->processTemplate( $template, $vars );
}


sub graph
{
	my $self = shift;
	my $using = $self->query()->param('using');
	lc( $using );
	
	my $resolution = $self->query()->param('resolution');
	my $cf = $self->query()->param('cf');
	
	my $uri = $self->query()->param('uri');
	my $urn = $self->query()->param('urn');
	
	my $endTime = $self->query()->param('end') || time();
	my $period = $self->query()->param('period');
	my $startTime = undef;
	# def'd from period
	if ( $period ) {
	    $startTime = $endTime - $period
    }
    # else let the service work it out
	
	my $graph = $self->SUPER::graph( $uri, $using, $urn, $startTime, $endTime,
	                                    $resolution, $cf );
	$self->header_add( -type => 'image/png' );
	return $$graph;
}


1;

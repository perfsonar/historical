use gmaps::paths;
use utils::xml;

use gmaps::Services::Lookup;
use gmaps::Services::Topology;
use gmaps::Services::Utilisation;
use gmaps::Services::PingER;
use gmaps::Services::BWCTL;
use gmaps::Services::OWAMP;

use gmaps::Graph::RRD;
use gmaps::Graph::RRD::Utilisation;
use gmaps::Graph::RRD::PingER;
use gmaps::Graph::RRD::Throughput;
use gmaps::Graph::RRD::Latency;

use URI::Escape;

use utils::urn;

use Template;
use Data::Dumper;

use LWP::UserAgent;

=head1 NAME

gmaps::Interface - An interface to interact with a remote service.  

=head1 DESCRIPTION

This module provides functions to query a remote perfsonar measurement point
or measurement archive. Inherited classes should overload the appropiate
methods to provide customised access to the service in question.

=head1 SYNOPSIS

    use gmaps::Service;
    
    # create a new service
    my $service = gmaps::Service->new( 'http://localhost:8080/endpoint' );
  
	# check to see that the service is alive
	if ( $service->isAlive() ) {
		
		# get a list of the available urn's on the service
		my $list = $service->getUrns();
		
		
		
	} else {
		
		print "Error: Service is not alive.";
		
	}

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=cut

package gmaps::Interface;

use fields qw( TEMPLATE );

our $gLSRoot = 'http://www.perfsonar.net/gls.root.hints';

our $logger = Log::Log4perl::get_logger( 'gmaps::Interface');

use strict;


#######################################################################
# generic interfaces to gmaps data
#######################################################################

=head2 new
create a new interface instance to query perfsonar servers
=cut
sub new
{
	my gmaps::Interface $self = shift;
	unless ( ref $self ) {
		$self = fields::new( $self );
	}
	return $self;
}

#######################################################################
# tools and utility functions
#######################################################################


=head2 template
accessor/mutator for the template
=cut
sub template
{
	my $self = shift;
	if ( @_ ) {
		$self->{'TEMPLATE'} = shift;
	}
	return $self->{'TEMPLATE'};
}

=head2 processTemplate
process the template 
=cut
sub processTemplate
{
	my $self = shift;
	my $xml = shift;
	my $vars = shift;

	$logger->logdie( "processTemplate must be overriden.");

}





#######################################################################
# Discovery
#######################################################################

=head2 discover( $uri, $using )
returns a list of the urn's representing the metadata contained within the
service at uri
=cut
sub discover
{
	my $self = shift;
	
	my $uri =shift;
	my $using = shift;
	lc( $using );
	if ( ! defined $uri ) {
		$uri = $self->query()->param( 'uri' );
	}
	$uri = utils::xml::unescape( $uri );
	$logger->debug( "url: $uri");

	my ( $using, $service ) = $self->createService( $uri, $using );
	$logger->debug( "Discovery mechanism '$using'.");		
	
	# return just list of urns
	my $data =  $service->discover();
	if ( scalar @$data < 1 ) {
		$logger->fatal( "No urns were found on '$using' service '$uri'");
	}

	return $data;	
}

=head2 topology( $uri, $using )
returns a list of the urn's representing the metadata contained within the
service at uri
=cut
sub topology
{
	my $self = shift;
	
	my $uri =shift;
	my $using = shift;
	lc( $using );
	if ( ! defined $uri ) {
		$uri = $self->query()->param( 'uri' );
	}
	$uri = utils::xml::unescape( $uri );
	$logger->debug( "url: $uri");

	my ( $using,  $service ) = $self->createService( $uri, $using );
	$logger->debug( "Discovery mechanism '$using'.");		
		
	# return just list of urns
	my $data =  $service->topology();
	if ( scalar @$data < 1 ) {
		$logger->fatal( "No urns were found on '$using' service '$uri'");
	}

	return $data;	
}




=head2 getGLS

returns the top level registered gLSs

=cut
sub getGLS
{
    my $self  = shift;
    
    my $ua = LWP::UserAgent->new;
    $ua->agent( ${gmaps::paths::version} );

    my $req = HTTP::Request->new(POST => $gLSRoot);
    my $res = $ua->request($req);
    
    my @gLS = ();
    if ($res->is_success) {
        push @gLS, split /\s+/, $res->content;
    }
    else {
        $logger->logdie( "Could get list of global Lookup services from '$gLSRoot'.");
    }

    return \@gLS;
}


=head2 getHLS

returns a list of hls's from a given gLS endpoint

=cut
sub getHLS
{
    my $self = shift;
    my $glsUrl = shift;
    
    # query a gLS for hLS's.
    my @hLS = ();
    
    my $list = $self->discover( $glsUrl, 'lookup' );
	foreach my $urn ( @$list ) {
	    
	    my $hash = utils::urn::toHash( $urn );

        if ( $hash->{serviceType} ne 'hLS' ) {
            $logger->error( "Unknown service type for '$urn'.");
            next;
	    }
	    
        push @hLS, $hash->{accessPoint}
            if $hash->{accessPoint};
	
	}
    
    return \@hLS;
}


=head2 getServices

given a hLS, will return a list (urn) of services registered on that hLS

=cut
sub getServicesFromHLS
{
    my $self = shift;
    my $hlsURL = shift;
    
    my $list = $self->discover( $hlsURL, 'lookup' );
	
	my @services = ();
	
	foreach my $urn ( @$list ) {
    
        # remap the serviceTypes
        my $hash = utils::urn::toHash( $urn );

        # need to dtermine the approrpiate service Type
        if ( $hash->{serviceType} eq 'hLS' ) {
            $hash->{serviceType} = 'lookup';
        } else {
            $hash->{serviceType} = $self->autoDetermineServiceType( $hash->{accessPoint} );
        }
        
        # need to add two service types for perfsonar buay
        if ( $hash->{serviceType} eq 'perfSONAR_BUOY' ) {
            
            my $serviceName = $hash->{serviceName};
            foreach my $type ( qw/ owamp bwctl / ) {
                $hash->{serviceType} = $type;
                $hash->{serviceName} =  $serviceName . ' (' . $type . ')';
                push @services, utils::urn::fromHash( $hash );
            }
            
        } else {    
            push @services, utils::urn::fromHash( $hash );
        }
    }
    
    return \@services;
}

=head2 getListOfServices

Queries the high level gLS and then hLS's to get service endpoints for perfsonar data

=cut
sub getServices
{
    my $self = shift;
    my $gLS = shift;
    
    # get top level LS list
    $gLS = $self->getGLS()->[0]
        if ! defined $gLS;

    # list of urn's of the endpoint services
    my @services = ();

    # find hLS's on gLS
    $logger->debug( "Querying global LS entry '" . $gLS . "'");
    my $hLS = $self->getHLS( $gLS );
    my $count = 1;
    foreach my $ls ( @$hLS ) {
        $logger->debug( "  Querying domain LS entry '$ls' ($count/" . scalar @$hLS . ")" );
        
        if ( URI::Escape::uri_unescape( $ls ) eq 'http://lab244.internet2.edu:8095/perfSONAR_PS/services/hLS' ) {
            $logger->warn( "skipping lookup of " . URI::Escape::uri_unescape($ls) );
            $count++;
            next;
        }
        
        # get endpoints for perfsonar services
        eval {
            my $services = $self->getServicesFromHLS( $ls );
            foreach my $service ( @$services ) {
                $logger->debug( "    found service $service");
                push @services, $service;
            }
        };
        if ( $@ ) {
#            $logger->warn( "ERROR! $@");
        }

        $count++;
    }

    return \@services;
}




=head2 fetch( uri, using, urn )
retrieve a table of information from the urn
=cut
sub fetch
{
	my $self = shift;
	
	my $uri =shift;
	my $using = shift;
	my $urn = shift;
	
	my $startTime = shift;
	my $endTime = shift;
	
	my $resolution = shift;
	my $cf = shift;
	
	$uri = utils::xml::unescape( $uri );
	$urn = utils::xml::unescape( $urn );
	
	$logger->debug( "url: $uri, urn: $urn: start: $startTime, end: $endTime, res: $resolution, cd: $cf");

	my $service = undef;
	( $using, $service ) = $self->createService( $uri, $using );
	
	# retrieve numeric data from service
	my $data = $service->fetch( $urn, 
	                            $startTime, $endTime, 
	                            $resolution, $cf );
	
	# TODO: This shoudl throw an exception instead 
	if ( scalar keys %$data < 1 ) {
		$logger->fatal( "No data was found on '$using' service '$uri' for '$urn'");
		exit;
	}
	
	return ( $service->fields(), $data );
}


=head2 graph( uri, using, urn )
generates a rrd graph
=cut
sub graph
{
	my $self = shift;
	
	my $uri = shift;
	my $using = shift;
	my $urn = shift;
    
	my $startTime = shift;
	my $endTime = shift;
	
	my $resolution = shift;
	my $cf = shift;
	
	# default
	$using = $self->autoDetermineServiceType( $uri )
		if ! defined $using;


	# determine the correct grpah type to create
	my $class = 'gmaps::Graph::RRD';
	if ( $using eq 'utilisation' ) {
		$class .= '::Utilisation';
	} elsif ( $using eq 'pinger' ) {
		$class .= '::PingER';
	} elsif ( $using eq 'bwctl' ) {
	    $class .= '::Throughput';
         $resolution = $resolution || 1800;
    } elsif ( $using eq 'owamp' ) {
        $class .= '::Latency';
	} else {
		$logger->warn( "Could not determine appropriate graphing class to use");
	}
	
	# default resolution
	$resolution = $resolution || 300;
	
	# fetch the data	
	my ( $fields, $data ) = $self->fetch( $uri, $using, $urn,
                        	    $startTime, $endTime,
                        		$resolution, $cf );
	
	### create the graph
	# get the start and end
	my @times = sort {$a <=> $b} keys %$data;
	my $start = $times[0];
	my $end = $times[$#times];

	# entries
	my $entries = scalar( @times );
	
	# don't bother if we don't have any data
	if ( $entries eq 0 ) {
		return undef;
	}
	

	# create temp rrd
	my ( undef, $rrdFile ) = &File::Temp::tempfile( ) ; #UNLINK => 1 );	
	no strict 'refs';
	my $rrd = $class->new( $rrdFile, $start, $resolution, $entries, @$fields );
	use strict 'refs';
	
	# add the data into the rrd
	my $prev = undef;
	my $realStart = undef;
	my $realEnd = undef;

	foreach my $t ( @times )
	{
		next if $t <= $prev;
		next if $t == 10;

		$realStart = $t if $t < $realStart || ! defined $realStart;
		$realEnd = $t if $t > $realEnd || ! defined $realEnd;

		$rrd->add( $t, $data->{$t} );
		
		$prev = $t;
	}
	
	# now get the graph from the rrd
	my ( undef, $pngFilename ) = &File::Temp::tempfile( UNLINK => 1 );		
	$logger->debug( "start time: $realStart, end time: $realEnd" );	
	# ref to scalar
	my $graph = $rrd->getGraph( $realStart, $realEnd, $pngFilename );

	# clean up
	unlink $pngFilename or $logger->warn( "Could not unlink '$pngFilename'" );
	undef $rrd;

	return $graph;	

}


#######################################################################
# UTILITY
#######################################################################

=head2 createService( $uri, $using )
returns the appropiate client service object for the uri. optional $using
will force it an appropiate class type
=cut
sub createService
{
	my $self = shift;
	my $uri = shift;
	my $using = shift;
	
	# auto determine from uri if no using supplied
	if ( ! defined $using ) {
		$using = $self->autoDetermineServiceType( $uri );		
	}
	
	# determine the class to use
	my $class = undef;
	if ( $using eq 'topology' ) {
		$class = 'Topology';	
	} elsif ( $using eq 'utilisation' ) {
		$class = 'Utilisation';
	} elsif ( $using eq 'pinger') {
		$class = 'PingER';
	} elsif ( $using eq 'bwctl' ) {
		$class = 'BWCTL';
	} elsif ( $using eq 'owamp' ) {
		$class = 'OWAMP';
	} elsif ( $using eq 'lookup' ) {
		$class = 'Lookup';
	} else {
		$logger->logdie( "Discovery mechanism '$using' is not supported.");		
	}
	# create the service
	my $method = 'gmaps::Services::' . $class;
	no strict 'refs';
	my $service = $method->new( $uri );
	use strict 'refs';
	$logger->debug( "Created a " . $service . " for '$uri'");

	return ( $using, $service );	
}


=head2 autoDetermineServiceType( $uri )
tries to determine the service type for hte uri provided
=cut
sub autoDetermineServiceType
{
	my $self = shift;
	my $uri = shift;
	
	if ( $uri =~ /rrd/i or $uri =~ /snmp/ ) {
		return 'utilisation';
	} elsif ( $uri =~ /topology/i ) {
			return 'topology';
	} elsif ( $uri =~ /pinger/i ) {
		return 'pinger';
	} elsif ( $uri =~ /LS/i ) {
		return 'lookup';
	} elsif ( $uri =~ /pSB/i ) {
	    return 'perfSONAR_BUOY';
	} else {
		$logger->logdie( "Cannot determine service type form uri '$uri'");
	}
	
	return undef;
}








1;


=head1 SEE ALSO

L<perfSONAR_PS::Transport>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: PingER.pm 227 2007-06-13 12:25:52Z zurawski $

=head1 AUTHOR

Yee-Ting Li, E<lt>ytl@slac.stanford.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut


use utils::urn;
use gmaps::Location;
use Log::Log4perl qw(get_logger);


=head1 NAME

gmaps::Services::Lookup - An interface to interact with a global lookup service 

=head1 DESCRIPTION

This module provides functions to query a remote perfsonar measurement point
or measurement archive. Inherited classes should overload the appropiate
methods to provide customised access to the service in question.

=head1 SYNOPSIS

    use gmaps::Services::PingER;
    
    # create a new service
    my $service = gmaps::Service::PingER->new( 'http://localhost:8080/endpoint' );
  
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

package gmaps::Services::Lookup;
use base 'gmaps::Service';

our $logger = Log::Log4perl->get_logger( "gmaps::Services::Lookup");

use strict;

=head2 new( uri )
Create a new client object to interact with the uri
=cut
sub new
{
	my gmaps::Services::Lookup $class = shift;
	my $self = fields::new( $class ); 
	$self->SUPER::new( @_ );

	return $self;
}

#######################################################################
# INTERFACE
#######################################################################

=head2 isAlive
returns aboolean of whether the pinger service is alive or not
=cut
sub isAlive
{
	my $self = shift;
	my $eventType = 'echo';
	return $self->SUPER::isAlive( $eventType );
}


=head2 discover
Returns a list of urns that the service contains
=cut
sub discover
{
	my $self = shift;
	my $data = $self->topology();
	my @urns = ();
	foreach my $urn ( @$data ) {
		push @urns, $urn->{urn};
	}
	return \@urns;
}


=head2 topology
retrieves as much information about the metadata of the service as possible
=cut
sub topology
{
	my $self = shift;
	my $array = $self->getPorts();
	return $array;
}


=head2 fetch( urn )
returns a hashof $hash->{$time}->{metric} values for the specified urn.
=cut
sub fetch
{
	my $self = shift;
	my $urn = shift;
	
	my $period = undef;
	
	my ( $temp, $temp, $temp, $path, @params ) = split /\:/, $urn; 
	$logger->debug( "PATH: $path, @params");
	
	my $src = undef;
	my $dst = undef;
	if( $path =~ m/^path\=(.*) to (.*)$/ ) {
		$src = $1;
		$dst = $2;
	} else {
		
		$logger->logdie( "Could not determine source and destination or urn");
		
	}
	$logger->debug( "Fetching '$urn': path='$src' to '$dst' params='@params'" );

	# determine if the port is a ip address
	my $vars = {
			'src' => $src,
			'dst' => $dst,
		};

	# form the parameters
	foreach my $s ( @params ) {
		my ( $k, $v ) = split /\=/, $s;
		$vars->{$k} = $v;
	}

	if ( defined $period ) {
		$vars->{'PERIOD'} = $period;
	} else {
		$vars->{'PERIOD'} = 86400;
	}
	# need to have real time becuase of problems with using N
	$vars->{"ENDTIME"} = time();
	$vars->{'STARTTIME'} = $vars->{'ENDTIME'} - $vars->{'PERIOD'};

	# fetch the data form the ma
	my $requestXML = 'Lookup/fetch_xml.tt2';
	my $filter = '//nmwg:message';
	
	# we only get one message back, so 
	my @temp = ();
	my ( $message, @temp ) = $self->processAndQuery( $requestXML, $vars, $filter );
	
	# now get teh actually data elements
	return $self->parseData( $message );
	
}



#######################################################################
# UTILITY
#######################################################################


###
# returns list of urns of monitorign ports
###
sub getPorts
{
	my $self = shift;
	my $urn = shift;
	
	my $requestXML = 'Lookup/query-all-ports_xml.tt2';
	my $filter = '//nmwg:message/nmwg:data[@id]/nmwg:metadata';

	# overload query
	my $vars = {
	};
	my @ans = $self->processAndQuery( $requestXML, $vars, $filter );
	
	# renove unique urns
	my %seen = ();
	
	my @out = ();
	foreach my $meta ( @ans ) {

		my $hash = {
			
			'serviceName'	=> undef,
			'accessPoint'	=> undef,
						
			'serviceType' => undef,
			'serviceDescription' => undef,
			
			'urn' => $urn,
			
			# mas
			'mas' => [],
		};
			
		foreach my $node ( $meta->childNodes() ) 
		{
			# hostnames
			# TODO: support other topology type (with ip address)
			#$logger->warn( "TAG: " . $node->localname() );
			
			if ( $node->localname() eq 'subject' ) {
				foreach my $subnode ( $node->childNodes() )  {
				    				    
        			#$logger->warn( "SUBTAG: " . $subnode->localname() );

					if ( $subnode->localname() eq 'service' ) {
						foreach my $subsubnode ( $subnode->childNodes() ) {
							if ( $subsubnode->localname() eq 'serviceName' ) {
								$hash->{serviceName} = $subsubnode->textContent;
							}
							elsif ( $subsubnode->localname() eq 'accessPoint' ) {
								$hash->{accessPoint} = $subsubnode->textContent;
							}
							elsif ( $subsubnode->localname() eq 'serviceType' ) {
								$hash->{serviceType} = $subsubnode->textContent;
							}
							elsif ( $subsubnode->localname() eq 'serviceDescription' ) {
								$hash->{serviceDescription} = $subsubnode->textContent;
							}
						}
					}
				} #subnode
			}

		}

		# don't bother if we don't have a valid port for this node
		next unless ( $hash->{accessPoint} && $hash->{serviceType} && $hash->{serviceName});


        # remap accessPoint to URL
        $hash->{accessPoint} = URI::Escape::uri_escape( $hash->{accessPoint} );
        
		# add params to urn (prob not what we want to do...)
		$hash->{urn} = 'urn:ogf:network:serviceType=' . $hash->{serviceType} . ':serviceName=' . $hash->{serviceName} . ':accessPoint=' . $hash->{accessPoint};

        # no point adding it more than once
        $seen{$hash->{urn}}++;
        next if $seen{$hash->{urn}} > 1;
        
		# add own ma
		push ( @{$hash->{mas}}, { 'type'=> 'LS', 'uri' => $self->uri() } ); 

        my ( $host, undef, undef ) = &perfSONAR_PS::Transport::splitURI( utils::xml::unescape( $hash->{accessPoint} ) );

		# determine coordinate posisionts
		# get urns for source and dst for location lookups etc
		( $hash->{latitude}, $hash->{longitude} ) = gmaps::Location->getLatLong( $host, $host, undef, $hash->{urn} );

        #$logger->warn( "ENTRY: " . Data::Dumper::Dumper $hash );

		# add it
		push @out, $hash

	}
	#$logger->info( "Found ports: @out");
	return \@out;
}

#######################################################################
# data handling
#######################################################################

=head2 parseData
given the <nmwg:message/> element, will parse through and retrieve a 
hash of $hash->{$time}->{minRtt|maxRtt...} values;
=cut
sub parseData
{
	my $self = shift;
    my $el = shift; # //message
    
    $logger->logdie( "Fetch not implemented in LS lookups");
    return undef;
}




1;



=head1 SEE ALSO

L<gmaps::Service>

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

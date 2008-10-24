use utils::urn;
use gmaps::Location;
use Log::Log4perl qw(get_logger);


=head1 NAME

gmaps::Services::Utilisation - An interface to interact with a remote 
utilisation service.  

=head1 DESCRIPTION

This module provides functions to query a remote perfsonar measurement point
or measurement archive. Inherited classes should overload the appropiate
methods to provide customised access to the service in question.

=head1 SYNOPSIS

    use gmaps::Services::Utilisation;
    
    # create a new service
    my $service = gmaps::Service::Utilisation->new( 'http://localhost:8080/endpoint' );
  
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
package gmaps::Services::Utilisation;
use base 'gmaps::Service';

our $logger = Log::Log4perl->get_logger( "gmaps::Services::Utilisation");

our $eventType = 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0';

use Data::Dumper;
use strict;

=head2 new( uri )
create a new instance of a utilisation client service
=cut
sub new
{
	my gmaps::Services::Utilisation $class = shift;
	my $self = fields::new( $class );
	$self->SUPER::new( @_ );
	return $self;
}


#######################################################################
# INTERFACE
#######################################################################


=head2 isAlive
returns boolean of whether the client service is alive or not 
=cut
sub isAlive
{
	my $self = shift;
	my $eventType = 'echo.ls';
	return $self->SUPER::isAlive( $eventType );
}


=head2 discover
retrieves as much information about the metadata of the service as possible
and returns a list of urns
=cut
sub discover
{
	my $self = shift;
	my @list = ();
	foreach my $a ( @{$self->getPorts()} ) {
		push @list, $a->{urn};
	}
	return \@list;
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



=head2 fetch( uri, startTime, endTime )
retrieves the data for the urn
=cut
sub fetch
{
	my $self = shift;
	my $urn = shift;
	
	my $startTime = shift;
	my $endTime = shift;
	
	my $resolution = shift || 60;
	my $cf = shift;
	
	
	( $startTime, $endTime ) = $self->checkTimeRange( $startTime, $endTime );
    
	
	my ( $domain, $node, $port ) = &utils::urn::fromUrn( $urn );
	$logger->debug( "Fetching '$urn': domain='$domain' node='$node' port='$port'" );

	# determine if the port is a ip address
	my $vars = {
			'ifName' => $port,
			'authRealm' => $domain,
			'hostName'  => $node,
		};

	if ( defined $eventType ) {
		$vars->{'eventType'} => $eventType,
	}

	# time range
	$vars->{"ENDTIME"} = $endTime
		if defined $endTime;
	$vars->{'STARTTIME'} = $startTime
		if defined $startTime;

	if ( defined $cf ) {
		$vars->{'CF'} = $cf;
	}
	if ( defined $resolution ) {
		$vars->{'RESOLUTION'} = $resolution;
	}

	# fetch the data form the ma
	my $requestXML = 'Utilisation/fetch_xml.tt2';
	my $filter = '//nmwg:message';
	
	# we only get one message back, so 
	my @temp = ();
	my ( $message, @temp ) = $self->processAndQuery( $requestXML, $vars, $filter );

	my $idRef = $self->getDataId( $message );	
	$logger->debug( "Found metadata ids for in=" . $idRef->{in} . ' and out=' . $idRef->{out} );
	
	# list the fields as in and out
	@{$self->{FIELDS}} = qw( in out );
	
	# now get teh actually data elements
	return parseData( $message, $idRef );
	
}


#######################################################################
# UTILITY
#######################################################################

=head2 getPorts( urn )
 returns list of urns of monitorign ports
=cut
sub getPorts
{
	my $self = shift;
	my $urn = shift;
	
	my $requestXML = 'Utilisation/query-all-ports_xml.tt2';
	my $filter = '//nmwg:message/nmwg:metadata[@id]/netutil:subject/nmwgt:interface';

	# overload query
	my $vars = {
		'EVENTTYPE' => $eventType,
	};
	my @ans = $self->processAndQuery( $requestXML, $vars, $filter );
		
	my @out = ();
	foreach my $meta ( @ans ) {

		my $hash = {
			'hostName' => undef,
			'description' => undef,
			'domain' => undef,
			'name' => undef,
			
			'longitude' => undef,
			'latitude' => undef,
			
			'urn' => $urn,
			'ipAddress' => undef,
			'ifName' => undef,
			'netmask' => undef,
			'ifDescription' => undef,
			'capacity' => undef,
			
			# mas
			'mas' => [],
		};
			
		foreach my $node ( $meta->childNodes() ) 
		{
			if ( $node->localname() eq 'hostName' ) {
				$hash->{node} = $node->to_literal();
				$hash->{hostName} = $node->to_literal();
				$hash->{name} = $node->to_literal();
			} elsif ( $node->localname() eq 'ifAddress' ) {
				$hash->{ipAddress} = $node->to_literal();
			} elsif ( $node->localname() eq 'ifName' ) {
				$hash->{ifName} = $node->to_literal();
			} elsif ( $node->localname() eq 'ifDescription' ) {
				$hash->{ifDescription} = $node->to_literal();	
			} elsif ( $node->localname() eq 'capacity' ) {
				$hash->{capacity} = $node->to_literal();
			} elsif ( $node->localname() eq 'authRealm' ) {
				$hash->{domain} = $node->to_literal();
			}
		}

		# problem is that some of the services out there are all layer 3 - however, 
		# are configured incorrectly such that the only discernable difference between
		# metadata is that of the ifName as the ipAddress points at the management ip
		# rather than the router/gateway ip.
		# determine layer
		if ( $hash->{ipAddress} && $hash->{ifName} ) {
			$hash->{port} = $hash->{ifName};
		} elsif( ! $hash->{ifName} ) {
			$hash->{port} = $hash->{ipAddress};
		} else {
			$hash->{port} = $hash->{ifName};
		}

		# if null domain
		if ( ! defined $hash->{domain} ) {
			$hash->{domain} = ${utils::urn::unknown};
		}

		# don't bother if we don't have a valid port for this node
		next unless ( $hash->{port} );

		# add own ma
		push ( @{$hash->{mas}}, { 'type'=> 'utilisation', 'uri' => $self->uri() } ); 

		# determine urn for node
		$hash->{urn} = &utils::urn::toUrn( { 'domain' => $hash->{domain}, 'node' => $hash->{node}, 'port' => $hash->{port}});

		# determine coordinate posisionts
		# TODO: host name may need to be qualified
		#$logger->debug( "fetch location: " . $hash->{urn} . " @ " . $hash->{hostName} . ', ' . $hash->{ipAddress} );
		( $hash->{latitude}, $hash->{longitude} ) = gmaps::Location->getLatLong( $hash->{urn}, undef, $hash->{hostName}, $hash->{ipAddress} );

#		$logger->debug( "Constructed URN: $urn\n" . Dumper $hash );	

		# add it
		push @out, $hash;

	}
	#$logger->info( "Found ports: @out");
	return \@out;
}



sub getDomains
{
	my $self = shift;

}




#######################################################################
# data handling
#######################################################################

# determines the appropiate id for the in and out
sub getDataId
{
	my $self = shift;
	my $message = shift;

	# METHOD 1:
        # determine the appropiate id's for the metadata/data relation from their direction
        # use the fact htat we have loaded the query with metaIn and metaOut, so search for these
        # in the metadata attribute list as metadataIdRef="#metaIn".
        # then we need to match the @id value to the @metadataidRef in the relevant //nmwg:data element

        my $idRef = {
                'in' => undef,
                'out' => undef,
        };
        foreach my $meta ( $message->findnodes( "//nmwg:metadata[\@id]" ) ) {
                $logger->debug( "META: $meta \n" . $meta->toString() );
                # get attribute
                if ( $meta->getAttribute( 'metadataIdRef') eq '#in' ) {
                        $idRef->{in} = $meta->getAttribute( 'id' );
                }
                elsif ( $meta->getAttribute( 'metadataIdRef') eq '#out' ) {
                        $idRef->{out} = $meta->getAttribute( 'id' );
                }

        }

	if ( defined $idRef->{in} && defined $idRef->{out} ) {
		return $idRef;
	}

	$logger->debug( "Trying method 2 to determine metadata/data relations" );

	# however, the java implementation rewrites the tags... :(
	# METHOD 2
	# do through each meta data and determine whether the direction is in or out	
	foreach my $direction ( qw/in out/ ) {
		my $xpath = "//nmwg:metadata[\@id][descendant::nmwgt:direction[text()='" . $direction . "']]" ;
		foreach my $meta ( ${utils::xml::xpc}->find( $xpath, $message )->get_nodelist() ) {
			$idRef->{$direction} = $meta->getAttribute( 'id' );
		}
	}

	if ( defined $idRef->{in} && defined $idRef->{out} ) {
                return $idRef;
    } else {
		$logger->fatal( "Could not determine appropiate metadata/data relationship" );
	}


}

sub parseData
{
        my $el = shift;# output of getUtilization
        my $idRefs = shift;

        my $data = undef;

		$logger->debug( "Metadata id's for in: " . $idRefs->{in} . ", out: " . $idRefs->{out});

        # now we need to fetch the data from the xpath xml structure
        $data = &mergeUtilizationData(
                                &getUtilizationData( $el, $idRefs->{in} ),
                                &getUtilizationData( $el, $idRefs->{out} )
                        );

        #$logger->debug( Dumper $data );
                
        return $data;
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
        my $el = shift; # //message
        my $metadataIdRef = shift;

        $logger->debug( "Getting utilisation data using '$metadataIdRef'" );
        my @tuples = ();

	foreach my $child ( $el->childNodes() ) {
		
		#$logger->fatal( " $metadataIdRef -> " . $child->localname() );
		
		if ( $child->localname() eq 'data'
		  && $child->getAttribute( 'metadataIdRef' ) eq $metadataIdRef )
		{
			$logger->debug( "Found! <data/> for $metadataIdRef" );
			
			foreach my $datum ( $child->childNodes() ) {
				if( $datum->localname() eq 'datum' ) {
					
					#$logger->info( "  " . $datum->toString );
					
					# get the time of the datum
					my $time = $datum->getAttribute( 'timeValue' );
					if ( ! $time ) {
						$time = $datum->getAttribute( 'time' );
					}
					next unless $time =~ /^\d+$/;

					# fix bug
					next if $time < 1000000;

					# get the value
					my $value = $datum->getAttribute('value');
					next if $value eq 'nan';

					# add
					push( @tuples, $time . ':' . $value );
				}
			}
			last; # don't bother searching through the rest of it
		}
	}

        $logger->debug( "Entries = " . scalar @tuples );

        return \@tuples ;
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

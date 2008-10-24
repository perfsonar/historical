#!/bin/env perl


#######################################################################
# class to query and retrieve info lookup services
#######################################################################

use gmaps::Service;

package gmaps::Lookup;
@ISA = ( 'gmaps::Service' );

use Log::Log4perl qw( get_logger );
our $logger = Log::Log4perl::get_logger( 'gmaps::Lookup' );

use strict;



#######################################################################
# class functions
#######################################################################
sub new
{
	my $classname = shift;
	return $classname->SUPER::new( @_ );
}


sub getDomains
{
	my $self = shift;
	$logger->logdie( "getDomains() is abstract and should be overridden.");

}

###
# returns list of topology serviecs by sending xquery to the service
###
sub getTopologyServices
{
	my $self = shift;
	$logger->logdie( "getTopologyServices() is abstract and should be overridden.");

}


###
# returns list of rrd services
###
sub getRRDServices
{
	my $self = shift;
	$logger->logdie( "getTopologyServices() is abstract and should be overridden.");

}


#######################################################################
# utility functions
#######################################################################


###
# sends the supplied text as xquery to the service
###
sub query
{
	my $self = shift;
	return 1;
}



1;
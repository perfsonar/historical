#!/bin/env perl

###
# 
###
use gmaps::MA::RRDMA;


my $ip = '134.55.209.93';



my $routerInfo = &gmaps::MA::RRDMA::getUtilizationData(  
						'mea1.es.net',
						'8080',
						'/axis/services/MeasurementArchiveService',						
						$ip );

my $meta = &gmaps::MA::RRDMA::getMetadata( $routerInfo );

my $history = &gmaps::MA::RRDMA::getGraph( $routerInfo, $meta );


1;

#!/bin/env perl

use gmaps::Topology;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

package gmaps::LookupService::StaticLS;

our $logger = Log::Log4perl->get_logger( "gmaps::LookupService::StaticLS");

our %maMap = (
				'perfsonar.net' => { 
				},
				'geant2.net' => { 
					host => 'stats.geant2.net', 
					port => '80', 
					endpoint => 'perfsonar/RRDMA-access/MeasurementArchiveService',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'geant.net' => { 
					host => 'stats.geant2.net', 
					port => '80', 
					endpoint => 'perfsonar/RRDMA-access/MeasurementArchiveService',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'es.net'	=> { 
					host => 'mea1.es.net', 
					port => '8080',
					endpoint => 'perfSONAR_PS/services/snmpMA',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'internet2.edu' => {
					host => 'util.net.internet2.edu',
					port => '8080',
					endpoint => 'perfSONAR_PS/services/snmpMA',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'switch.ch' => { 
					host => 'archive.sonar.net.switch.ch', 
					port => '8180', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'seeren.org' => { 
					host => 'loco4.man.poznan.pl', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},
				'esnet.cz' => {
					host => 'perfmonc.cesnet.cz', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'fnal.gov' => {
					host => 'lhcopnmon1-mgm.fnal.gov', 
					port => '8091', 
					endpoint => 'perfSONAR_PS/services/snmpMA',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
				'garr.it' => {
					host => 'srv4.dir.garr.it', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},									
				'garr.net' => {
					host => 'srv4.dir.garr.it', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},
				'grnet.gr' => {
					host => 'gridmachine.admin.grnet.gr', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},		
				'carnet.hr' => {
					host => 'noc-mon.srce.hr', 
					port => '8090', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},		
				'pionier.gov.pl' => {
					host => 'loco4.man.poznan.pl', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},		
				'surfnet.nl' => {
					host => 'sonar1.amsterdam.surfnet.nl', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},
				'surf.net' => {
					host => 'sonar1.amsterdam.surfnet.nl', 
					port => '8080', 
					endpoint => 'axis/services/MeasurementArchiveService',
					eventType => 'utilization'
				},
				'renater.fr' => {
					host => '193.49.159.5', 
					port => '8080', 
					endpoint => 'perfSONAR-RRD-MA-2.0/services/MeasurementArchiveService',
					eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
				},
                		'slac.stanford.edu' => {
              	 	 	    host => 'net-desk1.slac.stanford.edu',
            			    port => '8080',
                    		    endpoint => 'axis/services/snmpMA',
                    		    eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
                		},
                                'sox.net' => {
                                    host => 'bunsen.rnoc.gatech.edu',
                                    port => '8080',
                                    endpoint => 'axis/services/snmpMA',
                                    eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
                                },
                                'gatech.edu' => {
                                    host => 'bunsen.rnoc.gatech.edu',
                                    port => '8080',
                                    endpoint => 'axis/services/snmpMA',
                                    eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
                                },
                                'udel.edu' => {
                                    host => 'ale.pc.cis.udel.edu',
                                    port => '6767',
                                    endpoint => 'perfSONAR_PS/services/snmpMA',
                                    eventType => 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0'
                                },


			);


sub getDomains
{
	return keys %maMap;
}


sub getMA
{
	my $ip = shift;
	my $router = shift;

	$logger->info( "Looking up IP: '$ip', Router: '$router'" );

	if ( &gmaps::Topology::isIpAddress( $router ) ) {
		( $ip, $router ) = &gmaps::Topology::getDNS( $router );
	}
	
	my $ma = undef;
		
	# if the ip doesn' tnot resolve, search the ip and return the MA
	if ( ! defined $router || $router eq '' ) {
		$logger->warn( "Could not determine automatically ma for ip $ip!");

		if ( $ip =~ /^172\.16\./ || $ip =~ /^172\.17\./ ) {
			$ma = 'fnal.gov';
		} elsif ( $ip =~ /^172\.18\./ || $ip eq '192.68.191.149' ) {
			$ma = 'slac.stanford.edu';
		}
		if ( $ma ) {
			$logger->warn( "Manual override MA to $ma" );
		} 

	}

	
	# and do a mapping for the ma info
	foreach my $k ( keys %maMap ) {
		if( $router =~ /$k$/) {
			$logger->info( "Found $k" );
			$ma = $k;
		}
		last if ( $ma );
	}

	if ( ! defined $ma ) {
		$logger->fatal ( "Could not determine MA for ip=$ip, router=$router");
		return ( undef, undef, undef, undef );
	}

	$logger->debug( "Returning Host: '$maMap{$ma}{host}', Port: '$maMap{$ma}{port}', Endpoint: '$maMap{$ma}{endpoint}', Eventtype: '$maMap{$ma}{eventType}'" );
	return ( $maMap{$ma}{host}, $maMap{$ma}{port}, $maMap{$ma}{endpoint}, $maMap{$ma}{eventType} );
}


1;

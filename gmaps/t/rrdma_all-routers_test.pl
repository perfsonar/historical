#!/bin/env perl

use gmaps::MA::RRDMA;



my $routers = &gmaps::MA::RRDMA::getAllRouters( 
		'mea1.es.net', 8080, 'axis/services/MeasurementArchiveService',
		'utilization' );
		
foreach my $r ( @$routers ) {
	print "$r\n";
}

exit;
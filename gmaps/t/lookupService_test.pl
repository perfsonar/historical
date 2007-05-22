#!/bin/env perl

###
# 
###
use gmaps::LookupService;


my $routers = &gmaps::LookupService::getAllRouters(  
						'mea1.es.net', 8080, 'axis/services/MeasurementArchiveService'
						);

#						'selena.acad.bg',
#						'8070',
#						'/axis/services/LookupService' );

foreach my $r (@$routers) {
	print "$r\n";
}

1;

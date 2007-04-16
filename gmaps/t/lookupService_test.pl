#!/bin/env perl

###
# 
###
use gmaps::LookupService;


my $routers = &gmaps::LookupService::getAllRouters(  
						'localhost', 8080, ''
						);

#						'selena.acad.bg',
#						'8070',
#						'/axis/services/LookupService' );

foreach my $r (@$routers) {
	print "$r\n";
}

1;
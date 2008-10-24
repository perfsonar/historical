#!/usr/bin/perl

#######################################################################
# User configuration
#######################################################################

# base directory for distribution's libraries
use lib '/home/ytl/svn-branches/yee/gmaps-with-topologyservice/lib/';
#use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/branches/yee/gmaps-with-topologyservice/lib/';

# base directory for perfsonar-ps libraries
use lib '/home/ytl/svn-branches/merge/lib/';
#use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/perfSONAR-PS/lib/';

# set the path to the template directory from the main distribution
my $baseTemplatePath = '/home/ytl/svn-branches/yee/gmaps-with-topologyservice/templates/';
#my $baseTemplatePath = '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/branches/yee/gmaps-with-topologyservice/templates/';

# google maps api key
# key for http://packrat.internet2.edu:8008
my $key = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBSFy_mUREMGUpX34adV9Mvl5aD4pBR2JOSPu3HOy4flLnGZ0Zme_8n3OA';
# key for http://packrat.internet2.edu:8006
#my $key = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBQxBfPQj89LYXvY-op7uLXzHtX06xSfJnmZu7IlIu02hdsFrOzBoMXc8g';

# cache file for location/coordinate lookups
my $locationCache = '/tmp/location.db';

#######################################################################


use Log::Log4perl qw(:easy);
use gmaps::paths;
use gmaps::Interface::web;

use strict;

if ( -e ${gmaps::paths::logFile} ) {
  Log::Log4perl->init( ${gmaps::paths::logFile} );
} else {
  Log::Log4perl->easy_init($INFO);
}

${gmaps::paths::templatePath} = $baseTemplatePath;
${gmaps::paths::googleMapKey} = $key;
${gmaps::paths::locationCache} = $locationCache;

# start the web application
my $app = gmaps::Interface::web->new( );
$app->run();

exit;

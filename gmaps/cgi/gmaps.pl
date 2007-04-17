#!/usr/bin/perl -T


# base directory for distribution's libraries
use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/lib';

# base directory for perfsonar-ps libraries
use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/perfSONAR-PS/lib';

# set the path to the template directory from the main distribution
my $baseTemplatePath = '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/templates/';

# the url for the webserver's cgi script
my $server = 'http://134.79.24.133:8080/cgi-bin/gmaps.pl';


use gmaps::gmap;

use strict;

${gmaps::gmap::templatePath} = $baseTemplatePath;
${gmaps::gmap::server} = $server;

# start the web application
my $app = gmaps::gmap->new();
$app->run();

exit;

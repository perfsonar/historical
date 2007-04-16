#!/usr/bin/perl -T


# base directory for distribution's libraries
use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/lib';

# base directory for perfsonar-ps libraries
use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/perfSONAR-PS/lib';

# set the path to the template directory from the main distribution
my $baseTemplatePath = '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/templates/';


use gmaps::gmap;

use strict;

${gmaps::gmap::templatePath} = $baseTemplatePath;
# start the web application
my $app = gmaps::gmap->new();
$app->run();

exit;

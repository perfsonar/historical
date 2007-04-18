#!/usr/bin/perl -T

#######################################################################
# User configuration
#######################################################################

# base directory for distribution's libraries
use lib '/usr/local/perfSONAR-PS/www/gmaps/lib';

# base directory for perfsonar-ps libraries
use lib '/usr/local/perfSONAR-PS/lib';

# set the path to the template directory from the main distribution
my $baseTemplatePath = '/usr/local/perfSONAR-PS/www/gmaps/templates/';

# the url for the webserver's cgi script
my $server = 'http://packrat.internet2.edu/gmaps/index.cgi';

# google maps api key
my $key = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBTqtQtVm1aGyLMgsoakj_oYcMGl-hRvvNZF5z32oFlOKJTF99NOhxXUxg';

#######################################################################

use gmaps::gmap;

use strict;

${gmaps::gmap::templatePath} = $baseTemplatePath;
${gmaps::gmap::server} = $server;
${gmaps::gmap::googlemapKey} = $key;

# start the web application
my $app = gmaps::gmap->new();
$app->run();

exit;

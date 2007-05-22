#!/usr/bin/perl

#######################################################################
# User configuration
#######################################################################

# base directory for distribution's libraries
use lib '/usr/local/perfSONAR-PS/www/gmaps/lib';
#use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/lib';

# base directory for perfsonar-ps libraries
use lib '/usr/local/perfSONAR-PS/lib';
#use lib '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/perfSONAR-PS/lib';

# set the path to the template directory from the main distribution
my $baseTemplatePath = '/usr/local/perfSONAR-PS/www/gmaps/templates/';
#my $baseTemplatePath = '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/trunk/gmaps/templates/';

# the url for the webserver's cgi script
my $server = 'http://packrat.internet2.edu/gmaps/index.cgi';
#my $server = 'http://134.79.24.133:8080/cgi-bin/gmaps.pl';

# google maps api key
my $key = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBTqtQtVm1aGyLMgsoakj_oYcMGl-hRvvNZF5z32oFlOKJTF99NOhxXUxg';
#my $key = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBSCiUxZOw432i6dgwL13ERiRlaSNRS5laPT7HkzCJQupyaoW8s87EsHmQ';

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

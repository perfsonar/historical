package gmaps::paths;

our $templatePath = '../templates/';
our $imagePath = '../html/images/';

our $googleMapKey = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBSxuTV5jGC7iqe3CBEO67Q89TZmIxSf-liBltLkv8fiOfBtSRo2MwLYiw';

our $logFile = '/tmp/gmaps.logging';

our $gLSRoot = 'http://www.perfsonar.net/gls.root.hints';

# caceh for location coordinates of urn
# if not defined, will not use a cache
our $locationCache = '/tmp/location.db';
our $locationDoDNSLoc = 1;
our $locationDoGeoIPTools = 1;

our $version = 'perfSONAR-PS-gmaps/3.0';


1;

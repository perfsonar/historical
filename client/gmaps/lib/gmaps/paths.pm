package gmaps::paths;

our $templatePath = '/afs/slac.stanford.edu/u/sf/ytl/Work/perfSONAR/perfSONAR-PS/branches/yee/gmaps-with-topologyservice/templates/';
our $googleMapKey = 'ABQIAAAAVyIxGI3Xe9C2hg8IelerBBSxuTV5jGC7iqe3CBEO67Q89TZmIxSf-liBltLkv8fiOfBtSRo2MwLYiw';

our $logFile = '/tmp/gmaps.logging';

# caceh for location coordinates of urn

# if not defined, will not use a cache
our $locationCache = '/tmp/location.db';
our $locationDoDNSLoc = 1;
our $locationDoGeoIPTools = 1;

our $version = 'perfSONAR-PS-gmaps/2.0';

1;

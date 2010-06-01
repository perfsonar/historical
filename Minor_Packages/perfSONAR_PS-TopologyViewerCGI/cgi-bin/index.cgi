#!/usr/bin/perl -w

use strict;
use warnings;
use CGI;
use Config::General;
use XML::Tidy;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Client::Topology;
use perfSONAR_PS::Common qw( escapeString );

my $CONFIG_DIRECTORY = "$Bin/../etc";
my $CONFIG_FILE      = $CONFIG_DIRECTORY. "/topologyViewer.conf";

# Read in configuration information
my $config = Config::General->new( $CONFIG_FILE );
my %conf   = $config->getall;

my $cgi = CGI->new();

my $INSTANCE = $conf{'ts_instance'};
my $domain = $cgi->param("domain");

my $client = perfSONAR_PS::Client::Topology->new($INSTANCE);

unless ($INSTANCE) {
    print $cgi->header('text/html');
    print qq(<html>
                <title>Topology Lookup Error</title>
                <h1>Topology Lookup Error</h1>
                <br>
                Problem with configuration.
             </html>
    );
    exit 0;
}

unless ($domain) {
    print $cgi->header('text/html');
    print qq(<html>
                <title>Topology Lookup</title>
		<form>
                Enter Domain: <input type="text" name="domain" />
		<input type="submit" value="Submit" />
		</form>
             </html>
    );
    exit 0;
}

my $urn = "urn:ogf:network:domain=$domain";

my ($status, $res) = $client->xQuery('//*[@id="'.$urn.'"]');

if ($status != 0) {
    print $cgi->header('text/html');
    print qq(<html>
                <title>Topology Lookup Error</title>
                <h1>Topology Lookup Error</h1>
                <br>
                Problem looking up domain for $domain: $res
             </html>
    );
    exit 0;
}

print $cgi->header('text/xml');
my $obj = XML::Tidy->new(xml => $res);
print $obj->toString;

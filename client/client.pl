#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use XML::LibXML;
use File::Basename;

my $dirname;
my $libdir;

# we need to figure out what the library is at compile time so that "use lib"
# doesn't fail. To do this, we enclose the calculation of it in a BEGIN block.
BEGIN {
	$dirname = dirname($0);
	$libdir = $dirname."/../lib";
}

use lib "$libdir";

use perfSONAR_PS::Transport;
use perfSONAR_PS::Common qw( readXML );

Log::Log4perl->init($dirname."/logger.conf");
my $logger = get_logger("perfSONAR_PS");

our $DEBUGFLAG;
our $HOST = "localhost";
our $PORT = "4801";
our $ENDPOINT = '/perfSONAR_PS/services/status';
our $FILTER = '/';	# xpath query filter
our %opts = ();

our $help_needed;

my $ok = GetOptions (
		'debug'    	=> \$DEBUGFLAG,
		'server=s'	=> \$opts{HOST},
		'port=s'  	=> \$opts{PORT},
		'endpoint=s'	=> \$opts{ENDPOINT},
		'filter=s'	=> \$opts{FILTER},
		'help'     	=> \$help_needed
	);

# help?
if (not $ok or $help_needed) {
 	print "$0: sends an xml file to the server on specified port.\n";
  	print "    ./client.pl [--server=xxx.yyy.zzz --port=n --endpoint=ENDPOINT] [URI] FILENAME\n";
  	exit(1);	
}

# process two arguments
my $host;
my $port;
my $endpoint;
my $filter;
my $file;
if (scalar @ARGV eq 2) {
	($host, $port, $endpoint) = &perfSONAR_PS::Transport::splitURI($ARGV[0]);

	if (!defined $host && !defined $port && !defined $endpoint) {
		 die "Argument 1 must be a URI if more than one parameter used.\n";
	}

	$file = $ARGV[1];
} elsif (scalar @ARGV eq 1) {
	$file = $ARGV[0];
} else {
	die "Invalid number of parameters: must be 1 for just a file, or 2 for a uri and a file";
}

if (!-f $file) {
	die "File $file does not exist";
}

# find options
if (defined $opts{HOST}) {
	$host = $opts{HOST};
}
if (defined $opts{PORT}) {
	$port = $opts{PORT};
}
if (defined $opts{ENDPOINT}) {
	$endpoint = $opts{ENDPOINT};
}
if (defined $opts{FILTER}) {
	$filter = $opts{FILTER};
}

if ($DEBUGFLAG) {
	$logger->level($DEBUG);    
} else {
	$logger->level($INFO); 
}

# define the actual values
$host = $HOST unless defined $host; 
$port = $PORT unless defined $port;
$endpoint = $ENDPOINT unless defined $endpoint; 
$filter = $FILTER unless defined $filter;
 
print STDERR "HOST: $host, PORT: $port, ENDPOINT: $endpoint, FILE: $file\n" if $DEBUGFLAG;

# start a transport agent
my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);

# Read the source XML file
my $xml = readXML($file);
# Make a SOAP envelope, use the XML file as the body.
my $envelope = &perfSONAR_PS::Common::makeEnvelope($xml);
my $error;
# Send/receive to the server, store the response for later processing
my $responseContent = $sender->sendReceive($envelope, "", \$error);

if ($error ne "") {
	die("Error sending request to service: $error");
}

# dump the content to screen, using the xpath statement if necessary
&dump($responseContent, $filter);

exit(0);

1;


###
# dumps the response to screen; using the xpath query filter if defined
###
sub dump {
	my $response = shift;
	my $find = shift;

	my $xp;

	if(UNIVERSAL::can($response, "isa") ? "1" : "0" == 1 && $xml->isa('XML::LibXML')) {
		$xp = $response;
	} else {
		my $parser = XML::LibXML->new();
		$xp = $parser->parse_string($response);  
	}

	my @res = $xp->findnodes("$find");

	foreach my $n (@res) {
		print $n->toString() . "\n";
	}

	return;
}

=head1 NAME

client - A simple perfSONAR client.

=head1 DESCRIPTION

The purpose of this is to enable quick client side debugging of perfSONAR services.
 
=head1 SYNOPSIS
 
    # this will send the xml file echo-req.xml to srv4.dir.garr.it on port 8080
    # and endpoint /axis/services/MeasurementArchiveService
    $ client.pl \
           http://srv4.dir.garr.it:8080/axis/services/MeasurementArchiveService \
           echo-req.xml

    # ditto
    $ client.pl \
           --server=srv4.dir.garr.it \
           --port=8080 \
           --endpoint=/axis/services/MeasurementArchiveService \
           echo-req.xml
	       
    # this will override the port 8080 with the specified port 80
    $ client.pl \
           --port=80
           http://srv4.dir.garr.it:8080/axis/services/MeasurementArchiveService \
           echo-req.xml

    # this will override the endpoint with 
    # /perfsonar-RRDMA/services/MeasurementArchiveService
    $ client.pl \
           --endpoint=/perfsonar-RRDMA/services/MeasurementArchiveService
           http://srv4.dir.garr.it:8080/axis/services/MeasurementArchiveService \
           echo-req.xml
	        
    # this will filter the output of the returned xml to only show the elements
    # that have qname nmwg:data
    $ client.pl \
           --filter='//nmwg:data' \
           http://srv4.dir.garr.it:8080/axis/services/MeasurementArchiveService \
           echo-req.xml
	       
=head1 REQUIRES

Getopt::Long;
Log::Log4perl;
XML::LibXML;
perfSONAR_PS::Transport;
perfSONAR_PS::Common;

=head1 AUTHOR

Yee-Ting Li <ytl@slac.stanford.edu>

Based on original client by Jason Zurawski <zurawski@eecis.udel.edu>

=head1 VERSION

Current version is this one ;) 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski & Yee-Ting Li 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

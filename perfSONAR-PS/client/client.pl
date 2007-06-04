#!/usr/bin/perl -w -I ../lib

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
	       
	       		
=cut

use IO::File;
use Getopt::Long;
use strict;
use Log::Log4perl qw(get_logger :levels);

use perfSONAR_PS::Transport;
use perfSONAR_PS::Common qw( readXML );

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");
$logger->level($DEBUG);

our $DEBUG = 0;
our $HOST = "localhost";
our $PORT = "5000";
our $ENDPOINT = '/axis/services/MP';
our $FILTER = '//nmwg:message';	# xpath query filter
our %opts = ();

our $help_needed;

my $ok = GetOptions (
                     'debug'    	=> \$DEBUG,
                     'server=s'		=> \$opts{HOST},
					 'port=s'  		=> \$opts{PORT},
					 'endpoint=s'	=> \$opts{ENDPOINT},
					 'filter=s'		=> \$opts{FILTER},
                     'help'     	=> \$help_needed
                     );

# help?
if ( not $ok 
		or $help_needed )
{
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
if ( scalar @ARGV eq 2 ) {
	if ( $ARGV[0] =~ /^http:\/\/([^\/]*)\/?(.*)$/ ) {
		( $host, $port ) = split /:/, $1;
		$endpoint = $2;
	} else {
		die "Argument 1 must be a URI if more than one parameter used.\n";
	}
	$port =~ s/^://g if ( $port =~ m/^:/ ) ;
	$endpoint = '/' . $endpoint unless $endpoint =~ /^\//;

	$file = $ARGV[1];
} else {
	$file = $ARGV[0];
}

# find options
if ( defined $opts{HOST} ) {
	$host = $opts{HOST};
}
if ( defined $opts{PORT} ) {
	$port = $opts{PORT};
}
if ( defined $opts{ENDPOINT} ) {
	$endpoint = $opts{ENDPOINT};
}
if ( defined $opts{FILTER} ) {
	$filter = $opts{FILTER};
}

# define the actual values
$host = $HOST unless defined $host; 
$port = $PORT unless defined $port;
$endpoint = $ENDPOINT unless defined $endpoint; 
$filter = $FILTER unless defined $filter;
 
print STDERR "HOST: $host, PORT: $port, ENDPOINT: $endpoint, FILE: $file\n" if $DEBUG;

# start a transport agent
my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);

# Read the source XML file
my $xml = readXML($file);
# Make a SOAP envelope, use the XML file as the body.
my $envelope = $sender->makeEnvelope($xml);
# Send/receive to the server, store the response for later processing
my $responseContent = $sender->sendReceive($envelope);

# dump the content to screen, using the xpath statement if necessary
&dump( $responseContent, $filter );

exit(0);

1;


###
# dumps the response to screen; using the xpath query filter if defined
###
sub dump
{
	my $response = shift;
	my $find = shift;
	
	my $xp;
   if( UNIVERSAL::can($response, "isa") ? "1" : "0" == 1
      	&& $xml->isa('XML::XPath')) {
    	$xp = $response;  		
   } else {
   	    $xp = XML::XPath->new( xml => $response );
   }

    my $nodeset = $xp->find( $find );
    if($nodeset->size() <= 0) {
		die "Nothing found for xpath statement $find.\n";
    }
    
	# For now, print out the result message
    foreach my $node ($nodeset->get_nodelist) {
        print XML::XPath::XMLParser::as_string($node) , "\n";
    }
    
}



=head1 REQUIRES

IO::File;
perfSONAR_PS::Transport;
Getopt::Long;

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

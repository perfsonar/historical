#!/usr/bin/perl
# ################################################ #
#                                                  #
# Name:		server.pl                          #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A, 2>& /dev/null if you want     #
#               quiet                              #
# Purpose:	Receive XML messages, based on the #
#               NM-WG format from a participating  #
#               client.                            #
#                                                  #
# ################################################ #
use HTTP::Daemon;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;

use XML::Writer;
use XML::Writer::String;
use XML::XPath;
use XML::Parser;

use DBI;
use Time::HiRes qw( gettimeofday );
use Sleepycat::DbXml 'simple';
use IO::File;
use message;

# Add the pedantic variable to specify whether to
# check the input soapaction or not.  If it is not
# set, then a message will be accepted for any one.
$PEDANTIC = 0;
$DEBUG = 1;
$PORT = "";
$XMLDBENV = "";
$XMLDBCONT = "";
$LDSTORE = "";

$namespace = "http://ggf.org/ns/nmwg/base/2.0/";

if($#ARGV == 0) {
  if($ARGV[0] eq "-h" || $ARGV[0] eq "--h" || $ARGV[0] eq "-help" || $ARGV[0] eq "--help") {
    print "Usage: ./server.pl (-h | --h | -help | --help): This message.\n";
    print "       ./server.pl (-d | --d): Run In Daemon Mode\n";
    print "       ./server.pl: Run In Non-Daemon Mode\n";
  }
  elsif($ARGV[0] eq "-d" || $ARGV[0] eq "--d") {
    init();
	# flush the buffer
    $| = 1;
	# start the daemon
    &daemonize;
    server();
  }
  else {
    print "Try ./server.pl (-h | --h | -help | --help) for usage.\n";
    exit(1);
  }
}
else {
  init();
  server();
}


# ################################################ #
# Sub:		init                               #
# Args:		N/A                                #
# Purpose:	Prepare to run                     #
# ################################################ #
sub init {  
  readConf("./server.conf");

  # Read in the store of metadata info, we 
  # only want to get snmp data for what is 
  # in this file (not everything in the 
  # collect.conf is cool for us)

  system("$LDSTORE $XMLDBENV $XMLDBCONT");
  return;
}


# ################################################ #
# Sub:		readConf                           #
# Args:		$file - Filename to read           #
# Purpose:	Read and store info.               #
# ################################################ #
sub readConf {
  my ($file)  = @_;
  my $CONF = new IO::File("<$file") or die "Cannot open 'readDBConf' $file: $!\n" ;
  while (<$CONF>) {
    if(!($_ =~ m/^#.*$/)) {
      $_ =~ s/\n//;
      if($_ =~ m/^PORT=.*$/) {
        $_ =~ s/PORT=//;
        $PORT = $_;
      }
      elsif($_ =~ m/^XMLDBENV=.*$/) {
        $_ =~ s/XMLDBENV=//;
        $XMLDBENV = $_;
      }  
      elsif($_ =~ m/^XMLDBCONT=.*$/) {
        $_ =~ s/XMLDBCONT=//;
        $XMLDBCONT = $_;
      }
      elsif($_ =~ m/^LDSTORE=.*$/) {
        $_ =~ s/LDSTORE=//;
        $LDSTORE = $_;
      }
    }
  }
  $CONF->close();
  return; 
}


# ################################################ #
# Sub:		daemonize                          #
# Args:		N/A                                #
# Purpose:	Background process		   #
# ################################################ #
sub daemonize {
  #chdir '/' or die "Can't chdir to /: $!";
  open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
  open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
  defined(my $pid = fork) or die "Can't fork: $!";
  exit if $pid;
  setsid or die "Can't start a new session: $!";
  umask 0;
}


# ################################################ #
# Sub:		readXML                            #
# Args:		$file - Filename to read           #
# Purpose:	Read XML file, strip off leading   #
#		XML entry.                         #
# ################################################ #
sub readXML {
  my ($file)  = @_;
  my $xmlstring = "";
  my $XML = new IO::File("<$file") or die "Cannot open 'readXML' $file: $!\n" ;
  while (<$XML>) {
    if(!($_ =~ m/^<\?xml.*/)) {
      $xmlstring .= $_;
    }
  }
  $XML->close();
  return $xmlstring;  
}


# ################################################ #
# Sub:		server                             #
# Args:		N/A                                #
# Purpose:	Run the SOAP Server                #
# ################################################ #
sub server {  
  $daemon = HTTP::Daemon->new(
    LocalPort => $PORT,
    Reuse => 1
  ) || die;

  if($DEBUG) {
    print "Contact at:", $daemon->url, "\n";
  }

  my($soap_env) = "http://schemas.xmlsoap.org/soap/envelope/";
  my($soap_enc) = "http://schemas.xmlsoap.org/soap/encoding/";
  my($xsd) = "http://www.w3.org/2001/XMLSchema";
  my($xsi) = "http://www.w3.org/2001/XMLSchema-instance";
  my($namespace) = "http://ggf.org/ns/nmwg/base/2.0/";

  my $ofile = "/tmp/server." . &Time::HiRes::gettimeofday;

  while (my $call = $daemon->accept) {

    $message = new message;

    while (my $request = $call->get_request) {

      $response = HTTP::Response->new();
      $response->header('Content-Type' => 'text/xml');
      $response->header('user-agent' => 'NMWG-Server/20060517');
      $response->code("200");

      if($DEBUG) {
        print "The server got: \n" , $request->content , "\n";
      }

      my $xml = "";
      my $output = new IO::File(">$ofile");

      if($request->uri eq '/' && $request->method eq "POST") {
        $writer = new XML::Writer(NAMESPACES => 4,
                                  PREFIX_MAP => {$soap_env => "SOAP-ENV",
                                                 $soap_enc => "SOAP-ENC",
                                                 $xsd => "xsd",
                                                 $xsi => "xsi",
                                                 $namespace => "message"},
                                  UNSAFE => 1, OUTPUT => $output, DATA_MODE => 1, DATA_INDENT => 2);
        $writer->startTag([$soap_env, "Envelope"],
                          "xmlns:SOAP-ENC" => $soap_enc,
                          "xmlns:xsd" => $xsd,
                          "xmlns:xsi" => $xsi);
        $writer->emptyTag([$soap_env, "Header"]);
        $writer->startTag([$soap_env, "Body"]);
        $writer->startTag("nmwg:message", "type" => "response",
                          "xmlns:nmwg" => "http://ggf.org/ns/nmwg/base/2.0/",
													"xmlns:nmwgr" => "http://ggf.org/ns/nmwg/result/2.0/",
                          "xmlns:nmwgt" => "http://ggf.org/ns/nmwg/topology/2.0/",
                          "xmlns:nmtm" => "http://ggf.org/ns/nmwg/time/2.0/",
													"xmlns:ifevt" => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
                          "xmlns:netutil" => "http://ggf.org/ns/nmwg/characteristics/utilization/2.0/");
	if ($PEDANTIC > 0) {
          $action = $request->headers->{"soapaction"} ^ $namespace;
          if (!$action =~ m/^.*message\/$/) {
            $writer->raw("<nmwg:data id=\"" . message::genuid() . "\">\n");
            $writer->raw("<nmwgr:datum>\n");
            $writer->raw("Unrecognized Soapaction\n");
            $writer->raw("</nmwgr:datum>\n");
            $writer->raw("</nmwg:data>\n");
  	  }
        }

        $xp = XML::XPath->new( xml => $request->content );
        $xp->clear_namespaces();
        $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
        $nodeset = $xp->find('//nmwg:message');

        if($nodeset->size() <= 0) {
          $writer->characters("Message element not found or in wrong namespace.");
        }
        else {
          foreach my $node ($nodeset->get_nodelist) {
            $writer = $message->message($writer, XML::XPath::XMLParser::as_string($node));
          }
        }
      }
      else {
        $writer->raw("<nmwg:data id=\"" . message::genuid() . "\">\n");
        $writer->raw("<nmwgr:datum>\n");
        $writer->raw("Unrecognized URI or Method\n");
        $writer->raw("</nmwgr:datum>\n");
        $writer->raw("</nmwg:data>\n");
      }

      $writer->endTag("nmwg:message");
      $writer->endTag([$soap_env, "Body"]);
      $writer->endTag([$soap_env, "Envelope"]);
      $writer->end();
      $output->close();
      $xml = readXML($ofile);

      if($DEBUG > 1) {
        print "The server said: \n" , $xml , "\n\n";	
      }

      $response->content($xml);
      $call->send_response($response);
    }
    $call->close;

    undef($call);
    unlink $ofile;
  }
}

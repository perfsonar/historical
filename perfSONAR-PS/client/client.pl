#!/usr/bin/perl

# ################################################### #
#                                                     #
# Author:   Jason Zurawski (zurawski@eecis.udel.edu)  #
# Title:    client.pl                                 #
# Purpose:  Send an XML message, based on the NM-WG   #
#           format to a participating server.         #
# Last Modified:                                      #
#           05/15/06                                  #
#                                                     #
# ################################################### #

use XML::Writer;
use XML::Writer::String;
use XML::XPath;
use LWP::UserAgent;
use IO::File;

$DEBUG = 2;
$HOST = "";
$PORT = "";


if($#ARGV == -1) {
  print "Try ./client.pl (-h | --h | -help | --help) for usage.\n";
  print "    ./client.pl FILENAME for transmitting FILENAME to a server. \n";
  exit(1);
}
elsif($#ARGV == 0) {
  if($ARGV[0] eq "-h" || $ARGV[0] eq "--h" || $ARGV[0] eq "-help" || $ARGV[0] eq "--help") {
    print "Usage: ./client.pl (-h | --h | -help | --help): This message.\n";
    print "       ./client.pl FILENAME: for transmitting FILENAME to a server.\n";
  }
  else {
					# Read in the conf file information
    readConf("client.conf");

					# Read the source XML file
    my $xml = readXML($ARGV[0]);
					# Make a SOAP envelope, use the XML file
					# as the body.
    my $envelope = makeEnvelope($xml);
					# Send/receive to the server, store the 
					# response for later processing
    my $responseContent = sendReceive($envelope);

					# Use XPath to extract just the message
					# message element.
    $xp = XML::XPath->new( xml => $responseContent );
    $xp->clear_namespaces();
    $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
    $nodeset = $xp->find('//nmwg:message');
    if($nodeset->size() <= 0) {
      $nodeset = $xp->find('//message');
    }
					# For now, print out the result message
    if($DEBUG) {
      foreach my $node ($nodeset->get_nodelist) {
        print XML::XPath::XMLParser::as_string($node) , "\n";
      }
    }

    exit(0);
  }
}
else {
  print "Try ./client.pl (-h | --h | -help | --help) for usage.\n";
  print "    ./client.pl FILENAME for transmitting FILENAME to a server. \n";
  exit(1);
}



# ################################################### #
#                                                     #
# Name:      readConf                                 #
# Arguments: $FILE - the conf file name               #
# Returns:   N/A                                      #
# Purpose:   Read the configuration file, store conf  #
#            values in global variables.              # 
#                                                     #
# ################################################### #

sub readConf {
  my ($FILE)  = @_;
  open(CLIENT, $FILE);
  my @conf = <CLIENT>;
  close(CLIENT);

  foreach my $c (@conf) {
    if(!($c =~ m/^#.*$/)) {
      $c =~ s/\n//;
      if($c =~ m/^PORT=.*$/) {
        $c =~ s/PORT=//;
        $PORT = $c;
      }
      elsif($c =~ m/^HOST=.*$/) {
        $c =~ s/HOST=//;
        $HOST = $c;
      }
    }
  }
  return;
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


# ################################################### #
#                                                     #
# Name:      makeEnvelope                             #
# Arguments: $nmwgxml - raw XML string to be included #
#                       in SOAP envelope.             #
# Returns:   XML string of SOAP envelope              #
# Purpose:   Construct a SOAP envelope for transmiss- #
#            -ion to a server.                        # 
#                                                     #
# ################################################### #

sub makeEnvelope {
  ($nmwgxml) = @_;

  $soap_env = "http://schemas.xmlsoap.org/soap/envelope/";
  $soap_enc = "http://schemas.xmlsoap.org/soap/encoding/";
  $xsd = "http://www.w3.org/2001/XMLSchema";
  $xsi = "http://www.w3.org/2001/XMLSchema-instance";
  $namespace = "http://ggf.org/ns/nmwg/base/2.0/";

  $s = XML::Writer::String->new();
  $writer = new XML::Writer(NAMESPACES => 4,
                            PREFIX_MAP => {$soap_env => "SOAP-ENV",
                                           $soap_enc => "SOAP-ENC",
                                           $xsd => "xsd",
                                           $xsi => "xsi",
                                           $namespace => "message"},
                            UNSAFE => 1,
                            OUTPUT => $s,
                            DATA_MODE => 1,
                            DATA_INDENT => 3);
  $writer->startTag([$soap_env, "Envelope"],
                    "xmlns:SOAP-ENC" => $soap_enc,
                    "xmlns:xsd" => $xsd,
                    "xmlns:xsi" => $xsi);
  $writer->emptyTag([$soap_env, "Header"]);
  $writer->startTag([$soap_env, "Body"]);
  $writer->raw($nmwgxml);
  $writer->endTag([$soap_env, "Body"]);
  $writer->endTag([$soap_env, "Envelope"]);
  $writer->end();

  return $s->value;
}


# ################################################### #
#                                                     #
# Name:      sendReceive                              #
# Arguments: $envelope - the XML string of the SOAP   #
#            envelope                                 #
# Returns:   Content from the server, should be anot- #
#            -her SOAP envelope.                      #
# Purpose:   Contact the server, and send the SOAP    #
#            envelope over HTTP; a response should    #
#            return.                                  # 
#                                                     #
# ################################################### #

sub sendReceive {
  ($envelope) = @_;

  $endpoint = "/";
  $method_uri = "http://ggf.org/ns/nmwg/base/2.0/message/";
  $method_name = "";

  $httpEndpoint = qq[http://$HOST:$PORT$endpoint];
  $userAgent = LWP::UserAgent->new('timeout'=>5000);


  $sendSoap = HTTP::Request->new('POST', $httpEndpoint, new HTTP::Headers, $envelope);
  $sendSoap->header('SOAPAction' => $method_uri);
  $sendSoap->content_type  ('text/xml');
  $sendSoap->content_length(length($envelope));
  $httpResponse = $userAgent->request($sendSoap);
  $responseCode = $httpResponse->code();
  $responseContent = $httpResponse->content();

  return $responseContent;
}

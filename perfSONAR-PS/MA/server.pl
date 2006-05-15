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

$DEBUG = 2;
$PORT = "";
$XMLDBENV = "";
$XMLDBCONT = "";

$namespace = "http://ggf.org/ns/nmwg/base/2.0/";

if($#ARGV == 0) {
  if($ARGV[0] eq "-h" || $ARGV[0] eq "--h" || $ARGV[0] eq "-help" || $ARGV[0] eq "--help") {
    print "Usage: ./server.pl (-h | --h | -help | --help): This message.\n";
    print "       ./server.pl: Start NMWG Server.\n";
    print "       ./server.pl 2>& /dev/null &: Start NMWG Server and Redirect STDOUT to NULL.\n";
    print "       ./server.pl 2>& SOMEFILE &: Start NMWG Server and Redirect STDOUT to a File.\n";
  }
  else {
    print "Try ./server.pl (-h | --h | -help | --help) for usage.\n";
    exit(1);
  }
}
else {
  
  readConf("./server.conf");
  
		# Read in the store of metadata info, we 
		# only want to get snmp data for what is 
		# in this file (not everything in the 
		# collect.conf is cool for us)
  %store_metadata = ();
  %store_metadata = readStore(\%store_metadata);

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
      $response->header('user-agent' => 'NMWG-Server/20060502');
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
                          "xmlns:netutil" => "http://ggf.org/ns/nmwg/characteristics/utilization/2.0/");
        $action = $request->headers->{"soapaction"} ^ $namespace;
	
	
        if ($action =~ m/^.*message\/$/) {
	
          $xp = XML::XPath->new( xml => $request->content );
          $xp->clear_namespaces();
          $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
          $nodeset = $xp->find('//nmwg:message');

          if($nodeset->size() <= 0) {
            $writer->characters("Message element not found or in wrong namespace.");
          }
          else {
            foreach my $node ($nodeset->get_nodelist) {
              $writer = $message->message($writer, XML::XPath::XMLParser::as_string($node), \%store_metadata);
            }
          }
        }
        else {
          $writer->raw("<nmwg:data id=\"" . genuid() . "\">\n");
          $writer->raw("<nmwgr:datum>\n");
          $writer->raw("Unrecognized Soapaction\n");
          $writer->raw("</nmwgr:datum>\n");
          $writer->raw("</nmwg:data>\n");
        }
      }
      else {
        $writer->raw("<nmwg:data id=\"" . genuid() . "\">\n");
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

# ################################################ #
# Sub:		readConf                           #
# Args:		$file - Filename to read           #
# Purpose:	Read and store info.               #
# ################################################ #
sub readConf {
  my ($file)  = @_;
  
  open(READ, $file);
  @conf = <READ>;
  close(READ);

  foreach $c (@conf) {
    if(!($c =~ m/^#.*$/)) {
      $c =~ s/\n//;
      if($c =~ m/^PORT=.*$/) {
        $c =~ s/PORT=//;
        $PORT = $c;	
      }
      elsif($c =~ m/^XMLDBENV=.*$/) {
        $c =~ s/XMLDBENV=//;
        $XMLDBENV = $c;
      }  
      elsif($c =~ m/^XMLDBCONT=.*$/) {
        $c =~ s/XMLDBCONT=//;
        $XMLDBCONT = $c;
      }                 
    }
  }
  return;
}

# ################################################ #
# Sub:		readStore                          #
# Args:		$xml - contents of the store xml   #
#                      file.                       #
#               $sent - flattened hash of metadata #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Process each metadata block in the #
#               store.                             #
# ################################################ #
sub readStore {
  my($sent) = @_;
  my %metadata = %{$sent};

  $xml = readXML("./store.xml");  
  
  $xp = XML::XPath->new( xml => $xml );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  $xp->set_namespace('netutil', 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0/');
  $xp->set_namespace('nmwgt', 'http://ggf.org/ns/nmwg/topology/2.0/');
	  
  $nodeset = $xp->find('//nmwg:metadata');

  if($nodeset->size() <= 0) {
    $writer->characters("Metadata elements not found or in wrong namespace.");
  }
  else {
    foreach my $node ($nodeset->get_nodelist) {
	     
      my %md = ();
      foreach my $attr2 ($node->getAttributes) {
        $md{$node->getPrefix .":" . $node->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
      }      
      %md = goDeep($node, \%md);
      $metadata{$md{"nmwg:metadata-id"}} = \%md;	  
	  
      eval {
        my $env = new DbEnv(0);
        $env->set_cachesize(0, 64 * 1024, 1);
        $env->open($XMLDBENV,
                   Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN);
        my $theMgr = new XmlManager($env);
        my $containerTxn = $theMgr->createTransaction();
        my $container = $theMgr->openContainer($containerTxn, $XMLDBCONT, Db::DB_CREATE);
        $containerTxn->commit();
        my $updateContext = $theMgr->createUpdateContext();
            
        my $query_txn = $theMgr->createTransaction();
        my $context2 = $theMgr->createQueryContext();
        $context2->setNamespace( "nmwg" => "http://ggf.org/ns/nmwg/base/2.0/");
        $context2->setNamespace( "netutil" => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/");
        $context2->setNamespace( "nmwgt" => "http://ggf.org/ns/nmwg/topology/2.0/");
        $context2->setNamespace( "ping" => "http://ggf.org/ns/nmwg/tools/ping/2.0/");  

        if(howMany($theMgr, $container->getName(), "//nmwg:metadata[\@id=\"" . $md{"nmwg:metadata-id"} . "\"]", $context2 ) == 0) {      
          my $txn = $theMgr->createTransaction();
          my $myXMLDoc = $theMgr->createDocument();
          $myXMLDoc->setContent(XML::XPath::XMLParser::as_string($node));
          $myXMLDoc->setName($md{"nmwg:metadata-id"});
          $container->putDocument($txn, $myXMLDoc, $updateContext, 0);
          $txn->commit();
        } 	
      };
      if (my $e = catch std::exception) {
        warn "Error adding XML data to container $XMLDBCONT\n" ;
        warn $e->what() . "\n";
        exit(-1);
      }
      elsif ($@) {
        warn "Error adding XML data to container $XMLDBCONT\n" ;
        warn $@;
        exit(-1);
      }      

    } 
  }  

  return %metadata;
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
# Sub:		howMany                            #
# Args:		$mgr - db connection manager       #
#		$cname - collection name           #
#		$query - What we are searching for #
#		$context - query context           #
# Purpose:	Given the input, perform a query   #
#               and return the number of results   #
# ################################################ #
sub howMany($$$$) {
  my $mgr = shift ;
  my $cname = shift ;
  my $query = shift ;
  my $context = shift ;
  my $results;
  my $fullQuery = "collection('$cname')$query";
  eval {
    $results = $mgr->query($fullQuery, $context);		
  };
  if (my $e = catch std::exception) {
    warn "'howMany' Query $fullQuery failed\n";
    warn $e->what() . "\n";
    exit( -1 );
  }
  elsif ($@) {
    warn "'howMany' Query $fullQuery failed\n";
    warn $@;
    exit( -1 );
  }   
  return $results->size();
}

# ################################################ #
# Sub:		goDeep                             #
# Args:		$set - set of children nodes       #
#               $sent - flattened hash of metadata #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Keep enterning the metadata block  #
#               revealing all important elements/  #
#               attributes/values.                 #
# ################################################ #
sub goDeep {
  my ($set, $sent) = @_;
  my %b = %{$sent};  
  foreach my $element ($set->getChildNodes) {   
  
    $value = $element->getNodeValue;
    $value =~ s/\n//g;  
    $value =~ s/\s{2}//g;  
    
    if($value != "" || $value != " " || !($element->getNodeValue =~ m/\n/)) { 
      if($element->getNodeType == 3) {
        if($element->getParentNode->getLocalName eq "parameter") {		  
	  if($element->getParentNode->getAttribute("name") && $element->getParentNode->getAttribute("operator")) {	
            $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName . "-" . $element->getParentNode->getAttribute("name") . "-" . $element->getParentNode->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b);	  
	  }
	  elsif($element->getParentNode->getAttribute("name") && !($element->getParentNode->getAttribute("value"))) {  
            $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName . "-" . $element->getParentNode->getAttribute("name")} = $value;
            %b = goDeep($element, \%b);
	  }	 	  
	}
	else {
          $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName} = $element->getNodeValue;	
	  %b = goDeep($element, \%b);	
	}
      }
      else {
        if($element->getLocalName eq "parameter") {	
	  if($element->getAttribute("name") && $element->getAttribute("value")) {
            $b{$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name")} = $element->getAttribute("value");
            %b = goDeep($element, \%b);
	  }
	  elsif($element->getAttribute("name") && $element->getAttribute("operator")) {
            $b{$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name") . "-" . $element->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b);	  
	  }
	}
	else {
          foreach my $attr2 ($element->getAttributes) {
	   $b{$element->getPrefix .":" . $element->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
          }      
          %b = goDeep($element, \%b);
	}
      }      
    }
  }
  return %b;
}

#!/usr/bin/perl
# ################################################ #
#                                                  #
# Name:		loadStorage.pl                     #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		$XMLDBENV = XML DB environment     #
#               $XMLDBCONT = XML DB Container      #
# Purpose:	Load the XML DB with initial       #
#               information                        #
#                                                  #
# ################################################ #
use XML::Writer;
use XML::Writer::String;
use XML::XPath;
use XML::Parser;

use Sleepycat::DbXml 'simple';
use IO::File;

$XMLDBENV = shift;
$XMLDBCONT = shift;

				# get the contents of the store.xml file into
				# string form.
$xml = readXML("./store.xml");  
  
$xp = XML::XPath->new( xml => $xml );
$xp->clear_namespaces();
$xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
$xp->set_namespace('netutil', 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0/');
$xp->set_namespace('nmwgt', 'http://ggf.org/ns/nmwg/topology/2.0/');
	  
	  			# find all of the metadata elements
$nodeset = $xp->find('/nmwg:store/nmwg:metadata');

if($nodeset->size() <= 0) {
  $writer->characters("Metadata elements not found or in wrong namespace.");
}
else {
				# iterate over each found metadata element
				
  foreach my $node ($nodeset->get_nodelist) {
	     
	     			# store the md into a temporary hash, we will
				# unroll this when we need to query the XMLDB
    my %md = ();
    foreach my $attr2 ($node->getAttributes) {
      $md{$node->getPrefix .":" . $node->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
    }      
    %md = goDeep($node, \%md, $node->getPrefix .":" . $node->getLocalName);
	 	  
	  			# Open a connection to the XMLDB, set up a transaction
				# to query for the metadata values.  If we get a hit, 
				# dont insert into the DB, if we get nothing, insert the
				# md as new.	  		
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
  my ($set, $sent, $path) = @_;
  my %b = %{$sent};  
  foreach my $element ($set->getChildNodes) {   
  
    $value = $element->getNodeValue;
    $value =~ s/\n//g;  
    $value =~ s/\s{2}//g;  
    
    if($value != "" || $value != " " || !($element->getNodeValue =~ m/\n/)) { 
      if($element->getNodeType == 3) {
        if($element->getParentNode->getLocalName eq "parameter") {		  
	  if($element->getParentNode->getAttribute("name") && $element->getParentNode->getAttribute("operator")) {	
            $b{$path . "-" . $element->getParentNode->getAttribute("name") . "-" . $element->getParentNode->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b, $path);	  
	  }
	  elsif($element->getParentNode->getAttribute("name") && !($element->getParentNode->getAttribute("value"))) {  
            $b{$path . "-" . $element->getParentNode->getAttribute("name")} = $value;
            %b = goDeep($element, \%b, $path);
	  }	 	  
	}
	else {
          $b{$path} = $element->getNodeValue;	
	  %b = goDeep($element, \%b, $path);	
	}
      }
      else {
        if($element->getLocalName eq "parameter") {	
	  if($element->getAttribute("name") && $element->getAttribute("value")) {
            $b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name")} = $element->getAttribute("value");
            %b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);
	  }
	  elsif($element->getAttribute("name") && $element->getAttribute("operator")) {
            $b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name") . "-" . $element->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);	  
	  }
	}
	else {
          foreach my $attr2 ($element->getAttributes) {
	   $b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
          }      
          %b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);
	}
      }      
    }
  }
  return %b;
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

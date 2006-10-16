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
use XML::XPath;
use IO::File;
use Sleepycat::DbXml 'simple';

$XMLDBENV = shift;
$XMLDBCONT = shift;

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

  if(howMany($theMgr, $container->getName(), "//nmwg:metadata", $context2 ) == 0) {      

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
      print "Metadata elements not found or in wrong namespace.\n";
    }
    else {
				# iterate over each found metadata element			
      foreach my $node ($nodeset->get_nodelist) {
	  
				# Grab the md id (and anything else that is an 
				# attribute of the md, maybe we can use them 
				# later...  
        my %md = ();
        foreach my $attr2 ($node->getAttributes) {
          $md{$node->getPrefix .":" . $node->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
        }   
	
        my $txn = $theMgr->createTransaction();
        my $myXMLDoc = $theMgr->createDocument();
        $myXMLDoc->setContent(XML::XPath::XMLParser::as_string($node));
        $myXMLDoc->setName($md{"nmwg:metadata-id"});
        $container->putDocument($txn, $myXMLDoc, $updateContext, 0);
        $txn->commit();	
	
      }
    }   
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

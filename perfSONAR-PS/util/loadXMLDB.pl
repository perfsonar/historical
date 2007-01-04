#!/usr/bin/perl -w
# ################################################ #
#                                                  #
# Name:		loadXMLDB .pl                      #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		$XMLDBENV = XML DB environment     #
#               $XMLDBCONT = XML DB Container      #
#               $XMLFILE = XML File with store     #
#                          information.            #
# Purpose:	Load the XML DB with initial       #
#               information                        #
#                                                  #
# ################################################ #
use strict;
use XML::XPath;
use IO::File;
use Sleepycat::DbXml 'simple';

if($#ARGV <= -1 || $#ARGV == 1 || $#ARGV >= 3) {
  print "Try ./loadXMLDB.pl (-h | --h | -help | --help) for usage.\n";
  print "    ./loadXMLDB.pl ENVIRONMENT CONTAINER FILENAME:\n\n";
  print "    ENVIRONMENT\t- PATH to xmldb instance (ex. /home/jason/xmldb)\n";
  print "    CONTAINER\t- Container file within xmldb instance (ex. store.dbxml)\n";
  print "    FILENAME\t- Name of XML to read into database (ex. ./store.xml)\n";  
  exit(1);
}
elsif($#ARGV == 0) {
  if($ARGV[0] eq "-h" || $ARGV[0] eq "--h" || $ARGV[0] eq "-help" || $ARGV[0] eq "--help") {
    print "Usage: ./loadXMLDB.pl (-h | --h | -help | --help): This message.\n";
    print "       ./loadXMLDB.pl ENVIRONMENT CONTAINER FILENAME:\n\n";
    print "       ENVIRONMENT\t- PATH to xmldb instance (ex. /home/jason/xmldb)\n";
    print "       CONTAINER\t- Container file within xmldb instance (ex. store.dbxml)\n";
    print "       FILENAME\t- Name of XML to read into database (ex. ./store.xml)\n"; 
    exit(1);
  }
  else {
    print "Try ./loadXMLDB.pl (-h | --h | -help | --help) for usage.\n";
    print "    ./loadXMLDB.pl ENVIRONMENT CONTAINER FILENAME:\n\n";
    print "    ENVIRONMENT\t- PATH to xmldb instance (ex. /home/jason/xmldb)\n";
    print "    CONTAINER\t- Container file within xmldb instance (ex. store.dbxml)\n";
    print "    FILENAME\t- Name of XML to read into database (ex. ./store.xml)\n";  
    exit(1);
  }
}
else {
  
  my $XMLDBENV = $ARGV[0];
  my $XMLDBCONT = $ARGV[1];
  my $XMLFILE = $ARGV[2];
  
  my %ns = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
    netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
    nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
    snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
  );  
  
  eval {
    my $env = new DbEnv(0);
    $env->set_cachesize(0, 64 * 1024, 1);
    $env->open(
      $XMLDBENV,
      Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN
    );
    my $theMgr = new XmlManager($env);
    my $containerTxn = $theMgr->createTransaction();
    my $container = $theMgr->openContainer($containerTxn, $XMLDBCONT, Db::DB_CREATE);
    $containerTxn->commit();
    my $updateContext = $theMgr->createUpdateContext();
            
    my $query_txn = $theMgr->createTransaction();
    my $context2 = $theMgr->createQueryContext();    
    foreach my $prefix (keys %ns) {
      $context2->setNamespace($prefix, $ns{$prefix});
    }    

    if(&howMany($theMgr, $container->getName(), "//nmwg:metadata", $context2 ) == 0) {      

				# get the contents of the $XMLFILE into
				# string form.
      my $xml = &readXML($XMLFILE);  
  
      my $xp = XML::XPath->new( xml => $xml );
      $xp->clear_namespaces();      
      foreach my $prefix (keys %ns) {
        $xp->set_namespace($prefix, $ns{$prefix});
      }      
	  
	  			# find all of the metadata elements
      my $nodeset = $xp->find('/nmwg:store/nmwg:metadata');

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
    
    if(&howMany($theMgr, $container->getName(), "//nmwg:data", $context2 ) == 0) {      

				# get the contents of the $XMLFILE into
				# string form.
      my $xml = &readXML($XMLFILE);  
  
      my $xp = XML::XPath->new( xml => $xml );
      $xp->clear_namespaces();      
      foreach my $prefix (keys %ns) {
        $xp->set_namespace($prefix, $ns{$prefix});
      }      
	  
	  			# find all of the metadata elements
      my $nodeset = $xp->find('/nmwg:store/nmwg:data');

      if($nodeset->size() <= 0) {
        print "Data elements not found or in wrong namespace.\n";
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
          $myXMLDoc->setName($md{"nmwg:data-id"});
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


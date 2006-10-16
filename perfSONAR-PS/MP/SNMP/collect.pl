#!/usr/bin/perl
# ################################################ #
#                                                  #
# Name:		collect.pl                         #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A                                #
# Purpose:	Given some conf files, gather and  #
#               store SNMP data in a database.     #
#                                                  #
# ################################################ #
use Net::SNMP;
use DBI;
use Time::HiRes qw( gettimeofday );
use XML::XPath;
use IO::File;
use POSIX qw(setsid);
use Sleepycat::DbXml 'simple';

		# Read/store database access info
$DBNAME = "";
$DBUSER = "";
$DBPASS = "";
$XMLDBENV = "";
$XMLDBCONT = "";
$LDSTORE = "";
readDBConf("./db.conf");

		# Read/store snmp collection info, we will 
		# need this to actually gather the data.
%snmp = ();
%snmp = readCollectConf("./collect.conf", \%snmp);

		# start the 'loader' to get the XMLDB up to speed
		# the loader will basically see if the xmldb has
		# been populated yet.
system("$LDSTORE $XMLDBENV $XMLDBCONT");

		# Read in the XMLDB for metadata info, we 
		# only want to get snmp data for what is 
		# in the XMLDB (not everything in the 
		# collect.conf is cool for us)
%metadata = ();
%metadata = readStore(\%metadata);

		# flush the buffer
$| = 1;
		# start the daemon
&daemonize;

		# Main loop, we need to do the following 
		# things:
		#
		# 1) Open up a DB connection
		#
		# 2) For each metadata in the store.xml
		#    match it to the snmp connection info
		#    (if available)
		#
		# 3) If we find a match, we are ready to
		#    try an snmp query.  
		#
		# 4) If the query is cool, insert into 
		#    the DB and move on.
								
while(1) {
 
  $dbh = DBI->connect("$DBNAME","$DBUSER","$DBPASS")
    || die "Database unavailable";

  foreach my $m (keys %metadata) {
  
    if($snmp{$metadata{$m}{"hostName"}}[0] &&
       $snmp{$metadata{$m}{"hostName"}}[1] &&
       $metadata{$m}{"hostName"}) {
  
      ($session, $error) = Net::SNMP->session(
                             -community     => $snmp{$metadata{$m}{"hostName"}}[0],
                             -version       => $snmp{$metadata{$m}{"hostName"}}[1],
	    	             -hostname      => $metadata{$m}{"hostName"}
	  	           ) || die "Couldn't open SNMP session to " , $metadata{$m}{"hostName"} , "\n";

      if (!defined($session)) {
        my $msg = $error;
        printError("./log/netradar-error.log", $msg);
	
        $dbh->disconnect();
        exit(1);
      }

      if($metadata{$m}{"eventType"} && 
         $metadata{$m}{"ifIndex"}) {
        
	$metadata{$m}{"eventType"} =~ s/snmp\.//;
	
	$time = time();
        my $result = $session->get_request(
          -varbindlist => [$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}]
        );
  
        if (!defined($result)) {
          my $msg = $session , " - " , $error;
          printError("./log/netradar-error.log", $msg);
	  
          $dbh->disconnect();
          exit(1);
        }
    
        $ins = "insert into data (id, time, value, eventtype, misc) values (?, ?, ?, ?, ?)";
        $sth = $dbh->prepare($ins);
        $sth->execute($m, $time, $result->{$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}}, $metadata{$m}{"parameter-eventType"}, "") 
          || warn "Executing: ", $sth->errstr;  
      }
      else {
        my $msg =  "The OID, " , $metadata{$m}{"eventType"} , "." , $metadata{$m}{"ifIndex"} , " cannot be found.";
	printError("./log/netradar-error.log", $msg);
		         
	$session->close; 
        $dbh->disconnect();
	exit(1);
      }
      $session->close;    
    }
    else {
      my $msg = "I am seeing a community of:\"";
      $msg = $msg . $snmp{$metadata{$m}{"hostName"}}[0] , "\" a version of:\"";
      $msg = $msg . $snmp{$metadata{$m}{"hostName"}}[1] , "\" and a hostname of:\""; 
      $msg = $msg . $metadata{$m}{"hostName"} , "\" ... something is amiss.";
      printError("./log/netradar-error.log", $msg);
      
      $dbh->disconnect();
      exit(1);
    }
  }
  $dbh->disconnect();
  sleep(1); 
}



# ################################################ #
# Sub:		readStore                          #
# Args:		$file - the file to write the error#
#                       message to.                #
#               $msg - the message to write.       #
# Purpose:	Print out an error message.        #
# ################################################ #
sub printError {
  my($file, $msg) = @_;
  open(LOG, "+>>" . $file);
  ($sec, $micro) = Time::HiRes::gettimeofday;
  print LOG "TIME: " , $sec , "." , $micro , "\t\t";
  print LOG $msg , "\n";
  close(LOG);
  return;
}



# ################################################ #
# Sub:		readDBConf                         #
# Args:		$file - Filename to read           #
# Purpose:	Read and store database info.      #
# ################################################ #
sub readDBConf {
  my ($file)  = @_;
  my $CONF = new IO::File("<$file") or die "Cannot open 'readDBConf' $file: $!\n" ;
  while (<$CONF>) {
    if(!($_ =~ m/^#.*$/)) {
      $_ =~ s/\n//;
      if($_ =~ m/^DB=.*$/) {
        $_ =~ s/DB=//;
        $DBNAME = $_;
      }
      elsif($_ =~ m/^USER=.*$/) {
        $_ =~ s/USER=//;
        $DBUSER = $_;
      }
      elsif($_ =~ m/^PASS=.*$/) {
        $_ =~ s/PASS=//;
        $DBPASS = $_;
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
# Sub:		readCollectConf                    #
# Args:		$file - Filename to read           #
# Purpose:	Read and store snmp access info.   #
# ################################################ #
sub readCollectConf {
  my ($file, $sent)  = @_;
  my %snmp = %{$sent};
  my $CONF = new IO::File("<$file") or die "Cannot open 'readCollectConf' $file: $!\n" ;
  while (<$CONF>) {
    my $hostname = "";
    my @array = ();
    if($_ =~ m/^#.*/) {
      # ignore comments
    }
    else {
      $_ =~ s/\n//;
      @item = split(/\t/,$_);
            
      $hostname = $item[0];
      for($i = 1; $i <= 2; $i++) {
        $array[$i-1] = $item[$i];
      }
      $snmp{$hostname} = \@array;
    } 
  }          
  $CONF->close();
  return %snmp; 
}



# ################################################ #
# Sub:		readStore                          #
# Args:		$sent - flattened hash of metadata #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Process each metadata block in the #
#               xmldb store.                       #
# ################################################ #
sub readStore {
  my($sent) = @_;
  my %metadata = %{$sent};
  

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

    @resultsString = getContents($theMgr, $container->getName(), "//nmwg:metadata", $context2);   
    if($#resultsString != -1) {    
      for($x = 0; $x <= $#resultsString; $x++) {	
        $xp = XML::XPath->new( xml => $resultsString[$x] );
        $xp->clear_namespaces();
        $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
        $xp->set_namespace('netutil', 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0/');
        $xp->set_namespace('nmwgt', 'http://ggf.org/ns/nmwg/topology/2.0/');	  
	  	  	  
        $nodeset = $xp->find('//nmwg:metadata');
        if($nodeset->size() <= 0) {
          my $msg = "XMLDB has results, but either they are not nmwg:metadata, or the namespace is wrong.";
          printError("./log/netradar-error.log", $msg); 	
	  exit(1);  
        }
        else {          
	  foreach my $node ($nodeset->get_nodelist) {           
            my %md = ();
            my $id = "";
            my $mid = "";
            foreach $attr ($node->getAttributes) {
              if($attr->getLocalName eq "id") {
                $id = $attr->getNodeValue;
              }
              elsif($attr->getLocalName eq "metadataIdRef") {
                $mid = $attr->getNodeValue;
              }
            }
            %md = goDeep($node, \%md);
            $metadata{$id} = \%md;    
          	    
          }
        }
      }
    }
    else {
      my $msg = "XMLDB returned 0 results.";
      printError("./log/netradar-error.log", $msg);  
      exit(1);
    }  
  
  };
  if (my $e = catch std::exception) {
    my $msg =  "Error adding XML data to container $XMLDBCONT\t-\t" ;
    $msg = $msg . $e->what();
    printError("./log/netradar-error.log", $msg);
    exit(-1);
  }
  elsif ($@) {
    my $msg = "Error adding XML data to container $XMLDBCONT\t-\t" ;
    $msg = $msg . $@;
    printError("./log/netradar-error.log", $msg);
    exit(-1);
  } 
  
  return %metadata;
}



# ################################################ #
# Sub:		getContents                        #
# Args:		$mgr - db connection manager       #
#		$cname - collection name           #
#		$query - What we are searching for #
#		$context - query context           #
# Purpose:	Given the input, perform a query   #
#               and return the results             #
# ################################################ #
sub getContents($$$$) {
  my $mgr = shift ;
  my $cname = shift ;
  my $query = shift ;
  my $context = shift ;
  my $results = "";
  my $value = "";
  
  my @resString = ();
  my $fullQuery = "collection('$cname')$query";
  eval {
    $results = $mgr->query($fullQuery, $context);
    while( $results->next($value) ) {
      push @resString, $value."\n";
    }	
    $value = "";
  };
  if (my $e = catch std::exception) {
    my $msg = "Query $fullQuery failed\t-\t";
    $msg = $msg . $e->what();
    printError("./log/netradar-error.log", $msg);
    exit( -1 );
  }
  elsif ($@) {
    my $msg = "Query $fullQuery failed\t-\t";
    $msg = $msg . $@;
    printError("./log/netradar-error.log", $msg);
    exit( -1 );
  }     
  return @resString;
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
  my %md = %{$sent};
  
  foreach my $element ($set->getChildNodes) {      
     
    if($element->getNodeType == 3) {
      my $value = $element->getValue;
      $value =~ s/\s+//g;
      if($value) {
        $md{$element->getParentNode->getLocalName} = $value;
      }
    }
    elsif($element->getLocalName eq "parameter") {
      my $et = "";
      my $vl = "";
      foreach my $attr2 ($element->getAttributes) {
        if($attr2->getLocalName eq "name" || $attr2->getNodeValue eq "eventType") {
	  $et = $attr2->getNodeValue;
	}
	elsif($attr2->getLocalName eq "value") {
	  $vl = $attr2->getNodeValue;
	}
      }
      $md{$element->getLocalName."-".$et} = $vl;   
    }
    else {
      foreach my $attr ($element->getAttributes) {
	if($element->getLocalName eq "ifAddress") {
	  $md{$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
      }
      %md = goDeep($element, \%md);
    }
  }	  
  return %md;
}



# ################################################ #
# Sub:		daemonize                          #
# Args:		N/A                                #
# Purpose:	Background process		   #
# ################################################ #
sub daemonize {
  chdir '/' or die "Can't chdir to /: $!";
  open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
  open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
  defined(my $pid = fork) or die "Can't fork: $!";
  exit if $pid;
  setsid or die "Can't start a new session: $!";
  umask 0;
}

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

		# Read/store database access info
$DBNAME = "";
$DBUSER = "";
$DBPASS = "";
readDBConf("./db.conf");

		# Read/store snmp collection info, we will 
		# need this to actually gather the data.
%snmp = ();
%snmp = readCollectConf("./collect.conf", \%snmp);

		# Read in the store of metadata info, we 
		# only want to get snmp data for what is 
		# in this file (not everything in the 
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
        open(LOG, "+>>/var/log/netradar-error.log");
        ($sec, $micro) = Time::HiRes::gettimeofday;
        print LOG "ERROR: " , $error, "\tTIME: " , $sec , "." , $micro , "\n";
        close(LOG);
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
          open(LOG, "+>>/var/log/netradar-error.log");
          ($sec, $micro) = Time::HiRes::gettimeofday;
          print LOG "ERROR: " , $session , " - " , $error , "\tTIME: " , $sec , "." , $micro , "\n";
          $session->close;
          close(LOG);
          $dbh->disconnect();
          exit(1);
        }
    
        $ins = "insert into data (id, time, value, eventtype, misc) values (?, ?, ?, ?, ?)";
        $sth = $dbh->prepare($ins);
        $sth->execute($m, $time, $result->{$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}}, $metadata{$m}{"parameter-eventType"}, "") 
          || warn "Executing: ", $sth->errstr;  
      }
      else {
        open(LOG, "+>>/var/log/netradar-error.log");
        ($sec, $micro) = Time::HiRes::gettimeofday;
        print LOG "ERROR: The OID, " , $metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"};
	print LOG ", cannot be found\tTIME: " , $sec , "." , $micro , "\n";
        close(LOG);	         
	$session->close; 
        $dbh->disconnect();
	exit(1);
      }
      $session->close;    
    }
    else {
      open(LOG, "+>>/var/log/netradar-error.log");
      ($sec, $micro) = Time::HiRes::gettimeofday;
      print LOG "ERROR: I am seeing a community of:\"";
      print LOG $snmp{$metadata{$m}{"hostName"}}[0] , "\" a version of:\"";
      print LOG $snmp{$metadata{$m}{"hostName"}}[1] , "\" and a hostname of:\""; 
      print LOG $metadata{$m}{"hostName"} , "\" ... something is amiss";
      print LOG "\tTIME: " , $sec , "." , $micro , "\n";
      close(LOG);    
      $dbh->disconnect();
      exit(1);
    }
  }
  $dbh->disconnect();
  sleep(1); 
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

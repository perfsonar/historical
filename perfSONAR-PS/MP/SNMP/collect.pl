#!/usr/bin/perl -w -I ./Netradar
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
use strict;
use Net::SNMP;
use DBI;
use Time::HiRes qw( gettimeofday );
use XML::XPath;
use POSIX qw( setsid );

use Netradar::Common;
use Netradar::DB::XMLDB;
use Netradar::DB::SQL;

my $DEBUG = 1;
my $LOGFILE ="./log/netradar-error.log";
my $DBFILE = "./db.conf";

my %hash = ();
%hash = readConfiguration($DBFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the DB configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata);

# setup 'data' database connection
#if($hash{"DATA_DB_TYPE"} eq "mysql") {
  my $datadb = new Netradar::DB::SQL(
    $hash{"DATA_DB_NAME"}, 
    $hash{"DATA_DB_USER"},
    $hash{"DATA_DB_PASS"}
  );
  
  my @dbSchema = ("id", "time", "value", "eventtype", "misc");
  my %dbSchemaValues = (
    id => "", 
    time => "", 
    value => "", 
    eventtype => "",  
    misc => ""
  );
    
#}
#elsif($hash{"DATA_DB_TYPE"} eq "rrd") {
#}
#elsif($hash{"DATA_DB_TYPE"} eq "file") {
#}

if(!$DEBUG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}

		# Main loop, we need to do the following 
		# things:
		#
		# 1) Open up a DB connection
		#
		# 2) For each metadata in the storage, 
		#    attempt to get make an SNMP query.
		#
		# 3) If the query is cool, insert into 
		#    the DB and move on.
								
while(1) {
 
  $datadb->openDB;

  foreach my $m (keys %metadata) {
  
    if($metadata{$m}{"parameter-SNMPVersion"} &&
       $metadata{$m}{"parameter-SNMPCommunity"} &&
       $metadata{$m}{"hostName"}) {

      if($DEBUG) {
        print $metadata{$m}{"parameter-SNMPVersion"} , "\n";
        print $metadata{$m}{"parameter-SNMPCommunity"} , "\n";
        print $metadata{$m}{"hostName"} , "\n";	
      }

      my ($session, $error) = Net::SNMP->session(
                             -community     => $metadata{$m}{"parameter-SNMPCommunity"},
                             -version       => $metadata{$m}{"parameter-SNMPVersion"},
	    	             -hostname      => $metadata{$m}{"hostName"}
	  	           ) || die "Couldn't open SNMP session to " , $metadata{$m}{"hostName"} , "\n";

      if (!defined($session)) {
        printError($LOGFILE, $error);
        $datadb->closeDB;
        exit(1);
      }

      if($metadata{$m}{"eventType"} && 
         $metadata{$m}{"ifIndex"}) {
        
	$metadata{$m}{"eventType"} =~ s/snmp\.//;
	
	my $time = time();
        my $result = $session->get_request(
          -varbindlist => [$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}]
        );
  
        if (!defined($result)) {
          printError($LOGFILE, $session." - ".$error);	  
          $datadb->closeDB;
          exit(1);
        }
    
    
        %dbSchemaValues = (
          id => $m, 
          time => $time, 
          value => $result->{$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}}, 
          eventtype => $metadata{$m}{"parameter-eventType"},  
          misc => ""
        );	
        $datadb->insert("data", \@dbSchema, \%dbSchemaValues);
	 
	  
	if($DEBUG) {
	  print "insert into data (id, time, value, eventtype, misc) values (";
	  print $m , ", "; 
	  print $time , ", "; 
	  print $result->{$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}} , ", "; 
	  print $metadata{$m}{"parameter-eventType"} , ", "; 
	  print "\"\"" , ")\n"; 	  
	}  
	  
      }
      else {
	printError($LOGFILE, "The OID, ".$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}." cannot be found.");		         
	$session->close; 
        $datadb->closeDB;
	exit(1);
      }
      $session->close;    
    }
    else {
      printError($LOGFILE, "I am seeing a community of:\"".$metadata{$m}{"parameter-SNMPVersion"}."\" a version of:\"".$metadata{$m}{"parameter-SNMPCommunity"}."\" and a hostname of:\"".$metadata{$m}{"hostName"}."\" ... something is amiss."); 
      $datadb->closeDB;
      exit(1);
    }
  }
  $datadb->closeDB;
  sleep(1); 
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



# ################################################ #
# Sub:		readMetadata                       #
# Args:		$sent - flattened hash of metadata #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Process each metadata block in the #
#               xmldb store.                       #
# ################################################ #
sub readMetadata {
  my($sent) = @_;
  my %metadata = %{$sent};

  my %ns = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
    netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
    nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
    snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
  );
  
  if($hash{"METADATA_DB_TYPE"} eq "mysql") {
    my $msg = "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is not yet supported.";
    printError($LOGFILE, $msg);
    exit(1);  
  }
  elsif($hash{"METADATA_DB_TYPE"} eq "xmldb") {  
    my $metadatadb = new Netradar::DB::XMLDB(
      $hash{"METADATA_DB_NAME"}, 
      $hash{"METADATA_DB_FILE"},
      \%ns
    );

    $metadatadb->openDB;
    my @resultsString = $metadatadb->query("//nmwg:metadata");   
    if($#resultsString != -1) {    
      for(my $x = 0; $x <= $#resultsString; $x++) {	
        %metadata = parseMetadata($resultsString[$x], \%metadata, \%ns);
      }
    }
    else {
      printError($LOGFILE, "XMLDB returned 0 results.");  
      exit(1);
    }  
  }
  elsif($hash{"METADATA_DB_TYPE"} eq "file") {
    my $xml = readXML($hash{"METADATA_DB_FILE"});
    %metadata = parseMetadata($xml, \%metadata, \%ns);
  }
  else {
    printError($LOGFILE, "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is invalid.");
    exit(1);     
  }
  
  return %metadata;
}

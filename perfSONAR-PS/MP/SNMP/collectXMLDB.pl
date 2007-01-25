#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		collectXMLDB.pl                    #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A                                #
# Purpose:	Given some conf files, gather and  #
#               store SNMP data in a database.     #
#                                                  #
# ################################################ #
use strict;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::MP::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/perfSONAR-PS-error.log";
my $DBFILE = "./collectXMLDB.conf";

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($DBFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata);

		# setup 'data' database connection to
		# the xmldb
my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
);
 
my $datadb = new perfSONAR_PS::DB::XMLDB(
  $hash{"DATA_DB_NAME"}, 
  $hash{"DATA_DB_FILE"},
  \%ns
);

		# Prepare an SNMP object for each
		# metadata block.
my %snmp = ();
foreach my $m (keys %metadata) {
  $metadata{$m}{"eventType"} =~ s/snmp\.//;	  
  $snmp{$m} = new perfSONAR_PS::MP::SNMP(
    $metadata{$m}{"hostName"}, 
    "" ,
    $metadata{$m}{"parameter-SNMPVersion"},
    $metadata{$m}{"parameter-SNMPCommunity"},
    "");
}

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
		# 2) For each SNMP object, collect the data
		#
		# 3) insert into the resulting data into
		#    the rrd file
		#
		# 4) sleep, then start again

$datadb->openDB;
foreach my $s (keys %snmp) {
  $snmp{$s}->setSession;
}	
					
while(1) {
  foreach my $m (keys %metadata) {
    
    		# Record the time, then get the data.    
    my $time = time();    
    my $result = $snmp{$m}->collect($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
    		
		# if there is some sort of problem with
		# the target, see if you can re-establish
		# the session
    if($result == -1) {
      $snmp{$m}->closeSession;  
      $snmp{$m}->setSession;
    }
    else {
      my $xml = "<nmwg:datum xmlns:nmwg='http://ggf.org/ns/nmwg/base/2.0/' time='";
      $xml = $xml . $time . "' value='" . $result . "'/>";
      $datadb->insertElement("/nmwg:data[\@metadataIdRef='".$m."']", $xml);
      if($DEBUG) {
        print "Inserting:\t" , $xml , "\n";
      }
    } 
  }
  sleep(1); 
}

foreach my $s (keys %snmp) {
  $snmp{$s}->closeSession;
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
    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
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

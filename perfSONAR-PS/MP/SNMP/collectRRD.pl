#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		collectRRD.pl                      #
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

use perfSONAR-PS::Common;
use perfSONAR-PS::DB::File;
use perfSONAR-PS::DB::XMLDB;
use perfSONAR-PS::DB::RRD;
use perfSONAR-PS::MP::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/perfSONAR-PS-error.log";
my $DBFILE = "./collectRRD.conf";

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($DBFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata);

		# setup 'data' database connection to
		# the rrd file, the values should be in
		# the same order as when created (this
		# designates a 'template')
my @dbSchema = ("eth0-in", "eth0-out");

		# Map the oid values to the DS names
my %dbSchemaValues = (
  'eth0-in' => "1.3.6.1.2.1.2.2.1.10.2", 
  'eth0-out' => "1.3.6.1.2.1.2.2.1.16.2", 
  'eth1-in' => "1.3.6.1.2.1.2.2.1.10.4", 
  'eth1-out' => "1.3.6.1.2.1.2.2.1.16.4"
); 

my $datadb = new perfSONAR-PS::DB::RRD(
  $hash{"DATA_DB_NAME"} , 
  $hash{"DATA_DB_FILE"},
  1
);
		# Prepare an SNMP object for each
		# metadata block.
my %snmp = ();
foreach my $m (keys %metadata) {
  $metadata{$m}{"eventType"} =~ s/snmp\.//;
  if(!defined $snmp{$metadata{$m}{"hostName"}}) {    	  
    $snmp{$metadata{$m}{"hostName"}} = new perfSONAR-PS::MP::SNMP(
      $metadata{$m}{"hostName"}, 
      "" ,
      $metadata{$m}{"parameter-SNMPVersion"},
      $metadata{$m}{"parameter-SNMPCommunity"},
      "");
  }
  $snmp{$metadata{$m}{"hostName"}}->setVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
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
  foreach my $s (keys %snmp) {
    my $time = time();   
    
    my %results = ();
    %results = $snmp{$s}->collectVariables;

		# if there is some sort of problem with
		# the target, see if you can re-establish
		# the session
    if(defined $results{"error"} && $results{"error"} == -1) {  
      $snmp{$s}->closeSession;  
      $snmp{$s}->setSession;
    }
    else {
      my @final = ();
      foreach my $value (@dbSchema) {
        push @final, "$results{$dbSchemaValues{$value}}";
      }
      my $insert = $datadb->insert($time, \@final, \@dbSchema);

      if($DEBUG) {
        for(my $x = 0; $x <= $#dbSchema; $x++) {
          print $dbSchema[$x] , "-" , $final[$x] , "\n";
        }
        print "\n";
      }    
      if($datadb->getErrorMessage()) {
	printError($LOGFILE, "Insert Error: ".$datadb->getErrorMessage()."; insert returned: ".$insert);	
      }
    }
  }
  sleep(1); 
}

foreach my $s (keys %snmp) {
  $snmp{$s}->closeSession;
}	
$datadb->closeDB;


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
    my $metadatadb = new perfSONAR-PS::DB::XMLDB(
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

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
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::MP::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/perfSONAR-PS-error.log";
my $CONFFILE = "./collectRRD.conf";

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($CONFFILE, \%hash);



		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata);

		# Read in the appropriate data to be
		# polling for, this also relates to the 
		# choices in the configuration file.  
my %data = ();
%data = readData(\%data);

		# this is a shortcut hash that will map
		# snmp variables(from the MD) to the proper
		# rrdinformation (from the data)
my %lookup = ();

		# Prepare an SNMP object for each host, this
		# could mean multiple metadata instances share
		# the same snmp object.
my %snmp = ();
foreach my $m (keys %metadata) {
  print Dumper($metadata{$m}) , "\n";

  $metadata{$m}{"eventType"} =~ s/snmp\.//;
  
  if(!defined $snmp{$metadata{$m}{"hostName"}}) {    	  
    $snmp{$metadata{$m}{"hostName"}} = new perfSONAR_PS::MP::SNMP(
      $metadata{$m}{"hostName"}, 
      "" ,
      $metadata{$m}{"parameter-SNMPVersion"},
      $metadata{$m}{"parameter-SNMPCommunity"},
      "");
  }
  $snmp{$metadata{$m}{"hostName"}}->setVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});

		# map the lookup information
  foreach my $d (keys %data) {
    if($data{$d}{"metadataIdRef"} eq $m) {
      $lookup{$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}} = $d;
      last;
    }
  }
}
		# Prepare an rrd object for each
		# rrd file that was seen (we can map
		# multiple data blocks to a single rrd 
		# object
my %datadb = ();
foreach my $d (keys %data) {
  print Dumper($data{$d}) , "\n";
  
  if(!defined $datadb{$data{$d}{"parameter-file"}}) { 
    $datadb{$data{$d}{"parameter-file"}} = new perfSONAR_PS::DB::RRD(
      $hash{"DATA_DB_NAME"} , 
      $data{$d}{"parameter-file"},
      "",
      1
    );
  }
  		# load in the data sources
  $datadb{$data{$d}{"parameter-file"}}->setVariable($data{$d}{"parameter-dataSource"});
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
		# 1) Set up the SNMP connections
		#
		# 2) For each SNMP object, collect the data
		#
		# 3) insert into the resulting data into
		#    the rrd file
		#
		# 4) sleep, then start again

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
      foreach my $r (keys %results) {
      		
		# 'insert' the results as they come in to 
		# the RRD object, note that this isn't final
		# until after all SNMP objects have been 
		# polled
        $datadb{$data{$lookup{$r}}{"parameter-file"}}->insert($time, 
	                                                      $data{$lookup{$r}}{"parameter-dataSource"},
							      $results{$r});
	if($DEBUG) {
	  print "inserting: " , $time , "," , $data{$lookup{$r}}{"parameter-dataSource"} , "," , $results{$r} , "\n";
	} 
      }
    }
  }

		# No we commit, by doing this at the end
		# we ensure that ALL possible DS values for
		# the RRD files are updated at once for a 
		# given time value (we can't update the same
		# time value, even with different DS values
		# more than once.
  foreach my $db (keys %datadb) {
    $datadb{$db}->openDB;
    $datadb{$db}->insertCommit;
    $datadb{$db}->closeDB;
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


# ################################################ #
# Sub:		readData                           #
# Args:		$sent - flattened hash of data     #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Process each data block in the     #
#               store.                             #
# ################################################ #
sub readData {
  my($sent) = @_;
  my %data = %{$sent};

  my %ns = (
    nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
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
    my @resultsString = $metadatadb->query("//nmwg:data");   
    if($#resultsString != -1) {    
      for(my $x = 0; $x <= $#resultsString; $x++) {	
        %data = parseData($resultsString[$x], \%data, \%ns);
      }
    }
    else {
      printError($LOGFILE, "XMLDB returned 0 results.");  
      exit(1);
    }  
  }
  elsif($hash{"METADATA_DB_TYPE"} eq "file") {
    my $xml = readXML($hash{"METADATA_DB_FILE"});
    %data = parseData($xml, \%data, \%ns);
  }
  else {
    printError($LOGFILE, "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is invalid.");
    exit(1);     
  }
  
  return %data;
}

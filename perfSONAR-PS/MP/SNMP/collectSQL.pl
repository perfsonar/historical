#!/usr/bin/perl -w -I ../../lib
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
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );

use Netradar::Common;
use Netradar::DB::XMLDB;
use Netradar::DB::SQL;
use Netradar::MP::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/netradar-error.log";
my $DBFILE = "./collectSQL.conf";

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($DBFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata);

		# setup 'data' database connection
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
		# Prepare an SNMP object for each
		# metadata block.
my %snmp = ();
foreach my $m (keys %metadata) {
  $metadata{$m}{"eventType"} =~ s/snmp\.//;	  
  $snmp{$m} = new Netradar::MP::SNMP(
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
		# 2) For each metadata in the storage, 
		#    use it's snmp object to make a query.
		#
		# 3) insert into the resulting data into
		#    the database
		#
		# 4) sleep, then start again

$datadb->openDB;
foreach my $m (keys %metadata) {
  $snmp{$m}->setSession;
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
   		# Prepare and insert into the database.
      %dbSchemaValues = (
        id => $m, 
        time => $time, 
        value => $result, 
        eventtype => $metadata{$m}{"parameter-eventType"},  
        misc => ""
      );	
      my $status = $datadb->insert("data", \@dbSchema, \%dbSchemaValues);
      
      		# If the database had some sort of failure, 
		# see if the connection can be re-established 
      if($status == -1) {
        $datadb->closeDB;
	$datadb->openDB;
      }

      if($DEBUG) {
        print "insert into data (id, time, value, eventtype, misc) values (";
        print $m , ", "; 
        print $time , ", "; 
        print $result , ", "; 
        print $metadata{$m}{"parameter-eventType"} , ", "; 
        print "\"\"" , ")\n";
      }
    } 
  }
  sleep(1); 
}

foreach my $m (keys %metadata) {
  $snmp{$m}->closeSession;
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
  
  if($hash{"METADATA_DB_TYPE"} eq "xmldb") {  
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

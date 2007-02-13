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
use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MP::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/perfSONAR-PS-error.log";
my $CONFFILE = "./collectRRD.conf";

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($CONFFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
%metadata = readMetadata(\%metadata, \%ns);
%metadata = chainMetadata(\%metadata);

		# Read in the appropriate data to be
		# polling for, this also relates to the 
		# choices in the configuration file.  
my %data = ();
%data = readData(\%data, \%ns);

		# remove md that were used just for 
		# chaining purposes (i.e. if a md has a 
		# data trigger, we should keep it).
foreach my $m (keys %metadata) {
  my $flag = 0;
  foreach my $d (keys %data) {
    if($m eq $data{$d}{"nmwg:data-metadataIdRef"}) {
      $flag = 1;
      last;
    }
  }
  if(!$flag) {
    if($DEBUG) {
      print "Removing '".$m."' from the Metadata list.\n";
    }
    delete $metadata{$m};  
  }
}
		# this is a shortcut hash that will map
		# OIDs (from the MD) to the proper rrd 
		# information (from the data).  We also
		# will always be requesting the upTime
		# so we can keep a synchronization with
		# the remote clock.
my %lookup = ();
$lookup{"localhost-1.3.6.1.2.1.1.3.0"} = "timeticks";

		# Prepare an SNMP object for each host, this
		# could mean multiple metadata instances share
		# the same snmp object.
my %snmp = ();
foreach my $m (keys %metadata) {
  if($DEBUG) {
    print $m , " - " , Dumper($metadata{$m}) , "\n";
  }
  
  $metadata{$m}{"eventType"} =~ s/snmp\.//;
  
  if(!defined $snmp{$metadata{$m}{"hostName"}}) {    	  
    $snmp{$metadata{$m}{"hostName"}} = new perfSONAR_PS::MP::SNMP(
      $metadata{$m}{"hostName"}, 
      "" ,
      $metadata{$m}{"parameter-SNMPVersion"},
      $metadata{$m}{"parameter-SNMPCommunity"},
      "");
  }
  $snmp{$metadata{$m}{"hostName"}}->setVariable("1.3.6.1.2.1.1.3.0");  
  $snmp{$metadata{$m}{"hostName"}}->setVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
  
		# map the lookup information
  foreach my $d (keys %data) {
    if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) {
      $lookup{$metadata{$m}{"hostName"}."-".$metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"}} = $d;
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
  if($DEBUG) {
    print $d , " - " , Dumper($data{$d}) , "\n";
  }
  
  if($data{$d}{"parameter-type"} eq "rrd") {
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
  elsif($data{$d}{"parameter-type"} eq "sqlite") {
    print "We do not support this data type right now, sorry.\n";
    foreach my $m (keys %metadata) {
      if($m eq $data{$d}{"nmwg:data-metadataIdRef"}) {
      
        	#remove snmp reference
        $snmp{$metadata{$m}{"hostName"}}->removeVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
      		#remove md totally
        if($DEBUG) {
	  print "Removing '".$m."' from the Metadata list.\n";
        }
	delete $metadata{$m};
      }
    }
    		#remove SNMP if it has no variables?
    foreach my $s (keys %snmp) {
      print "SNMP: " , $s , " has count: " , $snmp{$s}->getVariableCount , "\n";
      if($snmp{$s}->getVariableCount == 1) {
        if($DEBUG) {
          print "Removing '".$s."' from the SNMP list.\n";
	}
	delete $snmp{$s};
      }
    }
  }
  elsif($data{$d}{"parameter-type"} eq "mysql") {
    print "We do not support this data type right now, sorry.\n";
    foreach my $m (keys %metadata) {
      if($m eq $data{$d}{"nmwg:data-metadataIdRef"}) {
      
        	#remove snmp reference
        $snmp{$metadata{$m}{"hostName"}}->removeVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
      		#remove md totally
        if($DEBUG) {
	  print "Removing '".$m."' from the Metadata list.\n";
        }
	delete $metadata{$m};
      }
    }
    		#remove SNMP if it has no variables?
    foreach my $s (keys %snmp) {
      print "SNMP: " , $s , " has count: " , $snmp{$s}->getVariableCount , "\n";
      if($snmp{$s}->getVariableCount == 1) {
        if($DEBUG) {
	  print "Removing '".$s."' from the SNMP list.\n";
	}
	delete $snmp{$s};
      }
    }
  }
  else {
    print "We do not support this data type right now, sorry.\n";
    foreach my $m (keys %metadata) {
      if($m eq $data{$d}{"nmwg:data-metadataIdRef"}) {
      
        	#remove snmp reference
        $snmp{$metadata{$m}{"hostName"}}->removeVariable($metadata{$m}{"eventType"}.".".$metadata{$m}{"ifIndex"});
      		#remove md totally
        if($DEBUG) {
	  print "Removing '".$m."' from the Metadata list.\n";
        }
	delete $metadata{$m};
      }
    }
    		#remove SNMP if it has no variables?
    foreach my $s (keys %snmp) {
      print "SNMP: " , $s , " has count: " , $snmp{$s}->getVariableCount , "\n";
      if($snmp{$s}->getVariableCount == 1) {
        if($DEBUG) {
	  print "Removing '".$s."' from the SNMP list.\n";
	}
	delete $snmp{$s};
      }
    }
  }  
}


if(!$DEBUG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}

if($DEBUG) {
  print "Starting '".threads->tid()."' as main\n";
}

my $reval:shared = 0;
my $sem = Thread::Semaphore->new(1);
my $mpThread = threads->new(\&measurementPoint, $DEBUG, $hash{"MP_SAMPLE_RATE"});
my $maThread = threads->new(\&measurementArchive, $DEBUG, $hash{"PORT"}, $hash{"ENDPOINT"});
my $regThread = threads->new(\&registerLS, $DEBUG, $hash{"LS_REGISTRATION_INTERVAL"}, $hash{"LS_INSTANCE"});

if(!defined $mpThread || !defined $maThread || !defined $regThread) {
  print "Thread creation has failed...exiting...\n";
  exit(1);
}

$mpThread->join();
$maThread->join();
$regThread->join();





# ################################################ #
# Sub:		measurementPoint                   #
# Args:		N/A                                #
# Purpose:	Performs measurements at a         #
#               periodic rate as specified in the  #
#               storage medium                     #
# ################################################ #
sub measurementPoint {
  my($DEBUG, $sampleRate) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MP\n";
  }
		# Pre-Loop tasks include:
		#
		# 1) Set up the SNMP connections
		#
		# 2) Set up the time keeping mechanism for 
		#    each host

  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $time = $sec.".".$frac;
  
  my %hostTicks = ();
  my %refTime = ();
  foreach my $s (keys %snmp) {
    $refTime{$s} = $time;
    $hostTicks{$s} = 0;
    $snmp{$s}->setSession;
  }

		# Main loop, we need to do the following 
		# things:
		#
		# 1) For each SNMP object, collect the data
		#
		# 2) Do some bookeeping on each time value
		#    to ensure that we are keeping synch
		#    with the time on the remote host (as 
		#    best as we can)
		# 
		# 3) insert into the resulting data into
		#    the rrd file
		#
		# 4) sleep, then start again
					
  while(1) {
  
    if($reval) {
      		# a change has been made to the MD 
		# structure (by the MA thread) so we
		# need to re-eval all of our objects 
		# (md, d, and snmp) to respect this 
		# change.


      # do stuff...
      

      		# Make sure the flag variable is 
		# not in use, then reset the flag 
		# value.
      $sem->down;
      {
        lock($reval);
        $reval = 0;
      }
      $sem->up;
    }  
  
    foreach my $s (keys %snmp) {
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
		# The first issue is to do bookeeping on 
		# the time info for the particular host 
		# we have just polled.  Update the 'remote'
		# time based on the timeticks we get back
		# in the SNMP packet.
        my $diff = 0;
        my $newHostTicks = 0;
        foreach my $r (keys %results) {
          if($lookup{"localhost-".$r} && $lookup{"localhost-".$r} eq "timeticks") {
	    if($hostTicks{$s} == 0) {
	      $hostTicks{$s} = $results{$r}/100;
	      $newHostTicks = $results{$r}/100;
	    }
	    else {	    
	      $newHostTicks = $results{$r}/100;	    
	    }
	    last;
	  }
        }    
      		# Calculate the difference, update, and adjust
		# this new time.
        $diff = $newHostTicks - $hostTicks{$s};
        $hostTicks{$s} = $newHostTicks;  
        $refTime{$s} += $diff;

		# 'insert' the results as they come in to 
		# the RRD object, note that this isn't final
		# until after all SNMP objects have been 
		# polled     
        foreach my $r (keys %results) { 
          if($lookup{$s."-".$r} && $lookup{$s."-".$r} ne "timeticks") {
	    if($DEBUG) {
	      print "inserting: " , $refTime{$s}  , "," , $data{$lookup{$s."-".$r}}{"parameter-dataSource"} , "," , $results{$r} , "\n";
	    }				
            $datadb{$data{$lookup{$s."-".$r}}{"parameter-file"}}->insert($refTime{$s}, 
	                                                                 $data{$lookup{$s."-".$r}}{"parameter-dataSource"},
			  				                 $results{$r});
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
    my @result = ();
    foreach my $db (keys %datadb) {
      $datadb{$db}->openDB;
      @result = $datadb{$db}->insertCommit;
      $datadb{$db}->closeDB;
    }
  
    sleep($sampleRate); 
  }

  foreach my $s (keys %snmp) {
    $snmp{$s}->closeSession;
  }
}


# ################################################ #
# Sub:		measurementArchive                 #
# Args:		N/A                                #
# Purpose:	Implements the WS functionality of #
#               an MA by listening on a port for   #
#               messages and responding            #
#               accordingly.                       #
# ################################################ #
sub measurementArchive {
  my($DEBUG, $port, $endPoint) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MA on port '".$port."' and endpoint '".$endPoint."'.\n";
  }

  my $listener = new perfSONAR_PS::Transport($port, $endPoint, "", "", "");  
  $listener->startDaemon;
  while(1) {
    if($listener->acceptCall == 1) {
      $listener->setResponse("Everything OK");
      
      print "REQUEST:\n" , $listener->getRequest , "\n";

      my %messagemd = ();
      %messagemd = parseMetadata($listener->getRequest, \%messagemd, \%ns);            
      print Dumper(%messagemd) , "\n";
      %messagemd = chainMetadata(\%messagemd);
      print "\n\n\n" , Dumper(%messagemd) , "\n";      

      my %messaged = ();
      %messaged = parseData($listener->getRequest, \%messaged, \%ns);      
      print "\n\n\n" , Dumper(%messaged) , "\n";
      
    }
    else {
      $listener->setResponse("Bad Request");

      printError($LOGFILE, "Sent Request has was not expected: ".
                 $listener->{REQUEST}->uri.", ".$listener->{REQUEST}->method.", ".
		 $listener->{REQUEST}->headers->{"soapaction"}.".");  
    }
    $listener->closeCall;
  }
  return;
}



# ################################################ #
# Sub:		registerLS                         #
# Args:		N/A                                #
# Purpose:	Periodically registers with a      #
#               specified LS instance.             #
# ################################################ #
sub registerLS {
  my($DEBUG, $registerRate, $lsInstance) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as to register with LS '".$lsInstance."'.\n";
  }
  return
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
  my($sent, $sentns) = @_;
  my %metadata = %{$sent};
  my %ns = %{$sentns};
  
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
  my($sent, $sentns) = @_;
  my %data = %{$sent};
  my %ns = %{$sentns};
  
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


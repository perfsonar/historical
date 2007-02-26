#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		snmpMA.pl                          #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A                                #
# Purpose:	Functions as an MA for snmp        #
#               measurements.                      #
#                                                  #
# ################################################ #
use strict;
use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::MA::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %conf = ();
readConfiguration("./snmpMA.conf", \%conf);


if(!$DEBUG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}


if($DEBUG) {
  print "Starting '".threads->tid()."' as main\n";
}

my $maThread = threads->new(\&measurementArchive);
my $regThread = threads->new(\&registerLS);

if(!defined $maThread || !defined $regThread) {
  print "Thread creation has failed...exiting...\n";
  exit(1);
}

$maThread->join();
$regThread->join();





# ################################################ #
# Sub:		measurementArchive                 #
# Args:		N/A                                #
# Purpose:	Implements the WS functionality of #
#               an MA by listening on a port for   #
#               messages and responding            #
#               accordingly.                       #
# ################################################ #
sub measurementArchive {
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MA on port '".$conf{"PORT"}."' and endpoint '".$conf{"ENDPOINT"}."'.\n";
  }

  my $listener = new perfSONAR_PS::Transport($conf{"PORT"}, $conf{"ENDPOINT"}, "", "", "");  
  $listener->startDaemon;

  my $MDId = genuid();
  my $DId = genuid();
    								
  while(1) {
    my $response = "";
    if($listener->acceptCall == 1) {
      my $ma = perfSONAR_PS::MA::SNMP->new(
        $conf{"METADATA_DB_TYPE"},
        $conf{"METADATA_DB_NAME"},
        $conf{"METADATA_DB_FILE"},
        $conf{"METADATA_DB_USER"},
        $conf{"METADATA_DB_PASS"},
	$conf{"LOGFILE"},
	$conf{"RRDTOOL"},
      );
      $response = $ma->handleRequest($listener->getRequest, \%ns); 
      $listener->setResponse($response, 1); 
    }
    else {
      my $msg = "Sent Request has was not expected: ".
                 $listener->{REQUEST}->uri.", ".$listener->{REQUEST}->method.", ".
		 $listener->{REQUEST}->headers->{"soapaction"}.".";
      printError($conf{"LOGFILE"}, $msg); 
      $response = getResultCodeMessage("", "", "response", "error.transport.soap", $msg); 
      $listener->setResponse($response, 1); 		 	  
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
  if($DEBUG) {
    print "Starting '".threads->tid()."' as to register with LS '".$conf{"LS_INSTANCE"}."'.\n";
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


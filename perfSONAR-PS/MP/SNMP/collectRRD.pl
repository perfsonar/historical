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
use perfSONAR_PS::MP::SNMP;
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
readConfiguration("./collectRRD.conf", \%conf);


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

my $mpThread = threads->new(\&measurementPoint);
#my $mpThread = threads->new(\&registerLS);

my $maThread = threads->new(\&measurementArchive);
my $regThread = threads->new(\&registerLS);

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
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MP2\n";
  }
  
  my $mp = new perfSONAR_PS::MP::SNMP(\%conf, \%ns, "", "");
  $mp->parseMetadata;
  $mp->prepareData;
  $mp->prepareCollectors;

		# Pre-Loop tasks include:
		#
		# 1) Set up the SNMP connections
		#
		# 2) Set up the time keeping mechanism for 
		#    each host
  my($sec, $frac) = Time::HiRes::gettimeofday;
  $mp->prepareTime($sec.".".$frac);

		# Main loop, we need to do the following 
		# things:
		#
		# 1) Ensure there are not 'new' points
		#    we need to worry about (if something
		#    was added in through the MA side
		#    perhaps)
		#
		# 2) collect and store measurements
		#    via the object
		#
		# 3) sleep and try again
  while(1) {
    if($reval) {
      		# a change has been made to the MD 
		# structure (by the MA thread) so we
		# need to re-eval all of our objects 
		# (md, d, and snmp) to respect this 
		# change.

      $mp = new perfSONAR_PS::MP::SNMP(\%conf, \%ns, "", "");
      $mp->parseMetadata;
      $mp->prepareData;
      $mp->prepareCollectors;

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
      
    $mp->collectMeasurements;
    
    sleep($conf{"MP_SAMPLE_RATE"});
  }
  return;  
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
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MA on port '".$conf{"PORT"}."' and endpoint '".$conf{"ENDPOINT"}."'.\n";
  }

  my $listener = new perfSONAR_PS::Transport($conf{"LOGFILE"}, $conf{"PORT"}, $conf{"ENDPOINT"}, "", "", "");  
  $listener->startDaemon;

  my $MDId = genuid();
  my $DId = genuid();
    								
  while(1) {
    my $response = "";
    if($listener->acceptCall == 1) {
      my $ma = perfSONAR_PS::MA::SNMP->new(\%conf);
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

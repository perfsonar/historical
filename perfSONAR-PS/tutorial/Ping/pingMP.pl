#!/usr/bin/perl -w -I ../../lib
use strict;
use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::MA::Ping;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::MP::Ping;
use perfSONAR_PS::MP::General;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %conf = ();
readConfiguration("./pingMP.conf", \%conf);


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
    print "Starting '".threads->tid()."' as MP\n";
  }

  my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "", "");
  $mp->parseMetadata;
  $mp->prepareData;
  $mp->prepareCollectors;  
 
  # initialize measurement info, time, etc.
  
  while(1) {

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

      if($DEBUG) {
        print "Request:\t" , $listener->getRequest , "\n";
      }

      my $ma = perfSONAR_PS::MA::Ping->new(\%conf, \%ns, "", "");
      $response = $ma->handleRequest($listener->getRequest); 
      
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

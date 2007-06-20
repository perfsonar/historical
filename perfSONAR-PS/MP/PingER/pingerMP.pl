#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use threads::shared;
use Thread::Semaphore; 
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
     
use perfSONAR_PS::Common;
use perfSONAR_PS::MP::PingER;

Log::Log4perl->init("logger.conf");

my $logger = get_logger("perfSONAR_PS");




my $DEBUGFLAG = '';
my $HELP = '';
my $CONFIGURATION = 'pinger3.xml';

my $status = GetOptions (
		'config=s' => \$CONFIGURATION,
		'verbose' => \$DEBUGFLAG,
        'help' => \$HELP );

if(!$status or $HELP) {
  print "$0: starts the pingER MP and MA.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  pinger => "http://ggf.org/ns/nmwg/tools/pinger/1.0/",
  nmwgt4 => "http://ggf.org/ns/nmwg/topology/l3/3.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

    # set logging level
if($DEBUGFLAG) {
  $logger->level($DEBUG);    
}
else {
  $logger->level($INFO); 
}

if(!$DEBUGFLAG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}

$logger->debug("Starting '".threads->tid()."'");

my $reval:shared = 0;
my $sem = Thread::Semaphore->new(1);

my $mpThread = threads->new(\&measurementPoint);
#my $maThread = threads->new(\&measurementArchive);
#my $regThread = threads->new(\&registerLS);

#if(!defined $maThread or !defined $mpThread or !defined $regThread) {
if( !defined $mpThread ) {
  $logger->fatal("Thread creation has failed...exiting.");
  exit(1);
}

$mpThread->join();
#$maThread->join();
#$regThread->join();




sub measurementPoint {
  $logger->debug("Starting '".threads->tid()."' as the MP.");
  
  my $mp = new perfSONAR_PS::MP::PingER( $CONFIGURATION, \%ns,);
  $mp->parseMetadata;
  $mp->prepareMetadata;

  $mp->run( );

#  $mp->prepareData;
#  $mp->prepareCollectors;  
#  while(1) {
#    $mp->collectMeasurements;
#    sleep($conf{"MP_SAMPLE_RATE"});
#  }
  return;  
}



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


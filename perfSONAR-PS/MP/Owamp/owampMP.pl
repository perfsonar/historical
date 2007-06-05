#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Data::Dumper;
use Log::Log4perl qw(get_logger :levels);

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::MA::Owamp;
use perfSONAR_PS::MP::Owamp;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';
my $status = GetOptions ('verbose' => \$DEBUGFLAG,
                         'help' => \$HELP);

if(!$status or $HELP) {
  print "$0: starts the snmp MP and MA.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}
my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  owamp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %conf = ();
readConfiguration("./owampMP.conf", \%conf);

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
my $maThread = threads->new(\&measurementArchive);
my $regThread = threads->new(\&registerLS);

if(!defined $mpThread or !defined $maThread or !defined $regThread) {
  $logger->fatal("Thread creation has failed...exiting.");
  exit(1);
}

$mpThread->join();
$maThread->join();
$regThread->join();







sub measurementPoint {
  $logger->debug("Starting '".threads->tid()."' as the MP.");

  my $mp = new perfSONAR_PS::MP::Owamp(\%conf, \%ns, "");
  $mp->parseMetadata;
  $mp->prepareData;
  $mp->prepareCollectors;

  # initialize measurement info, time, etc.
  
  while(1) {

    # collect measurement info
    
    sleep($conf{"MP_SAMPLE_RATE"});
  }
  return;  
}




sub measurementArchive {
  $logger->debug("Starting '".threads->tid()."' as the MA.");

  my $ma = new perfSONAR_PS::MA::Owamp(\%conf, \%ns);
  $ma->init;  
  while(1) {
    my $runThread = threads->new(\&measurementArchiveQuery, $ma);
    if(!defined $runThread) {
      $logger->fatal("Thread creation has failed...exiting");
      exit(1);
    }
    $runThread->join();  
  }  
  return;
}


sub measurementArchiveQuery {
  my($ma) = @_; 
  $logger->debug("Starting '".threads->tid()."' as the execution path.");
  
  $ma->receive;
  $ma->respond;
  return;
}





sub registerLS {
  $logger->debug("Starting '".threads->tid()."' as the LS registration to \"".$conf{"LS_INSTANCE"}."\".");

  return
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


=head1 NAME

owampMP.pl - An Owamp based collection agent (MeasurementPoint) with MA (MeasurementArchive) 
capabilities.

=head1 DESCRIPTION

This script creates an MP and MA for an Owamp based collector.  The service is also capable
of registering with an LS instance.  

=head1 SYNOPSIS

./owampMP.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute the 3 major tasks of
LS registration, MP operation, and MA listening and delivery.

=head2 measurementPoint

This function, meant to be used in the context of a thread, will continuously poll
the 'store.xml' list of metadata to gather measurements, storing them in backend
storage also specified by the 'store.xml' file.  

=head2 measurementArchive

This function, meant to be used in the context of a thread, will listen on an external
port (specified in the conf file) and serve requests for data from outside entities.  The
data and metadata are stored in various database structures.

=head2 registerLS

This function, meant to be used in the context of a thread, will continously register
and update its information with the LS specified in the conf file.  

=head2 daemonize

Sends the program to the background by eliminating ties to the calling terminal.  

=head1 REQUIRES

Getopt::Long;
threads
threads::shared
Thread::Semaphore
Time::HiRes qw( gettimeofday );
POSIX qw( setsid )
Log::Log4perl qw(get_logger :levels)
perfSONAR_PS::Common
perfSONAR_PS::Transport
perfSONAR_PS::MP::Owamp
perfSONAR_PS::MA::Owamp

=head1 AUTHOR

Warren Matthews <warren.matthews@oit.gatech.edu>, Jason Zurawski <zurawski@internet2.edu>

=head1 VERSION

$Id$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut


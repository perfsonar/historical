#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
     
use perfSONAR_PS::Common;
use skeletonMP;
use skeletonMA;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';
my $status = GetOptions ('verbose' => \$DEBUGFLAG,
                         'help' => \$HELP);

if(!$status or $HELP) {
  print "$0: starts the skeleton MP and MA.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
  skel => "http://ggf.org/ns/nmwg/tools/skeleton/2.0/"
);

		# Read in configuration information
my %conf = ();
readConfiguration("./skeletonMP.conf", \%conf);

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

my $mpThread = threads->new(\&measurementPoint);
my $maThread = threads->new(\&measurementArchive);

if(!defined $maThread or !defined $mpThread) {
  $logger->fatal("Thread creation has failed...exiting.");
  exit(1);
}

$mpThread->join();
$maThread->join();





sub measurementPoint {
  $logger->debug("Starting '".threads->tid()."' as the MP.");
  
  my $mp = new skeletonMP(\%conf, \%ns, "");
  $mp->parseMetadata;
  $mp->prepareData;
  $mp->prepareCollectors;  
  while(1) {
    $mp->collectMeasurements;
    sleep($conf{"MP_SAMPLE_RATE"});
  }
  return;  
}


sub measurementArchive {
  $logger->debug("Starting '".threads->tid()."' as the MA.");

  my $ma = new skeletonMA(\%conf, \%ns);
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

skeletonMP.pl - A skeleton of a collection agent (MeasurementPoint) with MA (MeasurementArchive) 
capabilities.

=head1 DESCRIPTION

This script creates an MP and MA for the skeleton collector. 

=head1 SYNOPSIS

./skeletonMP.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute the 2 major tasks of
MP operation, and MA listening and delivery.

=head2 measurementPoint

This function, meant to be used in the context of a thread, will continuously poll
the 'store.xml' list of metadata to gather measurements, storing them in backend
storage also specified by the 'store.xml' file.  

=head2 measurementArchive

This function, meant to be used in the context of a thread, will listen on an external
port (specified in the conf file) and serve requests for data from outside entities.  The
data and metadata are stored in various database structures.

=head2 measurementArchiveQuery

This performs the semi-automic operations of the MA.    

=head2 daemonize

Sends the program to the background by eliminating ties to the calling terminal.  

=head1 REQUIRES

Getopt::Long;
threads
Time::HiRes qw( gettimeofday );
POSIX qw( setsid )
Log::Log4perl
perfSONAR_PS::Common
perfSONAR_PS::Transport
skeletonMP
skeletonMA

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 VERSION

$Id:$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

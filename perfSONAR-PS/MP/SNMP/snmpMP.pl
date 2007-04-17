#!/usr/bin/perl -w -I ../../lib

use strict;
use Getopt::Long;

use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::MP::SNMP;
use perfSONAR_PS::MA::SNMP;

my $fileName = "snmpMP.pl";
my $functionName = "main";
my $DEBUG = '';
my $HELP = '';
my $status = GetOptions ('verbose' => \$DEBUG,
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
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %conf = ();
readConfiguration("./snmpMP.conf", \%conf);
$conf{"DEBUG"} = $DEBUG;

if(!$DEBUG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}

print $fileName.":\tStarting '".threads->tid()."' in ".$functionName."\n" if($DEBUG);

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







sub measurementPoint {
  my $functionName = "measurementPoint";
  print $fileName.":\tStarting '".threads->tid()."' as the MP in ".$functionName."\n" if($DEBUG);
  
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


sub measurementArchive {
  my $functionName = "measurementArchive";  
  print $fileName.":\tStarting '".threads->tid()."' as the MA in ".$functionName."\n" if($DEBUG);

  my $ma = new perfSONAR_PS::MA::SNMP(\%conf, \%ns, "");
  $ma->init;  
  while(1) {
    $ma->receive;
    $ma->respond;
  }  
  return;
}


sub registerLS {
  my $functionName = "registerLS";  
  print $fileName.":\tStarting '".threads->tid()."' as the LS registration to \"".
        $conf{"LS_INSTANCE"}."\" in ".$functionName."\n" if($DEBUG);
	
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

snmpMP.pl - An SNMP based collection agent (MeasurementPoint) with MA (MeasurementArchive) 
capabilities.

=head1 DESCRIPTION

This script creates an MP and MA for an SNMP based collector.  The service is also capable
of registering with an LS instance.  

=head1 SYNOPSIS

./snmpMP.pl [--verbose | --help]

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
perfSONAR_PS::Common
perfSONAR_PS::Transport
perfSONAR_PS::MP::SNMP
perfSONAR_PS::MA::SNMP

=head1 AUTHOR

Jason Zurawski <zurawski@internet2.edu>

=head1 VERSION

$Id$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

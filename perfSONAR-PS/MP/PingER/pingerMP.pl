#!/usr/bin/perl -w -I ../../lib

=head1 NAME

pingerMP.pl - An PingER based collection agent (MeasurementPoint). Exports results in perfSONAR
schema format to a remote MA

=head1 DESCRIPTION

This script creates an MP for a PingER based collector.  The service is not yet also capable
of registering with an LS instance.  

=head1 SYNOPSIS

./pingerMP.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute the major tasks of
LS registration, MP operation, and MA listening and delivery.

=head2 measurementPoint

This function, meant to be used in the context of a thread, will continuously poll
the 'store.xml' list of metadata to gather measurements, storing them in backend
storage also specified by the 'store.xml' file.

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
Log::Log4perl
perfSONAR_PS::Common
perfSONAR_PS::Transport
perfSONAR_PS::MP::PingER
perfSONAR_PS::XML::Base
perfSONAR_PS::XML::PingER


=head1 AUTHOR

Yee-Ting Li <ytl@slac.stanford.edu>

=head1 VERSION

$Id: pingMP.pl 224 2007-06-11 13:25:58Z zurawski $

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Yee-Ting Li

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut


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
use perfSONAR_PS::XML::Namespace;

# get the logging instance
Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';
our $CONFIGURATION = 'pingerMP.conf';

my $status = GetOptions (
		'config=s' => \$CONFIGURATION,
		'verbose' => \$DEBUGFLAG,
        'help' => \$HELP );

if(!$status or $HELP) {
  print "$0: starts the pingER MP.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}

#my %ns = (
#  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
#  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
#  pinger => "http://ggf.org/ns/nmwg/tools/pinger/2.0/",
#  nmtl3 => "http://ggf.org/ns/nmwg/topology/l3/3.0/",
#  nmtl4 => "http://ggf.org/ns/nmwg/topology/l4/3.0/",
#  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
#);
my $ns = perfSONAR_PS::XML::Namespace->new();


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

# parse the configuraiton file
my %conf = ();
readConfiguration( $CONFIGURATION, \%conf);

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



###
# create an instance of the MP
###
sub measurementPoint {
  $logger->debug("Starting '".threads->tid()."' as the MP.");
  
  my $mp = new perfSONAR_PS::MP::PingER( \%conf, $ns,);
  $mp->parseMetadata;
  $mp->prepareMetadata;

  # start scheduler for pings
  $mp->run( );

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


1;
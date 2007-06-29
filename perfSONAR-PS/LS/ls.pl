#!/usr/bin/perl -w -I ../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
     
use perfSONAR_PS::Common;
use perfSONAR_PS::LS::LS;

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
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
  perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
  psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"   
);

		# Read in configuration information
my %conf = ();
readConfiguration("./ls.conf", \%conf);

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

my $lsThread = threads->new(\&lookupService);
my $regThread = threads->new(\&registerLS);

if(!defined $lsThread or !defined $regThread) {
  $logger->fatal("Thread creation has failed...exiting.");
  exit(1);
}

$lsThread->join();
$regThread->join();

# need a 'reaping' thread to clean out the old stuff, run it
# every now and then




sub lookupService {
  $logger->debug("Starting '".threads->tid()."' as the LS.");

  my $ls = new perfSONAR_PS::LS::LS(\%conf, \%ns);
  $ls->init;  
  while(1) {
    my $runThread = threads->new(\&lookupServiceQuery, $ls);
    if(!defined $runThread) {
      $logger->fatal("Thread creation has failed...exiting");
      exit(1);
    }
    $runThread->join();  
  }  
  return;
}


sub lookupServiceQuery {
  my($ls) = @_; 
  $logger->debug("Starting '".threads->tid()."' as the execution path.");
  
  $ls->receive;
  $ls->respond;
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

ls.pl - A 'Lookup Service' that allows services in the framework to register existance
and capability as well as query for similar information.

=head1 DESCRIPTION

This script creates an an LS that sits in front of an XMLDB backend.  Services have a
specific description of themselves they they wish to register, along with a listing of
what data they can take care of.  The LS will accept this information, and answer with 
it when queried with XQuery/XPath expressions.

=head1 SYNOPSIS

./ls.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute the functions of the
LS.


=head2 lookupService

This function, meant to be used in the context of a thread, will listen on an external
port (specified in the conf file) and serve requests for data from outside entities.

=head2 lookupServiceQuery

This performs the semi-automic operations of the LS.  

=head2 registerLS

This function, meant to be used in the context of a thread, will continously register
and update its information with the LS specified in the conf file.  

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
perfSONAR_PS::MP::SNMP
perfSONAR_PS::MA::SNMP

=head1 AUTHOR

Jason Zurawski <zurawski@internet2.edu>

=head1 VERSION

$Id:$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

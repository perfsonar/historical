#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
use SimpleConfig;
     
use perfSONAR_PS::Common;
 
use perfSONAR_PS::MA::PingER;
use perfSONAR_PS::XML::Namespace;
use perfSONAR_PS::SimpleConfig;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("PingER");

my $DEBUGFLAG = undef;
my $HELP = '';
my $status = GetOptions ('verbose|v' => \$DEBUGFLAG,
                         'help|h|?' => \$HELP,
			  );

if(!$status or $HELP) {
  print "$0: starts the pinger MP and MA.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}

my $ns =  perfSONAR_PS::XML::Namespace->new();
my %local_ns = ();
foreach my $ns_key (qw/nmwg  nmwgt pinger  nmtl3 select/) {
 $local_ns{$ns_key} = $ns->getNsByKey($ns_key);
} 
my %CONF_PROMPTS = ( "METADATA_DB_TYPE" => "type of the internal metaData DB ( file| xmldb  ) ", 
                          "METADATA_DB_NAME" => " name of the internal   metaData  DB ", 
			  'PORT' => ' MA server port ',
                          'RRDTOOL' => ' RRD tool executable',
                          'DB_USER' => '  username to connect to the data SQL DB ',
                          'DB_PASS' =>  ' password to connect to the data SQL DB ',
			  'DB_NAME' => ' name of the data SQL DB ',
                          'DB_DRIVER' =>  '  perl driver name of the  data SQL DB ',
			  );

		# Read in configuration information
 
#
#   pinger configuration part is here
# 
my $pingerMA_conf = perfSONAR_PS::SimpleConfig->new( -FILE => 'pingerMA.conf', -PROMPTS => \%CONF_PROMPTS, -DIALOG => '1');
my $config_hash = $pingerMA_conf->parse(); 
$pingerMA_conf->store;

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

my $maThread = threads->create(\&measurementArchive );

if(!defined $maThread) {
  $logger->fatal("Thread creation has failed...exiting.");
  exit(1);
}

$maThread->join();


 


sub measurementArchive {
   
  $logger->debug("Starting '".threads->tid()."' as the MA.");

  my $ma =  perfSONAR_PS::MA::PingER->new(     $pingerMA_conf->getNormalizedData,  \%local_ns);
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

pingerMP.pl - An Pinger based MA (MeasurementArchive).

=head1 DESCRIPTION

This script creates an MA for an Pinger based collector. 

=head1 SYNOPSIS

./pingerMP.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute 
MA listening and delivery. 

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
perfSONAR_PS::MA::Pinger

=head1 AUTHOR

Jason Zurawski <zurawski@internet2.edu>
Maxim Grigoriev <maxim@fnal.gov>

=head1 VERSION

$Id: pingerMA.pl 228 2007-06-13 12:31:48Z zurawski $

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

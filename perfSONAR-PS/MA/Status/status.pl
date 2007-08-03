#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use threads;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);

use perfSONAR_PS::Common;
use perfSONAR_PS::MA::Status;
use perfSONAR_PS::MP::Status;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';
my $CONFIG_FILE  = '';
my $LINK_FILE = '';

my $status = GetOptions (
		'links=s' => \$LINK_FILE,
		'config=s' => \$CONFIG_FILE,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the snmp MP and MA.\n";
	print "\t$0 [--config /path/to/config --verbose --help]\n";
	exit(1);
}

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
		select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtopo => "http://ogf.org/schema/network/topology/base/20070707/",
	 );

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
	$CONFIG_FILE = "./status.conf";
}

# Read in configuration information
my %conf = ();
readConfiguration($CONFIG_FILE, \%conf);

if ($LINK_FILE ne "") {
	$conf{"LINK_FILE"} = $LINK_FILE;
	$conf{"LINK_FILE_TYPE"} = "file";
}

# set logging level
if($DEBUGFLAG) {
	$logger->level($DEBUG);    
} else {
	$logger->level($INFO); 
}

if(!$DEBUGFLAG) {
# flush the buffer
	$| = 1;
# start the daemon
	&daemonize;
}

$logger->debug("Starting '".threads->tid()."'");

my $ma = new perfSONAR_PS::MA::Status(\%conf, \%ns);
if ($ma->init != 0) {
	$logger->error("Couldn't initialize Status MA");
	exit(-1);
}

my $mp = new perfSONAR_PS::MP::Status(\%conf, \%ns, "", "");
if ($mp->init != 0) {
	$logger->error("Couldn't initialize Status monitor");
	exit(-1);
}

my $ma_pid = fork();
if ($ma_pid == 0) {
	measurementArchive();
	exit(0);
}

my $mp_pid = fork();
if ($mp_pid == 0) {
	measurementPoint();
	exit(0);
}

waitpid($mp_pid, 0);
waitpid($ma_pid, 0);

sub measurementArchive {
	$logger->debug("Starting '".$$."' as the MA.");

	while(1) {
		my $pid = fork();
		if ($pid == 0) {
			measurementArchiveQuery($ma);
			exit(0);
		} elsif ($pid < 0) {
			$logger->error("Error spawning child");
		} else {
			waitpid($pid, 0);
		}
	}

	return;
}

sub measurementArchiveQuery {
	my($ma) = @_; 
	$logger->debug("Starting '".$$."' as the execution path.");

	$ma->receive;
	$ma->respond;
	return;
}

sub measurementPoint {
	$logger->debug("Starting '".$$."' as the MP.");

	my $i = 0;
	while(1) {

		$logger->debug("Collection Measurements: Iteration $i");

		$mp->collectMeasurements($i);

		sleep($conf{"MP_SAMPLE_RATE"});
		$i++;
	}
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

status.pl - A Link Status MP (Measurement Point) and MA (Measurement Archive).

=head1 DESCRIPTION

This script creates an MP/MA for a link status collector.

=head1 SYNOPSIS

./statusMA.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script to execute the 3 major tasks of
LS registration, MP collection, and MA listening and delivery.

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
perfSONAR_PS::MA::Status

=head1 AUTHOR

Aaron Brown <aaron@internet2.edu>, Jason Zurawski <zurawski@internet2.edu>

=head1 VERSION

$Id$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

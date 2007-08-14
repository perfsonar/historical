#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
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

$logger->debug("Starting '".$$."'");

my ($enable_ma, $enable_mp);
my ($ma, $ma_pid, $mp, $mp_pid);

if (!defined $conf{DISABLE_MA} or $conf{DISABLE_MA} == 0) {
	$enable_ma = 1;
} else {
	$enable_ma = 0;
}

if (!defined $conf{DISABLE_COLLECTOR} or $conf{DISABLE_COLLECTOR} == 0) {
	$enable_mp = 1;
} else {
	$enable_mp = 0;
}

if ((!defined $conf{SAMPLE_RATE} or $conf{SAMPLE_RATE} == 0) and $enable_mp) {
	$logger->warn("Sample rate is unset. Disabling status collector");
	$enable_mp = 0;
}

if ($enable_ma) {
	$ma = new perfSONAR_PS::MA::Status(\%conf, \%ns);
	if ($ma->init != 0) {
		$logger->error("Couldn't initialize Status MA");
		exit(-1);
	}
}

if ($enable_mp) {
	$mp = new perfSONAR_PS::MP::Status(\%conf, \%ns, "", "");
	if ($mp->init != 0) {
		$logger->error("Couldn't initialize Status monitor");
		exit(-1);
	}
}

if ($enable_ma) {
	$ma_pid = fork();
	if ($ma_pid == 0) {
		measurementArchive();
		exit(0);
	}
}

if ($enable_mp) {
	$mp_pid = fork();
	if ($mp_pid == 0) {
		measurementPoint();
		exit(0);
	}
}

waitpid($ma_pid, 0) if ($enable_ma);
waitpid($mp_pid, 0) if ($enable_mp);

sub measurementArchive {
	$logger->debug("Starting '".$$."' as the MA.");

	while(1) {
		my $pid = fork();
		if ($pid == 0) {
			$ma->receive;
			$ma->respond;
			exit(0);
		} elsif ($pid < 0) {
			$logger->error("Error spawning child");
		} else {
			waitpid($pid, 0);
		}
	}
}

sub measurementPoint {
	$logger->debug("Starting '".$$."' as the MP.");

	my $i = 0;
	while(1) {
		my $do_update = 1;

		$do_update = 0 if ($i == 0);

		$mp->collectMeasurements($do_update);

		sleep($conf{"SAMPLE_RATE"});
		$i++;
	}
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

The following functions are used within this script to execute the 2 major tasks of
MP collection, and MA listening and delivery.

=head2 measurementPoint

This function, meant to be used in the context of a thread or process, will
continuously collect measurements using the Status MP.

=head2 measurementArchive

This function, meant to be used in the context of a thread or process, will
listen on an external port (specified in the conf file) and pass on requests for
data from outside entities to the MA.

=head2 registerLS

This function, meant to be used in the context of a thread or process, will
register the Status service with the LS specified in the configuration and
periodically refresh it.

=head2 daemonize

Sends the program to the background by eliminating ties to the calling terminal.  

=head1 REQUIRES

Getopt::Long;
Time::HiRes qw( gettimeofday );
POSIX qw( setsid )
Log::Log4perl
perfSONAR_PS::Common
perfSONAR_PS::MA::Status
perfSONAR_PS::MP::Status

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

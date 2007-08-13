#!/usr/bin/perl -w -I ../../lib

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::MA::Topology;
use perfSONAR_PS::MA::Topology::Topology;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';
my $status = GetOptions ('verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the topology MA.\n";
	print "\t$0 [--verbose --help]\n";
	exit(1);
}

# Read in configuration information
my %conf = ();
readConfiguration("./topologyMA.conf", \%conf);

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

my %ns = getTopologyNamespaces();
$ns{"nmwg"} = "http://ggf.org/ns/nmwg/base/2.0/";

$logger->debug("Starting '".$$."'");
my $ma = new perfSONAR_PS::MA::Topology(\%conf, \%ns);
if ($ma->init != 0) {
	$logger->error("Couldn't initialize Topology MA");
	exit(-1);
}

my $ma_pid = fork();
if ($ma_pid == 0) {
	measurementArchive();
	exit(0);
}

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
}

sub measurementArchiveQuery {
	my($ma) = @_; 
	$logger->debug("Starting '".$$."' as the execution path.");

	$ma->receive;
	$ma->respond;
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

topologyMA.pl - An MA (MeasurementArchive) to publish topology information.

=head1 DESCRIPTION

This script creates an MA for a Topology service.

=head1 SYNOPSIS

./topologyMA.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script.

=head2 measurementArchive

This function, meant to be used in the context of a thread or process, will
listen on an external port (specified in the conf file) and serve requests for
data from outside entities.  The data and metadata are stored in various
database structures.

=head2 measurementArchiveQuery

This performs the semi-automic operations of the MA.  

=head2 daemonize

Sends the program to the background by eliminating ties to the calling terminal.  

=head1 REQUIRES

Getopt::Long;
Time::HiRes qw( gettimeofday );
POSIX qw( setsid )
Log::Log4perl
perfSONAR_PS::Common
perfSONAR_PS::Transport
perfSONAR_PS::MA::Topology

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

#!/usr/bin/perl -w -I lib

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
use File::Basename;
use POSIX ":sys_wait_h";
use Cwd;

# we need a fully-qualified directory name in case we daemonize so that we can
# still access scripts or other files specified in configuration files in a
# relative manner. Also, we need to know the location in reference to the
# binary so that users can launch the daemon from wherever but specify scripts
# and whatnot relative to the binary.

my $libdir;
my $dirname = dirname($0);

if (!($dirname =~ /^\//)) {
	$dirname = getcwd . "/" . $dirname;
}

# we need to figure out what the library is at compile time so that "use lib"
# doesn't fail. To do this, we enclose the calculation of it in a BEGIN block.
BEGIN {
	$libdir = dirname($0)."/../../lib";
}

use lib "$libdir";

use perfSONAR_PS::Common;
use perfSONAR_PS::MA::Skeleton;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

$0 = "skeleton.pl  ($$)";

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG = '';
my $READ_ONLY = '';
my $HELP = '';
my $CONFIG_FILE  = '';

my $status = GetOptions (
		'read-only' => \$READ_ONLY,
		'config=s' => \$CONFIG_FILE,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the skeleton MA.\n";
	print "\t$0 [--config /path/to/config --read-only --verbose --help]\n";
	exit(1);
}

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
	$CONFIG_FILE = "./skeleton.conf";
}

# Read in configuration information
my %conf = ();

my $default_ma_conf = &perfSONAR_PS::MA::Skeleton::getDefaultConfig();
if (defined $default_ma_conf) {
	foreach my $key (keys %{ $default_ma_conf }) {
		$conf{$key} = $default_ma_conf->{$key};
	}
}

if (readConfiguration($CONFIG_FILE, \%conf) != 0) {
	$logger->error("Couldn't read in specified configuration file: $CONFIG_FILE");
	exit(-1);
}

# XXX override the users configuration if they specify differently on the
# command-line. An example would be "read-only" if the MA could be set
# read-only.
if (defined $READ_ONLY and $READ_ONLY ne "") {
	$conf{"READ_ONLY"} = 1;
}

foreach my $key (keys %conf) {
	$logger->debug("Config: $key = $conf{$key}");
}

my %ns;

my $default_ma_ns = &perfSONAR_PS::MA::Skeleton::getDefaultNamespaces();
foreach my $prefix (keys %{ $default_ma_ns }) {
	$ns{$prefix} = $default_ma_ns->{$prefix};
}

# XXX You could add any prefixes not included in the default set of namespaces
# $ns{"nmtopo4"} = "http://ggf.org/ns/topology/base/4.0/";

my ($enable_ls);

if (!defined $conf{ENABLE_REGISTRATION} or $conf{ENABLE_REGISTRATION} == 0) {
	$enable_ls = 0;
} else {
	$enable_ls = 1;
}

if ($enable_ls) {
	if (!defined $conf{"LS_INSTANCE"} or $conf{"LS_INSTANCE"} eq "") {
		my $msg = "You specified to specify a LS_INSTANCE so that we know which LS to register with.";
		$logger->error($msg);
		exit -1;
	}

	if (!defined $conf{"SERVICE_ACCESSPOINT"} or $conf{"SERVICE_ACCESSPOINT"} eq "") {
		my $msg = "You specified to specify a SERVICE_ACCESSPOINT so that people consulting the LS know how to get to this service.";
		$logger->error($msg);
		exit -1;
	}

	# configuration is done in minutes, but the LS registration
	# messages need this to be in seconds so we have to convert.
	$conf{"LS_REGISTRATION_INTERVAL"} *= 60;
}

# set logging level
if($DEBUGFLAG) {
	$logger->level($DEBUG);    
} else {
	$logger->level($INFO); 
}

$logger->debug("Starting '".$$."'");

my $ma = new perfSONAR_PS::MA::Skeleton(\%conf, \%ns, $dirname);
if ($ma->init != 0) {
	$logger->error("Couldn't initialize Skeleton MA");
	exit(-1);
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
if(!$DEBUGFLAG) {
	# flush the buffer
	$| = 1;
	&daemonize;
}

my $ma_pid = fork();
if ($ma_pid == 0) {
	measurementArchive();
	exit(0);
}

$child_pids{$ma_pid} = "";

my $ls_pid;
if ($enable_ls) {
	# launch the LS process and add its pid to the list of children pids
	# clear out the %child_pids on the child since it doesn't have any children
	$ls_pid = fork();
	if ($ls_pid == 0) {
		%child_pids = ();
		registerLS();
		exit(0);
	} elsif ($ls_pid < 0) {
		$logger->error("Couldn't spawn LS");
		killChildren();
		exit(-1);
	}

	$child_pids{$ls_pid} = "";
}

foreach my $pid (keys %child_pids) {
	waitpid($pid, 0);
}

sub measurementArchive {
	my $outstanding_children = 0;

	%child_pids = ();

	$logger->debug("Starting '".$$."' as the MA.");

	while(1) {
		if ($conf{"MAX_WORKER_PROCESSES"} > 0) {
			while ($outstanding_children >= $conf{"MAX_WORKER_PROCESSES"}) {
				$logger->debug("Waiting for a slot to open");
				my $kid = waitpid(-1, 0);
				if ($kid > 0) {
					delete $child_pids{$kid};
					$outstanding_children--;
				}
			}
		}

		my ($n, $request, $error);

		$n = $ma->receive(\$request, \$error);

		if (defined $error and $error ne "") {
			$logger->error("Error in receive call: $error");
		}

		if ($n == 0) {
			$logger->debug("Received 'shadow' request from below; no action required.");
			$request->finish();
		} elsif (defined $request) {
			my $pid = fork();
			if ($pid == 0) {
				%child_pids = ();
				$ma->handleRequest($request);
				$request->finish();
				exit(0);
			} elsif ($pid < 0) {
				$logger->error("Error spawning child");
			} else {
				$child_pids{$pid} = "";
				$outstanding_children++;
			}
		}

		$logger->debug("Reaping children");

		while((my $kid = waitpid(-1, WNOHANG)) > 0) {
			delete $child_pids{$kid};
			$outstanding_children--;
		}
	}  
}

sub registerLS {
	%child_pids = ();

	$logger->debug("Starting '".$$."' for LS registration");

	while(1) {
		$ma->registerLS;
		sleep($conf{"LS_REGISTRATION_INTERVAL"});
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

sub killChildren {
	foreach my $pid (keys %child_pids) {
		kill("SIGINT", $pid);
	}
}

sub signalHandler {
	killChildren();
	exit(0);
}

=head1 NAME

skeleton.pl - An basic MA (Measurement Archive) framework

=head1 DESCRIPTION

This script shows how a script for a given service should look. 

=head1 SYNOPSIS

./skeleton.pl [--verbose | --help]

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

=head2 killChildren

Kills all the children for this process off

=head2 signalHandler

Kills all the children for the process and then exits

=head1 REQUIRES

Getopt::Long;
Time::HiRes qw( gettimeofday );
POSIX qw( setsid )
Log::Log4perl
perfSONAR_PS::Common
perfSONAR_PS::Transport
perfSONAR_PS::MA::Skeleton

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

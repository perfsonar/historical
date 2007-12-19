#!/usr/local/bin/perl -w -I ../../../lib/

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
use File::Basename;
use POSIX ":sys_wait_h";
use Cwd;
use Module::Load;

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

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

$0 = "status.pl ($$)";

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG = '';
my $READ_ONLY = '';
my $HELP = '';
my $CONFIG_FILE  = '';
my $LINK_FILE = '';

my $status = GetOptions (
		'read-only' => \$READ_ONLY,
		'links=s' => \$LINK_FILE,
		'config=s' => \$CONFIG_FILE,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the Link Status MA and collector.\n";
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

my ($enable_ma, $enable_mp, $enable_ls);

if (!defined $conf{ENABLE_MA} or $conf{ENABLE_MA} == 0) {
	$enable_ma = 0;
} else {
	$enable_ma = 1;
}

if (!defined $conf{ENABLE_COLLECTOR} or $conf{ENABLE_COLLECTOR} == 0) {
	$enable_mp = 0;
} else {
	$enable_mp = 1;
}

if (!defined $conf{ENABLE_REGISTRATION} or $conf{ENABLE_REGISTRATION} == 0) {
	$enable_ls = 0;
} else {
	$enable_ls = 1;
}

if ($enable_ls and !$enable_ma) {
	$logger->warn("Registration enabled, but MA disabled. Disabling registration");
	$enable_ls = 0;
}

if (defined $READ_ONLY and $READ_ONLY ne "") {
	$conf{"READ_ONLY"} = 1;
}

if (!defined $conf{"PORT"} or $conf{"PORT"} == 0) {
	$conf{"PORT"} = 4801;
}

if (!defined $conf{"ENDPOINT"} or $conf{"ENDPOINT"} eq "") {
	$conf{"ENDPOINT"} = "/perfSONAR_PS/services/status";
}

if (!defined $conf{"MAX_WORKER_PROCESSES"} or $conf{"MAX_WORKER_PROCESSES"} eq "") {
	$conf{"MAX_WORKER_PROCESSES"} = 0; # Unlimited children
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

	# fill in sane defaults if the user does not

	if (!defined $conf{"LS_REGISTRATION_INTERVAL"} or $conf{"LS_REGISTRATION_INTERVAL"} eq "") {
		$conf{"LS_REGISTRATION_INTERVAL"} = 600; # 10 minutes
	} else {
		$conf{"LS_REGISTRATION_INTERVAL"} *= 60; # convert it to seconds for the LS
	}
	if (!defined $conf{SERVICE_TYPE} or $conf{SERVICE_TYPE}) {
		$conf{SERVICE_TYPE} = "MA";
	}

	if (!defined $conf{SERVICE_DESCRIPTION} or $conf{SERVICE_DESCRIPTION}) {
		$conf{SERVICE_DESCRIPTION} = "Link Status Measurement Archive";
	}
}

if ((!defined $conf{SAMPLE_RATE} or $conf{SAMPLE_RATE} == 0) and $enable_mp) {
	$logger->warn("Sample rate is unset. Disabling status collector");
	$enable_mp = 0;
}

if ($LINK_FILE ne "") {
	$conf{"LINK_FILE"} = $LINK_FILE;
	$conf{"LINK_FILE_TYPE"} = "file";
} elsif (!defined $conf{"LINK_FILE"} or $conf{"LINK_FILE"} eq "") {
	$conf{"LINK_FILE"} = "links.conf";
	$conf{"LINK_FILE"} = "file";
}

# set logging level
if ($DEBUGFLAG) {
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

my ($ma, $ma_pid, $mp, $mp_pid, $ls_pid);

if ($enable_ma) {
	load perfSONAR_PS::MA::Status;

	$ma = new perfSONAR_PS::MA::Status(\%conf, \%ns, $dirname);
	if ($ma->init != 0) {
		$logger->error("Couldn't initialize Status MA");
		exit(-1);
	}
}

if ($enable_mp) {
	load perfSONAR_PS::MP::Status;

	$mp = new perfSONAR_PS::MP::Status(\%conf, \%ns, "", $dirname);
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
	} elsif ($ma_pid < 0) {
		$logger->error("Couldn't spawn MA process");
		killChildren();
		exit(-1);
	}

	$child_pids{$ma_pid} = "";
}

if ($enable_mp) {
	$mp_pid = fork();
	if ($mp_pid == 0) {
		measurementPoint();
		exit(0);
	} elsif ($mp_pid < 0) {
		$logger->error("Couldn't spawn Collector process");
		killChildren();
		exit(-1);
	}

	$child_pids{$mp_pid} = "";
}

if ($enable_ls) {
	$ls_pid = fork();
	if ($ls_pid == 0) {
		registerLS();
		exit(0);
	} elsif ($ls_pid < 0) {
		$logger->error("Couldn't spawn MA process");
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

		my $request = $ma->receive;
		if (defined $request) {
			my $pid = fork();
			if ($pid == 0) {
				%child_pids = ();
				$ma->handleRequest($request);
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

sub measurementPoint {
	%child_pids = ();

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

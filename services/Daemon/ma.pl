#!/usr/bin/perl -w -I lib

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Log::Log4perl qw(get_logger :levels);
use File::Basename;
use Fcntl qw(:DEFAULT :flock);
use POSIX ":sys_wait_h";
use Cwd;
use Config::General;
use Module::Load;
use Data::Dumper;


sub psService($$$);
sub registerLS($);
sub daemonize();
sub managePID($$);
sub killChildren();
sub signalHandler();
sub handleRequest($$$);


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
use perfSONAR_PS::SOAP_Daemon;
use perfSONAR_PS::Messages;
use perfSONAR_PS::RequestHandler;
use perfSONAR_PS::XML::Document_string;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

$0 = "ma.pl  ($$)";

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG = '';
my $READ_ONLY = '';
my $HELP = '';
my $CONFIG_FILE  = '';
my $PIDDIR = '';
my $PIDFILE = '';

my $status = GetOptions (
		'config=s' => \$CONFIG_FILE,
		'piddir=s' => \$PIDDIR,
		'pidfile=s' => \$PIDFILE,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the MA daemon.\n";
	print "\t$0 [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid]\n";
	exit(1);
}

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
	$CONFIG_FILE = "./ma.conf";
}

# Read in configuration information
my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

if (!defined $conf{"max_worker_lifetime"} or $conf{"max_worker_lifetime"} eq "") {
	$logger->warn("Setting maximum worker lifetime at 60 seconds");
	$conf{"max_worker_lifetime"} = 60;
}

if (!defined $conf{"max_worker_processes"} or $conf{"max_worker_processes"} eq "") {
	$logger->warn("Setting maximum worker processes at 32");
	$conf{"max_worker_processes"} = 32;
}

if (!defined $conf{"ls_registration_interval"} or $conf{"ls_registration_interval"} eq "") {
	$logger->warn("Setting LS registration interval at 60 minutes");
	$conf{"ls_registration_interval"} = 60;
}

# turn the interval from minutes to seconds
$conf{"ls_registration_interval"} *= 60;

if (!defined $conf{"disable_echo"} or $conf{"disable_echo"} eq "") {
	$logger->warn("Enabling echo service for each endpoint unless specified otherwise");
	$conf{"disable_echo"} = 0;
}


if (!defined $PIDDIR or $PIDDIR eq "") {
	if (defined $conf{"pid_dir"} and $conf{"pid_dir"} ne "") {
		$PIDDIR = $conf{"pid_dir"};
	} else {
		$PIDDIR = "/var/run";
	}
}

if (!defined $PIDFILE or $PIDFILE eq "") {
	if (defined $conf{"pid_file"} and $conf{"pid_file"} ne "") {
		$PIDFILE = $conf{"pid_file"};
	} else {
		$PIDFILE = "ps.pid";
	}
}

# set logging level
if($DEBUGFLAG) {
	$logger->level($DEBUG);
} else {
	$logger->level($INFO);
}

managePID($PIDDIR, $PIDFILE);

$logger->debug("Starting '".$$."'");

my @ls_services;

my %loaded_modules = ();
my $echo_module = "perfSONAR_PS::MA::Echo";

my %handlers = ();
my %listeners = ();
my %modules_loaded = ();
my %port_configs = ();
my %service_configs = ();

foreach my $port (keys %{ $conf{"port"} }) {
	my %port_conf = %{ mergeConfig(\%conf, $conf{"port"}->{$port}) };

	$service_configs{$port} = \%port_conf;

        if (!defined $conf{"port"}->{$port}->{"endpoint"}) {
                $logger->warn("No endpoints specified for port $port");
                next;
        }

        my $listener = new perfSONAR_PS::SOAP_Daemon($port);
        if ($listener->startDaemon() != 0) {
                $logger->error("Couldn't start listener on port $port");
                exit(-1);
        }

        $listeners{$port} = $listener;

        $handlers{$port} = ();

	$service_configs{$port}->{"endpoint"} = ();

        foreach my $endpoint (keys %{ $conf{"port"}->{$port}->{"endpoint"} }) {
                my %endpoint_conf = %{ mergeConfig(\%port_conf, $conf{"port"}->{$port}->{"endpoint"}->{$endpoint}) };

		$service_configs{$port}->{"endpoint"}->{$endpoint} = \%endpoint_conf;

		$logger->debug("Adding endpoint $endpoint to $port");

                $handlers{$port}->{$endpoint} = perfSONAR_PS::RequestHandler->new();

                if (!defined $endpoint_conf{"module"} or $endpoint_conf{"module"} eq "") {
                        $logger->error("No module specified for $port:$endpoint");
                        exit(-1);
                }

                if (!defined $modules_loaded{$endpoint_conf{"module"}}) {
                        load $endpoint_conf{"module"};
                        $modules_loaded{$endpoint_conf{"module"}} = 1;
                }

                my $service = $endpoint_conf{"module"}->new(\%endpoint_conf, $port, $endpoint);
                if ($service->init($handlers{$port}->{$endpoint}) != 0) {
                        $logger->error("Failed to initialize module ".$endpoint_conf{"module"}." on $port:$endpoint");
                        exit(-1);
                }

		if ($service->needLS()) {
			my %ls_child_args = ();
			$ls_child_args{"service"} = $service;
			$ls_child_args{"conf"} = \%endpoint_conf;
			push @ls_services, \%ls_child_args;
		}

                # the echo module is loaded by default unless otherwise specified
                if ((!defined $endpoint_conf{"disable_echo"} or $endpoint_conf{"disable_echo"} == 0) and
			(!defined $conf{"disable_echo"} or $conf{"disable_echo"} == 0)) {
                        if (!defined $modules_loaded{$echo_module}) {
                                load $echo_module;
                                $modules_loaded{$echo_module} = 1;
                        }

                        my $echo = $echo_module->new(\%endpoint_conf, $port, $endpoint);
                        if ($echo->init($handlers{$port}->{$endpoint}) != 0) {
                                $logger->error("Failed to initialize echo module on $port:$endpoint");
                                exit(-1);
                        }
                }
        }
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
if(!$DEBUGFLAG) {
	# flush the buffer
	$| = 1;
#	&daemonize;
}

foreach my $port (keys %listeners) {
	my $pid = fork();
	if ($pid == 0) {
		psService($listeners{$port}, $handlers{$port}, $service_configs{$port});
		exit(0);
	} elsif ($pid < 0) {
		$logger->error("Couldn't spawn listener child");
		killChildren();
		exit(-1);
	} else {
		$child_pids{$pid} = "";
	}
}

foreach my $ls_args (@ls_services) {
	my $ls_pid = fork();
	if ($ls_pid == 0) {
		registerLS($ls_args);
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

sub psService($$$) {
	my ($listener, $handlers, $service_config) = @_;
	my $outstanding_children = 0;
	my $max_worker_processes;

	%child_pids = ();

	$logger->debug("Starting '".$$."' as the MA.");

	$max_worker_processes = $service_config->{"max_worker_processes"};

	while(1) {
		if ($max_worker_processes > 0) {
			while ($outstanding_children >= $max_worker_processes) {
				$logger->debug("Waiting for a slot to open");
				my $kid = waitpid(-1, 0);
				if ($kid > 0) {
					delete $child_pids{$kid};
					$outstanding_children--;
				}
			}
		}

		my ($res, $request, $error);

		$res = $listener->receive(\$request, \$error);

		if ($res ne "") {
			$logger->error("Receive failed: $error");
			if (defined $request) {
				my $ret_message = new perfSONAR_PS::XML::Document_string();
				getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", $res, $error, undef, 1);
				$request->setResponse($ret_message->getValue());
				$request->finish();
			}
		} elsif (defined $request) {
			if (!defined $handlers->{$request->getEndpoint()}) {
				my $ret_message = new perfSONAR_PS::XML::Document_string();
				my $msg = "Received message with has invalid endpoint: ".$request->getEndpoint();
				getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg, undef, 1);
				$request->setResponse($ret_message->getValue());
				$request->finish();
			} else {
				my $pid = fork();
				if ($pid == 0) {
					%child_pids = ();
					handleRequest($handlers->{$request->getEndpoint()}, $request, $service_config->{"endpoint"}->{$request->getEndpoint()});
					$request->finish();
					exit(0);
				} elsif ($pid < 0) {
					$logger->error("Error spawning child");
				} else {
					$child_pids{$pid} = "";
					$outstanding_children++;
				}
			}
		}

		$logger->debug("Reaping children");

		while((my $kid = waitpid(-1, WNOHANG)) > 0) {
			delete $child_pids{$kid};
			$outstanding_children--;
		}
	}
}

sub registerLS($) {
	my ($args) = @_;

	%child_pids = ();

	my $service = $args->{"service"};
	my $default_interval = $args->{"conf"}->{"ls_registration_interval"};

	$logger->debug("Starting '".$$."' for LS registration");

	while(1) {
		my $sleep_time;

		$service->registerLS(\$sleep_time);

		if (!defined $sleep_time or $sleep_time eq "") {
			$sleep_time = $default_interval;
		}

		$logger->debug("Sleeping for $sleep_time");

		sleep($sleep_time);
	}
}

sub handleRequest($$$) {
	my ($handler, $request, $endpoint_conf) = @_;

	# This function is a wrapper around the handler's handleRequest
	# function.  The purpose of the function is to handle the case where a
	# crash occurs while handling the request or the handling of the
	# request runs for too long.

	$logger->debug("Handle Request: ".Dumper($endpoint_conf));

	my $max_worker_lifetime = $endpoint_conf->{"max_worker_lifetime"};

	eval {
 		local $SIG{ALRM} = sub{ die "Request lasted too long\n" };
		alarm($max_worker_lifetime) if ($max_worker_lifetime > 0);
		$handler->handleRequest($request, $endpoint_conf);
 	};

	# disable the alarm after the eval is done
	alarm(0);

	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		my $ret_message = new perfSONAR_PS::XML::Document_string();
		getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred", undef, 1);
		$request->setResponse($ret_message->getValue());
	}
}

sub daemonize() {
	chdir '/' or die "Can't chdir to /: $!";
	open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
	open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
	open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
	defined(my $pid = fork) or die "Can't fork: $!";
	exit if $pid;
	setsid or die "Can't start a new session: $!";
	umask 0;
}

sub managePID($$) {
	my($piddir, $pidfile) = @_;
	die "Can't write pidfile: $pidfile\n" unless -w $piddir;
	$pidfile = $piddir ."/".$pidfile;
	sysopen(PIDFILE, $pidfile, O_RDWR | O_CREAT);
	flock(PIDFILE, LOCK_EX);
	my $p_id = <PIDFILE>;
	chomp($p_id);
	if($p_id ne "") {
		open(PSVIEW, "ps -p ".$p_id." |");
		my @output = <PSVIEW>;
		close(PSVIEW);
		if(!$?) {
			die "$0 already running: $p_id\n";
		}
		else {
			truncate(PIDFILE, 0);
			seek(PIDFILE, 0, 0);
			print PIDFILE "$$\n";
		}
	}
	else {
		print PIDFILE "$$\n";
	}
	flock(PIDFILE, LOCK_UN);
	close(PIDFILE);
	return;
}

sub killChildren() {
	foreach my $pid (keys %child_pids) {
		kill("SIGINT", $pid);
	}
}

sub signalHandler() {
	killChildren();
	exit(0);
}

=head1 NAME

ma.pl - An basic MA (Measurement Archive) framework

=head1 DESCRIPTION

This script shows how a script for a given service should look.

=head1 SYNOPSIS

./ma.pl [--verbose | --help]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=head1 FUNCTIONS

The following functions are used within this script.

=head2 psService

This function, meant to be used in the context of a thread or process, will
listen on an external port (specified in the conf file) and serve requests for
data from outside entities.  The data and metadata are stored in various
database structures.

=head2 psServiceQuery

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
perfSONAR_PS::MA::Echo

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

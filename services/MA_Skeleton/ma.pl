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
use Config::Simple;
use Module::Load;
use Data::Dumper;


sub measurementArchive($$);
sub registerLS($);
sub daemonize();
sub managePID($$);
sub killChildren();
sub signalHandler();
sub handleRequest($$$);
sub __handleRequest($$$);


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
use perfSONAR_PS::MA::Handler;
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

my $status = GetOptions (
		'config=s' => \$CONFIG_FILE,
		'piddir=s' => \$PIDDIR,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: starts the MA daemon.\n";
	print "\t$0 [--verbose --help --config=config.file --piddir=/path/to/pid/dir]\n";
	exit(1);
}

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
	$CONFIG_FILE = "./ma.conf";
}

# Read in configuration information
my %conf = ();

if (!Config::Simple->import_from($CONFIG_FILE, \%conf)) {
	$logger->error("Couldn't read in specified configuration file: $CONFIG_FILE");
	exit(-1);
}

if (!defined $conf{"default.port"} or $conf{"default.port"} eq "") {
	$conf{"default.port"} = 8080;
}

if (!defined $conf{"default.max_worker_lifetime"} or $conf{"default.max_worker_lifetime"} eq "") {
	$conf{"default.max_worker_lifetime"} = 0;
}

if (!defined $conf{"default.max_worker_processes"} or $conf{"default.max_worker_processes"} eq "") {
	$conf{"default.max_worker_processes"} = 0;
}
if (!defined $conf{"default.ls_registration_interval"} or $conf{"default.ls_registration_interval"} eq "") {
	$conf{"default.ls_registration_interval"} = 60;
}

$conf{"default.ls_registration_interval"} *= 60;

if (!defined $conf{"default.modules"} or $conf{"default.modules"} eq "") {
	$logger->error("No list of modules defined");
	exit(-1);
}

# if there is only a single element, the config thing returns it not as an
# array, but as a single element.
if (!ref($conf{"default.modules"}) or ref($conf{"default.modules"}) ne "ARRAY") {
	my @array = ();
	push @array, $conf{"default.modules"};

	$conf{"default.modules"} = \@array;
}

if (!defined $conf{"default.disable_echo"} or $conf{"default.disable_echo"} eq "") {
	$conf{"default.disable_echo"} = 0;
}

if ($conf{"default.disable_echo"} == 0) {
	push @{ $conf{"default.modules"} }, "perfSONAR_PS::MA::Echo";
}

# get rid of any duplicate modules
my %tmp_modules = ();
my @new_modules = ();

foreach my $module (@{ $conf{"default.modules"} }) {
	if (!defined $tmp_modules{$module}) {
		$tmp_modules{$module} = 1;
		push @new_modules, $module;
	} else {
		$logger->warn("Duplicate module load requested: $module");
	}
}

# make sure the echo module is loaded unless they explicitly disable it for some reason
if ($conf{"default.disable_echo"} == 0 and !defined $tmp_modules{"perfSONAR_PS::MA::Echo"}) {
	push @new_modules, "perfSONAR_PS::MA::Echo";
}

$conf{"default.modules"} = \@new_modules;

if (!defined $PIDDIR or $PIDDIR eq "") {
	if (defined $conf{"default.pid_dir"} and $conf{"default.pid_dir"} ne "") {
		$PIDDIR = $conf{"default.pid_dir"};
	} else {
		$PIDDIR = "/var/run";
	}
}

# set logging level
if($DEBUGFLAG) {
	$logger->level($DEBUG);
} else {
	$logger->level($INFO);
}

managePID($conf{"default.port"}, $PIDDIR);

$logger->debug("Starting '".$$."'");

my $ma_handler = new perfSONAR_PS::MA::Handler();
my @ls_modules;



foreach my $module (@{ $conf{"default.modules"} }) {
	load $module;
	my $ma = $module->new(\%conf);

	if ($ma->init($ma_handler) != 0) {
		$logger->error("Error initializing $module");
		exit(-1);
	}

	if ($ma->needLS()) {
		push @ls_modules, $ma;
	}
}

my $listener = new perfSONAR_PS::SOAP_Daemon($conf{"default.port"});
if ($listener->startDaemon() != 0) {
	$logger->error("Couldn't start MA SOAP listener");
	exit(-1);
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
if(!$DEBUGFLAG) {
	# flush the buffer
	$| = 1;
#	&daemonize;
}

my $ma_pid = fork();
if ($ma_pid == 0) {
	measurementArchive($ma_handler, \%conf);
	exit(0);
}

$child_pids{$ma_pid} = "";

foreach my $ma (@ls_modules) {
	my $ls_pid = fork();
	if ($ls_pid == 0) {
		registerLS($ma);
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

sub measurementArchive($$) {
	my ($ma_handler, $conf) = @_;
	my $outstanding_children = 0;

	%child_pids = ();

	$logger->debug("Starting '".$$."' as the MA.");

	while(1) {
		if (defined $conf{"default.max_worker_processes"} and $conf{"default.max_worker_processes"} > 0) {
			while ($outstanding_children >= $conf{"default.max_worker_processes"}) {
				$logger->debug("Waiting for a slot to open");
				my $kid = waitpid(-1, 0);
				if ($kid > 0) {
					delete $child_pids{$kid};
					$outstanding_children--;
				}
			}
		}

		my ($res, $request, $endpoint, $error);

		$res = $listener->receive(\$request, \$error);

		if ($res ne "") {
			$logger->error("Receive failed: $error");
			if (defined $request) {
				my $doc = new perfSONAR_PS::XML::Document_string();
				getResultCodeMessage($doc, "message.".genuid(), "", "", "response", $res, $error, undef, 1);
				$request->setResponse($doc->getValue());
				$request->finish();
			}
		} elsif (defined $request) {
			if ($ma_handler->isValidEndpoint($request->getEndpoint())) {
				my $pid = fork();
				if ($pid == 0) {
					%child_pids = ();
					handleRequest($ma_handler, $conf, $request);
					$request->finish();
					exit(0);
				} elsif ($pid < 0) {
					$logger->error("Error spawning child");
				} else {
					$child_pids{$pid} = "";
					$outstanding_children++;
				}
			} else {
				my $doc = new perfSONAR_PS::XML::Document_string();
				my $msg = "Received message with has invalid endpoint: ".$request->getEndpoint();
				getResultCodeMessage($doc, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg, undef, 1);
				$request->setResponse($doc->getValue());
				$request->finish();
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
	my ($ma) = @_;

	%child_pids = ();

	$logger->debug("Starting '".$$."' for LS registration");

	while(1) {
		my $sleep_time;

		$ma->registerLS(\$sleep_time);

		if (!defined $sleep_time or $sleep_time eq "") {
			$sleep_time = $conf{"default.ls_registration_interval"};
		}

		sleep($sleep_time);
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
	my($port, $piddir) = @_;
	die "Can't write pidfile to $piddir\n" unless -w $piddir;
	my $pidfile = $piddir."/ma.".$port.".pid";
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

sub handleRequest($$$) {
	my ($ma_handler, $conf, $request) = @_;

	# This function is a wrapper around the __handleRequest function.  The
	# purpose of the function is to handle the case where a crash occurs
	# while handling the request or the handling of the request runs for
	# too long.

	eval {
 		local $SIG{ALRM} = sub{ die "Request lasted too long\n" };
		alarm($conf{"default.max_worker_lifetime"}) if (defined $conf{"default.max_worker_lifetime"} and $conf{"default.max_worker_lifetime"} > 0);
		__handleRequest($ma_handler, $conf, $request);
 	};

	# disable the alarm after the eval is done
	alarm(0);

	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		my $doc = new perfSONAR_PS::XML::Document_string();
		getResultCodeMessage($doc, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred", undef, 1);
		$request->setResponse($doc->getValue());
	}

	$request->finish;
}

sub __handleRequest($$$) {
	my ($ma_handler, $conf, $request) = @_;

	my $error;
	my $localContent = "";

	$request->parse(\$error);

	if (defined $error and $error ne "") {
		my $doc = new perfSONAR_PS::XML::Document_string();
		getResultCodeMessage($doc, "message.".genuid(), "", "", "response", "error.transport.parse_error", "Error parsing request: $error", undef, 1);
		$request->setResponse($doc->getValue());
		return;
	}

	my $message = $request->getRequestDOM()->getDocumentElement();;
	my $messageId = $message->getAttribute("id");
	my $messageType = $message->getAttribute("type");
	my $messageIdReturn = "message.".genuid();
	my $messageTypeReturn = $messageType;

	$messageTypeReturn = $ma_handler->getMessageResponseType($request->getEndpoint(), $messageType);
	if (!defined $messageTypeReturn) {
		$messageTypeReturn = $messageType;
		$messageTypeReturn =~ s/Request/Response/;
		if (!($messageTypeReturn =~ /Response/)) {
			$messageTypeReturn .= "Response";
		}

		$logger->warn("No message response type for $messageType on endpoint ".$request->getEndpoint().". Using $messageTypeReturn as the response type");
	}

	my %message_parameters = ();

	my $msgParams = find($message, "./nmwg:parameters", 1);
	if (defined $msgParams) {
		foreach my $p ($msgParams->getChildrenByLocalName("parameter")) {
			my ($name, $value);

			$name = $p->getAttribute("name");
			$value = extract($p, 0);

			if (!defined $name or $name eq "") {
				next;
			}

			$message_parameters{$name} = $value;
		}
	}

	my $found_pair = 0;

	my $doc = new perfSONAR_PS::XML::Document_string();

	startMessage($doc, $messageIdReturn, $messageId, $messageTypeReturn, "", undef);

	foreach my $d ($message->getChildrenByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "data")) {
		my $found_md = 0;

		foreach my $m ($message->getChildrenByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = findvalue($m, "./nmwg:eventType");

				$found_pair = 1;

				my ($status, $res) = $ma_handler->handleEvent($doc, $request->getEndpoint, $messageType, \%message_parameters, $eventType, $m, $d, $request);

				if (defined $status and $status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");
					my $mdID = "metadata.".genuid();
					getResultCodeMetadata($doc, $mdID, $m->getAttribute("id"), $status);
					getResultCodeData($doc, "data.".genuid(), $mdID, $res, 1);
				}

				$found_md = 1;
			}
		}

		if ($found_md == 0) {
			my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
			my $mdId = "metadata.".genuid();
			my $dId = "data.".genuid();
			$logger->error($msg);
			getResultCodeMetadata($doc, $mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
			getResultCodeData($doc, $dId, $mdId, $msg, 1);
		}
	}

	if ($found_pair == 0) {
		my $mdID = "metadata.".genuid();
		getResultCodeMetadata($doc, $mdID, "", "error.ma.no_metadata_data_pair");
		getResultCodeData($doc, "data.".genuid(), $mdID, "There was no data/metadata pair found", 1);
	}

	endMessage($doc);

	$request->setResponse($doc->getValue());
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

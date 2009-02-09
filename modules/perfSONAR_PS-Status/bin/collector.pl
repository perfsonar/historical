#!/usr/bin/perl -w -I lib

=head1 NAME

perfsonar.pl - An basic Measurement Collection framework

=head1 DESCRIPTION

This script shows how a script for a given service should look.

=head1 SYNOPSIS

./perfsonar-collector.pl [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.
=cut

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use File::Basename;
use Fcntl qw(:DEFAULT :flock);
use POSIX ":sys_wait_h";
use Cwd;
use Config::General;
use Module::Load;
use Data::Dumper;

our $VERSION = 0.09;

sub handleCollector($);
sub managePID($$);
sub killChildren();
sub signalHandler();
sub handleRequest($$$);

my $confdir;

use FindBin qw($Bin);
use lib "$Bin/../lib";
$confdir = "$Bin/../etc";

use perfSONAR_PS::Common;
use perfSONAR_PS::Collectors::Status;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG = '';
my $READ_ONLY = '';
my $HELP = '';
my $CONFIG_FILE  = '';
my $LOGGER_CONF  = '';
my $PIDDIR = '';
my $PIDFILE = '';
my $LOGOUTPUT = '';
my $IGNORE_PID = '';
my $RUNAS_USER = q{};
my $RUNAS_GROUP = q{};

my ($status, $res);

$status = GetOptions (
        'config=s' => \$CONFIG_FILE,
        'logger=s' => \$LOGGER_CONF,
        'output=s' => \$LOGOUTPUT,
        'piddir=s' => \$PIDDIR,
        'pidfile=s' => \$PIDFILE,
        'user=s'    => \$RUNAS_USER,
        'group=s'   => \$RUNAS_GROUP,
        'ignorepid' => \$IGNORE_PID,
        'verbose' => \$DEBUGFLAG,
        'help' => \$HELP);

if( not $status or $HELP) {
    print "$0: starts the collector daemon.\n";
    print "\t$0 [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid --logger=logger/filename.conf --ignorepid]\n";
    exit(1);
}

my $logger;
if (!defined $LOGGER_CONF or $LOGGER_CONF eq "") {
    use Log::Log4perl qw(:easy);

    my $output_level = $INFO;
    if($DEBUGFLAG) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if (defined $LOGOUTPUT and $LOGOUTPUT ne "") {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger("perfSONAR_PS");
} else {
    use Log::Log4perl qw(get_logger :levels);

    my $output_level = $INFO;
    if($DEBUGFLAG) {
        $output_level = $DEBUG;
    }
 
    Log::Log4perl->init($LOGGER_CONF);
    $logger = get_logger("perfSONAR_PS");
    $logger->level($output_level);
}

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
    $CONFIG_FILE = $confdir."/collector.conf";
}

# The configuration directory gets passed to the modules so that relative paths
# defined in their configurations can be resolved.
$confdir = dirname($CONFIG_FILE);
if ( !( $confdir =~ /^\// ) ) {
    $confdir = getcwd . "/" . $confdir;
}

# Read in configuration information
my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

if (!defined $conf{"collection_interval"} or $conf{"collection_interval"} eq "") {
    $logger->warn("Setting default collection interval at 5 minutes");
    $conf{"collection_interval"} = 300;
}

my $pidfile;

if (!defined $IGNORE_PID or $IGNORE_PID eq "") {
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

    $pidfile = lockPIDFile($PIDDIR."/".$PIDFILE);
}

$logger->debug("Starting '".$$."'");

# Check if the daemon should run as a specific user/group and then switch to
# that user/group.
if (not $RUNAS_GROUP) {
    if ($conf{"group"}) {
        $RUNAS_GROUP = $conf{"group"};
    }
}

if (not $RUNAS_USER) {
    if ($conf{"user"}) {
        $RUNAS_USER = $conf{"user"};
    }
}

if ($RUNAS_USER and $RUNAS_GROUP) {
    if (setids(USER => $RUNAS_USER, GROUP => $RUNAS_GROUP) != 0) {
        $logger->error("Couldn't drop priviledges");
        exit(-1);
    }
} elsif ($RUNAS_USER or $RUNAS_GROUP) {
    # they need to specify both the user and group
    $logger->error("You need to specify both the user and group if you specify either");
    exit(-1);
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
if(!$DEBUGFLAG) {
# flush the buffer
    $| = 1;
    &daemonize;
}

$0 = "perfsonar-status-collector.pl ($$)";

if (!defined $IGNORE_PID or $IGNORE_PID eq "") {
    unlockPIDFile($pidfile);
}

my ($status, $res) = perfSONAR_PS::Collectors::Status->create_workers({ conf => \%conf, directory_offset => $confdir });
if ($status != 0) {
    $logger->error("Couldn't allocate status checkers: $res");
    exit(-1);
}

my $measurement_workers = $res;

foreach my $worker (@$measurement_workers) {
	my $pid = fork();
	if ($pid == 0) {
		$worker->run();
		exit(0);
	}

	$child_pids{$pid} = 1;
}

foreach my $pid (keys %child_pids) {
    waitpid($pid, 0);
}

=head2 killChildren
Kills all the children for this process off. It uses global variables
because this function is used by the signal handler to kill off all
child processes.
=cut
sub killChildren() {
    foreach my $pid (keys %child_pids) {
        kill("SIGINT", $pid);
    }
}

=head2 signalHandler
Kills all the children for the process and then exits
=cut
sub signalHandler() {
    killChildren();
    exit(0);
}

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Transport>,

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

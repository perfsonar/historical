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
use English '-no_match_vars';

our $VERSION = 0.09;

sub signalHandler;

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
    print "$PROGRAM_NAME: starts the collector daemon.\n";
    print "\t$PROGRAM_NAME [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid --logger=logger/filename.conf --ignorepid]\n";
    exit(1);
}

my $logger;
if (not $LOGGER_CONF) {
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

unless ($CONFIG_FILE) {
    $CONFIG_FILE = $confdir."/collector.conf";
}

unless ($CONFIG_FILE =~ /^\//) {
    $CONFIG_FILE = getcwd . "/" . $CONFIG_FILE;
}

# The configuration directory gets passed to the modules so that relative paths
# defined in their configurations can be resolved.
$confdir = dirname($CONFIG_FILE);

# Read in configuration information
my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

my $pidfile;

unless ($IGNORE_PID) {
    unless ($PIDDIR) {
        if (defined $conf{"pid_dir"} and $conf{"pid_dir"} ne "") {
            $PIDDIR = $conf{"pid_dir"};
        } else {
            $PIDDIR = "/var/run";
        }
    }

    unless ($PIDFILE) {
        if (defined $conf{"pid_file"} and $conf{"pid_file"} ne "") {
            $PIDFILE = $conf{"pid_file"};
        } else {
            $PIDFILE = "ps_collector.pid";
        }
    }

    $pidfile = lockPIDFile($PIDDIR."/".$PIDFILE);
}

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
        print "Error: Couldn't drop priviledges\n";
        exit(-1);
    }
} elsif ($RUNAS_USER or $RUNAS_GROUP) {
    # they need to specify both the user and group
    print "You need to specify both the user and group if you specify either\n";
    exit(-1);
}

my $worker = perfSONAR_PS::Collectors::Status->new();

($status, $res) = $worker->init({ conf => \%conf, directory_offset => $confdir });
if ($status != 0) {
    $logger->error("Couldn't allocate status collector: $res");
    exit(-1);
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
unless ($DEBUGFLAG) {
# flush the buffer
    $OUTPUT_AUTOFLUSH = 1;
    &daemonize;
}

$PROGRAM_NAME = "perfsonar-status-collector.pl ($PID)";

unless ($IGNORE_PID) {
    unlockPIDFile($pidfile);
}

$worker->run();

=head2 signalHandler
Kills all the children for the process and then exits
=cut
sub signalHandler {
    print "Exiting...\n";
    $worker->quit();
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

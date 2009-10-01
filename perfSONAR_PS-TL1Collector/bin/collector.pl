#!/usr/bin/perl -w -I lib

use warnings;
use strict;

our $VERSION = 3.1;

=head1 NAME

perfsonar.pl - An basic Measurement Collection framework

=head1 DESCRIPTION

This script shows how a script for a given service should look.

=head1 SYNOPSIS

./perfsonar-collector.pl [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid]

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.

=cut

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

sub signalHandler;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

use perfSONAR_PS::Common;
use perfSONAR_PS::Collectors::TL1Collector;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT}  = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG   = q{};
my $READ_ONLY   = q{};
my $HELP        = q{};
my $CONFIG_FILE = q{};
my $LOGGER_CONF = q{};
my $PIDDIR      = q{};
my $PIDFILE     = q{};
my $LOGOUTPUT   = q{};
my $IGNORE_PID  = q{};
my $RUNAS_USER  = q{};
my $RUNAS_GROUP = q{};

my ( $status, $res );

$status = GetOptions(
    'config=s'  => \$CONFIG_FILE,
    'logger=s'  => \$LOGGER_CONF,
    'output=s'  => \$LOGOUTPUT,
    'piddir=s'  => \$PIDDIR,
    'pidfile=s' => \$PIDFILE,
    'user=s'    => \$RUNAS_USER,
    'group=s'   => \$RUNAS_GROUP,
    'ignorepid' => \$IGNORE_PID,
    'verbose'   => \$DEBUGFLAG,
    'help'      => \$HELP
);

if ( not $status or $HELP ) {
    print "$PROGRAM_NAME: starts the collector daemon.\n";
    print "\t$PROGRAM_NAME [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid --logger=logger/filename.conf --ignorepid]\n";
    exit( 1 );
}

my $logger;
if ( not $LOGGER_CONF ) {
    use Log::Log4perl qw(:easy);

    my $output_level = $INFO;
    $output_level = $DEBUG if $DEBUGFLAG;

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );
    $logger_opts{file} = $LOGOUTPUT if $LOGOUTPUT;

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger( "perfSONAR_PS" );
}
else {
    use Log::Log4perl qw(get_logger :levels);

    Log::Log4perl->init( $LOGGER_CONF );
    $logger = get_logger( "perfSONAR_PS" );
    $logger->level( $DEBUG ) if ($DEBUGFLAG);
}

$CONFIG_FILE = $confdir . "/collector.conf" unless $CONFIG_FILE;
$CONFIG_FILE = getcwd . "/" . $CONFIG_FILE unless $CONFIG_FILE =~ /^\//;

# The configuration directory gets passed to the modules so that relative paths
# defined in their configurations can be resolved.
$confdir = dirname( $CONFIG_FILE );

# Read in configuration information
my $config = new Config::General( $CONFIG_FILE );
my %conf   = $config->getall;

my $pidfile;

unless ( $IGNORE_PID ) {
    unless ( $PIDDIR ) {
        if ( exists $conf{"pid_dir"} and $conf{"pid_dir"} ) {
            $PIDDIR = $conf{"pid_dir"};
        }
        else {
            $PIDDIR = "/var/run";
        }
    }

    unless ( $PIDFILE ) {
        if ( exists $conf{"pid_file"} and $conf{"pid_file"} ) {
            $PIDFILE = $conf{"pid_file"};
        }
        else {
            $PIDFILE = "ps_collector.pid";
        }
    }
    $pidfile = lockPIDFile( $PIDDIR . "/" . $PIDFILE );
}

# Check if the daemon should run as a specific user/group and then switch to
# that user/group.
unless ( $RUNAS_GROUP ) {
    $RUNAS_GROUP = $conf{"group"} if exists $conf{"group"} and $conf{"group"};
}

unless ( $RUNAS_USER ) {
    $RUNAS_USER = $conf{"user"} if exists $conf{"user"} and $conf{"user"};
}

if ( $RUNAS_USER and $RUNAS_GROUP ) {
    if ( setids( USER => $RUNAS_USER, GROUP => $RUNAS_GROUP ) != 0 ) {
        print "Error: Couldn't drop priviledges\n";
        exit( -1 );
    }
}
elsif ( $RUNAS_USER or $RUNAS_GROUP ) {

    # they need to specify both the user and group
    print "You need to specify both the user and group if you specify either\n";
    exit( -1 );
}

my $worker = perfSONAR_PS::Collectors::TL1Collector->new();

$logger->debug("Created worker");

( $status, $res ) = $worker->init( { conf => \%conf } );
if ( $status != 0 ) {
    $logger->error( "Couldn't allocate status collector: $res" );
    exit( -1 );
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
unless ( $DEBUGFLAG ) {

    # flush the buffer
    $OUTPUT_AUTOFLUSH = 1;
    &daemonize;
}

$PROGRAM_NAME = "perfsonar-status-collector.pl ($PID)";

unlockPIDFile( $pidfile ) unless $IGNORE_PID;

$logger->debug("Running worker");
$worker->run();

=head2 signalHandler

Kills all the children for the process and then exits

=cut

sub signalHandler {
    print "Exiting...\n";
    $worker->quit();
    exit( 0 );
}

__END__

=head1 SEE ALSO

L<Getopt::Long>, L<Time::HiRes>, L<POSIX>, L<File::Basename>, L<Fcntl>, L<Cwd>,
L<Config::General>, L<Module::Load>, L<Data::Dumper>, L<English>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Collectors::TL1Collector>,
L<perfSONAR_PS::Utils::Daemon>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: collector.pl 2845 2009-06-25 18:00:28Z aaron $

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

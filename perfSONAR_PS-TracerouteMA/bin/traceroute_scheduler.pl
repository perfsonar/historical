#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids unlockPIDFile/;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Services::MP::TracerouteScheduler;

use Getopt::Long;
use Config::General;
use Log::Log4perl qw/:easy/;

use Fcntl qw(:DEFAULT :flock);
use File::Basename;
use English '-no_match_vars';

# set the process name
$0 = "traceroute_scheduler.pl";

my @child_pids = ();

$SIG{INT}  = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $OWMESH_FILE;
my $LOGOUTPUT;
my $LOGGER_CONF;
my $PIDFILE;
my $DEBUGFLAG;
my $HELP;
my $RUNAS_USER;
my $RUNAS_GROUP;

my ( $status, $res );

$status = GetOptions(
    'owmesh=s'  => \$OWMESH_FILE,
    'output=s'  => \$LOGOUTPUT,
    'logger=s'  => \$LOGGER_CONF,
    'pidfile=s' => \$PIDFILE,
    'verbose'   => \$DEBUGFLAG,
    'user=s'    => \$RUNAS_USER,
    'group=s'   => \$RUNAS_GROUP,
    'help'      => \$HELP
);

if ( not $OWMESH_FILE ) {
    print "Error: no owmesh configuration file specified\n";
    exit( -1 );
}

my %conf = ();

if ( not $PIDFILE ) {
    $PIDFILE = $conf{"pid_file"};
}

if ( not $PIDFILE ) {
    $PIDFILE = "/var/run/traceroute-scheduler.pid";
}

( $status, $res ) = lockPIDFile( $PIDFILE );
if ( $status != 0 ) {
    print "Error: $res\n";
    exit( -1 );
}

my $fileHandle = $res;

if ( $RUNAS_USER and $RUNAS_GROUP ) {
    if ( setids( USER => $RUNAS_USER, GROUP => $RUNAS_GROUP ) != 0 ) {
        print "Error: Couldn't drop privileges\n";
        exit( -1 );
    }
}
elsif ( $RUNAS_USER or $RUNAS_GROUP ) {

    # they need to specify both the user and group
    print "Error: You need to specify both the user and group if you specify either\n";
    exit( -1 );
}

# Now that we've dropped privileges, create the logger. If we do it in reverse
# order, the daemon won't be able to write to the logger.
my $logger;
if ( not defined $LOGGER_CONF or $LOGGER_CONF eq q{} ) {
    use Log::Log4perl qw(:easy);

    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if ( defined $LOGOUTPUT and $LOGOUTPUT ne q{} ) {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger( "perfSONAR_PS" );
}
else {
    use Log::Log4perl qw(get_logger :levels);

    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if ( $LOGOUTPUT ) {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->init( $LOGGER_CONF );
    $logger = get_logger( "perfSONAR_PS" );
    $logger->level( $output_level ) if $output_level;
}

#Check configuration
unless ( -d $OWMESH_FILE ) {           
    my($filename, $dirname) = fileparse( $OWMESH_FILE );
    if ( $filename and lc( $filename ) eq "owmesh.conf" ) {
        $logger->info( "The 'owmesh' value was set to '" . $OWMESH_FILE . "', which is not a directory; converting to '" . $dirname . "'." );
        $OWMESH_FILE = $dirname;
    }
    else {
        $logger->fatal( "Value for 'owmesh' is '" . $OWMESH_FILE . "', please set to the *directory* that contains the owmesh.conf file" );
        return -1;
    }
}    


if ( not $DEBUGFLAG ) {
    ( $status, $res ) = daemonize();
    if ( $status != 0 ) {
        $logger->error( "Couldn't daemonize: " . $res  );
        exit( -1 );
    }
}

unlockPIDFile( $fileHandle );

#BEGIN handler
my $traceroute_scheduler = new perfSONAR_PS::Services::MP::TracerouteScheduler( $OWMESH_FILE );
while(1){
    eval{
        $traceroute_scheduler->run();
    };
    if($@){
        $logger->error($@);
    }
    sleep(30);
}

#END handler
exit( 0 );

sub signalHandler {
    exit( 0 );
}

#Need custom lock function since need to ignore child errors for traceroute libs to work
sub lockPIDFile {
    my ( $pidfile ) = @_;
    return ( -1, "Can't write pidfile: $pidfile" ) unless -w dirname( $pidfile );
    sysopen( PIDFILE, $pidfile, O_RDWR | O_CREAT ) or return ( -1, "Couldn't open file: $pidfile" );
    flock( PIDFILE, LOCK_EX );
    my $p_id = <PIDFILE>;
    chomp( $p_id ) if ( defined $p_id );
    if ( defined $p_id and $p_id ) {
        my $PSVIEW;

        open( $PSVIEW, "-|", "ps -p " . $p_id ) or return ( -1, "Open failed for pid: $p_id" );
        my @output = <$PSVIEW>;
        close( $PSVIEW );
        if ( $#output > 0 ) {
            return ( -1, "Application is already running on pid: $p_id" );
        }
    }

    return ( 0, *PIDFILE );
}

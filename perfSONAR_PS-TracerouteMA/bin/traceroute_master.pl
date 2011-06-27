#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Services::MP::TracerouteSender;

use Getopt::Long;
use Config::General;
use Log::Log4perl qw/:easy/;

# set the process name
$0 = "traceroute_master.pl";

my @child_pids = ();

$SIG{INT}  = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $CONFIG_FILE;
my $LOGOUTPUT;
my $LOGGER_CONF;
my $PIDFILE;
my $DEBUGFLAG;
my $HELP;
my $RUNAS_USER;
my $RUNAS_GROUP;

my ( $status, $res );

$status = GetOptions(
    'config=s'  => \$CONFIG_FILE,
    'output=s'  => \$LOGOUTPUT,
    'logger=s'  => \$LOGGER_CONF,
    'pidfile=s' => \$PIDFILE,
    'verbose'   => \$DEBUGFLAG,
    'user=s'    => \$RUNAS_USER,
    'group=s'   => \$RUNAS_GROUP,
    'help'      => \$HELP
);

if ( not $CONFIG_FILE ) {
    print "Error: no configuration file specified\n";
    exit( -1 );
}

my %conf = Config::General->new( $CONFIG_FILE )->getall();

if ( not $PIDFILE ) {
    $PIDFILE = $conf{"pid_file"};
}

if ( not $PIDFILE ) {
    $PIDFILE = "/var/run/traceroute_master.pid";
}

( $status, $res ) = lockPIDFile( $PIDFILE );
if ( $status != 0 ) {
    print "Error: $res\n";
    exit( -1 );
}

my $fileHandle = $res;

# Check if the daemon should run as a specific user/group and then switch to
# that user/group.
if ( not $RUNAS_GROUP ) {
    if ( $conf{"group"} ) {
        $RUNAS_GROUP = $conf{"group"};
    }
}

if ( not $RUNAS_USER ) {
    if ( $conf{"user"} ) {
        $RUNAS_USER = $conf{"user"};
    }
}

if ( $RUNAS_USER and $RUNAS_GROUP ) {
    if ( setids( USER => $RUNAS_USER, GROUP => $RUNAS_GROUP ) != 0 ) {
        print "Error: Couldn't drop priviledges\n";
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


#BEGIN read configuration
$logger->info( perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.start") );
my @collector_urls = ();
if ( ref $conf{"collector_urls"} eq "ARRAY" ) {
    @collector_urls = @{ $conf{'collector_urls'} };
}elsif ($conf{"collector_urls"}){
    push @collector_urls, $conf{'collector_urls'};
}else{
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "You must specify a list of collector urls with which to register data"
        });
    $logger->error( $log_msg );
    exit(-1);
}

my $data_dir = "";
if ( exists $conf{"data_dir"} && (-d $conf{"data_dir"}) && $conf{"data_dir"} =~ /(.+)/) { 
    $data_dir = $1;
} else {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "You must specify the data_dir property which indicates where to find data to be registered"
        });
    $logger->error( $log_msg );
    exit(-1);
}


if (ref $conf{"register_interval"}) {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "You must specify the register_interval property that indicates how often to register data"
        });
    $logger->error( $log_msg );
    exit(-1);
}

if (ref $conf{"batch_size"}) {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "You must specify the batch_size property that indicates how many test to register in one registration request"
        });
    $logger->error( $log_msg );
    exit(-1);
}

if (ref $conf{"batch_count"}) {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "You must specify the batch_count which specifies the maximum number of batches to register in any given registration interval"
        });
    $logger->error( $log_msg );
    exit(-1);
}

#END read configuration

if ( not $DEBUGFLAG ) {
    ( $status, $res ) = daemonize();
    if ( $status != 0 ) {
        my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end", 
        { status => -1, 
          msg => "Couldn't daemonize: " . $res 
        });
        $logger->error( $log_msg );
        exit( -1 );
    }
}

unlockPIDFile( $fileHandle );

#BEGIN handler
my $traceroute_sender = perfSONAR_PS::Services::MP::TracerouteSender->new(\@collector_urls, $conf{"register_interval"}, $data_dir, $conf{"collector_timeout"});
$logger->info( perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.TracerouteMaster.init.end") );
while(1){
    eval{
        $traceroute_sender->run();
    };
    if($@){
        $logger->error($@);
    }
    sleep($conf{"register_interval"});
}

#END handler
exit( 0 );

sub signalHandler {
    exit( 0 );
}

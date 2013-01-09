#!/usr/bin/perl

use strict;
use warnings;

=head1 NAME

SimpleLSBootStrapServerDaemon.pl - Detrmines lookup service to be used by this host

=head1 DESCRIPTION

This daemon determines lookup service to be used by host.

=cut

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;
use perfSONAR_PS::Utils::NetLogger;
use SimpleLSBootStrap::ServerDaemonHandler;

use Getopt::Long;
use Config::General;
use Log::Log4perl qw/:easy/;

# set the process name
$0 = "SimpleLSBootStrapServerDaemon.pl";

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
    $PIDFILE = "/var/run/SimpleLSBootStrapServerDaemon.pid";
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
    $logger = get_logger( "SimpleLSBootStrap" );
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
    $logger = get_logger( "SimpleLSBootStrap" );
    $logger->level( $output_level ) if $output_level;
}

#BEGIN read configuration
$logger->info( perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrapServerDaemon.init.start") );
if ( not $conf{"hosts_file"} ) {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrapServerDaemon.init.end", 
        { status => -1, 
          msg => "You must specify a hosts file with the hosts_file property"
        });
    $logger->error( $log_msg );
    exit(-1);
}
if ( not $conf{"output_file"} ) {
    my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrapServerDaemon.init.end", 
        { status => -1, 
          msg => "You must specify an output file with the output_file property"
        });
    $logger->error( $log_msg );
    exit(-1);
}
if ( not $conf{"update_interval"} ) {
    $conf{"update_interval"} = 3600;
}
#END read configuration

if ( not $DEBUGFLAG ) {
    ( $status, $res ) = daemonize();
    if ( $status != 0 ) {
        my $log_msg = perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrapServerDaemon.init.end", 
        { status => -1, 
          msg => "Couldn't daemonize: " . $res 
        });
        $logger->error( $log_msg );
        exit( -1 );
    }
}

unlockPIDFile( $fileHandle );

#BEGIN handler
my $handler = new SimpleLSBootStrap::ServerDaemonHandler();
$handler->init( \%conf );
$logger->info( perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrapServerDaemon.init.end") );

while(1){
    $handler->handle();
}
#END handler
exit( 0 );

sub signalHandler {
    exit( 0 );
}

__END__

=head1 SEE ALSO

L<FindBin>, L<Getopt::Long>, L<Config::General>, L<Log::Log4perl>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::Daemon>,
L<perfSONAR_PS::Utils::Host>, L<SimpleLSBootStrap::ServerDaemonHandler>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: daemon.pl 3949 2010-03-12 18:04:21Z alake $

=head1 AUTHOR

Andy Lake, andy@es.net

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2010, Internet2

All rights reserved.

=cut

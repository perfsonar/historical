use strict;
use warnings;

use lib "../lib";
use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;
use perfSONAR_PS::Utils::Host qw(get_ips);

use Getopt::Long;
use Config::General;
use Log::Log4perl qw/:easy/;

my $CONFIG_FILE;
my $LOGOUTPUT;
my $PIDFILE;
my $DEBUGFLAG;
my $HELP;
my $RUNAS_USER;
my $RUNAS_GROUP;

my ( $status, $res );

$status = GetOptions(
    'config=s'  => \$CONFIG_FILE,
    'output=s'  => \$LOGOUTPUT,
    'pidfile=s' => \$PIDFILE,
    'verbose'   => \$DEBUGFLAG,
    'user=s'    => \$RUNAS_USER,
    'group=s'   => \$RUNAS_GROUP,
    'help'      => \$HELP
);

if ( not $CONFIG_FILE ) {
    print "Error: no configuration file specified\n";
    exit(-1);
}

my %conf = Config::General->new($CONFIG_FILE)->getall();

if ( not $PIDFILE ) {
    $PIDFILE = $conf{"pid_file"};
}

if ( not $PIDFILE ) {
    $PIDFILE = "/var/run/ls_registration_daemon.pid";
}

( $status, $res ) = lockPIDFile($PIDFILE);
if ( $status != 0 ) {
    print "Error: $res\n";
    exit(-1);
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
        exit(-1);
    }
}
elsif ( $RUNAS_USER or $RUNAS_GROUP ) {

    # they need to specify both the user and group
    print "Error: You need to specify both the user and group if you specify either\n";
    exit(-1);
}

my $output_level = $INFO;

#if($DEBUGFLAG) {
$output_level = $DEBUG;

#}

my %logger_opts = (
    level  => $output_level,
    layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
);

if ($LOGOUTPUT) {
    $logger_opts{file} = $LOGOUTPUT;
}

Log::Log4perl->easy_init( \%logger_opts );
my $logger = get_logger("perfSONAR_PS::LSRegistrationDaemon");

if ( not $conf{"ls_instance"} ) {
    $logger->error("LS registration daemon needs to know which LS to register services with");
    exit(-1);
}

if ( not $conf{"ls_interval"} ) {
    $logger->error("No LS interval specified. Defaulting to 24 hours");
    $conf{"ls_interval"} = 24;
}

# the interval is configured in hours
$conf{"ls_interval"} = $conf{"ls_interval"} * 60 * 60;

my $site_confs = $conf{"site"};
if ( not $site_confs ) {
    $logger->error("No sites defined in configuration file");
    exit(-1);
}

if ( ref($site_confs) ne "ARRAY" ) {
    my @tmp = ();
    push @tmp, $site_confs;
    $site_confs = \@tmp;
}

my @pids = ();

my @site_children = ();

foreach my $site_conf (@$site_confs) {
    my $site_merge_conf = mergeConfig( \%conf, $site_conf );

    my $services = init_site($site_merge_conf);

    if ( not $services ) {
        print "Couldn't initialize site. Exitting.";
        exit(-1);
    }

    push @site_children, $services;
}

if ( not $DEBUG ) {
    ( $status, $res ) = daemonize();
    if ( $status != 0 ) {
        $logger->error( "Couldn't daemonize: " . $res );
        exit(-1);
    }
}

unlockPIDFile($fileHandle);

foreach my $site (@site_children) {

    # every site will register separately
    my $pid = fork();
    if ( $pid != 0 ) {
        push @pids, $pid;
        next;
    }
    else {
        handle_site($site);
    }
}

foreach my $pid (@pids) {
    waitpid( $pid, 0 );
}

sub init_site {
    my ($site_conf) = @_;

    my @services = ();

    my $services_conf = $site_conf->{service};
    if ( ref($services_conf) ne "ARRAY" ) {
        my @tmp = ();
        push @tmp, $services_conf;
        $services_conf = \@tmp;
    }

    foreach my $curr_service_conf (@$services_conf) {

        my $service_conf = mergeConfig( $site_conf, $curr_service_conf );

        if ( not $service_conf->{type} ) {

            # complain
            $logger->error("Error: No service type specified");
            exit(-1);
        }
        elsif ( lc( $service_conf->{type} ) eq "bwctl" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::BWCTL->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize bwctl watcher");
                exit(-1);
            }
            push @services, $service;
        }
        elsif ( lc( $service_conf->{type} ) eq "owamp" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::OWAMP->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize owamp watcher");
                exit(-1);
            }
            push @services, $service;
        }
        elsif ( lc( $service_conf->{type} ) eq "ping" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::Ping->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize ping watcher");
                exit(-1);
            }
            push @services, $service;
        }
        elsif ( lc( $service_conf->{type} ) eq "traceroute" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::Traceroute->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize traceroute watcher");
                exit(-1);
            }
            push @services, $service;
        }
        elsif ( lc( $service_conf->{type} ) eq "ndt" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::NDT->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize NDT watcher");
                exit(-1);
            }
            push @services, $service;
        }
        elsif ( lc( $service_conf->{type} ) eq "npad" ) {
            my $service = perfSONAR_PS::LSRegistrationDaemon::NPAD->new();
            if ( $service->init($service_conf) != 0 ) {

                # complain
                $logger->error("Error: Couldn't initialize NPAD watcher");
                exit(-1);
            }
            push @services, $service;
        }
        else {

            # error
            $logger->error( "Error: Unknown service type: " . $conf{type} . "" );
            exit(-1);
        }
    }

    return \@services;
}

sub handle_site {
    my ($services) = @_;

    while (1) {
        foreach my $service (@$services) {
            $service->refresh();
            sleep(60);
        }
    }

    return;
}

package perfSONAR_PS::LSRegistrationDaemon::Base;

use Socket;
use Socket6;
use Log::Log4perl qw/get_logger/;

use perfSONAR_PS::Utils::DNS qw(reverse_dns);
use perfSONAR_PS::Client::LS;

use fields 'CONF', 'STATUS', 'LOGGER', 'KEY', 'NEXT_REFRESH', 'LS_CLIENT';

sub new {
    my $class = shift;

    my $self = fields::new($class);

    return $self;
}

sub init {
    my ( $self, $conf ) = @_;

    $self->{CONF}   = $conf;
    $self->{STATUS} = "UNREGISTERED";
    $self->{LOGGER} = get_logger( ref($self) );

    if ( not $conf->{ls_instance} ) {
        $self->{LOGGER}->error("No ls instance available for this service to use");
        exit(-1);
    }

    $self->{LS_CLIENT} = perfSONAR_PS::Client::LS->new( { instance => $conf->{ls_instance} } );

    return 0;
}

sub service_name {
    my ($self) = @_;

    if ( $self->{CONF}->{service_name} ) {
        return $self->{CONF}->{service_name};
    }

    my $retval = "";
    if ( $self->{CONF}->{site_name} ) {
        $retval .= $self->{CONF}->{site_name} . " ";
    }
    $retval .= $self->type();

    return $retval;
}

sub service_desc {
    my ($self) = @_;

    if ( $self->{CONF}->{service_name} ) {
        return $self->{CONF}->{service_name};
    }

    my $retval = $self->type();
    if ( $self->{CONF}->{site_name} ) {
        $retval .= " at " . $self->{CONF}->{site_name};
    }

    if ( $self->{CONF}->{site_location} ) {
        $retval .= " in " . $self->{CONF}->{site_location};
    }

    return $retval;
}

sub refresh {
    my ($self) = @_;

    if ( $self->{STATUS} eq "BROKEN" ) {
        $self->{LOGGER}->debug("Refreshing broken service");
        return;
    }

    $self->{LOGGER}->debug( "Refreshing: " . $self->service_desc . "" );

    if ( $self->is_up ) {
        $self->{LOGGER}->debug("Service is up");
        if ( $self->{STATUS} ne "REGISTERED" ) {
            $self->register();
        }
        elsif ( time >= $self->{NEXT_REFRESH} ) {
            $self->keepalive();
        }
        else {
            $self->{LOGGER}->debug("No need to refresh");
        }
    }
    elsif ( $self->{STATUS} eq "REGISTERED" ) {
        $self->{LOGGER}->debug("Service isn't");
        $self->unregister();
    }
    else {
        $self->{LOGGER}->debug("Service failed");
    }

    return;
}

sub register {
    my ($self) = @_;

    my $addresses = $self->get_service_addresses();

    my @metadata = ();
    my %service  = ();
    $service{nonPerfSONARService} = 1;
    $service{name}                = $self->service_name();
    $service{description}         = $self->service_desc();
    $service{type}                = $self->service_type();
    $service{addresses}           = $addresses;

    my $ev       = $self->event_type();
    my $projects = $self->{CONF}->{site_project};

    my $node_addresses = $self->get_node_addresses();

    my $md = "";
    $md .= "<nmwg:metadata id=\"" . int( rand(9000000) ) . "\">\n";
    $md .= "  <nmwg:subject>\n";
    $md .= $self->create_node($node_addresses);
    $md .= "  </nmwg:subject>\n";
    $md .= "  <nmwg:eventType>$ev</nmwg:eventType>\n";
    if ($projects) {
        $md .= "  <nmwg:parameters>\n";
        if ( ref($projects) eq "ARRAY" ) {
            foreach my $project (@$projects) {
                $md .= "    <nmwg:parameter name=\"keyword\">project:" . $project . "</nmwg:parameter>\n";
            }
        }
        else {
            $md .= "    <nmwg:parameter name=\"keyword\">project:" . $projects . "</nmwg:parameter>\n";
        }
        $md .= "  </nmwg:parameters>\n";
    }
    $md .= "</nmwg:metadata>\n";

    push @metadata, $md;

    my $res = $self->{LS_CLIENT}->registerRequestLS( service => \%service, data => \@metadata );
    if ( $res and $res->{"key"} ) {
        $self->{LOGGER}->debug( "Registration succeeded with key: " . $res->{"key"} );
        $self->{STATUS}       = "REGISTERED";
        $self->{KEY}          = $res->{"key"};
        $self->{NEXT_REFRESH} = time + $self->{CONF}->{"ls_interval"};
    }
    else {
        my $error;
        if ( $res and $res->{error} ) {
            $self->{LOGGER}->debug( "Registration failed: " . $res->{error} );
        }
        else {
            $self->{LOGGER}->debug("Registration failed");
        }
    }

    return;
}

sub keepalive {
    my ($self) = @_;

    my $res = $self->{LS_CLIENT}->keepaliveRequestLS( key => $self->{KEY} );
    if ( $res->{eventType} ne "success.ls.keepalive" ) {
        $self->{STATUS} = "UNREGISTERED";
        $self->{LOGGER}->debug("Keepalive failed");
    }

    return;
}

sub unregister {
    my ($self) = @_;

    $self->{LS_CLIENT}->deregisterRequestLS( key => $self->{KEY} );
    $self->{STATUS} = "UNREGISTERED";

    return;
}

sub create_node {
    my ( $self, $addresses ) = @_;
    my $node = "";

    my $nmtb  = "http://ogf.org/schema/network/topology/base/20070828/";
    my $nmtl3 = "http://ogf.org/schema/network/topology/l3/20070828/";

    $node .= "<nmtb:node xmlns:nmtb=\"$nmtb\" xmlns:nmtl3=\"$nmtl3\">\n";
    foreach my $addr (@$addresses) {
        my $name = reverse_dns( $addr->{value} );
        if ($name) {
            $node .= " <nmtb:name type=\"dns\">$name</nmtb:name>\n";
        }
    }

    foreach my $addr (@$addresses) {
        $node .= " <nmtl3:port>\n";
        $node .= "   <nmtl3:address type=\"" . $addr->{type} . "\">" . $addr->{value} . "</nmtl3:address>\n";
        $node .= " </nmtl3:port>\n";
    }
    $node .= "</nmtb:node>\n";

    return $node;
}

package perfSONAR_PS::LSRegistrationDaemon::TCP_Service;

use perfSONAR_PS::Utils::DNS qw(resolve_address);
use perfSONAR_PS::Utils::Host qw(get_ips);

use base 'perfSONAR_PS::LSRegistrationDaemon::Base';

use fields 'ADDRESSES', 'PORT';

use IO::Socket;
use IO::Socket::INET6;
use IO::Socket::INET;

sub init {
    my ( $self, $conf ) = @_;

    unless ( $conf->{address} or $conf->{local} ) {
        $self->{STATUS} = "BROKEN";
        return -1;
    }

    my @addresses;

    if ( $conf->{address} ) {
        @addresses = ();

        my @tmp = ();
        if ( ref( $conf->{address} ) eq "ARRAY" ) {
            @tmp = @{ $conf->{address} };
        }
        else {
            push @tmp, $conf->{address};
        }

        my %addr_map = ();
        foreach my $addr (@tmp) {
            my @addrs = resolve_address($addr);
            foreach my $addr (@addrs) {
                $addr_map{$addr} = 1;
            }
        }

        @addresses = keys %addr_map;
    }
    elsif ( $conf->{local} ) {
        @addresses = get_ips();
    }

    $self->{ADDRESSES} = \@addresses;

    if ( $conf->{port} ) {
        $self->{PORT} = $conf->{port};
    }

    return $self->SUPER::init($conf);
}

sub is_up {
    my ($self) = @_;

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        my $sock;

        $self->{LOGGER}->debug( "Connecting to: " . $addr . ":" . $self->{PORT} . "" );

        if ( $addr =~ /:/ ) {
            $sock = IO::Socket::INET6->new( PeerAddr => $addr, PeerPort => $self->{PORT}, Proto => 'tcp', Timeout => 5 );
        }
        else {
            $sock = IO::Socket::INET->new( PeerAddr => $addr, PeerPort => $self->{PORT}, Proto => 'tcp', Timeout => 5 );
        }

        if ($sock) {
            $sock->close;

            return 1;
        }
    }

    return 0;
}

sub get_service_addresses {
    my ($self) = @_;

    my @addresses = ();

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        my $uri;

        $uri = "tcp://";
        if ( $addr =~ /:/ ) {
            $uri .= "[$addr]";
        }
        else {
            $uri .= "$addr";
        }

        $uri .= ":" . $self->{PORT};

        my %addr = ();
        $addr{"value"} = $uri;
        $addr{"type"}  = "uri";

        push @addresses, \%addr;
    }

    return \@addresses;
}

sub get_node_addresses {
    my ($self) = @_;

    my @addrs = ();

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        unless ( $addr =~ /:/ or $addr =~ /\d+\.\d+\.\d+\.\d+/ ) {

            # it's probably a hostname, try looking it up.
        }

        if ( $addr =~ /:/ ) {
            my %addr = ();
            $addr{"value"} = $addr;
            $addr{"type"}  = "ipv6";
            push @addrs, \%addr;
        }
        elsif ( $addr =~ /\d+\.\d+\.\d+\.\d+/ ) {
            my %addr = ();
            $addr{"value"} = $addr;
            $addr{"type"}  = "ipv4";
            push @addrs, \%addr;
        }
    }

    return \@addrs;
}

package perfSONAR_PS::LSRegistrationDaemon::BWCTL;

use base 'perfSONAR_PS::LSRegistrationDaemon::TCP_Service';

use constant DEFAULT_PORT   => 4823;
use constant DEFAULT_CONFIG => "/usr/local/etc/bwctld.conf";

sub init {
    my ( $self, $conf ) = @_;

    my $res;
    if ( $conf->{local} ) {
        my $bwctl_config = $conf->{config_file};
        if ( not $bwctl_config ) {
            $bwctl_config = DEFAULT_CONFIG;
        }

        $res = read_bwctl_config($bwctl_config);
        if ( $res->{error} ) {
            $self->{STATUS} = "BROKEN";
            return -1;
        }
    }
    else {
        my %tmp = ();
        $res = \%tmp;
    }

    if ( not $conf->{port} and not $res->{port} ) {
        $conf->{port} = DEFAULT_PORT;
    }
    elsif ( not $conf->{port} ) {
        $conf->{port} = $res->{port};
    }

    if ( $res->{addr} ) {
        my @tmp_addrs = ();
        push @tmp_addrs, $res->{addr};

        $conf->{address} = \@tmp_addrs;
    }

    return $self->SUPER::init($conf);
}

sub read_bwctl_config {
    my ($file) = @_;

    my %conf = ();

    my $FH;
    open( $FH, "<", $file ) or return \%conf;
    while ( my $line = <$FH> ) {
        $line =~ s/#.*//;     # get rid of any comment on the line
        $line =~ s/^\S+//;    # get rid of any leading whitespace
        $line =~ s/\S+$//;    # get rid of any trailing whitespace

        my ( $key, $value ) = split( /\S+/, $line );
        if ( not $key ) {
            next;
        }

        if ($value) {
            $conf{$key} = $value;
        }
        else {
            $conf{$key} = 1;
        }
    }
    close($FH);

    my $addr_to_parse;

    if ( $conf{"srcnode"} ) {
        $addr_to_parse = $conf{"srcnode"};
    }
    elsif ( $conf{"src_node"} ) {
        $addr_to_parse = $conf{"src_node"};
    }

    my ( $addr, $port );

    if ( $addr_to_parse and $addr_to_parse =~ /(.*):(.*)/ ) {
        $addr = $1;
        $port = $2;
    }

    my %res = ();
    if ($addr) {
        $res{addr} = $addr;
    }
    $res{port} = $port;

    return \%res;
}

sub type {
    my ($self) = @_;

    return "BWCTL Server";
}

sub service_type {
    my ($self) = @_;

    return "bwctl";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/bwctl/1.0";
}

package perfSONAR_PS::LSRegistrationDaemon::OWAMP;

use base 'perfSONAR_PS::LSRegistrationDaemon::TCP_Service';

use constant DEFAULT_PORT   => 861;
use constant DEFAULT_CONFIG => "/usr/local/etc/owampd.conf";

sub init {
    my ( $self, $conf ) = @_;

    my $res;
    if ( $conf->{local} ) {
        my $owamp_config = $conf->{config_file};
        if ( not $owamp_config ) {
            $owamp_config = DEFAULT_CONFIG;
        }

        $res = read_owamp_config($owamp_config);
        if ( $res->{error} ) {
            $self->{STATUS} = "BROKEN";
            return -1;
        }
    }
    else {
        my %tmp = ();
        $res = \%tmp;
    }

    if ( not $conf->{port} and not $res->{port} ) {
        $conf->{port} = DEFAULT_PORT;
    }
    elsif ( not $conf->{port} ) {
        $conf->{port} = $res->{port};
    }

    if ( $res->{addr} ) {
        my @tmp_addrs = ();
        push @tmp_addrs, $res->{addr};

        $conf->{address} = \@tmp_addrs;
    }

    return $self->SUPER::init($conf);
}

sub read_owamp_config {
    my ($file) = @_;

    my %conf = ();

    my $FH;

    open( $FH, "<", $file ) or return \%conf;
    while ( my $line = <$FH> ) {
        $line =~ s/#.*//;     # get rid of any comment on the line
        $line =~ s/^\S+//;    # get rid of any leading whitespace
        $line =~ s/\S+$//;    # get rid of any trailing whitespace

        my ( $key, $value ) = split( /\S+/, $line );
        if ( not $key ) {
            next;
        }

        if ($value) {
            $conf{$key} = $value;
        }
        else {
            $conf{$key} = 1;
        }
    }
    close($FH);

    my $addr_to_parse;

    if ( $conf{"srcnode"} ) {
        $addr_to_parse = $conf{"srcnode"};
    }
    elsif ( $conf{"src_node"} ) {
        $addr_to_parse = $conf{"src_node"};
    }

    my ( $addr, $port );

    if ( $addr_to_parse and $addr_to_parse =~ /(.*):(.*)/ ) {
        $addr = $1;
        $port = $2;
    }

    my %res = ();
    if ($addr) {
        $res{addr} = $addr;
    }
    $res{port} = $port;

    return \%res;
}

sub type {
    my ($self) = @_;

    return "OWAMP Server";
}

sub service_type {
    my ($self) = @_;

    return "owamp";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/owamp/1.0";
}

package perfSONAR_PS::LSRegistrationDaemon::NDT;

use base 'perfSONAR_PS::LSRegistrationDaemon::TCP_Service';

use constant DEFAULT_PORT => 7123;

sub init {
    my ( $self, $conf ) = @_;

    my $port = $conf->{port};
    if ( not $port ) {
        $conf->{port} = DEFAULT_PORT;
    }

    return $self->SUPER::init($conf);
}

sub get_service_addresses {
    my ($self) = @_;

    # we override the TCP_Service addresses function so that we can generate
    # URLs.

    my @addresses = ();

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        my $uri;

        $uri = "http://";
        if ( $addr =~ /:/ ) {
            $uri .= "[$addr]";
        }
        else {
            $uri .= "$addr";
        }

        $uri .= ":" . $self->{PORT};

        my %addr = ();
        $addr{"value"} = $uri;
        $addr{"type"}  = "url";

        push @addresses, \%addr;
    }

    return \@addresses;
}

sub type {
    my ($self) = @_;

    return "NDT Server";
}

sub service_type {
    my ($self) = @_;

    return "ndt";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/ndt/1.0";
}

package perfSONAR_PS::LSRegistrationDaemon::NPAD;

use base 'perfSONAR_PS::LSRegistrationDaemon::TCP_Service';

use constant DEFAULT_PORT   => 8200;
use constant DEFAULT_CONFIG => "/usr/local/npad-dist/config.xml";

sub init {
    my ( $self, $conf ) = @_;

    my $port = $conf->{port};
    if ( not $port and not $conf->{local} ) {
        $self->{STATUS} = "BROKEN";
        return -1;
    }
    elsif ( not $port ) {
        my $npad_config;

        $npad_config = $conf->{config_file};
        if ( not $npad_config ) {
            $npad_config = DEFAULT_CONFIG;
        }

        my $res = read_npad_config($npad_config);
        if ( $res->{error} ) {
            $self->{STATUS} = "BROKEN";
            return -1;
        }

        if ( $res->{port} ) {
            $conf->{port} = $res->{port};
        }
        else {
            $conf->{port} = DEFAULT_PORT;
        }
    }

    return $self->SUPER::init($conf);
}

sub read_npad_config {
    my ($file) = @_;

    my %conf;

    my $port;

    my $FH;
    open( $FH, "<", $file ) or return \%conf;
    while (<$FH>) {
        if (/key="webPort".*value="\([^"]\)"/) {
            $port = $1;
        }
    }
    close($FH);

    $conf{port} = $port;

    return \%conf;
}

sub get_service_addresses {
    my ($self) = @_;

    # we override the TCP_Service addresses function so that we can generate
    # URLs.

    my @addresses = ();

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        my $uri;

        $uri = "http://";
        if ( $addr =~ /:/ ) {
            $uri .= "[$addr]";
        }
        else {
            $uri .= "$addr";
        }

        $uri .= ":" . $self->{PORT};

        my %addr = ();
        $addr{"value"} = $uri;
        $addr{"type"}  = "url";

        push @addresses, \%addr;
    }

    return \@addresses;
}

sub type {
    my ($self) = @_;

    return "NPAD Server";
}

sub service_type {
    my ($self) = @_;

    return "npad";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/npad/1.0";
}

#### Traceroute/Ping Services ####

package perfSONAR_PS::LSRegistrationDaemon::ICMP_Service;

use Net::Ping;

use perfSONAR_PS::Utils::DNS qw(reverse_dns resolve_address);
use perfSONAR_PS::Utils::Host qw(get_ips);

use base 'perfSONAR_PS::LSRegistrationDaemon::Base';

use fields 'ADDRESSES';

sub init {
    my ( $self, $conf ) = @_;

    unless ( $conf->{address} or $conf->{local} ) {
        $self->{STATUS} = "BROKEN";
        return -1;
    }

    my @addresses;

    if ( $conf->{address} ) {
        @addresses = ();

        my @tmp = ();
        if ( ref( $conf->{address} ) eq "ARRAY" ) {
            @tmp = @{ $conf->{address} };
        }
        else {
            push @tmp, $conf->{address};
        }

        my %addr_map = ();
        foreach my $addr (@tmp) {
            my @addrs = resolve_address($addr);
            foreach my $addr (@addrs) {
                $addr_map{$addr} = 1;
            }
        }

        @addresses = keys %addr_map;
    }
    elsif ( $conf->{local} ) {
        @addresses = get_ips();
    }

    $self->{ADDRESSES} = \@addresses;

    return $self->SUPER::init($conf);
}

sub get_service_addresses {
    my ($self) = @_;

    my @addrs = ();

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        my %addr = ();
        $addr{"value"} = $addr;
        if ( $addr =~ /:/ ) {
            $addr{"type"} = "ipv6";
        }
        else {
            $addr{"type"} = "ipv4";
        }

        push @addrs, \%addr;
    }

    return \@addrs;
}

sub get_node_addresses {
    my ($self) = @_;

    return $self->get_service_addresses();
}

sub is_up {
    my ($self) = @_;

    foreach my $addr ( @{ $self->{ADDRESSES} } ) {
        if ( $addr =~ /:/ ) {
            next;
        }
        else {
            $self->{LOGGER}->debug( "Pinging: " . $addr . "" );
            my $ping = Net::Ping->new("external");
            if ( $ping->ping( $addr, 1 ) ) {
                return 1;
            }
        }
    }

    return 0;
}

package perfSONAR_PS::LSRegistrationDaemon::Ping;

use base 'perfSONAR_PS::LSRegistrationDaemon::ICMP_Service';

sub type {
    my ($self) = @_;

    return "Ping Responder";
}

sub service_type {
    my ($self) = @_;

    return "ping";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/ping/1.0";
}

package perfSONAR_PS::LSRegistrationDaemon::Traceroute;

use base 'perfSONAR_PS::LSRegistrationDaemon::ICMP_Service';

sub type {
    my ($self) = @_;

    return "Traceroute Responder";
}

sub service_type {
    my ($self) = @_;

    return "traceroute";
}

sub event_type {
    my ($self) = @_;

    return "http://ggf.org/ns/nmwg/tools/traceroute/1.0";
}


#!/usr/bin/perl

use lib 'lib';
use lib '../lib';

use File::Basename;
use POSIX qw( setsid );
use Fcntl qw(:DEFAULT :flock);
use Log::Log4perl qw(:easy);
use strict;
use IO::Select;
use Config::General;
use Getopt::Long;

my $CONFIG_FILE;
my $LOGOUTPUT;
my $PIDFILE;
my $DEBUGFLAG;
my $NAMED_PIPE;
my $HELP;

my $status = GetOptions (
        'config=s' => \$CONFIG_FILE,
        'output=s' => \$LOGOUTPUT,
        'pidfile=s' => \$PIDFILE,
        'verbose'  => \$DEBUGFLAG,
        'pipe=s'   => \$NAMED_PIPE,
        'help'     => \$HELP);

if (not $PIDFILE) {
    $PIDFILE="/var/run/ls_registration_daemon.pid";
}

my $pidfile = lockPIDFile($PIDFILE);

my $output_level = $INFO;
#if($DEBUGFLAG) {
    $output_level = $DEBUG;
#}

my %logger_opts = (
        level => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
        );

if ($LOGOUTPUT) {
    $logger_opts{file} = $LOGOUTPUT;
}

Log::Log4perl->easy_init( \%logger_opts );
my $logger = get_logger("perfSONAR_PS::LSRegistrationDaemon");

my %config = Config::General->new($CONFIG_FILE)->getall();

if (not defined $config{"ls_instance"}) {
    print "LS registration daemon needs to know which LS to register services with\n";
    exit(-1);
}

if (not $config{"ls_interval"}) {
    $config{"ls_interval"} = 24;
}

# the interval is configured in hours
$config{"ls_interval"} = $config{"ls_interval"} * 60 * 60;

if (not $NAMED_PIPE) {
    $NAMED_PIPE = $config{"pipe_path"};
}

if (not $NAMED_PIPE) {
    $NAMED_PIPE = "/var/run/ls_registration_agent.pipe";
}

unless (-p $NAMED_PIPE) {
    # create the pipe
    unlink $NAMED_PIPE;
    system('mknod', $NAMED_PIPE, 'p') && die "Unable to create named pipe $NAMED_PIPE: $!";
}

my $bwctl;
if (not $config{bwctl}->{disabled}) {
    $bwctl = perfSONAR_PS::Agent::LS::Registration::BWCTL->new();
    if ($bwctl->init(\%config)) {
        exit(-2);
    }
}

my $owamp;
if (not $config{owamp}->{disabled}) {
    $owamp = perfSONAR_PS::Agent::LS::Registration::OWAMP->new();
    if ($owamp->init(\%config)) {
        exit(-3);
    }
}

my $ndt;
if (not $config{ndt}->{disabled}) {
    $ndt = perfSONAR_PS::Agent::LS::Registration::NDT->new();
    if ($ndt->init(\%config)) {
        exit(-4);
    }
}

my $npad;
if (not $config{npad}->{disabled}) {
    $npad = perfSONAR_PS::Agent::LS::Registration::NPAD->new();
    if ($npad->init(\%config)) {
        exit(-5);
    }
}

my $ping;
if (not $config{ping}->{disabled}) {
    $ping = perfSONAR_PS::Agent::LS::Registration::Ping->new();
    if ($ping->init(\%config)) {
        exit(-2);
    }
}

my $traceroute;
if (not $config{traceroute}->{disabled}) {
    $traceroute = perfSONAR_PS::Agent::LS::Registration::Traceroute->new();
    if ($traceroute->init(\%config)) {
        exit(-2);
    }
}

my $pipe_handle;

# open the named pipe both read and write so that it doesn't try to tell us
# when the last person to write to the pipe closes. We really want to wait for
# the next writer who may come.
open($pipe_handle, "+<$NAMED_PIPE") || die("Couldn't open named pipe");

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
#if(not $DEBUGFLAG) {
# flush the buffer
    $| = 1;
        &daemonize;
#}

unlockPIDFile($pidfile);

while(1) {
    $bwctl->refresh() if ($bwctl);
    $owamp->refresh() if ($owamp);
    $ndt->refresh() if ($ndt);
    $npad->refresh() if ($npad);
    $ping->refresh() if ($ping);
    $traceroute->refresh() if ($traceroute);

    my $select = IO::Select->new();
    $select->add($pipe_handle);

    my @ready = $select->can_read(60);

    if ($#ready > -1) {
        my $line = <$pipe_handle>;
        chomp($line);
        $logger->info("Received message: ".$line);
        handle_message($line);
    }
}

sub handle_message {
    my ($msg) = @_;

    my ($service, $status, @config_options) = split(' ', $msg);
    if (lc($service) eq "bwctl") {
        return $bwctl->handle_message($status, @config_options);
    } elsif (lc($service) eq "owamp") {
        return $owamp->handle_message($status, @config_options);
    } elsif (lc($service) eq "ndt") {
        return $ndt->handle_message($status, @config_options);
    } elsif (lc($service) eq "npad") {
        return $npad->handle_message($status, @config_options);
    } else {
        print "Got message for unknown service ".lc($service)."\n";
    }
}

=head2 lockPIDFile($pidfile);
The lockPIDFile function checks for the existence of the specified file in
the specified directory. If found, it checks to see if the process in the
file still exists. If there is no running process, it returns the filehandle for the open pidfile that has been flock(LOCK_EX).
=cut
sub lockPIDFile {
    my($pidfile) = @_;
    my $logger = get_logger("perfSONAR_PS::LSRegistrationDaemon");
    $logger->debug("Locking pid file: $pidfile");
    die "Can't write pidfile: $pidfile\n" unless -w dirname($pidfile);
    sysopen(PIDFILE, $pidfile, O_RDWR | O_CREAT);
    flock(PIDFILE, LOCK_EX);
    my $p_id = <PIDFILE>;
    chomp($p_id) if (defined $p_id);
    if(defined $p_id and $p_id ne q{}) {
        open(PSVIEW, "ps -p ".$p_id." |");
        my @output = <PSVIEW>;
        close(PSVIEW);
        if(!$?) {
            die "$0 already running: $p_id\n";
        }
    }

    $logger->debug("Locked pid file");

    return *PIDFILE;
}

=head2 unlockPIDFile
This file writes the pid of the call process to the filehandle passed in,
unlocks the file and closes it.
=cut
sub unlockPIDFile {
    my($filehandle) = @_;
    my $logger = get_logger("perfSONAR_PS::LSRegistrationDaemon");

    truncate($filehandle, 0);
    seek($filehandle, 0, 0);
    print $filehandle "$$\n";
    flock($filehandle, LOCK_UN);
    close($filehandle);

    $logger->debug("Unlocked pid file");

    return;
}

=head2 daemonize
Sends the program to the background by eliminating ties to the calling terminal.
=cut
sub daemonize {
    chdir '/' or die "Can't chdir to /: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";
    umask 0;
    return;
}





package perfSONAR_PS::Agent::LS::Registration::Base;

use perfSONAR_PS::Client::LS;
use IO::Socket;
use IO::Interface qw(:flags);
use Log::Log4perl qw(:easy);

use fields 'LS_CLIENT', 'KEY', 'STATUS', 'APP_STATUS', 'NEXT_REGISTRATION', 'CONF', 'APP_CONFIG', 'LOGGER';

sub new {
    my ( $package ) = @_;

    my $self = fields::new($package);

    return $self;
}

sub init {
    my ($self, $conf) = @_;

    $self->{CONF} = $conf;

    $self->{STATUS} = "UNREGISTERED";
    $self->{APP_STATUS} = "STOPPED";
    $self->{LS_CLIENT} = perfSONAR_PS::Client::LS->new(instance => $conf->{"ls_instance"});

    return 0;
}

sub handle_message {
    my ($self, $msg, @config_options) = @_;

    if (lc($msg) eq "stop") {
        if ($self->{STATUS} eq "REGISTERED") {
            $self->unregister(@config_options);
            $self->{STATUS} = "UNREGISTERED";
        }

        $self->{APP_STATUS} = "STOPPED";
    } elsif (lc($msg) eq "start") {
        if ($self->{STATUS} eq "REGISTERED") {
            $self->unregister(@config_options);
            $self->{STATUS} = "UNREGISTERED";
        }

        $self->register(@config_options);

        $self->{APP_STATUS} = "STARTED";
    }
}

sub register {
    my ($self) = @_;

    die("must be overridden");
}

sub unregister {
    my ($self) = @_;

    if ($self->{STATUS} eq "REGISTERED") {
        $self->{LS_CLIENT}->deregisterRequestLS(key => $self->{KEY});
        $self->{STATUS} = "UNREGISTERED";
    }
}

sub refresh {
    my ($self) = @_;

    $self->{LOGGER}->debug("Refresh called");

    if ($self->{APP_STATUS} eq "STARTED") {
        $self->{LOGGER}->debug("Application is running");
        if ($self->{STATUS} eq "REGISTERED" and time >= $self->{NEXT_REGISTRATION}) {
            $self->{LOGGER}->debug("Application is registered and we need to register");
            $self->{LS_CLIENT}->keepaliveRequestLS(key => $self->{KEY});
        } elsif ($self->{STATUS} eq "UNREGISTERED") {
            $self->{LOGGER}->debug("Application is unregistered");
            $self->register($self->{APP_CONFIG});
        } else {
            $self->{LOGGER}->debug("Application is registered");
        }
    }
}

sub lookup_interfaces {
    my $s = IO::Socket::INET->new(Proto => 'tcp');
    my @ret_interfaces = ();

    my @interfaces = $s->if_list;
    foreach my $if (@interfaces) {
        my $if_flags = $s->if_flags($if);

        next if ($if_flags & IFF_LOOPBACK);
        next if (not ($if_flags & IFF_RUNNING));

        push @ret_interfaces, $s->if_addr($if);
    }

    return @ret_interfaces;
}

sub __boote_read_app_config {
    my ($self, $file) = @_;

    my %conf = ();

    open(FILE, $file);
    while(my $line = <FILE>) {
        $line =~ s/#.*//;  # get rid of any comment on the line
        $line =~ s/^\S+//; # get rid of any leading whitespace
        $line =~ s/\S+$//; # get rid of any trailing whitespace

        my ($key, $value) = split(/\S+/, $line);
        if (not $key) {
            next;
        }

        if ($value) {
            $conf{$key} = $value;
        } else {
            $conf{$key} = 1;
        }
    }

    return %conf;
}

sub create_event_type_md {
    my ($self, $eventType) = @_;

    my $md = "";
    $md .= "<nmwg:metadata id=\"".int(rand(9000000))."\">\n";
    $md .= "  <nmwg:subject>\n";
    $md .= $self->create_junk_node();
    $md .= "  </nmwg:subject>\n";
    $md .= "  <nmwg:eventType>$eventType</nmwg:eventType>\n";
    $md .= "</nmwg:metadata>\n";

    return $md;
}

sub create_junk_node {
    my $self = shift;
    my $node = "";
    my $nmtb = "http://ogf.org/schema/network/topology/base/20070828/";
    my $nmtl3 = "http://ogf.org/schema/network/topology/l3/20070828/";

    my @addresses = $self->lookup_interfaces();

    $node .= "<nmtb:node xmlns:nmtb=\"$nmtb\" xmlns:nmtl3=\"$nmtl3\">\n";
    foreach my $addr (@addresses) {
        my $addr_type;

        if ($addr =~ /:/) {
            $addr_type = "ipv6";
        } else {
            $addr_type = "ipv4";
        }

        $node .= " <nmtl3:port>\n";
        $node .= "   <nmtl3:address type=\"$addr_type\">$addr</nmtl3:address>\n";
        $node .= " </nmtl3:port>\n";
    }
    $node .= "</nmtb:node>\n";

    return $node;
}

package perfSONAR_PS::Agent::LS::Registration::BWCTL;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    my $config_file = $config_options[0];
    if (not $config_file) {
        return;
    }

    $self->{APP_CONFIG} = $config_file;

    my %res = $self->read_app_config($config_file);

    my $port = 4823;
    if ($res{port}) {
        $port = $res{port};
    }
   
    my @addresses; 
    if (not $res{addr}) {
        # Grab the list of address from the server
        @addresses = $self->lookup_interfaces();
    } else {
        @addresses = ();
        push @addresses, $res{addr};
    }

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{bwctl}->{service_name};
    $service{description} = $self->{CONF}->{bwctl}->{service_description};
    $service{type} = $self->{CONF}->{bwctl}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"type"} = "uri";
        if ($address =~ /:/) {
            $addr{"value"} = "tcp://[$address]:$port";
        } else {
            $addr{"value"} = "tcp://$address:$port";
        }
        push @serv_addrs, \%addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{bwctl}->{project}) {
        push @projects, $self->{CONF}->{bwctl}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/bwctl/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub read_app_config {
    my ($self, $file) = @_;

    my %conf = $self->__boote_read_app_config($file);
    my $addr_to_parse;

    if ($conf{"srcnode"}) {
        $addr_to_parse = $conf{"srcnode"};
    } elsif ($conf{"src_node"}) {
        $addr_to_parse = $conf{"src_node"};
    }

    my ($addr, $port);

    if ($addr_to_parse and $addr_to_parse =~ /(.*):(.*)/) {
        $addr = $1;
        $port = $2;
    }

    return ( addr => $addr, port => $port );
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::BWCTL");

    if (not $conf->{"bwctl"}->{"service_name"}) {
        my $name = "";

        $name .= "BWCTL Server";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"bwctl"}->{"service_name"} = $name;
    }

    if (not $conf->{"bwctl"}->{"service_description"}) {
        my $desc = "";

        $desc .= "BWCTL Server";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"bwctl"}->{"service_description"} = $desc;
    }

    if (not $conf->{"bwctl"}->{"service_type"}) {
        $conf->{"bwctl"}->{"service_type"} = "bwctl";
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::OWAMP;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    my $config_file = $config_options[0];
    if (not $config_file) {
        return;
    }

    $self->{APP_CONFIG} = $config_file;

    my %res = $self->read_app_config($config_file);

    my $port = 861;
    if ($res{port}) {
        $port = $res{port};
    }
   
    my @addresses; 
    if (not $res{addr}) {
        # Grab the list of address from the server
        @addresses = $self->lookup_interfaces();
    } else {
        @addresses = ();
        push @addresses, $res{addr};
    }

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{owamp}->{service_name};
    $service{description} = $self->{CONF}->{owamp}->{service_description};
    $service{type} = $self->{CONF}->{owamp}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"type"} = "uri";
        if ($address =~ /:/) {
            $addr{"value"} = "tcp://[$address]:$port";
        } else {
            $addr{"value"} = "tcp://$address:$port";
        }
        push @serv_addrs, \%addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{owamp}->{project}) {
        push @projects, $self->{CONF}->{owamp}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/owamp/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub read_app_config {
    my ($self, $file) = @_;

    my %conf = $self->__boote_read_app_config($file);
    my $addr_to_parse;

    if ($conf{"srcnode"}) {
        $addr_to_parse = $conf{"srcnode"};
    } elsif ($conf{"src_node"}) {
        $addr_to_parse = $conf{"src_node"};
    }

    my ($addr, $port);

    if ($addr_to_parse and $addr_to_parse =~ /(.*):(.*)/) {
        $addr = $1;
        $port = $2;
    }

    return ( addr => $addr, port => $port );
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::OWAMP");

    if (not $conf->{"owamp"}->{"service_name"}) {
        my $name = "";

        $name .= "OWAMP Server";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"owamp"}->{"service_name"} = $name;
    }

    if (not $conf->{"owamp"}->{"service_description"}) {
        my $desc = "";

        $desc .= "OWAMP Server";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"owamp"}->{"service_description"} = $desc;
    }

    if (not $conf->{"owamp"}->{"service_type"}) {
        $conf->{"owamp"}->{"service_type"} = "owamp";
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::NDT;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    # This isn't easily modifiable so for now, assume they haven't changed ports on me.
    my @addresses = $self->lookup_interfaces();
    my $web_port  = 7123;
    my $ctrl_port = 3001;

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{ndt}->{service_name};
    $service{description} = $self->{CONF}->{ndt}->{service_description};
    $service{type} = $self->{CONF}->{ndt}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"type"} = "uri";
        if ($address =~ /:/) {
            $addr{"value"} = "tcp://[$address]:$ctrl_port";
        } else {
            $addr{"value"} = "tcp://$address:$ctrl_port";
        }
        push @serv_addrs, \%addr;

        my %web_addr = ();
        $web_addr{"type"} = "url";
        if ($address =~ /:/) {
            $web_addr{"value"} = "http://[$address]:$web_port";
        } else {
            $web_addr{"value"} = "http://$address:$web_port";
        }
        push @serv_addrs, \%web_addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{ndt}->{project}) {
        push @projects, $self->{CONF}->{ndt}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/ndt/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::NDT");

    if (not $conf->{"ndt"}->{"service_type"}) {
        $conf->{"ndt"}->{"service_type"} = "ndt";
    }

    if (not $conf->{"ndt"}->{"service_name"}) {
        my $name = "";

        $name .= "NDT Server";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"ndt"}->{"service_name"} = $name;
    }

    if (not $conf->{"ndt"}->{"service_description"}) {
        my $desc = "";

        $desc .= "NDT Server";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"ndt"}->{"service_description"} = $desc;
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::NPAD;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    my $config_file = $config_options[0];
    if (not $config_file) {
        return;
    }

    $self->{APP_CONFIG} = $config_file;

    my %res = $self->read_app_config($config_file);

    my $ctrl_port = 8100;
    my $web_port  = 8200;

    if ($res{port}) {
        $ctrl_port = $res{port};
    }
   
    my @addresses; 
    if (not $res{addr}) {
        # Grab the list of address from the server
        @addresses = $self->lookup_interfaces();
    } else {
        @addresses = ();
        push @addresses, $res{addr};
    }

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{npad}->{service_name};
    $service{description} = $self->{CONF}->{npad}->{service_description};
    $service{type} = $self->{CONF}->{npad}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"type"} = "uri";
        if ($address =~ /:/) {
            $addr{"value"} = "tcp://[$address]:$ctrl_port";
        } else {
            $addr{"value"} = "tcp://$address:$ctrl_port";
        }
        push @serv_addrs, \%addr;

        my %web_addr = ();
        $web_addr{"type"} = "url";
        if ($address =~ /:/) {
            $web_addr{"value"} = "http://[$address]:$web_port";
        } else {
            $web_addr{"value"} = "http://$address:$web_port";
        }
        push @serv_addrs, \%web_addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{npad}->{project}) {
        push @projects, $self->{CONF}->{npad}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/npad/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub read_app_config {
    my ($self, $file) = @_;

    my ($control_addr, $control_port);

    open(NPAD_CONFIG, $file);
    while(<NPAD_CONFIG>) {
        if (/CONTROL_ADDR = (.*)/) {
            $control_addr = $1;
        } elsif (/CONTROL_PORT = (.*)/) {
            $control_port = $1;
        }
    }

    return ( addr => $control_addr, port => $control_port );
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::NPAD");

    if (not $conf->{"npad"}->{"service_type"}) {
        $conf->{"npad"}->{"service_type"} = "npad";
    }

    if (not $conf->{"npad"}->{"service_name"}) {
        my $name = "";

        $name .= "NPAD Server";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"npad"}->{"service_name"} = $name;
    }

    if (not $conf->{"npad"}->{"service_description"}) {
        my $desc = "";

        $desc .= "NPAD Server";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"npad"}->{"service_description"} = $desc;
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::Ping;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    # Grab the list of address from the server
    my @addresses = $self->lookup_interfaces();

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{ping}->{service_name};
    $service{description} = $self->{CONF}->{ping}->{service_description};
    $service{type} = $self->{CONF}->{ping}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"value"} = $address;
        if ($address =~ /:/) {
            $addr{"type"} = "ipv6";
        } else {
            $addr{"type"} = "ipv4";
        }
        push @serv_addrs, \%addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{ping}->{project}) {
        push @projects, $self->{CONF}->{ping}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/ping/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::Ping");

    if (not $conf->{"ping"}->{"service_type"}) {
        $conf->{"ping"}->{"service_type"} = "ping";
    }

    if (not $conf->{"ping"}->{"service_name"}) {
        my $name = "";

        $name .= "Ping Responder";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"ping"}->{"service_name"} = $name;
    }

    if (not $conf->{"ping"}->{"service_description"}) {
        my $desc = "";

        $desc .= "Ping Responder";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"ping"}->{"service_description"} = $desc;
    }

    $self->SUPER::init($conf);

    # Ping is always running
    $self->{APP_STATUS} = "STARTED";

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::Traceroute;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';
use Log::Log4perl qw(:easy);

sub register {
    my ($self, @config_options) = @_;

    # Grab the list of address from the server
    my @addresses = $self->lookup_interfaces();

    my @metadata = ();
    my %service = ();
    $service{nonPerfSONARService} = 1;
    $service{name} = $self->{CONF}->{traceroute}->{service_name};
    $service{description} = $self->{CONF}->{traceroute}->{service_description};
    $service{type} = $self->{CONF}->{traceroute}->{service_type};
    my @serv_addrs = ();
    foreach my $address (@addresses) {
        my %addr = ();
        $addr{"value"} = $address;
        if ($address =~ /:/) {
            $addr{"type"} = "ipv6";
        } else {
            $addr{"type"} = "ipv4";
        }
        push @serv_addrs, \%addr;
    }
    $service{addresses} = \@serv_addrs;
    my @projects = ();
    if ($self->{CONF}->{project}) {
        push @projects, $self->{CONF}->{project};
    }
    if ($self->{CONF}->{traceroute}->{project}) {
        push @projects, $self->{CONF}->{traceroute}->{project};
    }
    $service{projects} = \@projects;
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/traceroute/1.0");

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        $self->{NEXT_REGISTRATION} = time + $self->{CONF}->{"ls_interval"};
    }
}

sub init {
    my ($self, $conf) = @_;

    $self->{LOGGER} = get_logger("package perfSONAR_PS::Agent::LS::Registration::Traceroute");

    if (not $conf->{"traceroute"}->{"service_type"}) {
        $conf->{"traceroute"}->{"service_type"} = "traceroute";
    }

    if (not $conf->{"traceroute"}->{"service_name"}) {
        my $name = "";

        $name .= "Traceroute Responder";

        if ($conf->{"site_name"}) {
            $name = $conf->{site_name} . " " . $name;
        }

        $conf->{"traceroute"}->{"service_name"} = $name;
    }

    if (not $conf->{"traceroute"}->{"service_description"}) {
        my $desc = "";

        $desc .= "Traceroute Responder";
        if ($conf->{"project"}) {
            $desc .= " for ".$conf->{project};
        } elsif ($conf->{"site_project"}) {
            $desc .= " for ".$conf->{site_project};
        }

        if ($conf->{"site_name"}) {
            $desc .= " at ".$conf->{site_name};
        }

        if ($conf->{"site_location"}) {
            $desc .= " in ".$conf->{site_location};
        }

        $conf->{"traceroute"}->{"service_description"} = $desc;
    }

    $self->SUPER::init($conf);

    # Traceroute is always running
    $self->{APP_STATUS} = "STARTED";

    return 0;
}

# vim: expandtab shiftwidth=4 tabstop=4

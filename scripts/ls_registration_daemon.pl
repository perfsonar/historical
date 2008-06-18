#!/usr/bin/perl

use lib 'lib';

use Log::Log4perl qw(:easy);
use Data::Dumper;
use strict;
use IO::Select;
use Config::General;

my $level = $DEBUG;
Log::Log4perl->easy_init($level);

# XXX do the pid thing

my $config_file = shift;
my $named_pipe = shift;

my %config = Config::General->new($config_file)->getall();

print Dumper(\%config);

if (not defined $config{"ls_instance"}) {
    print "LS registration daemon needs to know which LS to register services with\n";
    exit(-1);
}

if (not $config{"ls_interval"}) {
    $config{"ls_interval"} = 24;
}

# the interval is configured in hours
$config{"ls_interval"} = $config{"ls_interval"} * 60 * 60;

if (not $named_pipe) {
    $named_pipe = $config{"pipe_path"};
}

if (not $named_pipe) {
    $named_pipe = "/var/run/ls_agent.pipe";
}

unless (-p $named_pipe) {
    # create the pipe
    unlink $named_pipe;
    system('mknod', $named_pipe, 'p') && die "Unable to create named pipe $named_pipe: $!";
}

my $bwctl = perfSONAR_PS::Agent::LS::Registration::BWCTL->new();
if ($bwctl->init(\%config)) {
    exit(-2);
}

my $owamp = perfSONAR_PS::Agent::LS::Registration::OWAMP->new();
if ($owamp->init(\%config)) {
    exit(-3);
}

my $ndt = perfSONAR_PS::Agent::LS::Registration::NDT->new();
if ($ndt->init(\%config)) {
    exit(-4);
}

my $npad = perfSONAR_PS::Agent::LS::Registration::NPAD->new();
if ($npad->init(\%config)) {
    exit(-5);
}

my $pipe_handle;

# open the named pipe both read and write so that it doesn't try to tell us
# when the last person to write to the pipe closes. We really want to wait for
# the next writer who may come.
open($pipe_handle, "+<$named_pipe");

# XXX background...

while(1) {
    my $select = IO::Select->new();
    $select->add($pipe_handle);

    my @ready = $select->can_read(60);

    if ($#ready > -1) {
        my $line = <$pipe_handle>;
        handle_message($line);
    } else {
        print "Timeout occurred\n";
    }

    $bwctl->refresh();
    $owamp->refresh();
    $ndt->refresh();
    $npad->refresh();
}

sub handle_message {
    my ($msg) = @_;

    my ($service, $status, $config) = split(' ', $msg);
    if (lc($service) eq "bwctl") {
        return $bwctl->handle_message($status, $config);
    } elsif (lc($service) eq "owamp") {
        return $owamp->handle_message($status, $config);
    } elsif (lc($service) eq "ndt") {
        return $ndt->handle_message($status, $config);
    } elsif (lc($service) eq "npad") {
        return $npad->handle_message($status, $config);
    } else {
        print "Got message for unknown service ".lc($service)."\n";
    }
}


package perfSONAR_PS::Agent::LS::Registration::Base;

use perfSONAR_PS::Client::LS;
use IO::Socket;
use IO::Interface qw(:flags);

use fields 'LS_CLIENT', 'KEY', 'STATUS', 'APP_STATUS', 'NEXT_REGISTRATION', 'CONF', 'APP_CONFIG';

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
    my ($self, $msg, $config) = @_;

    if (lc($msg) eq "stop") {
        if ($self->{STATUS} eq "REGISTERED") {
            $self->unregister($config);
            $self->{STATUS} = "UNREGISTERED";
        }

        $self->{APP_STATUS} = "STOPPED";
    } elsif (lc($msg) eq "start") {
        if ($self->{STATUS} eq "REGISTERED") {
            $self->unregister($config);
            $self->{STATUS} = "UNREGISTERED";
        }

        $self->register($config);

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

    if ($self->{APP_STATUS} eq "RUNNING") {
        if ($self->{STATUS} eq "REGISTERED" and time >= $self->{NEXT_REGISTRATION}) {
            $self->{LS_CLIENT}->keepaliveRequestLS(key => $self->{KEY});
        } elsif ($self->{STATUS} eq "UNREGISTERED") {
            $self->register($self->{APP_CONFIG});
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
    $md .= "  <nmwg:eventType>$eventType</nmwg:eventType>\n";
    $md .= "</nmwg:metadata>\n";

    return $md;
}

package perfSONAR_PS::Agent::LS::Registration::BWCTL;

use Data::Dumper;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';

sub register {
    my ($self, $config_file) = @_;

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
    push @metadata, $self->create_event_type_md("http://ggf.org/ns/nmwg/tools/bwctl/1.0");

    use Log::Log4perl qw(:easy);
    my $logger = get_logger("perfSONAR_PS::Topology");
    $logger->debug("Dumper: ".Dumper(\%service));
    $logger->debug("Conf: ".Dumper($self->{CONF}));
    $logger->debug("Addresses: ".Dumper(\@addresses));

    my $res = $self->{LS_CLIENT}->registerRequestLS(service => \%service, data => \@metadata);
    if ($res and $res->{"key"}) {
        $self->{STATUS} = "REGISTERED";
        $self->{KEY} = $res->{"key"};
        print "Registered!\n";
    } else {
        print "Failure!: ".Dumper($res)."\n";
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

    if (not $conf->{"bwctl"}->{"service_name"}) {
        $conf->{"bwctl"}->{"service_name"} = "BWCTL Server";
    }

    if (not $conf->{"bwctl"}->{"service_type"}) {
        $conf->{"bwctl"}->{"service_type"} = "bwctl";
    }

    if (not $conf->{"bwctl"}->{"service_description"}) {
        $conf->{"bwctl"}->{"service_description"} = "BWCTL Service";
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::OWAMP;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';

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

    if (not $conf->{"owamp"}->{"service_name"}) {
        $conf->{"owamp"}->{"service_name"} = "OWAMP Server";
    }

    if (not $conf->{"owamp"}->{"service_type"}) {
        $conf->{"owamp"}->{"service_type"} = "owamp";
    }

    if (not $conf->{"owamp"}->{"service_description"}) {
        $conf->{"owamp"}->{"service_description"} = "OWAMP Service";
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::NDT;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';

sub read_app_config {
    return ();
}

sub init {
    my ($self, $conf) = @_;

    if (not $conf->{"ndt"}->{"service_name"}) {
        $conf->{"ndt"}->{"service_name"} = "NDT Server";
    }

    if (not $conf->{"ndt"}->{"service_type"}) {
        $conf->{"ndt"}->{"service_type"} = "ndt";
    }

    if (not $conf->{"ndt"}->{"service_description"}) {
        $conf->{"ndt"}->{"service_description"} = "NDT Service";
    }

    $self->SUPER::init($conf);

    return 0;
}

package perfSONAR_PS::Agent::LS::Registration::NPAD;

use base 'perfSONAR_PS::Agent::LS::Registration::Base';

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

    if (not $conf->{"npad"}->{"service_name"}) {
        $conf->{"npad"}->{"service_name"} = "NPAD Server";
    }

    if (not $conf->{"npad"}->{"service_type"}) {
        $conf->{"npad"}->{"service_type"} = "npad";
    }

    if (not $conf->{"npad"}->{"service_description"}) {
        $conf->{"npad"}->{"service_description"} = "NPAD Service";
    }

    $self->SUPER::init($conf);

    return 0;
}

# vim: expandtab shiftwidth=4 tabstop=4

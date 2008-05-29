package perfSONAR_PS::Utils::TL1::Base;

use warnings;
use strict;

use Params::Validate qw(:all);

use perfSONAR_PS::Utils::TL1;

use fields 'USERNAME', 'PASSWORD', 'TYPE', 'ADDRESS', 'PORT', 'TL1AGENT', 'CACHE_DURATION', 'CACHE_TIME', 'LOGGER';

sub new {
    my ($class) = @_;

    my $self = fields::new($class);

    return $self;
}

sub initialize {
    my ($self, @params) = @_;

    #my $parameters = validateParams(@params,
    my $parameters = validate(@params,
            {
            type => 1,
            address => 1,
            port => 1,
            username => 1,
            password => 1,
            cache_time => 1,
            logger => 1,
            });

    $self->{TL1AGENT} = perfSONAR_PS::Utils::TL1->new(
            username => $parameters->{username},
            password => $parameters->{password},
            type => $parameters->{type},
            host => $parameters->{address},
            port => $parameters->{port}
            );

    $self->{USERNAME} = $parameters->{username};
    $self->{PASSWORD} = $parameters->{passwd};
    $self->{TYPE} = $parameters->{type};
    $self->{ADDRESS} = $parameters->{address};
    $self->{PORT} = $parameters->{port};

    $self->{CACHE_TIME} = 0;
    $self->{CACHE_DURATION} = $parameters->{cache_time};

    $self->{LOGGER} = $parameters->{logger};

    return $self;
}

sub getType {
    my ($self) = @_;

    return $self->{TYPE};
}

sub setType {
    my ($self, $type) = @_;

    $self->{TYPE} = $type;

    return;
}

sub setUsername {
    my ($self, $username) = @_;

    $self->{USERNAME} = $username;

    return;
}

sub getUsername {
    my ($self) = @_;

    return $self->{USERNAME};
}

sub setPassword {
    my ($self, $password) = @_;

    $self->{PASSWORD} = $password;

    return;
}

sub getPassword {
    my ($self) = @_;

    return $self->{PASSWORD};
}

sub setAddress {
    my ($self, $address) = @_;

    $self->{ADDRESS} = $address;

    return;
}

sub getAddress {
    my ($self) = @_;

    return $self->{ADDRESS};
}

sub setAgent {
    my ($self, $agent) = @_;

    $self->{TL1AGENT} = $agent;

    return;
}

sub getAgent {
    my ($self) = @_;

    return $self->{TL1AGENT};
}

sub send_cmd {
    my ($self, $cmd) = @_;

    my $res = $self->{TL1AGENT}->send($cmd);

    return split('\n', $res);
}

1;

# vim: expandtab shiftwidth=4 tabstop=4

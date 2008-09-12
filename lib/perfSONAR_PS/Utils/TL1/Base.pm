package perfSONAR_PS::Utils::TL1::Base;

use warnings;
use strict;

use Params::Validate qw(:all);

use perfSONAR_PS::Utils::TL1;

use fields 'USERNAME', 'PASSWORD', 'TYPE', 'ADDRESS', 'PORT', 'TL1AGENT', 'CACHE_DURATION', 'CACHE_TIME', 'LOGGER', 'MACHINE_TIME', 'CONNECTED';

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
    $self->{CONNECTED} = 0;

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

sub setCacheTime {
    my ($self, $time) = @_;

    $self->{CACHE_TIME} = $time;

    return $self->{CACHE_TIME};
}

sub getCacheTime {
    my ($self) = @_;

    return $self->{CACHE_TIME};
}

sub send_cmd {
    my ($self, $cmd) = @_;
    my $disconnect;

    $self->login();

    print "SEND: '$cmd'\n";
    my $res = $self->{TL1AGENT}->send($cmd);
    print "DONE SEND: '$cmd'\n";

    $self->logout();

    return split('\n', $res);
}

sub login {
    my ($self) = @_;

    if (not $self->{CONNECTED}) {
        $self->{TL1AGENT}->connect();
        $self->{TL1AGENT}->login();
    }

    $self->{CONNECTED}++;

    return 0;
}

sub logout {
    my ($self) = @_;

    $self->{CONNECTED}--;

    if (not $self->{CONNECTED}) {
        $self->{TL1AGENT}->disconnect();
    }

    return 0;
}

sub setMachineTime {
    my ($self, $time) = @_;

    my ($curr_date, $curr_time) = split(" ", $time);
    my ($year, $month, $day) = split("-", $curr_date);

    # make sure it's in 4 digit year form
    if (length($year) == 2) {
        # I don't see why it'd ever not be +2000, but...
        if ($year < 70) {
            $year += 2000;
        } else {
            $year += 1900;
        }
    }

    $self->{MACHINE_TIME} = "$year-$month-$day $curr_time";
}

sub getMachineTime {
    my ($self) = @_;

    return $self->{MACHINE_TIME};
}

1;

# vim: expandtab shiftwidth=4 tabstop=4

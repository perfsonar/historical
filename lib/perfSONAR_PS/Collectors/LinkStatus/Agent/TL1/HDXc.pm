package perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::HDXc;


use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Utils::TL1::HDXc;

our $VERSION = 0.09;

use fields 'AGENT', 'TYPE', 'LOGGER', 'ELEMENT_TYPE', 'ELEMENT_ID', 'ELEMENT_ID_TYPE';

sub new {
    my ($class, @params) = @_;

    my $parameters = validateParams(@params,
            {
            type => 1,
            address => 0,
            port => 0,
            username => 0,
            password => 0,
            agent => 0,
            element_id => 1,
            element_id_type => 1,
            element_type => 1,
            });

    my $self = fields::new($class);

    $self->{LOGGER} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1");

    # we need to be able to generate a new tl1 agent or reuse an existing one. Not neither.
    if (not $parameters->{agent} and
             (not $parameters->{address} or
             not $parameters->{port} or
             not $parameters->{username} or
             not $parameters->{password})
       ) {
        return;
    }

    # We only check the operational state (or what, at least, the primary state).
    if ($parameters->{type} ne "oper") {
        return;
    }

    if (not defined $parameters->{agent}) {
	$parameters->{agent} = perfSONAR_PS::Utils::TL1::HDXc->new();
	$parameters->{agent}->initialize(
                    username => $parameters->{username},
                    password => $parameters->{password},
                    address => $parameters->{address},
                    port => $parameters->{port},
                    cache_time => 300
                );
    }

    $self->type($parameters->{type});
    $self->agent($parameters->{agent});
    $self->element_id_type($parameters->{element_id_type});
    $self->element_id($parameters->{element_id});
    $self->element_type($parameters->{element_type});

    return $self;
}

sub run_line {
    my ($self) = @_;
    my ($status, $time);

    if ($self->{ELEMENT_ID_TYPE} eq "name") {
        $status = $self->{AGENT}->getLineByName($self->{ELEMENT_ID});
    } else {
        $status = $self->{AGENT}->getLine($self->{ELEMENT_ID});
    }

    $time = $self->{AGENT}->getCacheTime();

    if (not $status->{pst}) {
        return(0, $time, "unknown");
    }

    if (lc($status->{pst}) eq "oos") {
        return(0, $time, "down");
    } elsif (lc($status->{pst}) eq "is") {
        return(0, $time, "up");
    } else {
        return(0, $time, "unknown");
    }
}

sub run_sect {
    my ($self) = @_;
    my ($status, $time);

    $status = $self->{AGENT}->getSect($self->{ELEMENT_ID});

    $time = $self->{AGENT}->getCacheTime();

    # operational state

    # For facility management commands and reports (Chapter 14), indicates the operational state of the facil ity. The secondary state can be a combination of one or more states, listed using the ampersand (&), not the plus sign (+). 
    # ACT is active. 
    # DSBLD is disabled. 
    # LPBK is loopback. 
    # SLAT is system lineup and testing. 
    # TS is test access. 
    # For Ethernet reports, the <sst> value can be ACT or IDLE. The default value is IDLE.

    if (not $status->{sst}) {
        return(0, $time, "unknown");
    }

    if (lc($status->{pst}) eq "oos") {
        return(0, $time, "down");
    }

    my @states = split('&', $status->{sst});

    my %mapping = (
        act => "up",
        dsbld => "down",
        lpbk => "down",
        slat => "down",
        ts => "down",
    );

    my $oper_status;
    foreach my $state (@states) {
        my $curr_status;

        if (not $mapping{lc($state)}) {
            $curr_status = "unknown";
        } else {
            $curr_status = $mapping{lc($state)};
        }


        if (not $oper_status) {
            $oper_status = $curr_status;
        } elsif ($curr_status eq "unknown") {
            $oper_status = $curr_status;
        } elsif ($curr_status eq "down" and $oper_status eq "up") {
            $oper_status = $curr_status;
        }
    }

    return(0, $time, $oper_status);
}

sub run_ocn {
    my ($self) = @_;
    my ($status, $time);

    if ($self->{ELEMENT_ID_TYPE} eq "name") {
        $status = $self->{AGENT}->getOCNByName($self->{ELEMENT_ID});
    } else {
        $status = $self->{AGENT}->getOCN($self->{ELEMENT_ID});
    }

    $time = $self->{AGENT}->getCacheTime();

    # operational state

    # For facility management commands and reports (Chapter 14), indicates the operational state of the facil ity. The secondary state can be a combination of one or more states, listed using the ampersand (&), not the plus sign (+). 
    # ACT is active. 
    # DSBLD is disabled. 
    # LPBK is loopback. 
    # SLAT is system lineup and testing. 
    # TS is test access. 
    # For Ethernet reports, the <sst> value can be ACT or IDLE. The default value is IDLE.

    if (not $status->{sst}) {
        return(0, $time, "unknown");
    }

    if (lc($status->{pst}) eq "oos") {
        return(0, $time, "down");
    }

    my @states = split('&', $status->{sst});

    my %mapping = (
        act => "up",
        dsbld => "down",
        lpbk => "down",
        slat => "down",
        ts => "down",
    );

    my $oper_status;
    foreach my $state (@states) {
        my $curr_status;

        if (not $mapping{lc($state)}) {
            $curr_status = "unknown";
        } else {
            $curr_status = $mapping{lc($state)};
        }


        if (not $oper_status) {
            $oper_status = $curr_status;
        } elsif ($curr_status eq "unknown") {
            $oper_status = $curr_status;
        } elsif ($curr_status eq "down" and $oper_status eq "up") {
            $oper_status = $curr_status;
        }
    }

    return(0, $time, $oper_status);
}

sub run_crossconnect {
    my ($self) = @_;
    my $status = $self->{AGENT}->getCrossconnect($self->{ELEMENT_ID});
    my $time = $self->{AGENT}->getCacheTime();

    # <sst> is LPBK, TS, CLPBK, ACTIVE, SWITCHED, BRIDGED, or ROLL (for connection management commands and reports) 
    my %mapping = (
        lpbk => "down",
        ts => "down",
        clpbk => "down",
        roll => "up",
        active => "up",
    );

    my $oper_status;

    if (not $status->{sst} or $mapping{lc($status->{sst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $mapping{lc($status->{sst})};
    }

    return(0, $time, $oper_status);
}

sub run {
    my ($self) = @_;

    if ($self->{ELEMENT_TYPE} eq "crossconnect") {
        return $self->run_crossconnect();
    } elsif ($self->{ELEMENT_TYPE} eq "sect") {
        return $self->run_sect();
    } elsif ($self->{ELEMENT_TYPE} eq "line") {
        return $self->run_line();
    } elsif ($self->{ELEMENT_TYPE} eq "ocn") {
        return $self->run_ocn();
    }
}

sub type {
    my ($self, $type) = @_;

    if ($type) {
        $self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

sub agent {
    my ($self, $agent) = @_;

    if ($agent) {
        $self->{AGENT} = $agent;
    }

    return $self->{AGENT};
}

sub element_id {
    my ($self, $element_id) = @_;

    if ($element_id) {
        $self->{ELEMENT_ID} = $element_id;
    }

    return $self->{ELEMENT_ID};
}

sub element_type {
    my ($self, $element_type) = @_;

    if ($element_type and ($element_type eq "sect" or $element_type eq "line" or $element_type eq "ocn" or $element_type eq "crossconnect")) {
        $self->{ELEMENT_TYPE} = $element_type;
    }

    return $self->{ELEMENT_TYPE};
}

sub element_id_type {
    my ($self, $element_id_type) = @_;

    if ($element_id_type and ($element_id_type eq "name" or $element_id_type eq "aid")) {
        $self->{ELEMENT_ID_TYPE} = $element_id_type;
    }

    return $self->{ELEMENT_ID_TYPE};
}

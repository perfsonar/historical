package perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::HDXc;


use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::TL1::HDXc;

our $VERSION = 0.09;

use fields 'AGENT', 'TYPE', 'LOGGER', 'FACILITY_TYPE', 'FACILITY_NAME', 'FACILITY_NAME_TYPE';

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
            facility_name => 1,
            facility_name_type => 0,
            facility_type => 1,
            });

    my $self = fields::new($class);

    $self->{LOGGER} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1");

    # we need to be able to generate a new tl1 agent or reuse an existing one. Not neither.
    if (not $parameters->{agent} and
             (not $parameters->{address} or
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
                    cache_time => 30
                );
    }

    $self->type($parameters->{type});
    $self->agent($parameters->{agent});
    my $res = $self->set_element({ type => $parameters->{facility_type}, id => $parameters->{facility_name}, id_type => $parameters->{facility_name_type} });
	if (not $res) {
		$self->{LOGGER}->error("Invalid element type");
		return;
	}

    return $self;
}

sub run_line {
    my ($self) = @_;
    my ($status, $time);

    if ($self->{FACILITY_NAME_TYPE} eq "name") {
        $status = $self->{AGENT}->getLineByName($self->{FACILITY_NAME});
    } else {
        $status = $self->{AGENT}->getLine($self->{FACILITY_NAME});
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

    $status = $self->{AGENT}->getSect($self->{FACILITY_NAME});

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

    if ($self->{FACILITY_NAME_TYPE} eq "name") {
        $status = $self->{AGENT}->getOCNByName($self->{FACILITY_NAME});
    } else {
        $status = $self->{AGENT}->getOCN($self->{FACILITY_NAME});
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
    my $status = $self->{AGENT}->getCrossconnect($self->{FACILITY_NAME});
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

    if ($self->{FACILITY_TYPE} eq "crossconnect") {
        return $self->run_crossconnect();
    } elsif ($self->{FACILITY_TYPE} eq "sect") {
        return $self->run_sect();
    } elsif ($self->{FACILITY_TYPE} eq "line") {
        return $self->run_line();
    } elsif ($self->{FACILITY_TYPE} =~ /^oc(n|[0-9]+)/) {
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

sub set_element {
    my ($self, @params) = @_;

    my $parameters = validateParams(@params,
            {
            type => 1,
            id => 1,
            id_type => 0,
            });


    unless ($parameters->{type} eq "sect" or $parameters->{type} eq "line" or $parameters->{type} =~ /^oc(n|[0-9]+)/ or $parameters->{type} eq "crossconnect") {
        return undef;
    }

	$self->{FACILITY_NAME} = $parameters->{id};
	$self->{FACILITY_TYPE} = $parameters->{type};

	if ($parameters->{type} eq "sect") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid" ) {
				return undef;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "aid";
	} elsif ($parameters->{type} eq "line") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid" or $parameters->{id_type} eq "name") {
				return undef;
			}

			$self->{FACILITY_NAME_TYPE} = $parameters->{id_type};
		} else {
			$self->{FACILITY_NAME_TYPE} = "aid";
		}
	} elsif ($parameters->{type} =~ /^oc(n|[0-9]+)/) {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid" or $parameters->{id_type} eq "name") {
				return undef;
			}

			$self->{FACILITY_NAME_TYPE} = $parameters->{id_type};
		} else {
			$self->{FACILITY_NAME_TYPE} = "aid";
		}
	} elsif ($parameters->{type} eq "crossconnect") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return undef;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	}

    return $self->{FACILITY_NAME};
}

sub facility_name {
    my ($self) = @_;

    return $self->{FACILITY_NAME};
}

sub facility_type {
    my ($self) = @_;
	
	return $self->{FACILITY_TYPE};
}

sub facility_name_type {
    my ($self) = @_;

    return $self->{FACILITY_NAME_TYPE};
}

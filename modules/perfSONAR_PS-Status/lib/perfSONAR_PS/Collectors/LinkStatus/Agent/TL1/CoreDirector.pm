package perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::CoreDirector;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::TL1::CoreDirector;
use Data::Dumper;

our $VERSION = 0.09;

use fields 'AGENT', 'TYPE', 'LOGGER', 'FACILITY_TYPE', 'FACILITY_NAME', 'FACILITY_NAME_TYPE';

my %state_mapping = (
		"is-anr" => "degraded",
		"is-nr" => "up",
		"oos-au" => "down",
		"oos-auma" => "down",
		"oos-ma" => "down",
		);

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

    $self->{LOGGER} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::CoreDirector");

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
	$parameters->{agent} = perfSONAR_PS::Utils::TL1::CoreDirector->new();
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
		return;
	}


    return $self;
}

=head2
	Locates the cross-connect named (either alias or cktid) and returns its
	current status mapped to one of up, down or degraded.
=cut
sub checkCrossconnect {
	my ($self, $name) = @_;

	my $crss = $self->{AGENT}->getCrossconnect();
	foreach my $crs_key (keys %$crss) {
		my $crs = $crss->{$crs_key};

		if ($crs->{cktid} eq $self->{FACILITY_NAME} or $crs->{name} eq $self->{FACILITY_NAME}) {
			my $oper_status;

			unless ($crs->{pst} and $state_mapping{lc($crs->{pst})}) {
				$oper_status = "unknown";
			} else {
				$oper_status = $state_mapping{lc($crs->{pst})};
			}

			return(0, time, $oper_status);
		}
	}

	my $msg = "Couldn't find requested cross-connect";
	$self->{LOGGER}->error($msg);
	return (-1, $msg);
}

# Checks a EFLOW (used for VLANs) by seeing if it's constituent pieces are up/down.
sub checkEFLOW {
	my ($self, $id, $id_type) = @_;

	my ($name, $port, $vlan);

	if ($id_type eq "vlan") {
		($port, $vlan) = split("|", $id);
	} else {
		$name = $id;
	}

	my $eflows = $self->{AGENT}->getEFLOW();
	if (not $eflows) {
		my $msg = "Couldn't lookup requested eflow";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	foreach my $eflow_key (keys %$eflows) {
		my $eflow = $eflows->{$eflow_key};

		# skip the invalid eflows
		next unless (not $vlan or ($eflow->{"outervlanidrange"} and $eflow->{"outervlanidrange"} eq $vlan));

		next unless (not $port or ($eflow->{ingressportname} eq $port or $eflow->{egressportname} eq $port));

		next unless (not $name or $eflow_key eq $name);

		my $oper_status = "up";

		foreach my $type ("ingressport", "egressport") {
			my ($status, $time, $new_oper_status);

			if ($eflow->{$type."type"} eq "VCG") {
				($status, $time, $new_oper_status) = $self->{AGENT}->checkVCG($eflow->{$type."name"});
			} elsif ($eflow->{$type."type"} eq "ETTP") {
				($status, $time, $new_oper_status) = $self->{AGENT}->checkGIGE($eflow->{$type."name"});
			} else {
				return (0, time, "unknown");
			}

			if ($status == -1) {
				return (0, time, "unknown");
			}

			if ($new_oper_status eq "unknown" or $new_oper_status eq "down") {
				return (0, time, $new_oper_status);
			}

			if ($new_oper_status eq "degraded") {
				$oper_status = "degraded";
			}
		}

		return (0, time, $oper_status);
	}

	my $msg = "Couldn't find requested eflow, assuming it's down";
	$self->{LOGGER}->warn($msg);
	return (0, time, "down");
}

sub checkVCG {
    my ($self, $vcg_name) = @_;

    my $vcgs = $self->{AGENT}->getVCG();
	if (not $vcgs) {
		my $msg = "Couldn't look up VCG";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	foreach my $vcg_id (keys %$vcgs) {
		my $vcg = $vcgs->{$vcg_id};

		if ($vcg_name eq $vcg_id or $vcg->{alias} eq $vcg_name) {
			my $oper_status;

			unless ($vcg->{pst} and $state_mapping{lc($vcg->{pst})}) {
				$oper_status = "unknown";
			} else {
				$oper_status = $state_mapping{lc($vcg->{pst})};
			}

			return(0, time, $oper_status);
		}
	}

	my $msg = "Couldn't find requested VCG";
	$self->{LOGGER}->error($msg);
	return (-1, $msg);
}

sub checkGIGE {
    my ($self, $eth_name) = @_;

    my $eths = $self->{AGENT}->getGIGE();
	if (not $eths) {
		my $msg = "Couldn't look up Ethernet Port";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	foreach my $eth_id (keys %$eths) {
		my $eth = $eths->{$eth_id};

		if ($eth_name eq $eth_id or $eths->{$eth_id}->{alias} eq $eth_name) {
			my $oper_status;

			unless ($eth->{pst} and $state_mapping{lc($eth->{pst})}) {
				$oper_status = "unknown";
			} else {
				$oper_status = $state_mapping{lc($eth->{pst})};
			}

			return(0, time, $oper_status);
		}
	}

	my $msg = "Couldn't find requested VCG";
	$self->{LOGGER}->error($msg);
	return (-1, $msg);
}

sub checkOptical {
    my ($self, $aid) = @_;
    my $optical = $self->{AGENT}->getOCN($aid);

	if (not $optical) {
		my $msg = "Couldn't look up Optical Port";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

    my $oper_status;

    unless ($optical->{pst} and $state_mapping{lc($optical->{pst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $state_mapping{lc($optical->{pst})};
    }

    return(0, time, $oper_status);

}

sub checkSNC {
    my ($self, $name) = @_;
    my $status = $self->{AGENT}->getSNC($self->{FACILITY_NAME});

    my $oper_status;

    unless ($status->{pst} and $state_mapping{lc($status->{pst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $state_mapping{lc($status->{pst})};
    }

    return(0, time, $oper_status);
}

sub checkGTP {
    my ($self, $name) = @_;
    my $status = $self->{AGENT}->getGTP($self->{FACILITY_NAME});

    my $oper_status;

    unless ($status->{pst} and $state_mapping{lc($status->{pst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $state_mapping{lc($status->{pst})};
    }

    return(0, time, $oper_status);
}

sub run {
    my ($self) = @_;

    $self->{LOGGER}->debug("Running status collector on ".$self->{FACILITY_TYPE}."/".$self->{FACILITY_NAME});

    if ($self->{FACILITY_TYPE} eq "crossconnect") {
        return $self->checkCrossconnect($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} eq "vcg") {
        return $self->checkVCG($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} eq "vlan") {
        return $self->checkEFLOW($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} eq "eflow") {
        return $self->checkEFLOW($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} =~ /^oc(n|[0-9]+)/) {
        return $self->checkOptical($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
	} elsif ($self->{FACILITY_TYPE} =~ /gige/) {
        return $self->checkGIGE($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} eq "snc") {
        return $self->checkSNC($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
    } elsif ($self->{FACILITY_TYPE} eq "gtp") {
        return $self->checkGTP($self->{FACILITY_NAME}, $self->{FACILITY_NAME_TYPE});
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

	$parameters->{type} = lc($parameters->{type});
	$parameters->{id_type} = lc($parameters->{id_type}) if ($parameters->{id_type});

	if ($parameters->{type} eq "gtp") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} eq "eflow") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} eq "crossconnect") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} eq "snc") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} eq "vcg") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name" ) {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} =~ /^oc(n|[0-9]+)/) {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid") {
				return;
			}
		}
		$self->{FACILITY_NAME_TYPE} = "aid";
	} elsif ($parameters->{type} =~ /^(eth|gige)/) {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid") {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "aid";
	} elsif ($parameters->{type} eq "eflow") {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "name") {
				return;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "name";
	} elsif ($parameters->{type} eq "vlan") {
		unless ($parameters->{id} =~ /|/) {
			return;
		}

		$self->{FACILITY_NAME_TYPE} = "logical";
	} else {
		$self->{LOGGER}->error("Unknown element type: '".$parameters->{type}."'");
		return;
    }

	$self->{FACILITY_NAME} = $parameters->{id};
	$self->{FACILITY_TYPE} = $parameters->{type};

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

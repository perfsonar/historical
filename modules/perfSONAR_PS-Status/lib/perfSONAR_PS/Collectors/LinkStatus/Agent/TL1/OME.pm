package perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME;


use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::TL1::OME;
use Data::Dumper;

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
	$parameters->{agent} = perfSONAR_PS::Utils::TL1::OME->new();
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
		$self->{LOGGER}->error("Invalid element type: ".$parameters->{facility_type});
		return;
	}

    return $self;
}

sub run_eth {
    my ($self) = @_;
    my ($status, $time);

# pst
# IS In Service 
# IS-ANR In Service - Abnormal 
# OOS-MA Out-of-service maintenance for provisioning memory administration 
# OOS-AU Out-of-service autonomous from a failure detected point of view. It is not out of service from a state point of view. Alarm is raised if the entity is not able to perform its provisioned functions 
# OOS-AUMA Out-of-service autonomous management - the entity is not able to perform its provisioned functions and is purposefully removed from service 
# OOS-MAANR Out-of-service maintenance - abnormal. 

# sst
# ACT Active, carrying traffic 
# DISCD Idle, not carrying traffic 
# FLT Fault detected in equipment 
# SGEO Supporting entity outage 
# WRKRX Working in the receive direction 
# WRKTX Working in the transmit direction 
# DSBLD Missing layer 2 connection; Idle, not carrying traffic 

    my %mapping = (
        "is" => "up",
	"is-anr" => "degraded",
	"oos-ma" => "down",
	"oos-au" => "down",
	"oos-auma" => "down",
	"oos-maanr" => "down",
    );

    $status = $self->{AGENT}->getETH($self->{FACILITY_NAME});
    $time = $self->{AGENT}->getCacheTime();

    $self->{LOGGER}->debug(Dumper($status));

    if (not $status->{pst}) {
        return(0, $time, "unknown");
    }

    my $oper_status;

    unless ($status->{pst} and $mapping{lc($status->{pst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $mapping{lc($status->{pst})};
    }

    return(0, $time, $oper_status);
}

sub run_ocn {
    my ($self) = @_;
    my ($status, $time);

# pst
# IS In Service
# IS-ANR In Service - Abnormal 
# OOS-MA Out-of-service maintenance for provisioning memory administration 
# OOS-AU Out-of-service autonomous from a failure detected point of view. It is not out of service from a state point of view. Alarm is raised if the entity is not able to perform its provisioned functions 
# OOS-AUMA Out-of-service autonomous management - the entity is not able to perform its provisioned functions and is purposefully removed from service 
# OOS-MAANR Out-of-service maintenance - abnormal. 

# sst
# DISCD Disconnected (no cross-connects exist on facility) 
# LPBK Loopback 
# FLT Fault detected in equipment 
# TS Test 
# SGEO Supporting entity outage 
# WRKRX Working in the receive direction 
# WRKTX Working in the transmit direction 

    my %mapping = (
        "is" => "up",
	"is-anr" => "degraded",
	"oos-ma" => "down",
	"oos-au" => "down",
	"oos-auma" => "down",
	"oos-maanr" => "down",
    );

    $status = $self->{AGENT}->getOCN($self->{FACILITY_NAME});
    $time = $self->{AGENT}->getCacheTime();

    $self->{LOGGER}->debug("PST: '".$status->{pst}."'");
    $self->{LOGGER}->debug("SST: '".$status->{sst}."'");

    my $oper_status;

    unless ($status->{pst} and $mapping{lc($status->{pst})}) {
        $oper_status = "unknown";
    } else {
        $oper_status = $mapping{lc($status->{pst})};
    }

    return(0, $time, $oper_status);
}

sub run {
    my ($self) = @_;

    if ($self->{FACILITY_TYPE} =~ /^eth/) {
        return $self->run_eth();
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

	$parameters->{type} = lc($parameters->{type});
	$parameters->{id_type} = lc($parameters->{id_type}) if ($parameters->{id_type});

    unless ($parameters->{type} =~ /^eth/ or $parameters->{type} =~ /^oc(n|[0-9]+)/) {
		$self->{LOGGER}->error("Unknown element type: '".$parameters->{type}."'");
		return;
    }

	$self->{FACILITY_NAME} = $parameters->{id};
	$self->{FACILITY_TYPE} = $parameters->{type};

	if ($parameters->{type} =~ /^oc(n|[0-9]+)/) {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid") {
				return undef;
			}
		}
		$self->{FACILITY_NAME_TYPE} = "aid";
	} elsif ($parameters->{type} =~ /^eth/) {
		if ($parameters->{id_type}) {
			unless ($parameters->{id_type} eq "aid") {
				return undef;
			}
		}

		$self->{FACILITY_NAME_TYPE} = "aid";
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

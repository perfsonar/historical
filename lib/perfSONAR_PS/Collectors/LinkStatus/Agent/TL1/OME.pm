package perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME;


use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Utils::TL1::OME;
use Data::Dumper;

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
	$parameters->{agent} = perfSONAR_PS::Utils::TL1::OME->new();
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

    $status = $self->{AGENT}->getETH($self->{ELEMENT_ID});
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

    $status = $self->{AGENT}->getOCN($self->{ELEMENT_ID});
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

    if ($self->{ELEMENT_TYPE} eq "eth") {
        return $self->run_eth();
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

    if ($element_type and ($element_type eq "ocn" or $element_type eq "eth")) {
        $self->{ELEMENT_TYPE} = $element_type;
    }

    return $self->{ELEMENT_TYPE};
}

sub element_id_type {
    my ($self, $element_id_type) = @_;

    if ($element_id_type and $element_id_type eq "aid") {
        $self->{ELEMENT_ID_TYPE} = $element_id_type;
    }

    return $self->{ELEMENT_ID_TYPE};
}

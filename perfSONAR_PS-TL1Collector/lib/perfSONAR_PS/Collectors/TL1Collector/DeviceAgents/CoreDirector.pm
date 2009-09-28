package perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::CoreDirector;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::CoreDirector

=head1 DESCRIPTION

This module polls a Ciena CoreDirector using TL1 for the operational and administrative
status of its facilities. It will grab the operational and administrative status of all the
facilities it's been configured to handle and store that information into a
status database.

=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::TL1::CoreDirector;
use perfSONAR_PS::Status::Common;
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use base 'perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::Base';

use fields 'AGENT', 'OPTICAL_FACILITIES', 'ETHERNET_FACILITIES', 'VLAN_FACILITIES', 'EFLOW_FACILITIES', 'VCG_FACILITIES', 'CROSSCONNECT_FACILTIES', 'CHECK_ALL_OPTICAL_PORTS', 'CHECK_ALL_VLANS', 'CHECK_ALL_ETHERNET_PORTS', 'CHECK_ALL_CROSSCONNECTS', 'CHECK_ALL_EFLOWS', 'CHECK_ALL_VCGS', 'ROUTER_ADDRESS';

# Oper Status:
# 1 = up
# 2 = down
# 3 = degraded

# Admin Status:
# 1 = normaloperation
# 3 = maintenance
my %state_mapping = (
    "is-nr"    => { "oper_status" => 1,     "admin_status" => 1 },
    "is-anr"   => { "oper_status" => 3,     "admin_status" => 1 },
    "oos-au"   => { "oper_status" => 2,     "admin_status" => 1 },
    "oos-auma" => { "oper_status" => 2,     "admin_status" => 3 },
    "oos-ma"   => { "oper_status" => 2,     "admin_status" => 3 },
);

=head2 init( $self, { data_client, polling_interval, address, port, username, password, check_all_optical_ports, check_all_vlans, check_all_ethernet_ports, check_all_crossconnects, check_all_eflows, check_all_vcgs, facilities, identifier_pattern } )

TBD

=cut

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client              => 1,
            polling_interval         => 0,
            address                  => 1,
            port                     => 0,
            username                 => 1,
            password                 => 1,
            check_all_optical_ports  => 0,
            check_all_vlans          => 0,
            check_all_ethernet_ports => 0,
            check_all_crossconnects  => 0,
            check_all_eflows         => 0,
            check_all_vcgs           => 0,
            vlan_facilities          => 0,
            ethernet_facilities      => 0,
            optical_facilities       => 0,
            crossconnect_facilities  => 0,
            eflow_facilities         => 0,
            vcg_facilities           => 0,
            identifier_pattern       => 0,
        }
    );

    my $n = $self->SUPER::init( { data_client => $args->{data_client}, identifier_pattern => $args->{identifier_pattern}, polling_interval => $args->{polling_interval} } );
    if ( $n == -1 ) {
        return -1;
    }

    $self->{CHECK_ALL_OPTICAL_PORTS}  = $args->{check_all_optical_ports};
    $self->{CHECK_ALL_ETHERNET_PORTS} = $args->{check_all_ethernet_ports};
    $self->{CHECK_ALL_CROSSCONNECTS}  = $args->{check_all_crossconnects};
    $self->{CHECK_ALL_VLANS}          = $args->{check_all_vlans};
    $self->{CHECK_ALL_EFLOWS}         = $args->{check_all_eflows};
    $self->{CHECK_ALL_VCGS}           = $args->{check_all_vcgs};

    $self->{OPTICAL_FACILITIES}     = ();
    if ($args->{optical_facilities}) {
        $self->{OPTICAL_FACILITIES}     = $args->{optical_facilities};
    }

    $self->{CROSSCONNECT_FACILTIES} = ();
    if ($args->{crossconnect_facilities}) {
        $self->{CROSSCONNECT_FACILTIES}     = $args->{crossconnect_facilities};
    }

    $self->{ETHERNET_FACILITIES}    = ();
    if ($args->{ethernet_facilities}) {
        $self->{ETHERNET_FACILITIES}     = $args->{ethernet_facilities};
    }

    $self->{VLAN_FACILITIES}        = ();
    if ($args->{vlan_facilities}) {
        $self->{VLAN_FACILITIES}     = $args->{vlan_facilities};
    }

    $self->{EFLOW_FACILITIES}       = ();
    if ($args->{eflow_facilities}) {
        $self->{EFLOW_FACILITIES}     = $args->{eflow_facilities};
    }

    $self->{VCG_FACILITIES}         = ();
    if ($args->{vcg_facilities}) {
        $self->{VCG_FACILITIES}     = $args->{vcg_facilities};
    }

    $self->{AGENT} = perfSONAR_PS::Utils::TL1::CoreDirector->new();
    $self->{AGENT}->initialize(
        username   => $args->{username},
        password   => $args->{password},
        address    => $args->{address},
        port       => $args->{port},
        cache_time => 30
    );

    my $check_all = ( $self->{CHECK_ALL_CROSSCONNECTS} or $self->{CHECK_ALL_ETHERNET_PORTS} or $self->{CHECK_ALL_EFLOWS} or $self->{CHECK_ALL_VLANS} or $self->{CHECK_ALL_OPTICAL_PORTS} );
    if ( $check_all and ( not $self->{IDENTIFIER_PATTERN} or $self->{IDENTIFIER_PATTERN} !~ /%facility%/ ) ) {
        my $msg = "Performing generic facilities check, but invalid identifier pattern specified";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    $self->{ROUTER_ADDRESS} = $args->{address};

    return 0;
}

=head2 check_facilities( $self )

A function which is called by the Base class to check on the status of
faciltiies. The function checks all the facilities identified, and returns an
array of hashes describing each facility and its status.

=cut

sub check_facilities {
    my ( $self ) = @_;

    my @ret_counters = ();

    my ($status, $res);

    ($status, $res) = $self->handle_ethernet_ports();
    if ($status == 0) {
        foreach my $counter (@{ $res }) {
            push @ret_counters, $counter;
        }
    }

    ($status, $res) = $self->handle_optical_ports();
    if ($status == 0) {
        foreach my $counter (@{ $res }) {
            push @ret_counters, $counter;
        }
    }

    ($status, $res) = $self->handle_vlan_ports();
    if ($status == 0) {
        foreach my $counter (@{ $res }) {
            push @ret_counters, $counter;
        }
    }

    return ( 0, \@ret_counters);
}

sub handle_ethernet_ports {
    my ($self) = @_;

    my @ret_counters = ();

    $self->{LOGGER}->debug("handle_ethernet_ports(): start");

    if ( $self->{CHECK_ALL_ETHERNET_PORTS} or scalar( keys %{ $self->{ETHERNET_FACILITIES} } ) > 0 ) {
        my @ports = ();
        if ( $self->{CHECK_ALL_ETHERNET_PORTS} ) {
            my ( $status, $ports ) = $self->{AGENT}->get_ethernet_facilities();
            if ( $status == 0 ) {
                @ports = keys %{$ports};
            } else {
                $self->{LOGGER}->error("Error looking up ethernet ports: $ports");
            }
        }
        else {
            foreach my $fac (keys %{ $self->{ETHERNET_FACILITIES} }) {
                next if ($fac eq "*");
                push @ports, $fac;
            }
        }

        $self->{LOGGER}->debug("Checking ports: ".join(",", @ports));

        foreach my $port (@ports) {
            my ($status, $res) = $self->handle_ethernet_port($port);
            if ($status != 0) {
                return ($status, $res);
            }

            foreach my $counter (@{ $res }) {
                push @ret_counters, $counter;
            }
        }
    }

    $self->{LOGGER}->debug("handle_ethernet_ports(): stop");


    return (0, \@ret_counters);
}

sub handle_ethernet_port {
    my ( $self, $port_name ) = @_;

    my @ret_counters = ();

    my ( $status, $res, $port );
    ( $status, $port ) = $self->{AGENT}->get_ethernet_facilities( $port_name );
    if ( $status == -1 or not $port ) {
        my $msg = "Couldn't look up Ethernet Port";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $oper_status;
    my $admin_status;

    unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
        $oper_status  = "unknown";
        $admin_status = "unknown";
    }
    else {
        $oper_status  = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
        $admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
    }

    my ($in_octets, $out_octets, $in_packets, $out_packets, $in_errors, $out_errors, $in_discards, $out_discards);
    ($status, $res) = $self->{AGENT}->get_ethernet_mib_pms($port_name);
    if ($status == 0) {
        $in_packets = $res->{INTF_IN_PACKETS}->{value};
        $out_packets = $res->{INTF_OUT_PACKETS}->{value};
        $in_octets = $res->{INTF_IN_OCTETS}->{value};
        $out_octets = $res->{INTF_OUT_OCTETS}->{value};
        $in_discards = $res->{INTF_IN_DISCARDS}->{value};
        $out_discards = $res->{INTF_OUT_DISCARDS}->{value};
        $in_errors = $res->{INTF_IN_ERRORS}->{value};
        $out_errors = $res->{INTF_OUT_ERRORS}->{value};
    }

    my ( $capacity );
    # capacity is in Bps
    if ($port->{etherphy} =~ "10000") {
        $capacity = 10_000_000_000; 
    } elsif ($port->{etherphy} =~ "1000") {
        $capacity = 1_000_000_000;
    } elsif ($port->{etherphy} =~ "100") {
        $capacity = 100_000_000;
    }

    my ( $id );

    if ( $self->{ETHERNET_FACILITIES}->{ '*' } ) {
        $id           = $self->{ETHERNET_FACILITIES}->{ '*' }->{id}           if ( $self->{ETHERNET_FACILITIES}->{ '*' }->{id} );
        $admin_status = $self->{ETHERNET_FACILITIES}->{ '*' }->{admin_status} if ( $self->{ETHERNET_FACILITIES}->{ '*' }->{admin_status} );
        $oper_status  = $self->{ETHERNET_FACILITIES}->{ '*' }->{oper_status}  if ( $self->{ETHERNET_FACILITIES}->{ '*' }->{oper_status} );
    }

    if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} } ) {
        $id           = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{id}           if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{id} );
        $admin_status = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{admin_status} if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{admin_status} );
        $oper_status  = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{oper_status}  if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{oper_status} );
    }

    # Add 'utilization' counters
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_utilization})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_utilization}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name},  direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                     values      => { utilization => $in_octets },
        };

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name},  direction => "out" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                     values      => { utilization => $out_octets },
        };
    }

    # Add 'discard' counters
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_discards})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_discards}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name},  direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                     values      => { discards => $in_discards },
        };

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name},  direction => "out" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                     values      => { discards => $out_discards },
        };
    }

    # Add 'error' counters
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_errors})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_errors}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name},  direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/errors/2.0",
                     values      => { errors => $in_errors },
        };
    }

    # Add 'oper' status
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_oper_status})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_oper_status}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name}, description => $port->{alias} },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0",
                     values      => { oper_status => $oper_status },
        };
    }

    # Add 'admin' status
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_admin_status})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_admin_status}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name}, description => $port->{alias} },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0",
                     values      => { admin_status => $admin_status },
        };
    }

    # Add Port Capacity
    if ( ($self->{ETHERNET_FACILITIES}->{ $port->{name} } and $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{collect_capacity})
            or ($self->{ETHERNET_FACILITIES}->{ '*' } and $self->{ETHERNET_FACILITIES}->{ '*' }->{collect_capacity}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name}, description => $port->{alias} },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/capacity/provisioned/2.0",
                     values      => { capacity => $capacity },
        };
    }

   return (0, \@ret_counters);
}

sub handle_optical_ports {
    my ($self) = @_;

    my @ret_counters = ();

    $self->{LOGGER}->debug("handle_optical_ports(): start");

    if ( $self->{CHECK_ALL_OPTICAL_PORTS} or scalar( keys %{ $self->{OPTICAL_FACILITIES} } ) > 0 ) {
        my @ports = ();
        if ( $self->{CHECK_ALL_OPTICAL_PORTS} ) {
            my ( $status, $ports ) = $self->{AGENT}->get_optical_facilities();
            if ( $status == 0 ) {
                @ports = keys %{$ports};
            } else {
                $self->{LOGGER}->error("Error looking up optical ports: $ports");
            }
        }
        else {
            foreach my $fac (keys %{ $self->{OPTICAL_FACILITIES} }) {
                next if ($fac eq "*");
                push @ports, $fac;
            }
        }

        $self->{LOGGER}->debug("Checking ports: ".join(",", @ports));

        foreach my $port (@ports) {
            my ($status, $res) = $self->handle_optical_port($port);
            if ($status != 0) {
                return ($status, $res);
            }

            foreach my $counter (@{ $res }) {
                push @ret_counters, $counter;
            }
        }
    }

    $self->{LOGGER}->debug("handle_optical_ports(): stop");


    return (0, \@ret_counters);
}

sub handle_optical_port {
    my ( $self, $port_name ) = @_;

    my @ret_counters = ();

    my ( $status, $res, $port );
    ( $status, $port ) = $self->{AGENT}->get_optical_facilities( $port_name );
    if ( $status == -1 or not $port ) {
        my $msg = "Couldn't look up Optical Port: $port_name, $port";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $oper_status;
    my $admin_status;

    unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
        $oper_status  = "unknown";
        $admin_status = "unknown";
    }
    else {
        $oper_status  = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
        $admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
    }

    my ( $capacity );
    # capacity is in Bps
    if ($port->{rate} =~ /OC(\d+)/) {
        $capacity = $1*51_800_000;
    }

    my ( $id );
    if ( $self->{OPTICAL_FACILITIES}->{ '*' } ) {
        $id           = $self->{OPTICAL_FACILITIES}->{ '*' }->{id}           if ( $self->{OPTICAL_FACILITIES}->{ '*' }->{id} );
        $admin_status = $self->{OPTICAL_FACILITIES}->{ '*' }->{admin_status} if ( $self->{OPTICAL_FACILITIES}->{ '*' }->{admin_status} );
        $oper_status  = $self->{OPTICAL_FACILITIES}->{ '*' }->{oper_status}  if ( $self->{OPTICAL_FACILITIES}->{ '*' }->{oper_status} );
    }

    if ( $self->{OPTICAL_FACILITIES}->{ $port->{name} } ) {
        $id           = $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{id}           if ( $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{id} );
        $admin_status = $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{admin_status} if ( $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{admin_status} );
        $oper_status  = $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{oper_status}  if ( $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{oper_status} );
    }

    # Oper/Admin status
    if ( ($self->{OPTICAL_FACILITIES}->{ $port->{name} } and $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{collect_oper_status})
            or ($self->{OPTICAL_FACILITIES}->{ '*' } and $self->{OPTICAL_FACILITIES}->{ '*' }->{collect_oper_status}) ) {
        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name}, description => $port->{alias}, capacity => $capacity },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0",
                     values      => { oper_status => $oper_status },
        };
    }

    if ( ($self->{OPTICAL_FACILITIES}->{ $port->{name} } and $self->{OPTICAL_FACILITIES}->{ $port->{name} }->{collect_admin_status})
            or ($self->{OPTICAL_FACILITIES}->{ '*' } and $self->{OPTICAL_FACILITIES}->{ '*' }->{collect_admin_status}) ) {
        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $port->{name}, description => $port->{alias}, capacity => $capacity },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0",
                     values      => { admin_status => $admin_status },
        };
    }

   return (0, \@ret_counters);
}

sub handle_vlan_ports {
    my ( $self ) = @_;

    unless ( $self->{CHECK_ALL_VLANS} or scalar(keys %{ $self->{VLAN_FACILITIES} }) > 0 ) {
        my @tmp = ();
        return (0, \@tmp);
    }

    my @ret_counters = ();

    my ( $status, $res) = $self->{AGENT}->get_eflows();

    if ( $status != 0 ) {
        return ($status, $res);
    }

    my $eflows = $res;
    my %vlan_elements = ();

    foreach my $eflow_key ( keys %{$eflows} ) {
        my $eflow = $eflows->{$eflow_key};

        $self->{LOGGER}->debug("EFLOW: ".Dumper($eflow));

        unless ( $eflow->{"collectpm"} eq "YES" ) {   # we only care about monitored vlans
            $self->{LOGGER}->debug("Skipping $eflow_key");
            next;
        }

        my $vlan;
        if ($eflow->{"outervlanid"} and $eflow->{"outervlanid"} ne "0" and $eflow->{"outervlanid"} ne "1") {
            $vlan = $eflow->{"outervlanid"};
        } elsif ($eflow->{"outervlanidrange"} and $eflow->{"outervlanidrange"} ne "0" and $eflow->{"outervlanidrange"} ne "1") {
            $vlan = $eflow->{"outervlanidrange"};
        } else {
            $vlan = "untagged";
        }

        my ($vlan_name, $direction, $vcg_name);

        if ( $eflow->{ingressporttype} eq "ETTP" ) {
            $vlan_name = $eflow->{ingressportname} . "." . $vlan;
            $direction = "in_eflow";
        }
        elsif ( $eflow->{egressporttype} eq "ETTP" ) {
            $vlan_name = $eflow->{egressportname} . "." . $vlan;
            $direction = "out_eflow";
        }

        if ($eflow->{ingressporttype} eq "VCG") {
            $vcg_name = $eflow->{ingressportname};
        } elsif ($eflow->{egressporttype} eq "VCG") {
            $vcg_name = $eflow->{egressportname};
        }

        next unless ( $self->{CHECK_ALL_VLANS} or $self->{VLAN_FACILITIES}->{$vlan_name} );

        $vlan_elements{$vlan_name} = () unless ( $vlan_elements{$vlan_name} );

        $vlan_elements{$vlan_name}->{$direction} = $eflow;
        $vlan_elements{$vlan_name}->{"vcg"} = $vcg_name;
    }

    foreach my $vlan_name ( keys %vlan_elements ) {

        my ($oper_status, $admin_status);

        # The eflows link the ethernet port to the sonet stuff. We use
        # their stats gathering to get the "in" and "out" for this vlan.

        $self->{LOGGER}->debug("VLAN Name: ".$vlan_name);
        $self->{LOGGER}->debug("VLAN Elements: ".Dumper($vlan_elements{$vlan_name}));

        foreach my $direction ( "in_eflow", "out_eflow" ) {
            my $eflow = $vlan_elements{$vlan_name}->{$direction};


            # A 'vlan' doesn't have status of its own, so you have to check
            # both the ingress port and egress port of the eflow to get "its"
            # status.

            foreach my $type ( "ingressport", "egressport" ) {
                my ( $status, $new_oper_status, $new_admin_status );

                if ( $eflow->{ $type . "type" } and $eflow->{ $type . "type" } eq "VCG" ) {
                    ( $status, $new_oper_status, $new_admin_status ) = $self->checkVCG( $eflow->{ $type . "name" } );
                }
                elsif ( $eflow->{ $type . "type" } and $eflow->{ $type . "type" } eq "ETTP" ) {
                    ( $status, $new_oper_status, $new_admin_status ) = $self->checkETH( $eflow->{ $type . "name" } );
                }
                else {
                    $oper_status = "unknown";
                    last;
                }

                if ( $status == -1 ) {
                    $oper_status = "unknown";
                    last;
                }

                $oper_status = get_new_oper_status( $oper_status, $new_oper_status );
                $admin_status = get_new_admin_status( $admin_status, $new_admin_status );
            }
        }

        # We read the VCG stats as the 'vlan' stats since they're the best we
        # can get.
        my ($in_octets, $out_octets, $in_packets, $out_packets, $in_errors, $out_errors, $in_discards, $out_discards, $capacity, $description);
        if ($vlan_elements{$vlan_name}->{"vcg"}) {
            ($status, $res) = $self->{AGENT}->get_vcg_mib_pms($vlan_elements{$vlan_name}->{"vcg"});
            if ($status == 0) {
                # in/out are swapped since we're measuring the 'vcg' to get the 'vlan' elements.
                $out_packets = $res->{INTF_IN_PACKETS}->{value};
                $in_packets = $res->{INTF_OUT_PACKETS}->{value};
                $out_octets = $res->{INTF_IN_OCTETS}->{value};
                $in_octets = $res->{INTF_OUT_OCTETS}->{value};
                $out_discards = $res->{INTF_IN_DISCARDS}->{value};
                $in_discards = $res->{INTF_OUT_DISCARDS}->{value};
                $in_errors = $res->{INTF_IN_ERRORS}->{value};
            }

            # We read the VCG information to get the capacity since that's the best
            # we can go on.

            #PROVBW=2,OPERBW=2

            ($status, $res) = $self->{AGENT}->get_vcgs($vlan_elements{$vlan_name}->{"vcg"});
            if ($status == 0) {
                if ($res->{provbw}) {
                    $capacity = $res->{provbw}*50.112*1000*1000; # Convert to Bps
                }

                $description = $res->{alias};
            }
        }

        my ( $id );

        if ( $self->{VLAN_FACILITIES}->{'*'} ) {
            $id           = $self->{VLAN_FACILITIES}->{'*'}->{id}           if ( $self->{VLAN_FACILITIES}->{'*'}->{id} );
            $admin_status = $self->{VLAN_FACILITIES}->{'*'}->{admin_status} if ( $self->{VLAN_FACILITIES}->{'*'}->{admin_status} );
            $oper_status  = $self->{VLAN_FACILITIES}->{'*'}->{oper_status}  if ( $self->{VLAN_FACILITIES}->{'*'}->{oper_status} );
        }

        if ( $self->{VLAN_FACILITIES}->{$vlan_name} ) {
            $id           = $self->{VLAN_FACILITIES}->{$vlan_name}->{id}           if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{id} );
            $admin_status = $self->{VLAN_FACILITIES}->{$vlan_name}->{admin_status} if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{admin_status} );
            $oper_status  = $self->{VLAN_FACILITIES}->{$vlan_name}->{oper_status}  if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{oper_status} );
        }

        # Add 'utilization' counters
        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_utilization})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_utilization}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name,  direction => "in" },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                         values      => { utilization => $in_octets },
            };

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name,  direction => "out" },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                         values      => { utilization => $out_octets },
            };
        }

        # Add 'discard' counters
        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_discards})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_discards}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name,  direction => "in" },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                         values      => { discards => $in_discards },
            };

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name,  direction => "out" },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                         values      => { discards => $out_discards },
            };
        }

        # Add 'error' counter
        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_errors})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_errors}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name,  direction => "in" },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/errors/2.0",
                         values      => { errors => $in_errors },
            };
        }

        # Oper/Admin status
        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_oper_status})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_oper_status}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name },
                         data_type   => "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0",
                         values      => { oper_status => oper_status_to_num($oper_status) },
            };
        }

        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_admin_status})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_admin_status}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name },
                         data_type => "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0",
                         values      => { admin_status => admin_status_to_num($admin_status) },
            };
        }

        # Port Capacity
        if ( ($self->{VLAN_FACILITIES}->{ $vlan_name } and $self->{VLAN_FACILITIES}->{ $vlan_name }->{collect_capacity})
                or ($self->{VLAN_FACILITIES}->{ '*' } and $self->{VLAN_FACILITIES}->{ '*' }->{collect_capacity}) ) {

            push @ret_counters, {
                metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vlan_name },
                         data_type => "http://ggf.org/ns/nmwg/characteristic/interface/capacity/provisioned/2.0",
                         values      => { capacity => $capacity },
            };
        }
    }

    return (0, \@ret_counters);
}

sub handle_vcgs {
    my ($self) = @_;

    my @ret_counters = ();

    $self->{LOGGER}->debug("handle_vcgs(): start");

    if ( $self->{CHECK_ALL_VCG_PORTS} or scalar( keys %{ $self->{VCG_FACILITIES} } ) > 0 ) {
        my @vcgs = ();
        if ( $self->{CHECK_ALL_VCG_PORTS} ) {
            my ( $status, $vcgs ) = $self->{AGENT}->get_vcgs();
            if ( $status == 0 ) {
                @vcgs = keys %{$vcgs};
            } else {
                $self->{LOGGER}->error("Error looking up VCGs: $vcgs");
            }
        }
        else {
            foreach my $fac (keys %{ $self->{VCG_FACILITIES} }) {
                next if ($fac eq "*");
                push @vcgs, $fac;
            }
        }

        $self->{LOGGER}->debug("Checking vcgs: ".join(",", @vcgs));

        foreach my $vcg (@vcgs) {
            my ($status, $res) = $self->handle_vcg($vcg);
            if ($status != 0) {
                return ($status, $res);
            }

            foreach my $counter (@{ $res }) {
                push @ret_counters, $counter;
            }
        }
    }

    $self->{LOGGER}->debug("handle_vcgs(): stop");


    return (0, \@ret_counters);
}

sub handle_vcg {
    my ( $self, $vcg_name ) = @_;

    my @ret_counters = ();

    my ( $status, $vcgs, $res );
    ( $status, $vcgs ) = $self->{AGENT}->get_vcgs();
    if ( $status == -1 or not $vcgs ) {
        my $msg = "Couldn't look up VCG";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $vcg;

    foreach my $vcg_id ( keys %$vcgs ) {
        if ( $vcg_name eq $vcg_id or $vcgs->{$vcg_id}->{alias} eq $vcg_name ) {
            $vcg = $vcgs->{$vcg_id};
            last;
        }
    }

    unless ($vcg) {
        return (0, \@ret_counters);
    }
    my $oper_status;
    my $admin_status;

    unless ( $vcg->{pst} and $state_mapping{ lc( $vcg->{pst} ) } ) {
        $oper_status  = "unknown";
        $admin_status = "unknown";
    }
    else {
        $oper_status  = $state_mapping{ lc( $vcg->{pst} ) }->{"oper_status"};
        $admin_status = $state_mapping{ lc( $vcg->{pst} ) }->{"admin_status"};
    }

    my ($in_octets, $out_octets, $in_packets, $out_packets, $in_errors, $out_errors, $in_discards, $out_discards, $capacity, $description, $operbw);

    ($status, $res) = $self->{AGENT}->get_vcg_mib_pms($vcg->{name});
    if ($status == 0) {
        # in/out are swapped since we're measuring the 'vcg' to get the 'vlan' elements.
        $in_packets = $res->{INTF_IN_PACKETS}->{value};
        $out_packets = $res->{INTF_OUT_PACKETS}->{value};
        $in_octets = $res->{INTF_IN_OCTETS}->{value};
        $out_octets = $res->{INTF_OUT_OCTETS}->{value};
        $in_discards = $res->{INTF_IN_DISCARDS}->{value};
        $out_discards = $res->{INTF_OUT_DISCARDS}->{value};
        $in_errors = $res->{INTF_IN_ERRORS}->{value};
    }

    if ($vcg->{provbw}) {
        $capacity = $vcg->{provbw}*50.112*1000*1000; # Convert to Bps
        $operbw = $vcg->{operbw}*50.112*1000*1000;
    }

    $description = $vcg->{alias};

    my ( $id );
    if ( $self->{VCG_FACILITIES}->{ '*' } ) {
        $id           = $self->{VCG_FACILITIES}->{ '*' }->{id}           if ( $self->{VCG_FACILITIES}->{ '*' }->{id} );
        $admin_status = $self->{VCG_FACILITIES}->{ '*' }->{admin_status} if ( $self->{VCG_FACILITIES}->{ '*' }->{admin_status} );
        $oper_status  = $self->{VCG_FACILITIES}->{ '*' }->{oper_status}  if ( $self->{VCG_FACILITIES}->{ '*' }->{oper_status} );
    }

    if ( $self->{VCG_FACILITIES}->{ $vcg->{name} } ) {
        $id           = $self->{VCG_FACILITIES}->{ $vcg->{name} }->{id}           if ( $self->{VCG_FACILITIES}->{ $vcg->{name} }->{id} );
        $admin_status = $self->{VCG_FACILITIES}->{ $vcg->{name} }->{admin_status} if ( $self->{VCG_FACILITIES}->{ $vcg->{name} }->{admin_status} );
        $oper_status  = $self->{VCG_FACILITIES}->{ $vcg->{name} }->{oper_status}  if ( $self->{VCG_FACILITIES}->{ $vcg->{name} }->{oper_status} );
    }

    # Oper/Admin status
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_oper_status})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_oper_status}) ) {
        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name}, description => $description, capacity => $capacity },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0",
                     values      => { oper_status => $oper_status },
        };
    }

    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_admin_status})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_admin_status}) ) {
        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name}, description => $description, capacity => $capacity },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0",
                     values      => { admin_status => $admin_status },
        };
    }

    # Add 'utilization' counters
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_utilization})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_utilization}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name}, direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                     values      => { utilization => $in_octets },
        };

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name},  direction => "out" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0",
                     values      => { utilization => $out_octets },
        };
    }

    # Add 'discard' counters
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_discards})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_discards}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name},  direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                     values      => { discards => $in_discards },
        };

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name},  direction => "out" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/discards/2.0",
                     values      => { discards => $out_discards },
        };
    }

    # Add 'error' counter
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_errors})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_errors}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name},  direction => "in" },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/errors/2.0",
                     values      => { errors => $in_errors },
        };
    }

    # Oper/Admin status
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_oper_status})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_oper_status}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name} },
                     data_type   => "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0",
                     values      => { oper_status => oper_status_to_num($oper_status) },
        };
    }

    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_admin_status})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_admin_status}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name} },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0",
                     values      => { admin_status => admin_status_to_num($admin_status) },
        };
    }

    # Port Capacity
    if ( ($self->{VCG_FACILITIES}->{ $vcg->{name} } and $self->{VCG_FACILITIES}->{ $vcg->{name} }->{collect_capacity})
            or ($self->{VCG_FACILITIES}->{ '*' } and $self->{VCG_FACILITIES}->{ '*' }->{collect_capacity}) ) {

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name} },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/capacity/provisioned/2.0",
                     values      => { capacity => $capacity },
        };

        push @ret_counters, {
            metadata => { urn => $id, host_name => $self->{ROUTER_ADDRESS}, port_name => $vcg->{name} },
                     data_type => "http://ggf.org/ns/nmwg/characteristic/interface/capacity/actual/2.0",
                     values      => { capacity => $operbw },
        };
    }

    return (0, \@ret_counters);
}

=head2 checkVCG( $self, $vcg_name )

An internal function used to query the status of a specific Virtual
Concatentation Group (VCG). It is used when a user has configured the service
to check on EFLOWs or VLANs.

=cut

sub checkVCG {
    my ( $self, $vcg_name ) = @_;

    my ( $status, $vcgs );
    ( $status, $vcgs ) = $self->{AGENT}->get_vcgs();
    if ( $status == -1 or not $vcgs ) {
        my $msg = "Couldn't look up VCG";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    foreach my $vcg_id ( keys %$vcgs ) {
        my $vcg = $vcgs->{$vcg_id};

        if ( $vcg_name eq $vcg_id or $vcg->{alias} eq $vcg_name ) {
            my $oper_status;
            my $admin_status;

            unless ( $vcg->{pst} and $state_mapping{ lc( $vcg->{pst} ) } ) {
                $oper_status  = "unknown";
                $admin_status = "unknown";
            }
            else {
                $oper_status  = $state_mapping{ lc( $vcg->{pst} ) }->{"oper_status"};
                $admin_status = $state_mapping{ lc( $vcg->{pst} ) }->{"admin_status"};
            }

            return ( 0, $oper_status, $admin_status );
        }
    }

    my $msg = "Couldn't find requested VCG";
    $self->{LOGGER}->error( $msg );
    return ( -1, $msg );
}

=head2 checkETH( $self, $eth_aid )

An internal function used to query the status of a specific Ethernet port.  It
is used when a user has configured the service to check an Ethernet port as
well as if the user has configured the service to check on EFLOWs or VLANs.

=cut

sub checkETH {
    my ( $self, $eth_aid ) = @_;

    my ( $status, $port );
    ( $status, $port ) = $self->{AGENT}->get_ethernet_facilities( $eth_aid );
    if ( $status == -1 or not $port ) {
        my $msg = "Couldn't look up Ethernet Port";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $oper_status;
    my $admin_status;

    unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
        $oper_status  = "unknown";
        $admin_status = "unknown";
    }
    else {
        $oper_status  = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
        $admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
    }

    return ( 0, $oper_status, $admin_status );
}

=head2 connect( $self )

A function called by the Base class to connect to the device. It calls this
before calling the "check_facilities" function.

=cut

sub connect {
    my ( $self ) = @_;

    if ( $self->{AGENT}->connect( { inhibit_messages => 1 } ) == -1 ) {
        $self->{LOGGER}->error( "Could not connect to host" );
        return 0;
    }

    return 1;
}

=head2 disconnect( $self )

A function called by the Base class to disconnect fom the device. It calls this
after calling the "check_facilities" function.

=cut

sub disconnect {
    my ( $self ) = @_;

    return $self->{AGENT}->disconnect();
}

1;

__END__

=head1 SEE ALSO

L<Params::Validate>, L<Log::Log4perl>,
L<perfSONAR_PS::Utils::TL1::CoreDirector>, L<perfSONAR_PS::Status::Common>,
L<perfSONAR_PS::Utils::ParameterValidation>, L<Data::Dumper>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

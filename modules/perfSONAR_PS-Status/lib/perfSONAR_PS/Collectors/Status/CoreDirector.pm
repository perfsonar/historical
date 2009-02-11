package perfSONAR_PS::Collectors::Status::CoreDirector;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::TL1::CoreDirector;
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

our $VERSION = 0.09;

use base 'perfSONAR_PS::Collectors::Status::BaseWorker';

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'AGENT', 'IDENTIFIER_PATTERN', 'OPTICAL_FACILITIES', 'ETHERNET_FACILITIES', 'VLAN_FACILITIES', 'EFLOW_FACILITIES', 'VCG_FACILITIES', 'CROSSCONNECT_FACILTIES', 'DEFAULT_ADMIN_STATUS', 'CHECK_ALL_OPTICAL_PORTS', 'CHECK_ALL_VLANS',
    'CHECK_ALL_ETHERNET_PORTS', 'CHECK_ALL_CROSSCONNECTS', 'CHECK_ALL_EFLOWS', 'CHECK_ALL_VCGS';

my %state_mapping = (
    "is-anr"   => "degraded",
    "is-nr"    => "up",
    "oos-au"   => "down",
    "oos-auma" => "down",
    "oos-ma"   => "down",
);

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client          => 1,
            facilities_client      => 1,
            topology_id_client      => 1,
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
            facilities               => 0,
            identifier_pattern       => 0,
            default_admin_status     => 0,
        }
    );

    my $n = $self->SUPER::init( { facilities_client => $args->{facilities_client}, data_client => $args->{data_client}, topology_id_client => $args->{topology_id_client} } );
    if ( $n == -1 ) {
        return -1;
    }

    #	$self->{ADDRESS} = $args->{address};
    #	$self->{PORT} = $args->{port};
    #	$self->{USERNAME} = $args->{username};
    #	$self->{PASSWORD} = $args->{password};

    $self->{CHECK_ALL_OPTICAL_PORTS}  = $args->{check_all_optical_ports};
    $self->{CHECK_ALL_ETHERNET_PORTS} = $args->{check_all_ethernet_ports};
    $self->{CHECK_ALL_CROSSCONNECTS}  = $args->{check_all_crossconnects};
    $self->{CHECK_ALL_VLANS}          = $args->{check_all_vlans};
    $self->{CHECK_ALL_EFLOWS}         = $args->{check_all_eflows};
    $self->{CHECK_ALL_VCGS}           = $args->{check_all_vcgs};

    $self->{IDENTIFIER_PATTERN} = $args->{identifier_pattern};

    $self->{POLLING_INTERVAL} = $args->{polling_interval};
    unless ( $self->{POLLING_INTERVAL} ) {
        $self->{LOGGER}->warn( "No polling interval set for SNMP worker. Setting to 60 seconds" );
        $self->{POLLING_INTERVAL} = 60;
    }

    $self->{DEFAULT_ADMIN_STATUS} = $args->{default_admin_status};
    if ( not $self->{DEFAULT_ADMIN_STATUS} ) {
        $self->{LOGGER}->warn( "No default administrative status set for CoreDirector worker. Setting to 'normaloperation'" );
        $self->{DEFAULT_ADMIN_STATUS} = "normaloperation";
    }

    $self->{OPTICAL_FACILITIES}     = ();
    $self->{CROSSCONNECT_FACILTIES} = ();
    $self->{ETHERNET_FACILITIES}    = ();
    $self->{VLAN_FACILITIES}        = ();
    $self->{EFLOW_FACILITIES}       = ();
    $self->{VCG_FACILITIES}         = ();

    if ( $args->{facilities} ) {
        foreach my $facility ( @{ $args->{facilities} } ) {
            unless ( $facility->{type} ) {
                my $msg = "Facilities must have a 'type'. one of 'optical', 'crosconnect', 'eflow', 'vcg' or 'ethernet'";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            unless ( $facility->{name} ) {
                my $msg = "Facilities must have a 'name'. The meaning differs for each facility type, but must be an idenfier used by the switch to identify the element";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            unless ( $facility->{id} or $args->{identifier_pattern} ) {
                my $msg = "Facilities must have an 'id' if an identifier pattern is not specified";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            if ( $facility->{type} eq "optical" ) {
                $self->{OPTICAL_FACILITIES}->{ $facility->{name} } = $facility;
            }
            elsif ( $facility->{type} eq "ethernet" ) {
                $self->{ETHERNET_FACILITIES}->{ $facility->{name} } = $facility;
            }
            elsif ( $facility->{type} eq "eflow" ) {
                $self->{EFLOW_FACILITIES}->{ $facility->{name} } = $facility;
            }
            elsif ( $facility->{type} eq "vcg" ) {
                $self->{VCG_FACILITIES}->{ $facility->{name} } = $facility;
            }
            elsif ( $facility->{type} eq "crossconnect" ) {
                $self->{CROSSCONNECT_FACILTIES}->{ $facility->{name} } = $facility;
            }
            elsif ( $facility->{type} eq "vlan" ) {
                if ( $facility->{name} !~ /(.*)\.([A-Z]+)_(egress|ingress)$/ ) {
                    my $msg = "VLAN facilities must be named like '[ethernet_port].[vlan_number]_(egress|ingress)' or '[vcg_name].[vlan_number]_(egress|ingress)'";
                    $self->{LOGGER}->error( $msg );
                    return ( -1, $msg );
                }

                if ( $facility->{name} =~ /(.*)\.([A-Z]+)_(egress|ingress)$/ ) {
                    $facility->{port}      = $1;
                    $facility->{vlan}      = $2;
                    $facility->{direction} = $3;

                    push @{ $self->{VLAN_FACILITIES} }, $facility;
                }
            }
        }
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

    return 0;
}

sub run {
    my ( $self ) = @_;

    my $prev_update_successful;

    while ( 1 ) {
        if ( $self->{NEXT_RUNTIME} ) {
			$self->{TOPOLOGY_ID_CLIENT}->closeDB;
			$self->{FACILITIES_CLIENT}->closeDB;
			$self->{DATA_CLIENT}->closeDB;

            sleep( $self->{NEXT_RUNTIME} - time );
        }

        $self->{NEXT_RUNTIME} = time + $self->{POLLING_INTERVAL};

		my ($status, $res);

        ( $status, $res ) = $self->{FACILITIES_CLIENT}->openDB;
        if ( $status != 0 ) {
            my $msg = "Couldn't open database client: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        ( $status, $res ) = $self->{TOPOLOGY_ID_CLIENT}->openDB;
        if ( $status != 0 ) {
            my $msg = "Couldn't open database client: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
        if ( $status != 0 ) {
            my $msg = "Couldn't open database client: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        if ( $self->{AGENT}->connect( { inhibitMessages => 1 } ) == -1 ) {
            $self->{LOGGER}->error( "Could not connect to host" );
            next;
        }

        my $curr_time = time;

        my @facilities_to_update = ();

        if ( $self->{CHECK_ALL_CROSSCONNECTS} or scalar( keys %{ $self->{CROSSCONNECT_FACILTIES} } ) > 0 ) {

            # we grab all the cross-connects and then pare down the data set to just those of interest
            my $crss = $self->{AGENT}->getCrossconnect();
            my @facility_names;
            if ( $self->{CHECK_ALL_CROSSCONNECTS} ) {
                foreach my $crs_key ( keys %{$crss} ) {
                    my $crs = $crss->{$crs_key};

                    if ( $crs->{cktid} ) {
                        push @facility_names, $crs->{cktid};
                    }
                    else {
                        push @facility_names, $crs->{name};
                    }
                }
            }
            else {
                @facility_names = keys %{ $self->{CROSSCONNECT_FACILTIES} };
            }

            foreach my $name ( @facility_names ) {
                foreach my $crs_key ( keys %$crss ) {
                    my $crs = $crss->{$crs_key};

                    if ( $crs->{cktid} eq $name or $crs->{name} eq $name ) {
                        my $oper_status;

                        unless ( $crs->{pst} and $state_mapping{ lc( $crs->{pst} ) } ) {
                            $oper_status = "unknown";
                        }
                        else {
                            $oper_status = $state_mapping{ lc( $crs->{pst} ) };
                        }

                        my ( $id, $admin_status );
                        if ( $self->{CROSSCONNECT_FACILTIES}->{$name} ) {
                            $id           = $self->{CROSSCONNECT_FACILTIES}->{$name}->{id}           if ( $self->{CROSSCONNECT_FACILTIES}->{$name}->{id} );
                            $admin_status = $self->{CROSSCONNECT_FACILTIES}->{$name}->{admin_status} if ( $self->{CROSSCONNECT_FACILTIES}->{$name}->{admin_status} );
                            $oper_status  = $self->{CROSSCONNECT_FACILTIES}->{$name}->{oper_status}  if ( $self->{CROSSCONNECT_FACILTIES}->{$name}->{oper_status} );
                        }

                        my %facility = (
                            id           => $id,
                            name         => $name,
                            type         => "crossconnect",
                            oper_status  => $oper_status,
                            admin_status => $admin_status,
                        );

                        push @facilities_to_update, \%facility;

                        last;
                    }
                }
            }
        }

        if ( $self->{CHECK_ALL_VCGS} or scalar( keys %{ $self->{VCG_FACILITIES} } ) > 0 ) {

            # we grab all the cross-connects and then pare down the data set to just those of interest
            my $opticals = $self->{AGENT}->getVCG();
            my @facility_names;
            if ( $self->{CHECK_ALL_VCGS} ) {
                @facility_names = keys %{$opticals};
            }
            else {
                @facility_names = keys %{ $self->{VCG_FACILITIES} };
            }

            foreach my $name ( @facility_names ) {
                my ( $status, $oper_status ) = $self->checkVCG( $name );
                next if ( $status != 0 );

                my ( $id, $admin_status );
                if ( $self->{VCG_FACILITIES}->{$name} ) {
                    $id           = $self->{VCG_FACILITIES}->{$name}->{id}           if ( $self->{VCG_FACILITIES}->{$name}->{id} );
                    $admin_status = $self->{VCG_FACILITIES}->{$name}->{admin_status} if ( $self->{VCG_FACILITIES}->{$name}->{admin_status} );
                    $oper_status  = $self->{VCG_FACILITIES}->{$name}->{oper_status}  if ( $self->{VCG_FACILITIES}->{$name}->{oper_status} );
                }

                my %facility = (
                    id           => $id,
                    name         => $name,
					type         => "vcg",
                    oper_status  => $oper_status,
                    admin_status => $admin_status,
                );

                push @facilities_to_update, \%facility;
            }
        }

        if ( $self->{CHECK_ALL_OPTICAL_PORTS} or scalar( keys %{ $self->{OPTICAL_FACILITIES} } ) > 0 ) {

            # we grab all the cross-connects and then pare down the data set to just those of interest
            my $opticals = $self->{AGENT}->getOCN();
            my @facility_names;
            if ( $self->{CHECK_ALL_OPTICAL_PORTS} ) {
                @facility_names = keys %{$opticals};
            }
            else {
                @facility_names = keys %{ $self->{OPTICAL_FACILITIES} };
            }

            foreach my $name ( @facility_names ) {
                if ( $opticals->{$name} ) {
                    my $oper_status;

                    unless ( $opticals->{$name}->{pst} and $state_mapping{ lc( $opticals->{$name}->{pst} ) } ) {
                        $oper_status = "unknown";
                    }
                    else {
                        $oper_status = $state_mapping{ lc( $opticals->{$name}->{pst} ) };
                    }

                    my ( $id, $admin_status );
                    if ( $self->{OPTICAL_FACILITIES}->{$name} ) {
                        $id           = $self->{OPTICAL_FACILITIES}->{$name}->{id}           if ( $self->{OPTICAL_FACILITIES}->{$name}->{id} );
                        $admin_status = $self->{OPTICAL_FACILITIES}->{$name}->{admin_status} if ( $self->{OPTICAL_FACILITIES}->{$name}->{admin_status} );
                        $oper_status  = $self->{OPTICAL_FACILITIES}->{$name}->{oper_status}  if ( $self->{OPTICAL_FACILITIES}->{$name}->{oper_status} );
                    }

                    my %facility = (
                        id           => $id,
                        name         => $name,
						type         => "optical",
                        oper_status  => $oper_status,
                        admin_status => $admin_status,
                    );

                    push @facilities_to_update, \%facility;
                }
            }
        }

        if ( $self->{CHECK_ALL_EFLOWS} or scalar( keys %{ $self->{EFLOW_FACILITIES} } ) > 0 ) {

            # we grab all the eflows and then pare down the data set to just those of interest
            my $eflows = $self->{AGENT}->getEFLOW();
            my @facility_names;
            if ( $self->{CHECK_ALL_EFLOWS} ) {
                @facility_names = keys %{$eflows};
            }
            else {
                @facility_names = keys %{ $self->{EFLOW_FACILITIES} };
            }

            # An eflow doesn't have status of its own, so you have to check
            # both the ingress port and egress port of the eflow to get "its"
            # status.
            foreach my $name ( @facility_names ) {

                next if ( not $eflows->{$name} );

                my $eflow = $eflows->{$name};

                my $oper_status = "up";

                foreach my $type ( "ingressport", "egressport" ) {
                    my ( $status, $new_oper_status );

                    if ( $eflow->{ $type . "type" } eq "VCG" ) {
                        ( $status, $new_oper_status ) = $self->checkVCG( $eflow->{ $type . "name" } );
                    }
                    elsif ( $eflow->{ $type . "type" } eq "ETTP" ) {
                        ( $status, $new_oper_status ) = $self->checkETH( $eflow->{ $type . "name" } );
                    }
                    else {
                        $oper_status = "unknown";
                        last;
                    }

                    if ( $status == -1 ) {
                        $oper_status = "unknown";
                        last;
                    }

                    if ( $new_oper_status eq "unknown" or $new_oper_status eq "down" ) {
                        $oper_status = $new_oper_status;
                        last;
                    }

                    if ( $new_oper_status eq "degraded" ) {
                        $oper_status = "degraded";
                    }
                }

                my ( $id, $admin_status );
                if ( $self->{EFLOW_FACILITIES}->{$name} ) {
                    $id           = $self->{EFLOW_FACILITIES}->{$name}->{id}           if ( $self->{EFLOW_FACILITIES}->{$name}->{id} );
                    $admin_status = $self->{EFLOW_FACILITIES}->{$name}->{admin_status} if ( $self->{EFLOW_FACILITIES}->{$name}->{admin_status} );
                    $oper_status  = $self->{EFLOW_FACILITIES}->{$name}->{oper_status}  if ( $self->{EFLOW_FACILITIES}->{$name}->{oper_status} );
                }

                my %facility = (
                    id           => $id,
                    name         => $name,
					type         => "eflow",
                    oper_status  => $oper_status,
                    admin_status => $admin_status,
                );

                push @facilities_to_update, \%facility;
            }
        }

        #		if ($self->{CHECK_ALL_VLANS} or scalar(keys %{ $self->{VLAN_FACILITIES} }) > 0) {
        #
        #			# we grab all the cross-connects and then pare down the data set to just those of interest
        #			my $eflows = $self->{AGENT}->getEFLOW();
        #
        #			my @eflows_to_check;
        #			foreach my $eflow_key (keys %{ $eflows }) {
        #				my $eflow = $eflows->{$eflow_key};
        #				if ($self->{CHECK_ALL_VLANS}) {
        #					push @eflows_to_check, $eflow;
        #				} else {
        #					next unless ($eflow->{"outervlanidrange"}); # we only care about actual vlans
        #
        #					foreach my $vlan (@{ $self->{VLAN_FACILITIES} }) {
        #						my $port = $vlan->{port};
        #						my $vlan = $vlan->{vlan};
        #						my $direction = $vlan->{direction};
        #
        #						next unless ($eflow->{"outervlanidrange"} and $eflow->{"outervlanidrange"} eq $vlan);
        #
        #						next unless ($eflow->{$direction."portname"} eq $port);
        #
        #						push @eflows_to_check, $eflow;
        #					}
        #				}
        #			}
        #
        #			# An eflow doesn't have status of its own, so you have to check
        #			# both the ingress port and egress port of the eflow to get "its"
        #			# status.
        #			foreach my $eflow (@eflows_to_check) {
        #
        #				my $oper_status = "up";
        #
        #				foreach my $type ("ingressport", "egressport") {
        #					my ($status, $time, $new_oper_status);
        #
        #					if ($eflow->{$type."type"} eq "VCG") {
        #						($status, $time, $new_oper_status) = $self->{AGENT}->checkVCG($eflow->{$type."name"});
        #					} elsif ($eflow->{$type."type"} eq "ETTP") {
        #						($status, $time, $new_oper_status) = $self->{AGENT}->checkETH($eflow->{$type."name"});
        #					} else {
        #						$oper_status = "unknown";
        #						last;
        #					}
        #
        #					if ($status == -1) {
        #						$oper_status = "unknown";
        #						last;
        #					}
        #
        #					if ($new_oper_status eq "unknown" or $new_oper_status eq "down") {
        #						$oper_status = $new_oper_status;
        #						last;
        #					}
        #
        #					if ($new_oper_status eq "degraded") {
        #						$oper_status = "degraded";
        #					}
        #				}
        #
        #				my ($id, $admin_status);
##
        #				foreach my $vlan (@{ $self->{VLAN_FACILITIES} }) {
        #					my $port = $vlan->{port};
        #					my $vlan = $vlan->{vlan};
        #					my $direction = $vlan->{direction};
        #
        #					next unless ($eflow->{"outervlanidrange"} and $eflow->{"outervlanidrange"} eq $vlan);
        #
        #					next unless (not $port or ($eflow->{ingressportname} eq $port or $eflow->{egressportname} eq $port));
        #
        #					$id = $vlan->{id};
        #					$admin_status = $vlan->{admin_status};
        #					last;
        #				}
        #
        #				my %facility = (
        #						id => $id,
        #						name => $name,
        #						oper_status => $oper_status,
        #						admin_status => $admin_status,
        #						);
        #
        #				push @facilities_to_update, \%facility;
        #			}
        #		}

        if ( $self->{CHECK_ALL_ETHERNET_PORTS} or scalar( keys %{ $self->{ETHERNET_FACILITIES} } ) > 0 ) {
            my @ports_to_check = ();
            if ( $self->{CHECK_ALL_ETHERNET_PORTS} ) {
                my $ports = $self->{AGENT}->getETH();
                foreach my $ethernet_key ( keys %{$ports} ) {
                    push @ports_to_check, $ports->{$ethernet_key};
                }
            }
            else {
                foreach my $ethernet_aid ( keys %{ $self->{ETHERNET_FACILITIES} } ) {
                    my $port = $self->{AGENT}->getETH( $ethernet_aid );
                    if ( $port ) {
                        push @ports_to_check, $port;
                    }
                }
            }

            foreach my $port ( @ports_to_check ) {
                my $oper_status;

                unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
                    $oper_status = "unknown";
                }
                else {
                    $oper_status = $state_mapping{ lc( $port->{pst} ) };
                }

                my ( $id, $admin_status );
                if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} } ) {
                    $id           = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{id}           if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{id} );
                    $admin_status = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{admin_status} if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{admin_status} );
                    $oper_status  = $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{oper_status}  if ( $self->{ETHERNET_FACILITIES}->{ $port->{name} }->{oper_status} );
                }

                my %facility = (
                    id           => $id,
                    name         => $port->{name},
					type         => "ethernet",
                    oper_status  => $oper_status,
                    admin_status => $admin_status,
                );

                push @facilities_to_update, \%facility;

                last;
            }
        }

        my %new_update_successful = ();
        foreach my $facility ( @facilities_to_update ) {
            my $id;
            if ( $facility->{id} ) {
                $id = $facility->{id};
            }
            else {
                $id = $self->{IDENTIFIER_PATTERN};
                $id =~ s/\%facility\%/$facility->{name}/g;
            }

            my $admin_status = $facility->{admin_status};
            if ( not $admin_status ) {
                $admin_status = $self->{DEFAULT_ADMIN_STATUS};
            }

			my $key;

			my ($status, $res) = $self->{FACILITIES_CLIENT}->query_facilities({ host => $self->{AGENT}->getAddress, host_type => "coredirector", facility => $facility->{name}, facility_type => $facility->{type} });
			if ($status != 0) {
				next;
			}

			foreach my $facility_ref (@$res) {
				$key = $facility_ref->{key};
            }

            if (not $key) {
                my ($status, $res) = $self->{FACILITIES_CLIENT}->add_facility({ host => $self->{AGENT}->getAddress, host_type => "coredirector", facility => $facility->{name}, facility_type => $facility->{type} });
				if ($status != 0) {
					next;
				}

				foreach my $facility_ref (@$res) {
					$key = $facility_ref->{key};
                }
				if (not $key) {
					$self->{LOGGER}->error("Couldn't add facility");
					next;
				}
            }

			($status, $res) = $self->{TOPOLOGY_ID_CLIENT}->add_topology_id({ topology_id => $id, element_id => $key });
			if ($status != 0) {
				$self->{LOGGER}->warn("Couldn't add topology id to metadata: $res");
			}

            my $do_update;

            if ( $prev_update_successful && $prev_update_successful->{$key} ) {
                $self->{LOGGER}->debug( "Doing update" );
                $do_update = 1;
            }

            ( $status, $res ) = $self->{DATA_CLIENT}->update_status( { element_id => $key, time => $curr_time, oper_status => $facility->{oper_status}, admin_status => $admin_status, do_update => $do_update } );
            if ( $status != 0 ) {
                $self->{LOGGER}->error( "Couldn't store status for element $id: $res" );
                $new_update_successful{$key} = 0;
            }
            else {
                $new_update_successful{$key} = 1;
            }
        }

        $prev_update_successful = \%new_update_successful;

        $self->{AGENT}->disconnect();
    }

	return;
}

sub checkVCG {
    my ( $self, $vcg_name ) = @_;

    my $vcgs = $self->{AGENT}->getVCG();
    if ( not $vcgs ) {
        my $msg = "Couldn't look up VCG";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    foreach my $vcg_id ( keys %$vcgs ) {
        my $vcg = $vcgs->{$vcg_id};

        if ( $vcg_name eq $vcg_id or $vcg->{alias} eq $vcg_name ) {
            my $oper_status;

            unless ( $vcg->{pst} and $state_mapping{ lc( $vcg->{pst} ) } ) {
                $oper_status = "unknown";
            }
            else {
                $oper_status = $state_mapping{ lc( $vcg->{pst} ) };
            }

            return ( 0, $oper_status );
        }
    }

    my $msg = "Couldn't find requested VCG";
    $self->{LOGGER}->error( $msg );
    return ( -1, $msg );
}

sub checkETH {
    my ( $self, $eth_aid ) = @_;

    my $port = $self->{AGENT}->getETH( $eth_aid );
    if ( not $port ) {
        my $msg = "Couldn't look up Ethernet Port";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $oper_status;

    unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $state_mapping{ lc( $port->{pst} ) };
    }

    return ( 0, $oper_status );
}

1;

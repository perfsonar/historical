package perfSONAR_PS::Collectors::Status::DeviceAgents::CoreDirector;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::Status::DeviceAgents::CoreDirector

=head1 DESCRIPTION

TBD

=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::TL1::CoreDirector;
use perfSONAR_PS::Status::Common;
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use base 'perfSONAR_PS::Collectors::Status::DeviceAgents::Base';

use fields 'AGENT', 'OPTICAL_FACILITIES', 'ETHERNET_FACILITIES', 'VLAN_FACILITIES', 'EFLOW_FACILITIES', 'VCG_FACILITIES', 'CROSSCONNECT_FACILTIES', 'CHECK_ALL_OPTICAL_PORTS', 'CHECK_ALL_VLANS', 'CHECK_ALL_ETHERNET_PORTS', 'CHECK_ALL_CROSSCONNECTS', 'CHECK_ALL_EFLOWS', 'CHECK_ALL_VCGS';

my %state_mapping = (
    "is-nr"    => { "oper_status" => "up",       "admin_status" => "normaloperation" },
    "is-anr"   => { "oper_status" => "degraded", "admin_status" => "normaloperation" },
    "oos-au"   => { "oper_status" => "down",     "admin_status" => "normaloperation" },
    "oos-auma" => { "oper_status" => "down",     "admin_status" => "maintenance" },
    "oos-ma"   => { "oper_status" => "down",     "admin_status" => "maintenance" },
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
            facilities               => 0,
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
    $self->{CROSSCONNECT_FACILTIES} = ();
    $self->{ETHERNET_FACILITIES}    = ();
    $self->{VLAN_FACILITIES}        = ();
    $self->{EFLOW_FACILITIES}       = ();
    $self->{VCG_FACILITIES}         = ();

    if ( $args->{facilities} ) {
        foreach my $facility ( @{ $args->{facilities} } ) {
            unless ( $facility->{type} ) {
                my $msg = "Facilities must have a 'type'. one of 'optical', 'crosconnect', 'eflow', 'vcg', 'ethernet' or 'vlan'";
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
                if ( $facility->{name} !~ /(.*)\.([A-Z]+)$/ ) {
                    my $msg = "VLAN facilities must be named like '[ethernet_port].[vlan_number]'";
                    $self->{LOGGER}->error( $msg );
                    return ( -1, $msg );
                }

                if ( $facility->{name} =~ /(.*)\.([A-Z]+)$/ ) {
                    $facility->{port} = $1;
                    $facility->{vlan} = $2;

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

=head2 check_facilities( $self )

TBD

=cut

sub check_facilities {
    my ( $self ) = @_;

    my @facilities_to_update = ();

    my $status;

    if ( $self->{CHECK_ALL_CROSSCONNECTS} or scalar( keys %{ $self->{CROSSCONNECT_FACILTIES} } ) > 0 ) {

        # we grab all the cross-connects and then pare down the data set to just those of interest
        my $crss;
        ( $status, $crss ) = $self->{AGENT}->getCrossconnect();
        if ( $status == 0 ) {
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
                        my $admin_status;

                        unless ( $crs->{pst} and $state_mapping{ lc( $crs->{pst} ) } ) {
                            $oper_status  = "unknown";
                            $admin_status = "unknown";
                        }
                        else {
                            $oper_status  = $state_mapping{ lc( $crs->{pst} ) }->{"oper_status"};
                            $admin_status = $state_mapping{ lc( $crs->{pst} ) }->{"admin_status"};
                        }

                        my ( $id );
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
    }

    if ( $self->{CHECK_ALL_VCGS} or scalar( keys %{ $self->{VCG_FACILITIES} } ) > 0 ) {
        my $vcgs;
        ( $status, $vcgs ) = $self->{AGENT}->getVCG();
        if ( $status == 0 ) {
            my @facility_names;
            if ( $self->{CHECK_ALL_VCGS} ) {
                @facility_names = keys %{$vcgs};
            }
            else {
                @facility_names = keys %{ $self->{VCG_FACILITIES} };
            }

            foreach my $name ( @facility_names ) {
                my ( $status, $oper_status, $admin_status ) = $self->checkVCG( $name );
                next if ( $status != 0 );

                my ( $id );
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
    }

    if ( $self->{CHECK_ALL_OPTICAL_PORTS} or scalar( keys %{ $self->{OPTICAL_FACILITIES} } ) > 0 ) {
        my $opticals;

        ( $status, $opticals ) = $self->{AGENT}->getOCN();
        if ( $status == 0 ) {
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
                    my $admin_status;

                    unless ( $opticals->{$name}->{pst} and $state_mapping{ lc( $opticals->{$name}->{pst} ) } ) {
                        $oper_status  = "unknown";
                        $admin_status = "unknown";
                    }
                    else {
                        $oper_status  = $state_mapping{ lc( $opticals->{$name}->{pst} ) }->{"oper_status"};
                        $admin_status = $state_mapping{ lc( $opticals->{$name}->{pst} ) }->{"admin_status"};
                    }

                    my $id;
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
    }

    if ( $self->{CHECK_ALL_EFLOWS} or scalar( keys %{ $self->{EFLOW_FACILITIES} } ) > 0 ) {
        my $eflows;
        ( $status, $eflows ) = $self->{AGENT}->getEFLOW();
        if ( $status == 0 ) {
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

                my $oper_status;
                my $admin_status;

                foreach my $type ( "ingressport", "egressport" ) {
                    my ( $status, $new_oper_status, $new_admin_status );

                    if ( $eflow->{ $type . "type" } eq "VCG" ) {
                        ( $status, $new_oper_status, $new_admin_status ) = $self->checkVCG( $eflow->{ $type . "name" } );
                    }
                    elsif ( $eflow->{ $type . "type" } eq "ETTP" ) {
                        ( $status, $new_oper_status, $new_admin_status ) = $self->checkETH( $eflow->{ $type . "name" } );
                    }
                    else {
                        $oper_status  = "unknown";
                        $admin_status = "unknown";
                        last;
                    }

                    if ( $status == -1 ) {
                        $oper_status  = "unknown";
                        $admin_status = "unknown";
                        last;
                    }

                    $oper_status  = get_new_oper_status( $oper_status,   $new_oper_status );
                    $admin_status = get_new_admin_status( $admin_status, $new_admin_status );
                }

                $oper_status  = "unknown" if ( not $oper_status );
                $admin_status = "unknown" if ( not $admin_status );

                my ( $id );
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
    }

    if ( $self->{CHECK_ALL_VLANS} or scalar( keys %{ $self->{VLAN_FACILITIES} } ) > 0 ) {
        my ( $status, $eflows ) = $self->{AGENT}->getEFLOW();

        if ( $status == 0 ) {
            my %vlan_elements = ();

            foreach my $eflow_key ( keys %{$eflows} ) {
                my $eflow = $eflows->{$eflow_key};

                next unless ( $eflow->{"outervlanidrange"} );    # we only care about actual vlans

                my $vlan_number = $eflow->{"outervlanidrange"};

                my $vlan_name;
                if ( $eflow->{ingressporttype} eq "ETTP" ) {
                    $vlan_name = $eflow->{ingressportname} . "." . $vlan_number;
                }
                elsif ( $eflow->{egressporttype} eq "ETTP" ) {
                    $vlan_name = $eflow->{egressportname} . "." . $vlan_number;
                }
                else {
                    next;
                }

                next unless ( $self->{CHECK_ALL_VLANS} or $self->{VLAN_FACILITIES}->{$vlan_name} );

                $vlan_elements{$vlan_name} = () unless ( $vlan_elements{$vlan_name} );

                push @{ $vlan_elements{$vlan_name} }, $eflow;
            }

            # An eflow doesn't have status of its own, so you have to check
            # both the ingress port and egress port of the eflow to get "its"
            # status.
            foreach my $vlan_name ( keys %vlan_elements ) {

                my $oper_status;
                my $admin_status;
                foreach my $eflow ( @{ $vlan_elements{$vlan_name} } ) {
                    foreach my $type ( "ingressport", "egressport" ) {
                        my ( $status, $new_oper_status, $new_admin_status );

                        if ( $eflow->{ $type . "type" } eq "VCG" ) {
                            ( $status, $new_oper_status, $new_admin_status ) = $self->checkVCG( $eflow->{ $type . "name" } );
                        }
                        elsif ( $eflow->{ $type . "type" } eq "ETTP" ) {
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

                        $oper_status  = get_new_oper_status( $oper_status,   $new_oper_status );
                        $admin_status = get_new_admin_status( $admin_status, $new_admin_status );
                    }
                }

                my ( $id );

                if ( $self->{VLAN_FACILITIES}->{$vlan_name} ) {
                    $id           = $self->{VLAN_FACILITIES}->{$vlan_name}->{id}           if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{id} );
                    $admin_status = $self->{VLAN_FACILITIES}->{$vlan_name}->{admin_status} if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{admin_status} );
                    $oper_status  = $self->{VLAN_FACILITIES}->{$vlan_name}->{oper_status}  if ( $self->{VLAN_FACILITIES}->{$vlan_name}->{oper_status} );
                }

                my %facility = (
                    id           => $id,
                    name         => $vlan_name,
                    type         => "vlan",
                    oper_status  => $oper_status,
                    admin_status => $admin_status,
                );

                $self->{LOGGER}->debug( "Adding $vlan_name to facilities list" );

                push @facilities_to_update, \%facility;
            }
        }
    }

    if ( $self->{CHECK_ALL_ETHERNET_PORTS} or scalar( keys %{ $self->{ETHERNET_FACILITIES} } ) > 0 ) {
        my @ports_to_check = ();
        if ( $self->{CHECK_ALL_ETHERNET_PORTS} ) {
            my $ports;
            ( $status, $ports ) = $self->{AGENT}->getETH();
            if ( $status == 0 ) {
                foreach my $ethernet_key ( keys %{$ports} ) {
                    push @ports_to_check, $ports->{$ethernet_key};
                }
            }
        }
        else {
            foreach my $ethernet_aid ( keys %{ $self->{ETHERNET_FACILITIES} } ) {
                my $port;
                ( $status, $port ) = $self->{AGENT}->getETH( $ethernet_aid );
                if ( $status == 0 && $port ) {
                    push @ports_to_check, $port;
                }
            }
        }

        foreach my $port ( @ports_to_check ) {
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

            my ( $id );
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
        }
    }

    return ( 0, \@facilities_to_update );
}

=head2 checkVCG( $self, $vcg_name )

TBD

=cut

sub checkVCG {
    my ( $self, $vcg_name ) = @_;

    my ( $status, $vcgs );
    ( $status, $vcgs ) = $self->{AGENT}->getVCG();
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

TBD

=cut

sub checkETH {
    my ( $self, $eth_aid ) = @_;

    my ( $status, $port );
    ( $status, $port ) = $self->{AGENT}->getETH( $eth_aid );
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

TBD

=cut

sub connect {
    my ( $self ) = @_;

    if ( $self->{AGENT}->connect( { inhibitMessages => 1 } ) == -1 ) {
        $self->{LOGGER}->error( "Could not connect to host" );
        return 0;
    }

    return 1;
}

=head2 disconnect( $self )

TBD

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

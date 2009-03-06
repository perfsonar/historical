package perfSONAR_PS::Collectors::Status::DeviceAgents::OME;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::TL1::OME;
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

our $VERSION = 0.09;

use base 'perfSONAR_PS::Collectors::Status::DeviceAgents::Base';

use fields 'AGENT', 'OPTICAL_FACILITIES', 'ETHERNET_FACILITIES', 'WAN_FACILITIES', 'CHECK_ALL_OPTICAL_PORTS', 'CHECK_ALL_ETHERNET_PORTS', 'CHECK_ALL_WAN_PORTS';

my %state_mapping = (
		"is" => { "oper_status" => "up", "admin_status" => "normaloperation" },
		"is-anr" => { "oper_status" => "degraded", "admin_status" => "normaloperation" },
		"oos-ma" => { "oper_status" => "down", "admin_status" => "maintenance" },
		"oos-au" => { "oper_status" => "down", "admin_status" => "normaloperation" },
		"oos-auma" => { "oper_status" => "down", "admin_status" => "maintenance" },
		"oos-maanr" => { "oper_status" => "down", "admin_status" => "maintenance" },
		);

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
            check_all_ethernet_ports => 0,
            check_all_wan_ports      => 0,
            check_all_crossconnects  => 0,
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
    $self->{CHECK_ALL_WAN_PORTS} = $args->{check_all_wan_ports};

    $self->{OPTICAL_FACILITIES}     = ();
    $self->{ETHERNET_FACILITIES}    = ();
    $self->{WAN_FACILITIES}    = ();

    if ( $args->{facilities} ) {
        foreach my $facility ( @{ $args->{facilities} } ) {
            unless ( $facility->{type} ) {
                my $msg = "Facilities must have a 'type'. one of 'optical', 'ethernet', 'wan'";
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
            elsif ( $facility->{type} eq "wan" ) {
                $self->{WAN_FACILITIES}->{ $facility->{name} } = $facility;
            }
        }
    }

    $self->{AGENT} = perfSONAR_PS::Utils::TL1::OME->new();
    $self->{AGENT}->initialize(
        username   => $args->{username},
        password   => $args->{password},
        address    => $args->{address},
        port       => $args->{port},
        cache_time => 30
    );

    my $check_all = ( $self->{CHECK_ALL_WAN_PORTS} or $self->{CHECK_ALL_ETHERNET_PORTS} or $self->{CHECK_ALL_OPTICAL_PORTS} );
    if ( $check_all and ( not $self->{IDENTIFIER_PATTERN} or $self->{IDENTIFIER_PATTERN} !~ /%facility%/ ) ) {
        my $msg = "Performing generic facilities check, but invalid identifier pattern specified";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    return 0;
}

sub check_facilities {
    my ( $self ) = @_;

	my @facilities = ();

	my $optical_ports;
	my $ethernet_ports;
	my $wan_ports;

	if ( $self->{CHECK_ALL_OPTICAL_PORTS} or scalar( keys %{ $self->{OPTICAL_FACILITIES} } ) > 0 ) {
		my ($status, $res) = $self->{AGENT}->getOCN();
		if ($status == 0) {
			$optical_ports = $res;
		}
	}

	if ( $self->{CHECK_ALL_ETHERNET_PORTS} or scalar( keys %{ $self->{ETHERNET_FACILITIES} } ) > 0 ) {
		my ($status, $res) = $self->{AGENT}->getETH();
		if ($status == 0) {
			$ethernet_ports = $res;
		}
	}

	if ( $self->{CHECK_ALL_WAN_PORTS} or scalar( keys %{ $self->{WAN_FACILITIES} } ) > 0 ) {
		my ($status, $res) = $self->{AGENT}->getWAN();
		if ($status == 0) {
			$wan_ports = $res;
		}
	}

	if ( $optical_ports ) {
		my @facility_names;
		if ( $self->{CHECK_ALL_OPTICAL_PORTS} ) {
			@facility_names = keys %{$optical_ports};
		}
		else {
			@facility_names = keys %{ $self->{OPTICAL_FACILITIES} };
		}

		foreach my $name ( @facility_names ) {
			my $port = $optical_ports->{$name};

			next unless ($port);

			my $oper_status;
			my $admin_status;

			unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
				$oper_status = "unknown";
				$admin_status = "unknown";
			}
			else {
				$oper_status = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
				$admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
			}

			my ( $id );
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

			push @facilities, \%facility;
		}
	}

	if ( $ethernet_ports ) {
		my @facility_names;
		if ( $self->{CHECK_ALL_ETHERNET_PORTS} ) {
			@facility_names = keys %{$ethernet_ports};
		}
		else {
			@facility_names = keys %{ $self->{ETHERNET_FACILITIES} };
		}

		foreach my $name ( @facility_names ) {
			my $port = $ethernet_ports->{$name};

			next unless ($port);

			my $oper_status;
			my $admin_status;

			unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
				$oper_status = "unknown";
				$admin_status = "unknown";
			}
			else {
				$oper_status = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
				$admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
			}

			my ( $id );
			if ( $self->{ETHERNET_FACILITIES}->{$name} ) {
				$id           = $self->{ETHERNET_FACILITIES}->{$name}->{id}           if ( $self->{ETHERNET_FACILITIES}->{$name}->{id} );
				$admin_status = $self->{ETHERNET_FACILITIES}->{$name}->{admin_status} if ( $self->{ETHERNET_FACILITIES}->{$name}->{admin_status} );
				$oper_status  = $self->{ETHERNET_FACILITIES}->{$name}->{oper_status}  if ( $self->{ETHERNET_FACILITIES}->{$name}->{oper_status} );
			}

			my %facility = (
					id           => $id,
					name         => $name,
					type         => "ethernet",
					oper_status  => $oper_status,
					admin_status => $admin_status,
					);

			push @facilities, \%facility;
		}
	}

	if ( $wan_ports ) {
		my @facility_names;
		if ( $self->{CHECK_ALL_WAN_PORTS} ) {
			@facility_names = keys %{$wan_ports};
		}
		else {
			@facility_names = keys %{ $self->{WAN_FACILITIES} };
		}

		foreach my $name ( @facility_names ) {
			my $port = $wan_ports->{$name};

			next unless ($port);

			my $oper_status;
			my $admin_status;

			unless ( $port->{pst} and $state_mapping{ lc( $port->{pst} ) } ) {
				$oper_status = "unknown";
				$admin_status = "unknown";
			}
			else {
				$oper_status = $state_mapping{ lc( $port->{pst} ) }->{"oper_status"};
				$admin_status = $state_mapping{ lc( $port->{pst} ) }->{"admin_status"};
			}

			my ( $id );
			if ( $self->{WAN_FACILITIES}->{$name} ) {
				$id           = $self->{WAN_FACILITIES}->{$name}->{id}           if ( $self->{WAN_FACILITIES}->{$name}->{id} );
				$admin_status = $self->{WAN_FACILITIES}->{$name}->{admin_status} if ( $self->{WAN_FACILITIES}->{$name}->{admin_status} );
				$oper_status  = $self->{WAN_FACILITIES}->{$name}->{oper_status}  if ( $self->{WAN_FACILITIES}->{$name}->{oper_status} );
			}

			my %facility = (
					id           => $id,
					name         => $name,
					type         => "ethernet",
					oper_status  => $oper_status,
					admin_status => $admin_status,
					);

			push @facilities, \%facility;
		}
	}

    return (0, \@facilities);
}

sub connect {
	my ($self) = @_;

	if ( $self->{AGENT}->connect( { inhibitMessages => 1 } ) == -1 ) {
		$self->{LOGGER}->error( "Could not connect to host" );
		return 0;
	}

	return 1;
}

sub disconnect {
	my ($self) = @_;

	return $self->{AGENT}->disconnect();
}

1;

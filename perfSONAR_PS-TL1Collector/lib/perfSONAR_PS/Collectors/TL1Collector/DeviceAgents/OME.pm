package perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::OME;

use strict;
use warnings;

our $VERSION = 3.3;

=head1 NAME

perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::OME

=head1 DESCRIPTION

This module polls a OME6500 using TL1 for the operational and administrative
status of its facilities. It will grab the operational and administrative
status of all the facilities it's been configured to handle and store that
information into a status database.


=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::TL1::OME;
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use base 'perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::Base';

use fields 'AGENT', 'OPTICAL_FACILITIES', 'ETHERNET_FACILITIES', 'WAN_FACILITIES', 'CHECK_ALL_OPTICAL_PORTS', 'CHECK_ALL_ETHERNET_PORTS', 'CHECK_ALL_WAN_PORTS';

my %state_mapping = (
    "is"        => { "oper_status" => "up",       "admin_status" => "normaloperation" },
    "is-anr"    => { "oper_status" => "degraded", "admin_status" => "normaloperation" },
    "oos-ma"    => { "oper_status" => "down",     "admin_status" => "maintenance" },
    "oos-au"    => { "oper_status" => "down",     "admin_status" => "normaloperation" },
    "oos-auma"  => { "oper_status" => "down",     "admin_status" => "maintenance" },
    "oos-maanr" => { "oper_status" => "down",     "admin_status" => "maintenance" },
);

=head2 init( $self, { data_client, polling_interval, address, port, username, password, check_all_optical_ports, check_all_ethernet_ports, check_all_wan_ports, facilities, identifier_pattern } )

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
            check_all_ethernet_ports => 0,
            check_all_wan_ports      => 0,
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
    $self->{CHECK_ALL_WAN_PORTS}      = $args->{check_all_wan_ports};

    $self->{OPTICAL_FACILITIES}  = ();
    $self->{ETHERNET_FACILITIES} = ();
    $self->{WAN_FACILITIES}      = ();

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

=head2 check_facilities( $self )

A function which is called by the Base class to check on the status of
faciltiies. The function checks all the ports identified, and returns an array
of hashes describing each facility and its status.

=cut

sub check_facilities {
    my ( $self ) = @_;

    my @facilities = ();

    my $optical_ports;
    my $ethernet_ports;
    my $wan_ports;

    if ( $self->{CHECK_ALL_OPTICAL_PORTS} or scalar( keys %{ $self->{OPTICAL_FACILITIES} } ) > 0 ) {
        my ( $status, $res ) = $self->{AGENT}->get_optical_facilities();
        if ( $status == 0 ) {
            $optical_ports = $res;
        }
    }

    if ( $self->{CHECK_ALL_ETHERNET_PORTS} or scalar( keys %{ $self->{ETHERNET_FACILITIES} } ) > 0 ) {
        my ( $status, $res ) = $self->{AGENT}->get_ethernet_facilities();
        if ( $status == 0 ) {
            $ethernet_ports = $res;
        }
    }

    if ( $self->{CHECK_ALL_WAN_PORTS} or scalar( keys %{ $self->{WAN_FACILITIES} } ) > 0 ) {
        my ( $status, $res ) = $self->{AGENT}->get_wan_facilities();
        if ( $status == 0 ) {
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

            next unless ( $port );

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

            next unless ( $port );

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

            next unless ( $port );

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

    return ( 0, \@facilities );
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

=head2 disconnect($self)

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

L<Params::Validate>, L<Log::Log4perl>, L<perfSONAR_PS::Utils::TL1::OME>,
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

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

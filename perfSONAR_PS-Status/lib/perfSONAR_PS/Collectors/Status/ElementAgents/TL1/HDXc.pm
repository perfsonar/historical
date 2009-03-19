package perfSONAR_PS::Collectors::Status::ElementAgents::TL1::HDXc;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::Status::ElementAgents::TL1::HDXc

=head1 DESCRIPTION

TBD

=cut

use fields 'AGENT', 'TYPE', 'LOGGER', 'ELEMENT_TYPE', 'ELEMENT_ID', 'ELEMENT_ID_TYPE';

=head2 new( $class, { type, address, port, username, password, agent, element_id, element_id_type, element_type } )

TBD

=cut

sub new {
    my ( $class, @params ) = @_;

    my $parameters = validateParams(
        @params,
        {
            type            => 1,
            address         => 0,
            port            => 0,
            username        => 0,
            password        => 0,
            agent           => 0,
            element_id      => 1,
            element_id_type => 0,
            element_type    => 1,
        }
    );

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    # we need to be able to generate a new tl1 agent or reuse an existing one. Not neither.
    if (
        not $parameters->{agent}
        and (  not $parameters->{address}
            or not $parameters->{username}
            or not $parameters->{password} )
        )
    {
        return;
    }

    # We only check the operational state (or what, at least, the primary state).
    if ( $parameters->{type} ne "oper" ) {
        return;
    }

    if ( not defined $parameters->{agent} ) {
        $parameters->{agent} = perfSONAR_PS::Utils::TL1::HDXc->new();
        $parameters->{agent}->initialize(
            username   => $parameters->{username},
            password   => $parameters->{password},
            address    => $parameters->{address},
            port       => $parameters->{port},
            cache_time => 300
        );
    }

    $self->type( $parameters->{type} );
    $self->agent( $parameters->{agent} );
    my $res = $self->set_element( { type => $parameters->{element_type}, id => $parameters->{element_id}, id_type => $parameters->{element_id_type} } );
    if ( not $res ) {
        return;
    }

    return $self;
}

my %state_mapping = (
    "is"  => "up",
    "oss" => "down",
);

=head2 run_eth( $self )

TBD

=cut

sub run_eth {
    my ( $self ) = @_;
    my ( $status, $time );

    $status = $self->{AGENT}->getETH( $self->{ELEMENT_ID} );
    $time   = $self->{AGENT}->getCacheTime();

    $self->{LOGGER}->debug( Dumper( $status ) );

    if ( not $status->{pst} ) {
        return ( 0, $time, "unknown" );
    }

    my $oper_status;

    unless ( $status->{pst} and $state_mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $state_mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 run_ocn( $self )

TBD

=cut

sub run_ocn {
    my ( $self ) = @_;
    my ( $status, $time );

    $status = $self->{AGENT}->getOCN( $self->{ELEMENT_ID} );
    $time   = $self->{AGENT}->getCacheTime();

    my $oper_status;

    unless ( $status->{pst} and $state_mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $state_mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 run( $self )

TBD

=cut

sub run {
    my ( $self ) = @_;

    if ( $self->{ELEMENT_TYPE} =~ /^eth/ ) {
        return $self->run_eth();
    }
    elsif ( $self->{ELEMENT_TYPE} =~ /^oc(n|[0-9]+)/ or $self->{ELEMENT_TYPE} eq "optical" ) {
        return $self->run_ocn();
    }
}

=head2 type( $self, $type )

TBD

=cut

sub type {
    my ( $self, $type ) = @_;

    if ( $type ) {
        $self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

=head2 agent( $self, $agent )

TBD

=cut

sub agent {
    my ( $self, $agent ) = @_;

    if ( $agent ) {
        $self->{AGENT} = $agent;
    }

    return $self->{AGENT};
}

=head2 set_element( $self,  { type, id, id_type } )

TBD

=cut

sub set_element {
    my ( $self, @params ) = @_;

    my $parameters = validateParams(
        @params,
        {
            type    => 1,
            id      => 1,
            id_type => 0,
        }
    );

    $parameters->{type} = lc( $parameters->{type} );
    $parameters->{id_type} = lc( $parameters->{id_type} ) if ( $parameters->{id_type} );

    unless ( $parameters->{type} =~ /^eth/ or $parameters->{type} =~ /^oc(n|[0-9]+)/ or $parameters->{type} eq "optical" ) {
        $self->{LOGGER}->error( "Unknown element type: '" . $parameters->{type} . "'" );
        return;
    }

    $self->{ELEMENT_ID}   = $parameters->{id};
    $self->{ELEMENT_TYPE} = $parameters->{type};

    if ( $parameters->{type} =~ /^oc(n|[0-9]+)/ or $parameters->{type} eq "optical" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "aid" ) {
                return;
            }
        }
        $self->{ELEMENT_ID_TYPE} = "aid";
    }
    elsif ( $parameters->{type} =~ /^eth/ ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "aid" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "aid";
    }

    return $self->{ELEMENT_ID};
}

=head2 element_id( $self )

TBD

=cut

sub element_id {
    my ( $self ) = @_;

    return $self->{ELEMENT_ID};
}

=head2 element_type( $self )

TBD

=cut

sub element_type {
    my ( $self ) = @_;

    return $self->{ELEMENT_TYPE};
}

=head2 element_id_type( $self )

TBD

=cut

sub element_id_type {
    my ( $self ) = @_;

    return $self->{ELEMENT_ID_TYPE};
}

1;

__END__

=head1 SEE ALSO

L<Params::Validate>, L<Log::Log4perl>,
L<perfSONAR_PS::Utils::ParameterValidation>, L<perfSONAR_PS::Utils::TL1::OME>,
L<Data::Dumper>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id:$

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

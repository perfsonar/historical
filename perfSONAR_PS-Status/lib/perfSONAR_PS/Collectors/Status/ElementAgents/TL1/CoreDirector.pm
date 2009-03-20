package perfSONAR_PS::Collectors::Status::ElementAgents::TL1::CoreDirector;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::Status::ElementAgents::TL1::CoreDirector

=head1 DESCRIPTION

TBD

=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::TL1::CoreDirector;
use Data::Dumper;

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
        $parameters->{agent} = perfSONAR_PS::Utils::TL1::CoreDirector->new();
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

=head2 runVCG( $self )

TBD

=cut

sub runVCG {
    my ( $self ) = @_;
    my $status   = $self->{AGENT}->getVCG( $self->{ELEMENT_ID} );
    my $time     = $self->{AGENT}->getCacheTime();

    print "VCGRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 runCTP( $self, $name )

TBD

=cut

sub runCTP {
    my ( $self, $name ) = @_;
    my $status = $self->{AGENT}->getCTP( $self->{ELEMENT_ID} );
    my $time   = $self->{AGENT}->getCacheTime();

    print "CTPRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 runSNC( $self, $name )

TBD

=cut

sub runSNC {
    my ( $self, $name ) = @_;
    my $status = $self->{AGENT}->getSNC( $self->{ELEMENT_ID} );
    my $time   = $self->{AGENT}->getCacheTime();

    print "SNCRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 runETH( $self, $aid )

TBD

=cut

sub runETH {
    my ( $self, $aid ) = @_;

    return;
}

=head2 runOCN( $self, $aid )

TBD

=cut

sub runOCN {
    my ( $self, $aid ) = @_;
    my $status = $self->{AGENT}->getOCN( $self->{ELEMENT_ID} );
    my $time   = $self->{AGENT}->getCacheTime();

    print "OCNRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );

}

=head2 runGTP( $self, $name )

TBD

=cut

sub runGTP {
    my ( $self, $name ) = @_;
    my $status = $self->{AGENT}->getGTP( $self->{ELEMENT_ID} );
    my $time   = $self->{AGENT}->getCacheTime();

    print "GTPRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 runCrossconnect( $self, $name )

TBD

=cut

sub runCrossconnect {
    my ( $self, $name ) = @_;
    my $status = $self->{AGENT}->getCrossconnect( $self->{ELEMENT_ID} );
    my $time   = $self->{AGENT}->getCacheTime();

    print "CRSRES(" . $self->{ELEMENT_ID} . "): " . Dumper( $status );
    print "-PST: '" . lc( $status->{pst} ) . "'\n";

    my %mapping = (
        "is-anr"   => "degraded",
        "is-nr"    => "up",
        "oos-au"   => "down",
        "oos-auma" => "down",
        "oos-ma"   => "down",
    );

    my $oper_status;

    unless ( $status->{pst} and $mapping{ lc( $status->{pst} ) } ) {
        $oper_status = "unknown";
    }
    else {
        $oper_status = $mapping{ lc( $status->{pst} ) };
    }

    return ( 0, $time, $oper_status );
}

=head2 run( $self )

TBD

=cut

sub run {
    my ( $self ) = @_;

    $self->{LOGGER}->debug( "Running status collector on " . $self->{ELEMENT_TYPE} . "/" . $self->{ELEMENT_ID} );

    if ( $self->{ELEMENT_TYPE} eq "crossconnect" ) {
        return $self->runCrossconnect();
    }
    elsif ( $self->{ELEMENT_TYPE} eq "vcg" ) {
        return $self->runVCG();
    }
    elsif ( $self->{ELEMENT_TYPE} eq "snc" ) {
        return $self->runSNC();
    }
    elsif ( $self->{ELEMENT_TYPE} =~ /^oc(n|[0-9]+)/ ) {
        return $self->runOCN();
    }
    elsif ( $self->{ELEMENT_TYPE} eq "gtp" ) {
        return $self->runGTP();
    }
    elsif ( $self->{ELEMENT_TYPE} eq "ctp" ) {
        return $self->runCTP();
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

=head2 set_element( $self, { type, id, id_type } )

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

    unless ( $parameters->{type} =~ /^eth/ or $parameters->{type} eq "vcg" or $parameters->{type} eq "snc" or $parameters->{type} eq "gtp" or $parameters->{type} =~ /^oc(n|[0-9]+)/ or $parameters->{type} eq "ctp" or $parameters->{type} eq "crossconnect" ) {
        $self->{LOGGER}->error( "Unknown element type: '" . $parameters->{type} . "'" );
        return;
    }

    $self->{ELEMENT_ID}   = $parameters->{id};
    $self->{ELEMENT_TYPE} = $parameters->{type};

    if ( $parameters->{type} eq "gtp" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} eq "eflow" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} eq "crossconnect" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} eq "snc" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} eq "vcg" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} eq "sts" ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "name" ) {
                return;
            }
        }

        $self->{ELEMENT_ID_TYPE} = "name";
    }
    elsif ( $parameters->{type} =~ /oc(n|[0-9]+)/ ) {
        if ( $parameters->{id_type} ) {
            unless ( $parameters->{id_type} eq "aid" ) {
                return;
            }
        }
        $self->{ELEMENT_ID_TYPE} = "aid";
    }
    elsif ( $parameters->{type} =~ /eth/ ) {
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
L<perfSONAR_PS::Utils::ParameterValidation>,
L<perfSONAR_PS::Utils::TL1::CoreDirector>, L<Data::Dumper>

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

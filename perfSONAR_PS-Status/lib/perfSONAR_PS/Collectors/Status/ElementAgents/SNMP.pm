package perfSONAR_PS::Collectors::Status::ElementAgents::SNMP;

use strict;
use warnings;

our $VERSION = 3.2;

=head1 NAME

perfSONAR_PS::Collectors::Status::ElementAgents::SNMP

=head1 DESCRIPTION

This module provides an agent for the Link Status Collector that gets status
information for a link by asking an SNMP server.

This agent will query the SNMP service and return the estimated time on the
SNMP server, along with the status of the given interface. The actual structure
of the agent is split into two pieces (stored in one file for clarity). There's
an element whose sole purpose is to grab all the SNMP stats from a given host
and cache them. This is described at the bottom of the file. Then, there is a
higher-level agent, whose sole purpose is to get a single data point for a
single ifIndex. The caching object is meant to be shared among all the agents
so that it does not clutter the SNMP server with numerous calls each time
status information is grabbed. While users can get the caching element for a
given agent, they should not interact with it directly.

=head1 API

=cut

use fields 'TYPE', 'HOSTNAME', 'IFINDEX', 'COMMUNITY', 'VERSION', 'OID', 'AGENT';

=head2 new ($package, $status_type, $hostname, $ifIndex, $version, $community, $oid, $agent)

This function instantiates a new SNMP Agent for grabbing the ifIndex/oid off the
specified host. The $agent element is an optional one that can be used to pass
in an existing caching object. If unspecified, a new caching object will be
created.

=cut

sub new {
    my ( $class, $type, $hostname, $ifIndex, $version, $community, $oid, $agent ) = @_;

    my $self = fields::new( $class );

    if ( defined $agent and $agent ) {
        $self->{"AGENT"} = $agent;
    }
    else {
        $self->{"AGENT"} = new perfSONAR_PS::Collectors::LinkStatus::SNMPAgent( $hostname, q{}, $version, $community, q{} );
    }

    $self->{"TYPE"}      = $type;
    $self->{"HOSTNAME"}  = $hostname;
    $self->{"IFINDEX"}   = $ifIndex;
    $self->{"COMMUNITY"} = $community;
    $self->{"VERSION"}   = $version;
    $self->{"OID"}       = $oid;

    return $self;
}

=head2 type

Gets/sets the status type of this agent: admin or oper.

=cut

sub type {
    my ( $self, $type ) = @_;

    if ( defined $type and $type ) {
        $self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

=head2 hostname ($self, $hostname)

Gets/sets the hostname for this agent to poll.

=cut

sub hostname {
    my ( $self, $hostname ) = @_;

    if ( defined $hostname and $hostname ) {
        $self->{HOSTNAME} = $hostname;
    }

    return $self->{HOSTNAME};
}

=head2 ifIndex ($self, $ifIndex)

Gets/sets the ifIndex that this agent returns the status of.

=cut

sub ifIndex {
    my ( $self, $ifIndex ) = @_;

    if ( defined $ifIndex and $ifIndex ) {
        $self->{IFINDEX} = $ifIndex;
    }

    return $self->{IFINDEX};
}

=head2 community ($self, $community)

Gets/sets the community string that will be used by this agent.

=cut

sub community {
    my ( $self, $community ) = @_;

    if ( defined $community and $community ) {
        $self->{COMMUNITY} = $community;
    }

    return $self->{COMMUNITY};
}

=head2 version ($self, $version)

Gets/sets the snmp version string for this agent.

=cut

sub version {
    my ( $self, $version ) = @_;

    if ( defined $version and $version ) {
        $self->{VERSION} = $version;
    }

    return $self->{VERSION};
}

=head2 OID ($self, $oid)

Gets/sets the OID for this agent.

=cut

sub OID {
    my ( $self, $oid ) = @_;

    if ( defined $oid and $oid ) {
        $self->{OID} = $oid;
    }

    return $self->{OID};
}

=head2 agent ($self, $agent)

Gets/sets the caching snmp object used by this agent

=cut

sub agent {
    my ( $self, $agent ) = @_;

    if ( defined $agent and $agent ) {
        $self->{AGENT} = $agent;
    }

    return $self->{AGENT};
}

=head2 run ($self)

Queries the local caching object for the OID/ifIndex of interest and grabs the
most recent time for the SNMP server. It then converts the result of the
OID/ifIndex into a known status type and returns the time/status.

=cut

sub run {
    my ( $self ) = @_;

    $self->{AGENT}->setSession;
    my $measurement_value = $self->{AGENT}->getVar( $self->{OID} . "." . $self->{IFINDEX} );
    my $measurement_time  = $self->{AGENT}->getHostTime;
    $self->{AGENT}->closeSession;

    if ( defined $measurement_value and $measurement_value ) {
        if ( exists $self->{OID} and $self->{OID} eq "1.3.6.1.2.1.2.2.1.8" ) {
            if ( $measurement_value eq "2" ) {
                $measurement_value = "down";
            }
            elsif ( $measurement_value eq "1" ) {
                $measurement_value = "up";
            }
            else {
                $measurement_value = "unknown";
            }
        }
        elsif ( exists $self->{OID} and $self->{OID} eq "1.3.6.1.2.1.2.2.1.7" ) {
            if ( $measurement_value eq "2" ) {
                $measurement_value = "down";
            }
            elsif ( $measurement_value eq "1" ) {
                $measurement_value = "normaloperation";
            }
            elsif ( $measurement_value eq "3" ) {
                $measurement_value = "troubleshooting";
            }
            else {
                $measurement_value = "unknown";
            }
        }
    }
    else {
        return ( -1, "No value for measurement" );
    }

    return ( 0, $measurement_time, $measurement_value );
}

1;

# ================ Internal Package perfSONAR_PS::Collectors::LinkStatus::SNMPAgent ================

package perfSONAR_PS::Collectors::Status::ElementAgents::SNMP::Host;

use strict;
use warnings;

our $VERSION = 3.2;

=head1 NAME

TBD

=head1 DESCRIPTION

TBD

=head1 API

=cut

use Net::SNMP;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;

use fields 'HOST', 'PORT', 'VERSION', 'COMMUNITY', 'VARIABLES', 'CACHED_TIME', 'CACHE_LENGTH', 'HOSTTICKS', 'SESSION', 'ERROR', 'REFTIME', 'CACHED';

=head2 new( $class, $host, $port, $ver, $comm, $vars, $cache_length )

TBD

=cut

sub new {
    my ( $class, $host, $port, $ver, $comm, $vars, $cache_length ) = @_;

    my $self = fields::new( $class );

    if ( defined $host and $host ) {
        $self->{"HOST"} = $host;
    }
    if ( defined $port and $port ) {
        $self->{"PORT"} = $port;
    }
    else {
        $self->{"PORT"} = 161;
    }
    if ( defined $ver and $ver ) {
        $self->{"VERSION"} = $ver;
    }
    if ( defined $comm and $comm ) {
        $self->{"COMMUNITY"} = $comm;
    }
    if ( defined $vars and $vars ) {
        $self->{"VARIABLES"} = \%{$vars};
    }
    else {
        $self->{"VARIABLES"} = ();
    }
    if ( defined $cache_length and $cache_length ) {
        $self->{"CACHE_LENGTH"} = $cache_length;
    }
    else {
        $self->{"CACHE_LENGTH"} = 1;
    }

    $self->{"VARIABLES"}->{"1.3.6.1.2.1.1.3.0"} = q{};    # add the host ticks so we can track it
    $self->{"HOSTTICKS"} = 0;

    return $self;
}

=head2 setHost( $self, $host )

TBD

=cut

sub setHost {
    my ( $self, $host ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $host and $host ) {
        $self->{HOST}      = $host;
        $self->{HOSTTICKS} = 0;
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setPort( $self, $port )

TBD

=cut

sub setPort {
    my ( $self, $port ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $port and $port ) {
        $self->{PORT} = $port;
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setVersion( $self, $ver )

TBD

=cut

sub setVersion {
    my ( $self, $ver ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $ver and $ver ) {
        $self->{VERSION} = $ver;
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setCommunity( $self, $comm )

TBD

=cut

sub setCommunity {
    my ( $self, $comm ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $comm and $comm ) {
        $self->{COMMUNITY} = $comm;
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setVariables( $self, $vars )

TBD

=cut

sub setVariables {
    my ( $self, $vars ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $vars and $vars ) {
        $self->{"VARIABLES"} = \%{$vars};
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setCacheLength( $self, $cache_length )

TBD

=cut

sub setCacheLength {
    my ( $self, $cache_length ) = @_;

    if ( defined $cache_length and $cache_length ) {
        $self->{"CACHE_LENGTH"} = $cache_length;
    }
    return;
}

=head2 addVariable( $self, $var )

TBD

=cut

sub addVariable {
    my ( $self, $var ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( not defined $var or $var eq q{} ) {
        $logger->error( "Missing argument." );
    }
    else {
        $self->{VARIABLES}->{$var} = q{};
    }
    return;
}

=head2 getVar( $self, $var ) 

TBD

=cut

sub getVar {
    my ( $self, $var ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( not defined $var or $var eq q{} ) {
        $logger->error( "Missing argument." );
        return;
    }

    if ( not exists $self->{VARIABLES}->{$var} or not exists $self->{CACHED_TIME} or time() - $self->{CACHED_TIME} > $self->{CACHE_LENGTH} ) {
        $self->{VARIABLES}->{$var} = "";

        my ( $status, $res ) = $self->collectVariables();
        if ( $status != 0 ) {
            return;
        }

        my %results = %{$res};

        $self->{CACHED}      = \%results;
        $self->{CACHED_TIME} = time();
    }

    return $self->{CACHED}->{$var};
}

=head2 getHostTime( $self )

TBD

=cut

sub getHostTime {
    my ( $self ) = @_;
    return $self->{REFTIME};
}

=head2 refreshVariables( $self )

TBD

=cut

sub refreshVariables {
    my ( $self ) = @_;
    my ( $status, $res ) = $self->collectVariables();

    if ( $status != 0 ) {
        return;
    }

    my %results = %{$res};

    $self->{CACHED}      = \%results;
    $self->{CACHED_TIME} = time();

    return;
}

=head2 getVariableCount( $self )

TBD

=cut

sub getVariableCount {
    my ( $self ) = @_;

    my $num = 0;
    foreach my $oid ( keys %{ $self->{VARIABLES} } ) {
        $num++;
    }
    return $num;
}

=head2 removeVariables( $self )

TBD

=cut

sub removeVariables {
    my ( $self ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    undef $self->{VARIABLES};
    if ( exists $self->{VARIABLES} and $self->{VARIABLES} ) {
        $logger->error( "Remove failure." );
    }
    return;
}

=head2 removeVariable( $self, $var )

TBD

=cut

sub removeVariable {
    my ( $self, $var ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $var and $var ) {
        delete $self->{VARIABLES}->{$var};
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

=head2 setSession( $self )

TBD

=cut

sub setSession {
    my ( $self ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if (    ( exists $self->{COMMUNITY} and $self->{COMMUNITY} )
        and ( exists $self->{VERSION} and $self->{VERSION} )
        and ( exists $self->{HOST}    and $self->{HOST} )
        and ( exists $self->{PORT}    and $self->{PORT} ) )
    {

        ( $self->{SESSION}, $self->{ERROR} ) = Net::SNMP->session(
            -community => $self->{COMMUNITY},
            -version   => $self->{VERSION},
            -hostname  => $self->{HOST},
            -port      => $self->{PORT},
            -translate => [ -timeticks => 0x0 ]
        ) or $logger->error( "Couldn't open SNMP session to \"" . $self->{HOST} . "\"." );

        unless ( exists $self->{SESSION} ) {
            $logger->error( "SNMP error: " . $self->{ERROR} );
        }
    }
    else {
        $logger->error( "Session requires arguments 'host', 'version', and 'community'." );
    }
    return;
}

=head2 closeSession( $self )

TBD

=cut

sub closeSession {
    my ( $self ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( exists $self->{SESSION} and $self->{SESSION} ) {
        $self->{SESSION}->close;
    }
    else {
        $logger->error( "Cannont close undefined session." );
    }
    return;
}

=head2 collectVariables( $self ) 

TBD

=cut

sub collectVariables {
    my ( $self ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( exists $self->{SESSION} and $self->{SESSION} ) {
        my @oids = ();

        foreach my $oid ( keys %{ $self->{VARIABLES} } ) {
            push @oids, $oid;
        }

        my $res = $self->{SESSION}->get_request( -varbindlist => \@oids ) or $logger->error( "SNMP error." );

        if ( not defined( $res ) ) {
            my $msg = "SNMP error: " . $self->{SESSION}->error;
            $logger->error( $msg );
            return ( -1, $msg );
        }
        else {
            my %results;

            %results = %{$res};

            if ( not exists $results{"1.3.6.1.2.1.1.3.0"} ) {
                $logger->warn( "No time values, getTime may be screwy" );
            }
            else {
                my $new_ticks = $results{"1.3.6.1.2.1.1.3.0"} / 100;

                if ( $self->{HOSTTICKS} == 0 ) {
                    my ( $sec, $frac ) = Time::HiRes::gettimeofday;
                    $self->{REFTIME} = $sec . "." . $frac;
                }
                else {
                    $self->{REFTIME} += $new_ticks - $self->{HOSTTICKS};
                }

                $self->{HOSTTICKS} = $new_ticks;
            }

            return ( 0, $res );
        }
    }
    else {
        my $msg = "Session to \"" . $self->{HOST} . "\" not found.";
        $logger->error( $msg );
        return ( -1, $msg );
    }
}

=head2 collect( $self, $var )

TBD

=cut

sub collect {
    my ( $self, $var ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::SNMPAgent" );

    if ( defined $var and $var ) {
        if ( exists $self->{SESSION} ) {
            my $results = $self->{SESSION}->get_request( -varbindlist => [$var] ) or $logger->error( "SNMP error: \"" . $self->{ERROR} . "\"." );
            if ( not defined( $results ) ) {
                $logger->error( "SNMP error: \"" . $self->{ERROR} . "\"." );
                return -1;
            }
            else {
                return $results->{"$var"};
            }
        }
        else {
            $logger->error( "Session to \"" . $self->{HOST} . "\" not found." );
            return -1;
        }
    }
    else {
        $logger->error( "Missing argument." );
    }
    return;
}

1;

__END__

=head1 SEE ALSO

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu
Jason Zurawski, zurawski@inernet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2010, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

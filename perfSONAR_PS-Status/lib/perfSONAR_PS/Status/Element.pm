package perfSONAR_PS::Status::Element;

use strict;
use warnings;

our $VERSION = 3.2;

=head1 NAME

perfSONAR_PS::Status::Element

=head1 DESCRIPTION

A module that provides an object with an interface for element status
information.  This module is to be treated as an object representing the status
of an element for a certain range of time.

=head1 API

=cut

use fields 'ID', 'START_TIME', 'END_TIME', 'OPER_STATUS', 'ADMIN_STATUS';

=head2 new ($package, $element_id, $start_time, $end_time, $oper_status, $admin_status)

Creates a new instance of a Element object with the specified values (None of
which is required, they can all be set later).

=cut

sub new {
    my ( $package, $element_id, $start_time, $end_time, $oper_status, $admin_status ) = @_;

    my $self = fields::new( $package );

    if ( defined $element_id and $element_id ) {
        $self->{ID} = $element_id;
    }
    if ( defined $start_time and $start_time ) {
        $self->{START_TIME} = $start_time;
    }
    if ( defined $end_time and $end_time ) {
        $self->{END_TIME} = $end_time;
    }
    if ( defined $oper_status and $oper_status ) {
        $self->{OPER_STATUS} = $oper_status;
    }
    if ( defined $admin_status and $admin_status ) {
        $self->{ADMIN_STATUS} = $admin_status;
    }

    return $self;
}

=head2 setID ($self, $id)

Sets the identifier for this element.

=cut

sub setID {
    my ( $self, $id ) = @_;

    $self->{ID} = $id if defined $id;

    return;
}

=head2 setStartTime ($self, $starttime)

Sets the start time of the range over which this element had the specified status

=cut

sub setStartTime {
    my ( $self, $starttime ) = @_;

    $self->{START_TIME} = $starttime if defined $starttime;

    return;
}

=head2 setEndTime ($self, $endtime)

Sets the end time of the range over which this element had the specified status

=cut

sub setEndTime {
    my ( $self, $endtime ) = @_;

    $self->{END_TIME} = $endtime if defined $endtime;

    return;
}

=head2 setOperStatus ($self, $oper_status)

Sets the operational status of this element over the range of time specified

=cut

sub setOperStatus {
    my ( $self, $oper_status ) = @_;

    $self->{OPER_STATUS} = $oper_status if defined $oper_status;

    return;
}

=head2 setAdminStatus ($self, $admin_status)

Sets the administrative status of this element over the range of time specified

=cut

sub setAdminStatus {
    my ( $self, $admin_status ) = @_;

    $self->{ADMIN_STATUS} = $admin_status if defined $admin_status;

    return;
}

=head2 getID ($self)

Gets the identifier for this element

=cut

sub getID {
    my ( $self ) = @_;

    return $self->{ID};
}

=head2 getStartTime ($self)

Gets the start time of the range over which this element had the specified status

=cut

sub getStartTime {
    my ( $self ) = @_;

    return $self->{START_TIME};
}

=head2 getEndTime ($self)

Gets the end time of the range over which this element had the specified status

=cut

sub getEndTime {
    my ( $self ) = @_;

    return $self->{END_TIME};
}

=head2 getOperStatus ($self)

Gets the operational status of this element

=cut

sub getOperStatus {
    my ( $self ) = @_;

    return $self->{OPER_STATUS};
}

=head2 getAdminStatus ($self)

Gets the administrative status of this element

=cut

sub getAdminStatus {
    my ( $self ) = @_;

    return $self->{ADMIN_STATUS};
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

$Id: Element.pm 2640 2009-03-20 01:21:21Z zurawski $

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut

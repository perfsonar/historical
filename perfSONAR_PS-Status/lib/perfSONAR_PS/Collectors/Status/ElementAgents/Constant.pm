package perfSONAR_PS::Collectors::Status::ElementAgents::Constant;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::LinkStatus::Agent::Constant

=head1 DESCRIPTION

This module provides an agent for the Link Status Collector that simply returns
a constant value.  When run, this agent will simply return the constant value
its been configured to return along with the machine's current time.

=head1 API

=cut

use fields 'TYPE', 'CONSTANT';

=head2 new ($self, $status_type, $constant)

Creates a new Constant Agent of the specified type and with the specified
constant value.

=cut

sub new {
    my ( $class, $type, $constant ) = @_;

    my $self = fields::new( $class );

    $self->{"TYPE"}     = $type;
    $self->{"CONSTANT"} = $constant;

    return $self;
}

=head2 type

Set/return the status type of this agent: admin or oper.

=cut

sub type {
    my ( $self, $type ) = @_;

    if ( $type ) {
        $self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

=head2 constant ($self, $constant)

Sets/Gets the constant value to be returned.

=cut

sub constant {
    my ( $self, $constant ) = @_;

    if ( $constant ) {
        $self->{CONSTANT} = $constant;
    }

    return $self->{CONSTANT};
}

=head2 run ($self)

Returns the constant value that's been configured along with the current time of
the machine its being run on.

=cut

sub run {
    my ( $self ) = @_;

    my $time = time;

    if ( not defined $self->{CONSTANT} or $self->{CONSTANT} eq q{} ) {
        my $msg = "no constant defined";
        return ( -1, $msg );
    }

    return ( 0, $time, $self->{CONSTANT} );
}

1;

__END__

=head1 SEE ALSO

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
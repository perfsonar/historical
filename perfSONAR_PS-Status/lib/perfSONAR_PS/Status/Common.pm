package perfSONAR_PS::Status::Common;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Status::Common 

=head1 DESCRIPTION

A module that provides common methods for Link Status clients and services
within the perfSONAR-PS framework.  This module is a catch all for common
methods (for now) in the Link Status port of the perfSONAR-PS framework.  This
module IS NOT an object, and the methods can be invoked directly.

=head1 API

=cut

use base 'Exporter';

our @EXPORT = qw( is_valid_oper_status is_valid_admin_status get_new_admin_status get_new_oper_status );

my %valid_oper_states = (
    up       => q{},
    down     => q{},
    degraded => q{},
    unknown  => q{},
);

my %valid_admin_states = (
    normaloperation => q{},
    maintenance     => q{},
    troubleshooting => q{},
    underrepair     => q{},
    unknown         => q{},
);

=head2 is_valid_oper_status($state)

Checks if the given string is a valid operational state for a link.

=cut

sub is_valid_oper_status {
    my ( $state ) = @_;
    return 1 if ( defined $valid_oper_states{ lc( $state ) } );
    return 0;
}

=head2 is_valid_admin_status($state)

Checks if the given string is a valid administrative state for a link.

=cut

sub is_valid_admin_status {
    my ( $state ) = @_;
    return 1 if ( exists $valid_admin_states{ lc( $state ) } );
    return 0;
}

=head2 get_new_oper_status($old_oper_status, $new_oper_status)

TBD

=cut

sub get_new_oper_status {
    my ( $old_oper_status, $new_oper_status ) = @_;

    unless ( $old_oper_status ) {
        return $new_oper_status;
    }

    if ( $old_oper_status eq "unknown" or $new_oper_status eq "unknown" ) {
        return "unknown";
    }
    elsif ( $old_oper_status eq "down" or $new_oper_status eq "down" ) {
        return "down";
    }
    elsif ( $old_oper_status eq "degraded" or $new_oper_status eq "degraded" ) {
        return "degraded";
    }
    else {
        return "up";
    }
}

=head2 get_new_admin_status($old_admin_status, $new_admin_status)

TBD

=cut

sub get_new_admin_status {
    my ( $old_admin_status, $new_admin_status ) = @_;

    unless ( $old_admin_status ) {
        return $new_admin_status;
    }

    if ( $old_admin_status eq "unknown" or $new_admin_status eq "unknown" ) {
        return "unknown";
    }
    elsif ( $old_admin_status eq "underrepair" or $new_admin_status eq "underrepair" ) {
        return "underrepair";
    }
    elsif ( $old_admin_status eq "troubleshooting" or $new_admin_status eq "troubleshooting" ) {
        return "troubleshooting";
    }
    elsif ( $old_admin_status eq "maintenance" or $new_admin_status eq "maintenance" ) {
        return "maintenance";
    }
    else {
        return "normaloperation";
    }
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

Aaron Brown <aaron@internet2.edu>

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

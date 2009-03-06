package perfSONAR_PS::Status::Common;

use strict;
use warnings;

our $VERSION = 0.09;

use base 'Exporter';

our @EXPORT = ('is_valid_oper_status', 'is_valid_admin_status', 'get_new_admin_status', 'get_new_oper_status');

my %valid_oper_states = (
        up => '',
        down => '',
        degraded => '',
        unknown => '',
        );

my %valid_admin_states = (
        normaloperation => '',
        maintenance => '',
        troubleshooting => '',
        underrepair => '',
        unknown => '',
        );

sub is_valid_oper_status {
    my ($state) = @_;
    return 1 if (defined $valid_oper_states{lc($state)});
    return 0;
}

sub is_valid_admin_status {
    my ($state) = @_;
    return 1 if (defined $valid_admin_states{lc($state)});
    return 0;
}

sub get_new_oper_status {
    my ($old_oper_status, $new_oper_status) = @_;

    if (not $old_oper_status) {
        return $new_oper_status;
    }

    if ($old_oper_status eq "unknown" or $new_oper_status eq "unknown") {
        return "unknown";
    } elsif ($old_oper_status eq "down" or $new_oper_status eq "down") {
        return "down";
    } elsif ($old_oper_status eq "degraded" or $new_oper_status eq "degraded") {
        return "degraded";
    } else {
        return "up";
    }
}

sub get_new_admin_status {
    my ($old_admin_status, $new_admin_status) = @_;

    if (not $old_admin_status) {
        return $new_admin_status;
    }

    if ($old_admin_status eq "unknown" or $new_admin_status eq "unknown") {
        return "unknown";
    } elsif ($old_admin_status eq "underrepair" or $new_admin_status eq "underrepair") {
        return "underrepair";
    } elsif ($old_admin_status eq "troubleshooting" or $new_admin_status eq "troubleshooting") {
        return "troubleshooting";
    } elsif ($old_admin_status eq "maintenance" or $new_admin_status eq "maintenance") {
        return "maintenance";
    } else {
        return "normaloperation";
    }
}

1;

__END__

=head1 NAME

perfSONAR_PS::Status::Common - A module that provides common methods for Link
Status clients and services within the perfSONAR-PS framework.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) in the Link Status port
of the perfSONAR-PS framework.  This module IS NOT an object, and the methods
can be invoked directly.

=head1 SYNOPSIS

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The API of perfSONAR_PS::Status::Common offers simple calls to common
activities in the perfSONAR-PS framework.  

=head2 is_valid_admin_status($state)

Checks if the given string is a valid administrative state for a link.

=head2 is_valid_oper_status($state)

Checks if the given string is a valid operational state for a link.

=head1 SEE ALSO

L<Exporter>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown <aaron@internet2.edu>

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4

package perfSONAR_PS::Utils::Host;

=head1 NAME

perfSONAR_PS::Utils::DNS - A module that provides utility methods for interacting with DNS servers.

=head1 DESCRIPTION

This module provides a set of methods for interacting with DNS servers. This
module IS NOT an object, and the methods can be invoked directly. The methods
need to be explicitly imported to get use them.

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and
each method does not have the 'self knowledge' of variables that may travel
between functions.

=head1 API

The API of perfSONAR_PS::Utils::DNS provides a simple set of functions for
interacting with DNS servers.
=cut


use base 'Exporter';

use strict;
use warnings;

our @EXPORT_OK = ('get_ips');

sub get_ips {
    my @ret_interfaces = ();

    my $IFCONFIG;
    open($IFCONFIG, "-|", "/sbin/ifconfig");
    my $is_eth = 0;
    while(<$IFCONFIG>) {
        if (/Link encap:([^ ]+)/) {
            if (lc($1) eq "ethernet") {
                $is_eth = 1;
            } else {
                $is_eth = 0;
            }
        }

        next if (not $is_eth);

        if (/inet addr:(\d+\.\d+\.\d+\.\d+)/) {
            print "IPv4: $_";
            push @ret_interfaces, $1;
        } elsif (/inet6 addr: (\d*:[^\/ ]*)(\/\d+)? +Scope:Global/) {
            print "IPv6: $_";
            push @ret_interfaces, $1;
        }
    }
    close($IFCONFIG);

    return @ret_interfaces;
}

1;

#!/usr/bin/perl -w

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

gen_rand_status.pl

=head1 DESCRIPTION

This is a sample script to show how status information about a given link should
be output. It randomly selects a status based on the type of status being
checked.

The first paramter will always exist and will be the type of status being looked
up: 'admin' or 'oper'

A real script might consult an SNMP MA or consult the router via the CLI

If the script is an 'admin' or 'oper' script, the output should look like: timestamp,[status]
If the script is an 'oper/admin' script, the output should look like: timestamp,[oper status],[admin status] 

=cut

my $type = shift;

unless ( $type ) {
    print time() . ",unknown";
    exit( -1 );
}

my @oper_statuses = ( "up", "down", "degraded", );

my @admin_statuses = ( "normaloperation", "maintenance", "troubleshooting", "underrepair", );

if ( $type eq "admin" ) {
    my $n      = int( rand( $#admin_statuses + 1 ) );
    my $status = $admin_statuses[$n];
    print time() . "," . $status;
}
elsif ( $type eq "oper" ) {
    my $n      = int( rand( $#oper_statuses + 1 ) );
    my $status = $oper_statuses[$n];
    print time() . "," . $status;
}
elsif ( $type eq "oper/admin" or $type eq "admin/oper" ) {
    my $n            = int( rand( $#oper_statuses + 1 ) );
    my $oper_status  = $oper_statuses[$n];
    my $m            = int( rand( $#admin_statuses + 1 ) );
    my $admin_status = $admin_statuses[$m];
    print time() . "," . $oper_status . "," . $admin_status;
}
else {
    my $status = "unknown";
    print time() . "," . $status;
}

__END__

=head1 SEE ALSO

N/A

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

Aarobn Brown, aaron@internet2.edu
Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008-2009, Internet2

All rights reserved.

=cut

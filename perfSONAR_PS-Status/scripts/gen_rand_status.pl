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

Aaron Brown, aaron@internet2.edu
Jason Zurawski, zurawski@internet2.edu

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

Copyright (c) 2008-2009, Internet2

All rights reserved.

=cut

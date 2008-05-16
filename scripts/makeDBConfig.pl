#!/usr/bin/perl -w

use strict;
use warnings;
use File::Temp qw(tempfile);

=head1 NAME

makeDBConfig - Create the DB_CONFIG file for the XML DB.

=head1 DESCRIPTION

The DB_CONFIG file is used by the XMLDB to control environmental
items like number of locks and the size of the cache.  This file is
very valuable to dynamic services such as the LS.

=cut

my ( $fileHandle, $fileName ) = tempfile();

print $fileHandle "set_lock_timeout 1000000\n";
print $fileHandle "set_txn_timeout 1000000\n";
print $fileHandle "set_lk_max_lockers 1000000\n";
print $fileHandle "set_lk_max_locks 1000000\n";
print $fileHandle "set_lk_max_objects 1000000\n";
print $fileHandle "set_lk_detect DB_LOCK_MINLOCKS\n";
print $fileHandle "set_cachesize 0 33554432 0\n";

close($fileHandle);

print $fileName;

__END__
	
=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.

=cut

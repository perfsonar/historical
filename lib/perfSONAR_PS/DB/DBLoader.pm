package perfSONAR_PS::DB::DBLoader;


use DBIx::Class::Schema::Loader;
 

use base qw/DBIx::Class::Schema::Loader/;

__PACKAGE__->loader_options(relationships => 1);

1;

__END__
=head1 NAME

perfSONAR_PS::DB::DBLoader - A module to load schema relationships for databases.

=head1 DESCRIPTION

N/A

=head1 SYNOPSIS

    use perfSONAR_PS::DB::DBLoader;
  
    # fill in
    
=head1 DETAILS

N/A 

=head1 API

N/A

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

XXX

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

use perfSONAR_PS::Error::Base;


=head1 NAME

perfSONAR_PS::Error - A module that provides the exceptions framework for perfSONAR PS

=head1 DESCRIPTION

This module provides the common exception types that will be presented.

head1 API

=cut


package perfSONAR_PS::Error::Common;
use base "perfSONAR_PS::Error::Base";


# configuration and service startup

package perfSONAR_PS::Error::Common::Configuration;
use base "perfSONAR_PS::Error::Common";

package perfSONAR_PS::Error::Common::NoLogger;
use base "perfSONAR_PS::Error::Common";

package perfSONAR_PS::Error::Common::ActionNotSupported;
use base "perfSONAR_PS::Error::Common";


#YTL: i'm guessing the manager maps to our daemon architecture here

package perfSONAR_PS::Error::Common::Manager;
use base "perfSONAR_PS::Error::Common::Manager";

package perfSONAR_PS::Error::Common::Manager::NoConfiguration;
use base "perfSONAR_PS::Error::Common::Manager";

package perfSONAR_PS::Error::Common::Manager::CantCreateComponent;
use base "perfSONAR_PS::Error::Common::Manager";


#YTL: storage related stuff; queryies etc. do we want MA's to subclass these errors? or should the mas
# just return these? ie do we need the granularity of each MA having their own error types considering
# we can have the specific message of the error as part of the error object 

package perfSONAR_PS::Error::Common::Storage;
use base "perfSONAR_PS::Error::Common";


package perfSONAR_PS::Error::Common::Storage::Query;
use base "perfSONAR_PS::Error::Common::Storage";

package perfSONAR_PS::Error::Common::Storage::Fetch;
use base "perfSONAR_PS::Error::Common::Storage";

package perfSONAR_PS::Error::Common::Storage::Open;
use base "perfSONAR_PS::Error::Common::Storage";

package perfSONAR_PS::Error::Common::Storage::Update;
use base "perfSONAR_PS::Error::Common::Storage";

package perfSONAR_PS::Error::Common::Storage::Delete;
use base "perfSONAR_PS::Error::Common::Storage";

package perfSONAR_PS::Error::Common::Storage::Close;
use base "perfSONAR_PS::Error::Common::Storage";



1;

=head1 SEE ALSO

L<Exporter>, L<Error::Simple>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id$

=head1 AUTHOR

Yee-Ting Li <ytl@slac.stanford.edu>

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

use package perfSONAR_PS::Error;

=head1 NAME

perfSONAR_PS::Error::MA - A module that provides the exceptions framework for perfSONAR PS

=head1 DESCRIPTION

This module provides the message exception types that will be presented.

head1 API

=cut


package perfSONAR_PS::Error::Message;
use base "perfSONAR_PS::Error";


package perfSONAR_PS::Error::Message::Chaining;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::MessagesType
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::NoMessageType;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::EventType;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::InvalidKey;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::InvalidMessageType;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::InvalidSubject;
use base "perfSONAR_PS::Error::Message";

package perfSONAR_PS::Error::Message::NoMetadataDataPair;
use base "perfSONAR_PS::Error::Message";


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



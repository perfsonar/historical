package perfSONAR_PS::Error_compat;

our $VERSION = 0.03;

use base 'Error';

my $debug = 0;

sub new {
	my $self = shift;
	my $eventType = shift;
	my $text = shift;

	my @args = ();

	if ($debug) {
		local $Error::Debug = 1;
	}

	local $Error::Depth = $Error::Depth + 1;

	my $obj = $self->SUPER::new(-text => $text, @args);

	$obj->{EVENT_TYPE} = $eventType;

	return $obj;
}

sub eventType($) {
	my $self = shift;

	return $self->{EVENT_TYPE};
}

sub errorMessage($) {
	my $self = shift;

	return $self->text();
}

1;

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Transport>,
L<perfSONAR_PS::Client::Status::MA>, L<perfSONAR_PS::Client::Topology::MA>


To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

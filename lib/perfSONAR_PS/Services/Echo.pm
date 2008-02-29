package perfSONAR_PS::Services::Echo;

use base 'perfSONAR_PS::Services::Base';

use warnings;
use strict;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

our $VERSION = 0.06;

sub init {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::Echo");

	$handler->registerEventHandler("EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/2.0", $self);
	$handler->registerEventHandler("EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/ls/2.0", $self);
	$handler->registerEventHandler("EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/ma/2.0", $self);
	$handler->registerEventHandler_Regex("EchoRequest", "^echo.*", $self);

	return 0;
}

sub needLS {
	my ($self) = @_;

	return 0;
}

sub registerLS {
	my ($self, $ret_sleep_time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::Echo");

	$logger->warn("Can't register an echo handler with an LS");

	return -1;
}

sub handleEvent {
	my ($self, @args) = @_;
	my $parameters = validate(@args,
			{
			output => 1,
			messageId => 1,
			messageType => 1,
			messageParameters => 1,
			eventType => 1,
			subject => 1,
			filterChain => 1,
			data => 1,
			rawRequest => 1,
			doOutputMetadata => 1,
			});

	my $output = $parameters->{"output"};
	my $messageId = $parameters->{"messageId"};
	my $messageType = $parameters->{"messageType"};
	my $message_parameters = $parameters->{"messageParameters"};
	my $eventType = $parameters->{"eventType"};
	my $d = $parameters->{"data"};
	my $raw_request = $parameters->{"rawRequest"};
	my @subjects = @{ $parameters->{'subject'} };
	my $md = $subjects[0];

	my $mdID = "metadata.".genuid();
	my $msg = "The echo request has passed.";

	getResultCodeMetadata($output, $mdID, $md->getAttribute("id"), "success.echo");
	getResultCodeData($output, "data.".genuid(), $mdID, $msg, 1);

	return;
}

1;

__END__
=head1 NAME

perfSONAR_PS::Services::Echo - A simple module that implements perfSONAR echo
functionality.

=head1 DESCRIPTION

This module aims to provide a request handler that is compatible with the
perfSONAR echo specification.

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::RequestHandler>


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

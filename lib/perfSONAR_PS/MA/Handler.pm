package perfSONAR_PS::MA::Handler;

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl qw(get_logger);

sub new($) {
	my ($package) = @_;
	my %hash = ();

	$hash{"EV_HANDLERS"} = ();
	$hash{"EV_REGEX_HANDLERS"} = ();
	$hash{"MSG_HANDLERS"} = ();

	bless \%hash => $package;
}

sub addMessageHandler($$$) {
	my ($self, $messageType, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding message handler for $messageType");

	if (defined $self->{MSG_HANDLERS}->{$messageType}) {
		$logger->error("There already exists a handler for message $messageType");
		return -1;
	}

	$self->{MSG_HANDLERS}->{$messageType} = $service;

	return 0;
}

sub addEventHandler($$$$) {
	my ($self, $messageType, $eventType, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding event handler for events of type $eventType on messages of $messageType");

	if (!defined $self->{EV_HANDLERS}->{$messageType}) {
		$self->{EV_HANDLERS}->{$messageType} = ();
	}

	if (defined $self->{EV_HANDLERS}->{$messageType}->{$eventType}) {
		$logger->error("There already exists a handler for events of type $eventType on messages of type $messageType");
		return -1;
	}

#	if (!defined $service->handleEvent) {
#		$logger->error("Trying to add a handler that does not contain a handleEvent function");
#		return -1;
#	}

	$self->{EV_HANDLERS}->{$messageType}->{$eventType} = $service;

	return 0;
}

sub addEventHandler_Regex($$$$) {
	my ($self, $messageType, $eventRegex, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding event handler for events matching $eventRegex on messages of $messageType");

	if (!defined $self->{EV_REGEX_HANDLERS}->{$messageType}) {
		$self->{EV_REGEX_HANDLERS}->{$messageType} = ();
	}

	if (defined $self->{EV_REGEX_HANDLERS}->{$messageType}->{$eventRegex}) {
		$logger->error("There already exists a handler for events of the form /$eventRegex\/ on messages of type $messageType");
		return -1;
	}

#	if (!defined $service->handleEvent) {
#		$logger->error("Trying to add a handler that does not contain a handleEvent function");
#		return -1;
#	}

	$self->{EV_REGEX_HANDLERS}->{$messageType}->{$eventRegex} = $service;

	return 0;

}

sub messageBegin($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces) = @_;

	if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 0;
	}

	if (!defined $self->{MSG_HANDLERS}->{$messageType}->handleMessageBegin) {
		return 0;
	}

	return $self->{MSG_HANDLERS}->{$messageType}->handleMessageBegin($ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
}

sub messageEnd($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType) = @_;

	if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 0;
	}

	if (!defined $self->{MSG_HANDLERS}->{$messageType}->handleMessageEnd) {
		return 0;
	}

	return $self->{MSG_HANDLERS}->{$messageType}->handleMessageEnd($ret_message, $messageId);
}

sub handleEvent($$$$$$$$$$) {
	my ($self, $doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	if (defined $eventType and $eventType ne "") {
		$logger->debug("Handling event: $messageType, $eventType");
	} else {
		$logger->debug("Handling metadata/data pair: $messageType");
	}

	if (defined $self->{EV_HANDLERS}->{$messageType} and defined $self->{EV_HANDLERS}->{$messageType}->{$eventType}) {
		return $self->{EV_HANDLERS}->{$messageType}->{$eventType}->handleEvent($doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request);
	}

	if (defined $self->{EV_REGEX_HANDLERS}->{$messageType}) {
		$logger->debug("There exists regex's for this message type");
		foreach my $regex (keys %{$self->{EV_REGEX_HANDLERS}->{$messageType}}) {
			$logger->debug("Checking $eventType against $regex");
			if ($eventType =~ /$regex/) {
				return $self->{EV_REGEX_HANDLERS}->{$messageType}->{$regex}->handleEvent($doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request);
			}
		}
	}

	if (defined $self->{MSG_HANDLERS}->{$messageType}) {
		return $self->{MSG_HANDLERS}->{$messageType}->handleEvent($doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request);
	}

	return ("error.ma.event_type", "Event type \"$eventType\" is not yet supported for messages with type \"$messageType\"");
}

sub isValidMessageType($$) {
	my ($self, $messageType) = @_;

	if (defined $self->{EV_HANDLERS}->{$messageType} or defined $self->{EV_REGEX_HANDLERS}->{$messageType} or defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 1;
	}

	return 0;
}

sub isValidEventType($$$) {
	my ($self, $messageType, $value) = @_;

	if (defined $self->{EV_HANDLERS}->{$messageType} and defined $self->{EV_HANDLERS}->{$messageType}->{$eventType}) {
		return 1;
	}

	if (defined $self->{EV_HANDLERS}->{$messageType} and defined $self->{EV_HANDLERS}->{$messageType}->{"*"}) {
		return 1;
	}

	if (defined $self->{EV_REGEX_HANDLERS}->{$messageType}) {
		foreach my $regex (keys %{$self->{EV_REGEX_HANDLERS}->{$messageType}}) {
			if ($eventType =~ /$regex/) {
				return 1;
			}
		}
	}

	return 0;
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::Handler - A module that provides an object to register event
and message handlers for an MA.

=head1 DESCRIPTION

This module is used by the daemon in the pS-PS Daemon architecture. The daemon
creates a Handler object and passes it to each of the modules who, in turn,
register which message types or event types they are interested in.

=head1 SYNOPSIS

=head1 DETAILS

=head1 API

=head2 new($)

This function allocates a new Handler object.

=head2 add($self, $endpoint, $messageType, $eventType, $ma)

This function is used to tell which message or event an MA is interested in.
The 'handleEvent' function in the specified ma will be called for each
metadata/data pair with the specified event type is found in a message of the
specified type that came in on the specified endpoint. If no eventType is
specified, then then handleEvent function is called for all metadata/data
pairs, no matter the event type. If the endpoint is unstated, the handler will
be called when a matching metadata/data pair on the specified message type with
the specified event type is located on any endpoint.

=head2 addRegex($self, $endpoint, $messageType, $regex, $ma)

This function is called by an MA to register its interest in any metadata/data
pair containing an event type that matches the specified regular expression.
Like the 'add' function, if the endpoint is unspecified, the 'handleEvent'
function will be called when a matching metadata/data pair is found in the
specified messageType on any endpoint.

=head2 handleEvent($self, $output, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_request)

This function is called by the daemon when a metadata/data pair is found in a
message. $output contains the response document that being constructed.
$endpoint contains the endpoint. $messageType contains the type of the message.
$message_parameters is a reference to a hash containing the parameters.
$eventType contains the event type (if it exists). $md contains the metadata.
$d contains the data. $raw_request contains the raw request element.

=head2 setMessageResponseType($self, $endpoint, $requestType, $responseType)

This function is called by the MA to specify what the response type for a
message on the specified endpoint should be. If the endpoint is left blank, it
applies to all endpoints.

=head2 getMessageResponseType($self, $endpoint, $requestType)

This function is called by the MA to find what the proper response type is for
a given message on a given endpoint.

=head2 isValidEndpoint($self, $endpoint)

This function is called by the daemon to verify that some Module is listening
on a specific endpoint.

=head1 SEE ALSO

L<Exporter>, L<HTTP::Daemon>, L<Log::Log4perl>, L<perfSONAR_PS::Transport>
L<XML::XPath>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu, Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

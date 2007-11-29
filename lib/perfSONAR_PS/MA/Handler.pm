package perfSONAR_PS::MA::Handler;

use strict;
use warnings;

use Log::Log4perl qw(get_logger);

sub new($) {
	my ($package) = @_;
	my %hash = ();

	$hash{"EP_EV_HANDLERS"} = ();
	$hash{"ALL_EV_HANDLERS"} = ();
	$hash{"EP_EV_HANDLERS_REGEX"} = ();
	$hash{"ALL_EV_HANDLERS_REGEX"} = ();
	$hash{"EP_MSG_HANDLERS"} = ();
	$hash{"ALL_MSG_HANDLERS"} = ();
	$hash{"EV_MSG_RESP_TYPES"} = ();
	$hash{"VALIDENDPOINTS"} = ();

	bless \%hash => $package;
}

sub add($$$$$) {
	my ($self, $endpoint, $messageType, $eventType, $ma) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	if ($endpoint eq "") {
		if ($eventType eq "") {
			$logger->debug("Adding message handler for message type $messageType on all endpoints.");
		} else {
			$logger->debug("Adding event handler for event type $eventType on messages of type $messageType on all endpoints.");
		}
	} else {
		if ($eventType eq "") {
			$logger->debug("Adding message handler for message type $messageType on endpoint $endpoint.");
		} else {
			$logger->debug("Adding event handler for event type $eventType on messages of type $messageType on endpoint $endpoint.");
		}
	}

	if ($endpoint eq "") {
		if (!defined $self->{ALL_EV_HANDLERS}->{$messageType}) {
			$self->{ALL_EV_HANDLERS}->{$messageType} = ();
		}

		if ($eventType eq "") {
			$self->{ALL_MSG_HANDLERS}->{$messageType} = $ma;
		} else {
			$self->{ALL_EV_HANDLERS}->{$messageType}->{$eventType} = $ma;
		}
	} else {
		$endpoint =~ s/^(\/)+//g;

		$self->{VALIDENDPOINTS}->{$endpoint} = "";

		if ($eventType ne "") {
			if (!defined $self->{EP_EV_HANDLERS}->{$endpoint}) {
				$self->{EP_EV_HANDLERS}->{$endpoint} = ();
			}

			if (!defined $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType}) {
				$self->{EP_EV_HANDLERS}->{$endpoint}->{$endpoint}->{$messageType} = ();
			}

			$self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType}->{$eventType} = $ma;
		} else {
			if (!defined $self->{EP_MSG_HANDLERS}->{$endpoint}) {
				$self->{EP_MSG_HANDLERS}->{$endpoint} = ();
			}

			$self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType} = $ma;
		}
	}

	return 0;
}

sub addRegex($$$$$) {
	my ($self, $endpoint, $messageType, $eventRegex, $ma) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding handler for $endpoint, $messageType, $eventRegex");

	if ($endpoint eq "") {
		if (!defined $self->{ALL_EV_HANDLERS_REGEX}->{$messageType}) {
			$self->{ALL_EV_HANDLERS_REGEX}->{$messageType} = ();
		}

		$self->{ALL_EV_HANDLERS_REGEX}->{$messageType}->{$eventRegex} = $ma;
	} else {
		$endpoint =~ s/^(\/)+//g;

		if (!defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint}) {
			$self->{EP_EV_HANDLERS_REGEX}->{$endpoint} = ();
		}

		if (!defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType}) {
			$self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType} = ();
		}

		$self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType}->{$eventRegex} = $ma;
	}

	return 0;
}

sub handleEvent($$$$$$$$$) {
	my ($self, $doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	if (defined $eventType and $eventType ne "") {
		$logger->debug("Handling event: $endpoint, $messageType, $eventType");
	} else {
		$logger->debug("Handling metadata/data pair: $endpoint, $messageType");
	}

	my ($valid_endpoint, $valid_messagetype);

	$valid_endpoint = defined $self->{VALIDENDPOINTS}->{$endpoint};
	$valid_messagetype = ($valid_endpoint and
					(defined $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType} or
					 defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType} or
					 defined $self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType} or
					 defined $self->{ALL_EV_HANDLERS}->{$messageType} or
					 defined $self->{ALL_EV_HANDLERS_REGEX}->{$messageType} or
					 defined $self->{ALL_MSG_HANDLERS}->{$messageType}));

	if (!$valid_endpoint) {
		return ("error.perfSONAR_PS.transport", "Received message with invalid endpoint: $endpoint");
	}

	if (!$valid_messagetype) {
		return ("error.ma.message.type", "Message type \"".$messageType."\" is not yet supported");
	}

	if (defined $self->{EP_EV_HANDLERS}->{$endpoint} and
			defined $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType} and
			defined $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType}->{$eventType}) {
		return $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType}->{$eventType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
	}

	if (defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint} and
			defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType}) {
		foreach my $regex (keys %{$self->{EP_EV_HANDLERS_REGEX}->{$messageType}}) {
			if ($eventType =~ /$regex/) {
				return $self->{EP_EV_HANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
			}
		}
	}

	if (defined $self->{ALL_EV_HANDLERS}->{$messageType} and defined $self->{ALL_EV_HANDLERS}->{$messageType}->{$eventType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				return $self->{ALL_EV_HANDLERS}->{$messageType}->{$eventType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
			}
		}
	}

	if (defined $self->{ALL_EV_HANDLERS_REGEX}->{$messageType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				foreach my $regex (keys %{$self->{ALL_EV_HANDLERS_REGEX}->{$messageType}}) {
					if ($eventType =~ /$regex/) {
						return $self->{ALL_EV_HANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
					}
				}
			}
		}
	}

	if (defined $self->{EP_MSG_HANDLERS}->{$endpoint} and
		defined $self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType}) {
		return $self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
	}

	if (defined $self->{ALL_MSG_HANDLERS}->{$messageType}) {
		return $self->{ALL_MSG_HANDLERS}->{$messageType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message);
	}

	return ("error.ma.event_type", "Event type \"$eventType\" is not yet supported for messages with type \"$messageType\" on endpoint \"$endpoint\"");
}

sub setMessageResponseType($$$$) {
	my ($self, $endpoint, $requestType, $responseType) = @_;

	if ($endpoint eq "") {
		$self->{ALL_MSG_RESP_TYPES}->{$requestType} = $responseType;
	} else {
		if (!defined $self->{EV_MSG_RESP_TYPES}->{$endpoint}) {
			$self->{EV_MSG_RESP_TYPES}->{$endpoint} = ();
			$self->{VALIDENDPOINTS}->{$endpoint} = 1;
		}

		$self->{EV_MSG_RESP_TYPES}->{$endpoint}->{$requestType} = $responseType;
	}
}

sub getMessageResponseType($$$) {
	my ($self, $endpoint, $requestType) = @_;

	if (defined $self->{EV_MSG_RESP_TYPES}->{$endpoint}) {
		return $self->{EV_MSG_RESP_TYPES}->{$endpoint}->{$requestType};
	} elsif (defined $self->{VALIDENDPOINTS}->{$endpoint} and
			defined $self->{ALL_MSG_RESP_TYPES}->{$requestType}) {
		return $self->{ALL_MSG_RESP_TYPES}->{$requestType};
	} else {
		return undef;
	}
}

sub isValidEndpoint($$) {
	my ($self, $endpoint) = @_;

	$endpoint = "/".$endpoint if ($endpoint =~ /^[^\/]/);

	return $self->{VALIDENDPOINTS}->{$endpoint};
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
$d contains the data. $raw_message contains the raw request element.

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

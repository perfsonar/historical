package perfSONAR_PS::RequestHandler;

use fields 'EV_HANDLERS', 'EV_REGEX_HANDLERS', 'MSG_HANDLERS', 'FULL_MSG_HANDLERS';

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::XML::Document_string;
use perfSONAR_PS::Messages;

sub new($) {
	my ($package) = @_;

	my $self = fields::new($package);

	$self->{"EV_HANDLERS"} = ();
	$self->{"EV_REGEX_HANDLERS"} = ();
	$self->{"MSG_HANDLERS"} = ();
	$self->{"FULL_MSG_HANDLERS"} = ();

	return $self;
}

sub addFullMessageHandler($$$$) {
	my ($self, $messageType, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	$logger->debug("Adding message handler for $messageType");

	if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
		$logger->error("There already exists a handler for message $messageType");
		return -1;
	}

	$self->{FULL_MSG_HANDLERS}->{$messageType} = $service;

	return 0;
}

sub addMessageHandler($$$) {
	my ($self, $messageType, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

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
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	$logger->debug("Adding event handler for events of type $eventType on messages of $messageType");

	if (!defined $self->{EV_HANDLERS}->{$messageType}) {
		$self->{EV_HANDLERS}->{$messageType} = ();
	}

	if (defined $self->{EV_HANDLERS}->{$messageType}->{$eventType}) {
		$logger->error("There already exists a handler for events of type $eventType on messages of type $messageType");
		return -1;
	}

	$self->{EV_HANDLERS}->{$messageType}->{$eventType} = $service;

	return 0;
}

sub addEventHandler_Regex($$$$) {
	my ($self, $messageType, $eventRegex, $service) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	$logger->debug("Adding event handler for events matching $eventRegex on messages of $messageType");

	if (!defined $self->{EV_REGEX_HANDLERS}->{$messageType}) {
		$self->{EV_REGEX_HANDLERS}->{$messageType} = ();
	}

	if (defined $self->{EV_REGEX_HANDLERS}->{$messageType}->{$eventRegex}) {
		$logger->error("There already exists a handler for events of the form /$eventRegex\/ on messages of type $messageType");
		return -1;
	}

	$self->{EV_REGEX_HANDLERS}->{$messageType}->{$eventRegex} = $service;

	return 0;
}

sub handleMessage($$$$$) {
	my ($self, $doc, $messageType, $message, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
		return $self->{FULL_MSG_HANDLERS}->{$messageType}->handleMessage($doc, $messageType, $message, $request);
	}

	my $mdID = "metadata.".genuid();
	getResultCodeMetadata($doc, $mdID, "", "error.ma.messages_type");
	getResultCodeData($doc, "data.".genuid(), $mdID, "Message type \"$messageType\" not yet supported", 1);
}

sub messageBegin($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces) = @_;

	if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 0;
	}

	return $self->{MSG_HANDLERS}->{$messageType}->handleMessageBegin($ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
}

sub messageEnd($$$$) {
	my ($self, $ret_message, $messageId, $messageType) = @_;

	if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 0;
	}

	return $self->{MSG_HANDLERS}->{$messageType}->handleMessageEnd($ret_message, $messageId, $messageType);
}

sub handleEvent($$$$$$$$$$) {
	my ($self, $doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	my $messageType = $args->{"messageType"};
	my $eventType = $args->{"eventType"};

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
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	$logger->debug("Checking if messages of type $messageType are valid");

	if (defined $self->{EV_HANDLERS}->{$messageType} or defined $self->{EV_REGEX_HANDLERS}->{$messageType}
			or defined $self->{MSG_HANDLERS}->{$messageType} or defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
		return 1;
	}

	return 0;
}

sub isValidEventType($$$) {
	my ($self, $messageType, $eventType) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	$logger->debug("Checking if $eventType is valid on messages of type $messageType");

	if (defined $self->{EV_HANDLERS}->{$messageType} and defined $self->{EV_HANDLERS}->{$messageType}->{$eventType}) {
		return 1;
	}

	if (defined $self->{EV_REGEX_HANDLERS}->{$messageType}) {
		foreach my $regex (keys %{$self->{EV_REGEX_HANDLERS}->{$messageType}}) {
			if ($eventType =~ /$regex/) {
				return 1;
			}
		}
	}

	if (defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 1;
	}

	return 0;
}

sub hasFullMessageHandler($$) {
	my ($self, $messageType) = @_;

	if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
		return 1;
	}

	return 0;
}

sub hasMessageHandler($$) {
	my ($self, $messageType) = @_;

	if (defined $self->{MSG_HANDLERS}->{$messageType}) {
		return 1;
	}

	return 0;
}

sub handleRequest($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::RequestHandler");

	my $error;
	my $localContent = "";

	$request->parse(\$error);

	if (defined $error and $error ne "") {
		my $ret_message = new perfSONAR_PS::XML::Document_string();
		getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", "error.transport.parse_error", "Error parsing request: $error", undef, 1);
		$request->setResponse($ret_message->getValue());
		return;
	}

	my $message = $request->getRequestDOM()->getDocumentElement();;
	my $messageId = $message->getAttribute("id");
	my $messageType = $message->getAttribute("type");

	if (!defined $messageType or $messageType eq "") {
		my $ret_message = new perfSONAR_PS::XML::Document_string();
		my $mdID = "metadata.".genuid();
		getResultCodeMetadata($ret_message, $mdID, "", "error.ma.no_message_type");
		getResultCodeData($ret_message, "data.".genuid(), $mdID, "There was no message type specified", 1);
		$request->setResponse($ret_message->getValue());
		return;
	} elsif ($self->isValidMessageType($messageType) == 0) {
		my $ret_message = new perfSONAR_PS::XML::Document_string();
		my $mdID = "metadata.".genuid();
		getResultCodeMetadata($ret_message, $mdID, "", "error.ma.invalid_message_type");
		getResultCodeData($ret_message, "data.".genuid(), $mdID, "Messages of type $messageType are unsupported", 1);
		$request->setResponse($ret_message->getValue());
		return;
	}

	chainMetadata($message);

	# The module will handle everything for this message type
	if ($self->hasFullMessageHandler($messageType)) {
		my $ret_message = new perfSONAR_PS::XML::Document_string();
		$self->handleMessage($ret_message, $messageType, $message, $request);
		$request->setResponse($ret_message->getValue());
		return;
	}

	# Otherwise, since the message is valid, there must be some event types
	# it accepts. We'll try those.
	my %message_parameters = ();

	my $msgParams = find($message, "./nmwg:parameters", 1);
	if (defined $msgParams) {
		foreach my $p ($msgParams->getChildrenByLocalName("parameter")) {
			my ($name, $value);

			$name = $p->getAttribute("name");
			$value = extract($p, 0);

			if (!defined $name or $name eq "") {
				next;
			}

			$message_parameters{$name} = $value;
		}
	}

	my $found_pair = 0;

	my $ret_message = new perfSONAR_PS::XML::Document_string();

	my ($retMessageType, $retMessageNamespaces);
	my $n = $self->messageBegin($ret_message, $messageId, $messageType, $msgParams, $request, \$retMessageType, \$retMessageNamespaces);
	if ($n == 0) {
		# if they return non-zero, it means the module began the message for us
		# if they retutn zero, they expect us to start the message
		my $retMessageId = "message.".genuid();

		# we weren't given a return message type, so try to construct
		# one by replacing Request with Response or sticking the term
		# "Response" on the end of the type.
		if (!defined $retMessageType or $retMessageType eq "") {
			$retMessageType = $messageType;
			$retMessageType =~ s/Request/Response/;
			if (!($retMessageType =~ /Response/)) {
				$retMessageType .= "Response";
			}
		}

		startMessage($ret_message, $retMessageType, $messageId, $retMessageType, "", $retMessageNamespaces);
	}

	foreach my $d ($message->getChildrenByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "data")) {
		my $found_md = 0;

		foreach my $m ($message->getChildrenByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				$found_pair = 1;
				$found_md = 1;

				my $eventType;
				my $eventTypes = find($m, "./nmwg:eventType", 0);
				foreach my $e ($eventTypes->get_nodelist) {
					my $value = extract($e, 1);
					if ($self->isValidEventType($messageType, $value)) {
						$eventType = $value;
						last;
					}
				}

				my ($status, $res);

				if (!defined $eventType) {
					$status = "error.ma.event_type";
					$res = "No supported event types for message of type \"$messageType\"";
				} else {
					($status, $res) = $self->handleEvent($ret_message, $messageId, $messageType, \%message_parameters, $eventType, $m, $d, $request);
				}

				if (defined $status and $status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");
					my $mdID = "metadata.".genuid();
					getResultCodeMetadata($ret_message, $mdID, $m->getAttribute("id"), $status);
					getResultCodeData($ret_message, "data.".genuid(), $mdID, $res, 1);
				}
			}
		}

		if ($found_md == 0) {
			my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
			my $mdId = "metadata.".genuid();
			my $dId = "data.".genuid();
			$logger->error($msg);
			getResultCodeMetadata($ret_message, $mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
			getResultCodeData($ret_message, $dId, $mdId, $msg, 1);
		}
	}

	if ($found_pair == 0) {
		my $mdID = "metadata.".genuid();
		getResultCodeMetadata($ret_message, $mdID, "", "error.ma.no_metadata_data_pair");
		getResultCodeData($ret_message, "data.".genuid(), $mdID, "There was no data/metadata pair found", 1);
	}

	$n = $self->messageEnd($ret_message, $messageId, $messageType);
	if ($n == 0) {
		endMessage($ret_message);
	}

	$request->setResponse($ret_message->getValue());
}

1;

__END__
=head1 NAME

perfSONAR_PS::RequestHandler - A module that provides an object to register event
and message handlers for a perfSONAR Service.

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

This function is used to tell which message or event a pS service is interested
in.  The 'handleEvent' function in the specified ma will be called for each
metadata/data pair with the specified event type is found in a message of the
specified type that came in on the specified endpoint. If no eventType is
specified, then then handleEvent function is called for all metadata/data
pairs, no matter the event type. If the endpoint is unstated, the handler will
be called when a matching metadata/data pair on the specified message type with
the specified event type is located on any endpoint.

=head2 addRegex($self, $endpoint, $messageType, $regex, $ma)

This function is called by a pS service to register its interest in any
metadata/data pair containing an event type that matches the specified regular
expression.  Like the 'add' function, if the endpoint is unspecified, the
'handleEvent' function will be called when a matching metadata/data pair is
found in the specified messageType on any endpoint.

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

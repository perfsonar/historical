package perfSONAR_PS::RequestHandler;

=head1 NAME

perfSONAR_PS::RequestHandler - A module that provides an object to register event
and message handlers for a perfSONAR Service.

=head1 DESCRIPTION

This module is used by the daemon in the pS-PS Daemon architecture. The daemon
creates a Handler object and passes it to each of the modules who, in turn,
register which message types or event types they are interested in.

=cut

use fields 'EV_HANDLERS', 'EV_REGEX_HANDLERS', 'MSG_HANDLERS', 'FULL_MSG_HANDLERS';

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::Common;
use perfSONAR_PS::XML::Document_string;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Error_compat qw/:try/;

=head1 API
=cut

=head2 new($)
    This function allocates a new Handler object.
=cut
sub new($) {
    my ($package) = @_;

    my $self = fields::new($package);

    $self->{"EV_HANDLERS"} = ();
    $self->{"EV_REGEX_HANDLERS"} = ();
    $self->{"MSG_HANDLERS"} = ();
    $self->{"FULL_MSG_HANDLERS"} = ();

    return $self;
}

=head2 addFullMessageHandler($self, $messageType, $service)
    This function is used by a pS service to specify that it would like to
    handle the complete processing for messages of the specified type. If
    called, the service must have a handleMessage function. This function
    will be called when a message of the specified type is received. The
    handleMessage function is then responsible for all handling of the
    message.
=cut
sub addFullMessageHandler($$$$) {
    my ($self, $messageType, $service) = validate_pos(@_,
                1,
                { type => SCALAR },
                { can => 'handleMessage'},
            );

    my $logger = get_logger("perfSONAR_PS::RequestHandler");

    $logger->debug("Adding message handler for $messageType");

    if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
        $logger->error("There already exists a handler for message $messageType");
        return -1;
    }

    $self->{FULL_MSG_HANDLERS}->{$messageType} = $service;

    return 0;
}

=head2 addMessageHandler($self, $messageType, $service)
    This function is used by a pS service to specify that it would like to
    be informed of all the metadata/data pairs for a given message. The
    handler will also inform the module when a new message of the specified
    type is received as well as when it has finished processing for the
    message. If a message handler is registered, the following functions
    must be defined in the $service specified: handleMessageBegin,
    handleMessageEnd and handleEvent. handleMessageBegin will be called
    when a new message of the specified type is received. handleEvent will
    be called each time a metadata/data pair is found in the message.
    handleMessageEnd will be called when all the metadata/data pairs have
    been handled.
=cut
sub addMessageHandler($$$) {
    my ($self, $messageType, $service) = validate_pos(@_,
                1,
                { type => SCALAR },
                { can => [ 'handleMessageBegin', 'handleMessageEnd', 'handleEvent' ]}
            );

    my $logger = get_logger("perfSONAR_PS::RequestHandler");

    $logger->debug("Adding message handler for $messageType");

    if (defined $self->{MSG_HANDLERS}->{$messageType}) {
        $logger->error("There already exists a handler for message $messageType");
        return -1;
    }

    $self->{MSG_HANDLERS}->{$messageType} = $service;

    return 0;
}

=head2 addEventHandler($self, $messageType, $eventType, $service)
    This function is used to tell which events a pS service is interested
    in. If added, there must be a 'handleEvent' function defined in the
    service module. The 'handleEvent' function in the specified service
    will be called for each metadata/data pair with an event type of the
    specified type found in a message of the specified type.
=cut
sub addEventHandler($$$$) {
    my ($self, $messageType, $eventType, $service) = validate_pos(@_,
                1,
                { type => SCALAR },
                { type => SCALAR },
                { can => [ 'handleEvent' ]}
            );

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

=head2 addEventHandler_Regex($self, $messageType, $eventRegex, $service)
    This function is used to tell which events a pS service is interested
    in. If added, there must be a 'handleEvent' function defined in the
    service module. The 'handleEvent' function in the specified service
    will be called for each metadata/data pair with an event type matching
    the specified regular expression found in a message of the specified
    type.
=cut
sub addEventHandler_Regex($$$$) {
    my ($self, $messageType, $eventRegex, $service) = validate_pos(@_,
                1,
                { type => SCALAR },
                { type => SCALAR },
                { can => [ 'handleEvent' ]}
            );
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

=head2 __handleMessage ($self, $doc, $messageType, $message, $request);
    The __handleMessage function is called when a message is encountered that
    has a full message handler.
=cut
sub __handleMessage($$$$$) {
    my ($self, $doc, $messageType, $message, $request) = @_;
    my $logger = get_logger("perfSONAR_PS::RequestHandler");

    if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
        return $self->{FULL_MSG_HANDLERS}->{$messageType}->handleMessage($doc, $messageType, $message, $request);
    }

    my $mdID = "metadata.".genuid();
    getResultCodeMetadata($doc, $mdID, "", "error.ma.messages_type");
    getResultCodeData($doc, "data.".genuid(), $mdID, "Message type \"$messageType\" not yet supported", 1);
}


=head2 __handleMessageBegin ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
    The __handleMessageBegin function is called when a new message is encountered
    that has a message handler.
=cut
sub __handleMessageBegin($$$$$$$$) {
    my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces) = @_;

    if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
        return 0;
    }

    return $self->{MSG_HANDLERS}->{$messageType}->handleMessageBegin($ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
}

=head2 __handleMessageEnd ($self, $ret_message, $messageId, $messageType);
    The __handleMessageEnd function is called when all the metadata/data pairs in a
    message have been handled.
=cut
sub __handleMessageEnd($$$$) {
    my ($self, $ret_message, $messageId, $messageType) = @_;

    if (!defined $self->{MSG_HANDLERS}->{$messageType}) {
        return 0;
    }

    return $self->{MSG_HANDLERS}->{$messageType}->handleMessageEnd($ret_message, $messageId, $messageType);
}

=head2 handleEvent ($self, $doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request);
    The handleEvent function is called when a metadata/data pair is found
    in a message. $doc contains the response document that being
    constructed. $messageId contains the identifier for the message.
    $messageType contains the type of the message. $message_parameters is
    a reference to a hash containing the message parameters. $eventType
    contains the event type (if it exists). $md contains the metadata. $d
    contains the data. $raw_request contains the raw request element.
=cut
sub __handleEvent($$$$$$$$$$) {
    my ($self, $doc, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
    my $logger = get_logger("perfSONAR_PS::RequestHandler");

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

    throw perfSONAR_PS::Error_compat("error.ma.event_type", "Event type \"$eventType\" is not yet supported for messages with type \"$messageType\"");
}

=head2 isValidMessageType($self, $messageType);
    The isValidMessageType function can be used to check if a specific
    message type can be handled by either a full message handler, a message
    handler or an event type handler for events in that type of message. It
    returns 0 if it's invalid and non-zero if it's valid.
=cut
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

=head2 isValidEventType($self, $messageType, $eventType);
    The isValidEventType function can be used to check if a specific
    event type found in a specific message type can be handled. It returns
    0 if it's invalid and non-zero if it's valid.
=cut
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

=head2 hasFullMessageHandler($self, $messageType);
    The hasFullMessageHandler checks if there is a full message handler for
    the specified message type.
=cut
sub hasFullMessageHandler($$) {
    my ($self, $messageType) = @_;

    if (defined $self->{FULL_MSG_HANDLERS}->{$messageType}) {
        return 1;
    }

    return 0;
}

=head2 hasMessageHandler($self, $messageType);
    The hasMessageHandler checks if there is a message handler for
    the specified message type.
=cut
sub hasMessageHandler($$) {
    my ($self, $messageType) = @_;

    if (defined $self->{MSG_HANDLERS}->{$messageType}) {
        return 1;
    }

    return 0;
}

=head2 handleRequest($self, $request);
    The handleRequest function takes a perfSONAR_PS::Request element
    containing an incoming SOAP request and handles that request by parsing
    it, checking the message type, and either calling a full message
    handler, or iterating through the message calling the handler for each
    event type. This function sets the response for the request.
=cut
sub handleMessage($$$) {
    my ($self, $message, $request) = @_;
    my $logger = get_logger("perfSONAR_PS::RequestHandler");

    my $messageId = $message->getAttribute("id");
    my $messageType = $message->getAttribute("type");

    if (!defined $messageType or $messageType eq "") {
        throw perfSONAR_PS::Error_compat("error.ma.no_message_type", "There was no message type specified");
    } elsif ($self->isValidMessageType($messageType) == 0) {
        throw perfSONAR_PS::Error_compat("error.ma.invalid_message_type", "Messages of type $messageType are unsupported", 1);
    }

    chainMetadata($message);

    # The module will handle everything for this message type
    if ($self->hasFullMessageHandler($messageType)) {
        my $ret_message = new perfSONAR_PS::XML::Document_string();
        $self->__handleMessage($ret_message, $messageType, $message, $request);
        $request->setResponse($ret_message->getValue());
        return;
    }

    # Otherwise, since the message is valid, there must be some event types
    # it accepts. We'll try those.
    my %message_parameters = ();

    my $msgParams = find($message, "./nmwg:parameters", 1);
    if (defined $msgParams) {
        my $find_res = find($msgParams, "./*[local-name()='parameter']", 0);
        if ($find_res) {
        foreach my $p ($find_res->get_nodelist) {
            my ($name, $value);

            $name = $p->getAttribute("name");
            $value = extract($p, 0);

            if (!defined $name or $name eq "") {
                next;
            }

            $message_parameters{$name} = $value;
        }
        }
    }

    my $found_pair = 0;

    my $ret_message = new perfSONAR_PS::XML::Document_string();

    my ($retMessageType, $retMessageNamespaces);
    my $n = $self->__handleMessageBegin($ret_message, $messageId, $messageType, $msgParams, $request, \$retMessageType, \$retMessageNamespaces);
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

                my $errorEventType;
                my $errorMessage;
                if (!defined $eventType) {
                    $errorEventType = "error.ma.event_type";
                    $errorMessage = "No supported event types for message of type \"$messageType\"";
                } else {
                    try {
                        $self->__handleEvent($ret_message, $messageId, $messageType, \%message_parameters, $eventType, $m, $d, $request);
                    }
                    catch perfSONAR_PS::Error_compat with {
                        my $ex = shift;

                        $errorEventType = $ex->eventType;
                        $errorMessage = $ex->errorMessage;
                    } otherwise {
                        my $ex = shift;

                        $logger->error("Error handling metadata/data block: $ex");

                        $errorEventType = "error.ma.internal_error";
                        $errorMessage = "An internal error occurred while servicing this metadata/data block";
                    }
                }

                if (defined $errorEventType and $errorEventType ne "") {
                    $logger->error("Couldn't handle requested metadata: $errorMessage");
                    my $mdID = "metadata.".genuid();
                    getResultCodeMetadata($ret_message, $mdID, $m->getAttribute("id"), $errorEventType);
                    getResultCodeData($ret_message, "data.".genuid(), $mdID, $errorMessage, 1);
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

    $n = $self->__handleMessageEnd($ret_message, $messageId, $messageType);
    if ($n == 0) {
        endMessage($ret_message);
    }

    $request->setResponse($ret_message->getValue());
}

1;

__END__

=head1 SEE ALSO

L<Log::Log4perl>, L<perfSONAR_PS::XML::Document_string>
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>

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
# vim: expandtab shiftwidth=4 tabstop=4

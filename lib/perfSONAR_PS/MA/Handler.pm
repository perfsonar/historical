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
	$hash{"VALIDENDPOINTS"} = ();

	bless \%hash => $package;
}

sub add($$$$$) {
	my ($self, $endpoint, $messageType, $eventType, $ma) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding handler for $endpoint, $messageType, $eventType");

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

sub handleEvent($$$$) {
	my ($self, $doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Handling event: $endpoint, $messageType, $eventType");

	my ($valid_endpoint, $valid_messagetype, $valid_eventtype);

	my $valid_endpoint = defined $self->{VALIDENDPOINTS}->{$endpoint};
	my $valid_messagetype = ($valid_endpoint and
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
		return $self->{EP_EV_HANDLERS}->{$endpoint}->{$messageType}->{$eventType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
	}

	if (defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint} and
			defined $self->{EP_EV_HANDLERS_REGEX}->{$endpoint}->{$messageType}) {
		foreach my $regex (keys %{$self->{EP_EV_HANDLERS_REGEX}->{$messageType}}) {
			if ($eventType =~ /$regex/) {
				return $self->{EP_EV_HANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
			}
		}
	}

	if (defined $self->{ALL_EV_HANDLERS}->{$messageType} and defined $self->{ALL_EV_HANDLERS}->{$messageType}->{$eventType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				return $self->{ALL_EV_HANDLERS}->{$messageType}->{$eventType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
			}
		}
	}

	if (defined $self->{ALL_EV_HANDLERS_REGEX}->{$messageType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				foreach my $regex (keys %{$self->{ALL_EV_HANDLERS_REGEX}->{$messageType}}) {
					if ($eventType =~ /$regex/) {
						return $self->{ALL_EV_HANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
					}
				}
			}
		}
	}

	if (defined $self->{EP_MSG_HANDLERS}->{$endpoint} and
		defined $self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType}) {
		return $self->{EP_MSG_HANDLERS}->{$endpoint}->{$messageType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
	}

	if (defined $self->{ALL_MSG_HANDLERS}->{$messageType}) {
		return $self->{ALL_MSG_HANDLERS}->{$messageType}->handleEvent($doc, $endpoint, $messageType, $message_parameters, $eventType, $md, $d);
	}

	return ("error.ma.event_type", "Event type \"$eventType\" is not yet supported for messages with type \"$messageType\" on endpoint \"$endpoint\"");
}

1;

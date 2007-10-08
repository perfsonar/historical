package perfSONAR_PS::MA::Handler;

use strict;
use warnings;

use Log::Log4perl qw(get_logger);

sub new($) {
	my ($package) = @_;
	my %hash = ();

	$hash{"ENDPOINTSPECIFICHANDLERS"} = ();
	$hash{"GENERICHANDLERS"} = ();
	$hash{"ENDPOINTSPECIFICHANDLERS_REGEX"} = ();
	$hash{"GENERICHANDLERS_REGEX"} = ();
	$hash{"VALIDENDPOINTS"} = ();

	bless \%hash => $package;
}

sub add($$$$$) {
	my ($self, $endpoint, $messageType, $eventType, $ma) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding handler for $endpoint, $messageType, $eventType");

	if ($endpoint eq "") {
		if (!defined $self->{GENERICHANDLERS}->{$messageType}) {
			$self->{GENERICHANDLERS}->{$messageType} = ();
		}

		$self->{GENERICHANDLERS}->{$messageType}->{$eventType} = $ma;
	} else {
		$endpoint =~ s/^(\/)+//g;

		$self->{VALIDENDPOINTS}->{$endpoint} = "";

		if (!defined $self->{ENDPOINTSPECIFIC}->{$endpoint}) {
			$self->{ENDPOINTSPECIFIC}->{$endpoint} = ();
		}

		if (!defined $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}) {
			$self->{ENDPOINTSPECIFIC}->{$endpoint}->{$endpoint}->{$messageType} = ();
		}

		$self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}->{$eventType} = $ma;
	}

	return 0;
}

sub addRegex($$$$$) {
	my ($self, $endpoint, $messageType, $eventRegex, $ma) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Adding handler for $endpoint, $messageType, $eventRegex");

	if ($endpoint eq "") {
		if (!defined $self->{GENERICHANDLERS_REGEX}->{$messageType}) {
			$self->{GENERICHANDLERS_REGEX}->{$messageType} = ();
		}

		$self->{GENERICHANDLERS_REGEX}->{$messageType}->{$eventRegex} = $ma;
	} else {
		$endpoint =~ s/^(\/)+//g;

		if (!defined $self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint}) {
			$self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint} = ();
		}

		if (!defined $self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint}->{$messageType}) {
			$self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint}->{$messageType} = ();
		}

		$self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint}->{$messageType}->{$eventRegex} = $ma;
	}

	return 0;
}

sub handleEvent($$$$) {
	my ($self, $endpoint, $messageType, $eventType, $md, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Handler");

	$logger->debug("Handling event: $endpoint, $messageType, $eventType");

	if (defined $self->{ENDPOINTSPECIFIC}->{$endpoint} and
			defined $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType} and
			defined $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}->{$eventType}) {
		return $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}->{$eventType}->handleEvent($endpoint, $messageType, $eventType, $md, $d);
	}

	if (defined $self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint} and
			defined $self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$endpoint}->{$messageType}) {
		foreach my $regex (keys %{$self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$messageType}}) {
			if ($eventType =~ /$regex/) {
				return $self->{ENDPOINTSPECIFICHANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($endpoint, $messageType, $eventType, $md, $d);
			}
		}
	}

	if (defined $self->{GENERICHANDLERS}->{$messageType} and defined $self->{GENERICHANDLERS}->{$messageType}->{$eventType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				return $self->{GENERICHANDLERS}->{$messageType}->{$eventType}->handleEvent($endpoint, $messageType, $eventType, $md, $d);
			}
		}
	}

	if (defined $self->{GENERICHANDLERS_REGEX}->{$messageType}) {
		foreach my $valid_endpoint (keys %{ $self->{VALIDENDPOINTS} }) {
			if ($valid_endpoint eq $endpoint) {
				foreach my $regex (keys %{$self->{GENERICHANDLERS_REGEX}->{$messageType}}) {
					if ($eventType =~ /$regex/) {
						return $self->{GENERICHANDLERS_REGEX}->{$messageType}->{$regex}->handleEvent($endpoint, $messageType, $eventType, $md, $d);
					}
				}
			}
		}
	}

	if (!defined $self->{VALIDENDPOINTS}->{$endpoint}) {
		return ("error.perfSONAR_PS.transport", "Received message with invalid endpoint: $endpoint");
	}

	if (!defined $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}) {
		return ("error.ma.message.type", "Message type \"".$messageType."\" is not yet supported");
	}

	if (!defined $self->{ENDPOINTSPECIFIC}->{$endpoint}->{$messageType}->{$eventType}) {
		return ("error.ma.event_type", "Event type \"$eventType\" is not yet supported for messages with type \"$messageType\"");
	}
}

1;

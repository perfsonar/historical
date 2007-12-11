=head1 NAME

perfSONAR_PS::Services::MA::Skeleton - A skeleton of a Measurement Archive module.

=head1 DESCRIPTION

This module aims to be easily modifiable to support new and different MAs.

=cut

package perfSONAR_PS::Services::MA::Skeleton;

=head2 perfSONAR_PS::Services::Base
	All perfSONAR Message Handling Modules need to be of type
	perfSONAR_PS::Services::Base. This adds the 'new' function and a set of
	functions that can be used to set various values for this MA.
=cut
use base 'perfSONAR_PS::Services::Base';

use strict;
use warnings;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

=head2 init($self, $handler);
	This routine is called on startup for each endpoint that uses this
	module. The function should be used to verify the configuration and set
	any default values. The function should return 0 if the configuration
	is valid, and -1 if an error is found.
=cut
sub init($$) {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::Skeleton");

	# Check the configuration and set some default values

	# If they haven't specified whether or not to perform LS registration, set it to false
	if (!defined $self->{CONF}->{"skeleton"}->{"enable_registration"} or
		$self->{CONF}->{"skeleton"}->{"enable_registration"} eq "") {
		$logger->warn("Disabling registration since its use is unspecified");
		$self->{CONF}->{"skeleton"}->{"enable_registration"} = 0;
	}

	if ($self->{CONF}->{"skeleton"}->{"enable_registration"}) {
		if (!defined $self->{CONF}->{"skeleton"}->{"service_accesspoint"} or $self->{CONF}->{"skeleton"}->{"service_accesspoint"} eq "") {
			$logger->error("No access point specified for SNMP service");
			return -1;
		}

		# Verify an LS instance exists. If no ls is set specifically
		# for the skeleton MA, check if a global ls_instance exists. If
		# so, set it to be the skeleton MA's ls_instance.
		if (!defined $self->{CONF}->{"skeleton"}->{"ls_instance"} or $self->{CONF}->{"skeleton"}->{"ls_instance"} eq "") {
			if (defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne "") {
				$self->{CONF}->{"skeleton"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
			} else {
				$logger->error("No LS instance specified for SNMP service");
				return -1;
			}
		}

		# Verify an LS registration interval exists. If no interval
		# exists, check to see if one was globally set. If not, set it
		# to a default of 30 minutes. If one does exist, change the
		# registration interval from minutes to seconds.
		if (!defined $self->{CONF}->{"skeleton"}->{"ls_registration_interval"} or $self->{CONF}->{"skeleton"}->{"ls_registration_interval"} eq "") {
			if (defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne "") {
				$self->{CONF}->{"skeleton"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
			} else {
				$logger->warn("Setting registration interval to 30 minutes");
				$self->{CONF}->{"skeleton"}->{"ls_registration_interval"} = 1800;
			}
		} else {
			# turn the registration interval from minutes to seconds
			$self->{CONF}->{"skeleton"}->{"ls_registration_interval"} *= 60;
		}

		# set a default service description
		if(!defined $self->{CONF}->{"skeleton"}->{"service_description"} or
				$self->{CONF}->{"skeleton"}->{"service_description"} eq "") {
			$self->{CONF}->{"skeleton"}->{"service_description"} = "perfSONAR_PS Skeleton MA";
			$logger->warn("Setting 'service_description' to 'perfSONAR_PS Skeleton MA'.");
		}

		# set a default service name
		if(!defined $self->{CONF}->{"skeleton"}->{"service_name"} or
				$self->{CONF}->{"skeleton"}->{"service_name"} eq "") {
			$self->{CONF}->{"skeleton"}->{"service_name"} = "Skeleton MA";
			$logger->warn("Setting 'service_name' to 'Skeleton MA'.");
		}

		# set a default service type
		if(!defined $self->{CONF}->{"skeleton"}->{"service_type"} or
				$self->{CONF}->{"skeleton"}->{"service_type"} eq "") {
			$self->{CONF}->{"skeleton"}->{"service_type"} = "MA";
			$logger->warn("Setting 'service_type' to 'MA'.");
		}

		# Create the LS client. This client will be reused each time
		# the registerLS function is called.
		my %ls_conf = (
				SERVICE_TYPE => $self->{CONF}->{"skeleton"}->{"service_type"},
				SERVICE_NAME => $self->{CONF}->{"skeleton"}->{"service_name"},
				SERVICE_DESCRIPTION => $self->{CONF}->{"skeleton"}->{"service_description"},
				SERVICE_ACCESSPOINT => $self->{CONF}->{"skeleton"}->{"service_accesspoint"},
			      );

		$self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"skeleton"}->{"ls_instance"}, \%ls_conf, $self->{NAMESPACES});
	}

	# Add a handler for events types "SkeletonRequest" in messages of type "SkeletonMessage"
	$handler->addEventHandler("SkeletonMessage", "SkeletonRequest", $self);

	# Add a handler for all events in messages of type "SkeletonMessage"
	$handler->addMessageHandler("SkeletonMessage2", "SkeletonRequest", $self);

	# Add a complete handler for messages of type "SkeletonMessage"
	$handler->addFullMessageHandler("SkeletonMessage3", $self);

	return 0;
}

=head2 needLS();
	This function returns whether or not this MA will need a registration
	process. It returns 0 if none is needed and non-zero if one is needed.
	If non-zero is returned, the function registerLS must be defined.
=cut
sub needLS($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	return $self->{CONF}->{"skeleton"}->{"enable_registration"};
}

=head2 registerLS($self, $sleep_time)
	This function is called in a separate process from the message
	handling. It is used to register the MA's metadata with an LS.
	Generally, this is done using the LS client software. The $sleep_time
	variable is a reference that can be used to return how long the process
	should sleep for before calling the registerLS function again.
=cut
sub registerLS($$) {
	my ($self, $sleep_time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	# Obtain the metadata as an array of strings containing the metadata
	my @metadata = $self->getMetadataToRegister();

	$self->{LS_CLIENT}->registerStatic(\@metadata);

	# Set the next sleep_time. This could be used to dynamically change the
	# registration interval if desired.
	if (defined $sleep_time) {
		$$sleep_time = $self->{CONF}->{"status"}->{"ls_registration_interval"};
	}
}

=head2 handleMessage ($self, $doc, $messageType, $message, $raw_request);
	If a "full" message handler is registered, this function is called
	when a new message is received. $doc is the
	perfSONAR_PS::XML::Document_string output element. $messageType is the
	type of the message. $message is a DOM element containing the message.
	$raw_request is the perfSONAR_PS::Request element that was received.
	This function must handle all aspects of the message processing and
	must store the response in $doc. No return value is necessary.
=cut
sub handleMessage($$$$$) {
	my ($self, $doc, $messageType, $message, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

}

=head2 handleMessageBegin ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
	 When a message handler is added, this function is called when a
	 message is received. The function can be used to initialize any per
	 request fields. This could include things like opening database
	 connections once instead of opening them each time a metadata/data
	 pair is found.  $retMessageType is a reference to a scalar and can be
	 used to set the message type of the returned message.
	 $retMessageNamespaces can be used to set the namespaces on the new
	 messages. If the returned value is zero, the daemon will begin the
	 message. If the returned value is non-zero, the module must start the
	 message.
=cut
sub handleMessageBegin($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	return 0;
}

=head2 handleMessageEnd ($self, $ret_message, $messageId);
	When a message handler is added, this function is called when the
	message is finished. This function can be used to cleanup any per
	request fields (like open database connections). If the function
	returns 0, the daemon will end the message. If the returned value is
	non-zero, the module must end the message.
=cut
sub handleMessageEnd($$$) {
	my ($self, $ret_message, $messageId) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	return 0;
}

=head2 handleEvent ($self, $output, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request);
	The handleEvent function is called when a metadata/data pair is found
	in a received message. $output is an element of type
	perfSONAR_PS::XML::Document_string that must be used to construct the
	response. $messageId and $messageType are strings containing the
	identifier and type of the message. $eventType is the event type in the
	md/d pair. This may be undefined if the event metadata does not contain
	an event type element. $md and $d are XML elements for the metadata and
	data. $raw_request is the perfSONAR_PS::Request element corresponding
	to the incoming request. The return value should be an array of two
	empty strings on success. On failure, the function can generate its own
	error metadata/dat and should return an array like above. However, the
	function can also return an array consisting of an event type and an
	error message and the daemon will create the appropriate error
	metadata/data.
=cut
sub handleEvent($$$$$$$$$) {
	my ($self, $output, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	my $retMetadata;
	my $retData;
	my $mdID = "metadata.".genuid();
	my $msg = "The skeleton exists.";

	my @ret_elements = ();

	getResultCodeMetadata($output, $mdID, $md->getAttribute("id"), "success.skeleton");
	getResultCodeData($output, "data.".genuid(), $mdID, $msg, 1);

	return ("", "");
}

1;

=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::LS::Register>


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

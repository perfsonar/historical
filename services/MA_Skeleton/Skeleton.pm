#!/usr/bin/perl -w

package perfSONAR_PS::MA::Skeleton;

use warnings;
use strict;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::LS::Register;

our @ISA = qw(perfSONAR_PS::MA::Base Exporter);
our @EXPORT = ('getDefaultNamespaces', 'getDefaultConfig' );

# XXX fill in any default configuration values that your MA may have
my %config_defaults = (
	ENABLE_MA => 1,
	ENABLE_LS => 0,
	PORT => 8083,
	ENDPOINT => "/perfSONAR_PS/services/skeleton",
	MAX_WORKER_PROCESSES => 0,
	MAX_WORKER_LIFETIME => 0,
	LS_REGISTRATION_INTERVAL => 10,
	SERVICE_TYPE => "MA",
	SERVICE_DESCRIPTION => "Skeleton Measurement Archive",
);

my %default_namespaces = (
	nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
);

sub getDefaultConfig {
	return \%config_defaults;
}

sub getDefaultNamespaces {
	return \%default_namespaces;
}
sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	# XXX
	# any required initialization should be done here.  This includes
	# initializing and verifying the database as well as any other data
	# structures used by this MA

	if ($self->SUPER::init != 0) {
		$logger->error("Couldn't initialize parent class");
		return -1;
	}

	return 0;
}

sub registerLS($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	# XXX
	# This function will be called periodically to register/reregister data
	# with the LS. The function should generate an array of metadata
	# strings to register and call $ls->register_withData with the array.

	#my $ls = new perfSONAR_PS::LS::Register($self->{CONF}, $self->{NAMESPACES});
	# return $ls->register_withData(\@mds);
	$logger->warn("No registerLS function implemented");
}

sub receive($$$) {
	my ($self, $ret_request, $ret_error) = @_;

	return $self->{LISTENER}->acceptCall($ret_request, $ret_error);
}

sub handleRequest($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	# This function is a wrapper around the __handleRequest function.  The
	# purpose of the function is to handle the case where a crash occurs
	# while handling the request or the handling of the request runs for
	# too long.

	eval {
 		local $SIG{ALRM} = sub{ die "Request lasted too long\n" };
		alarm($self->{CONF}->{"MAX_WORKER_LIFETIME"}) if (defined $self->{CONF}->{"MAX_WORKER_LIFETIME"} and $self->{CONF}->{"MAX_WORKER_LIFETIME"} > 0);
		__handleRequest($self, $request);
 	};

	# disable the alarm after the eval is done
	alarm(0);

	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		$request->setResponse(getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred"));
	}

	$request->finish;

	return;
}

sub __handleRequest($$) {
	my($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");
	my $messageIdReturn = genuid();
	my $messageId = $request->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $request->getRequestDOM()->getDocumentElement->getAttribute("type");

	my ($status, $response);

	# XXX
	# This function calls the handler type for each different message type.
	# When the response is returned, it creates the response message for
	# the request.

	if($messageType eq "SetupDataRequest") {
		($status, $response) = $self->handleMessage($messageType, $request->getRequestDOM()->documentElement);
	} else {
		$status = "error.ma.message.type";
		$response = "Message type \"".$messageType."\" is not yet supported";
		$logger->error($response);
	}

	if ($status ne "") {
		$logger->error("Unable to handle skeleton request: $status/$response");
		$request->setResponse(getResultCodeMessage($messageIdReturn, $messageId, "", $messageType."Response", $status, $response, 1));
	} else {
		my %all_namespaces = ();

		my $request_namespaces = $request->getNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$request->setResponse(getResultMessage($messageIdReturn, $messageId, $messageType, $response, \%all_namespaces));
	}
}

sub handleMessage($$$) {
	my ($self, $messageType, $message) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Skeleton");

	# XXX
	# This function handles the message. In the basic case, it simply
	# iterates through the metadata/data pairs calling a function each time
	# it finds one. It then generates the response md/d pair from the
	# results returned. This need not be one function that handles all
	# message types. One could create a set of functions that each handle
	# one or more different message types.

	my $localContent = "";

	my $found_pair = 0;

	foreach my $d ($message->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($message->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = findvalue($m, "./nmwg:eventType");

				$found_pair = 1;

				my ($status, $res);

				if (!defined $eventType or $eventType eq "") {
					$status = "error.ma.no_eventtype";
					$res = "No event type specified for metadata: ".$m->getAttribute("id");
				} else {
					($status, $res) = $self->handleMetadataPair($messageType, $eventType, $m, $d);
				}

				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");
					my $mdID = "metadata.".genuid();
					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
				} else {
					$localContent .= $m->toString;
					$localContent .= createData("data.".genuid(), $m->getAttribute("id"), $res);
				}
			}
		}
	}

	if ($found_pair == 0) {
		my $status = "error.ma.no_metadata_data_pair";
		my $res = "There was no data/metadata pair found";

		my $mdID = "metadata.".genuid();

		$localContent .= getResultCodeMetadata($mdID, "", $status);
		$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
	}

	return ("", $localContent);
}

sub handleMetadataPair($$$$) {
	my ($self, $messageType, $eventType, $md, $d) = @_;

	# XXX
	# This function actually handles a metadata/data pair. This need not be
	# a single function to handle all md/d pairs. It could be split up into
	# separate functions that each handle one or more md/d pairs.

	my $status = "error.ma.invalid_event_type";
	my $message =  "Event type $eventType is not valid in a message of type $messageType";

	return ($status, $message);
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::Skeleton - A skeleton of an MA module that can be modified as needed.

=head1 DESCRIPTION

This module aims to be easily modifiable to support new and different MA types.

=head1 SYNOPSIS

use perfSONAR_PS::MA::Skeleton;

my %conf;

my $default_ma_conf = &perfSONAR_PS::MA::Skeleton::getDefaultConfig();
if (defined $default_ma_conf) {
	foreach my $key (keys %{ $default_ma_conf }) {
		$conf{$key} = $default_ma_conf->{$key};
	}
}

if (readConfiguration($CONFIG_FILE, \%conf) != 0) {
	print "Couldn't read config file: $CONFIG_FILE\n";
	exit(-1);
}

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
	 );

my $ma = perfSONAR_PS::MA::Skeleton->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Skeleton->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

if ($ma->init != 0) {
	print "Error: couldn't initialize measurement archive\n";
	exit(-1);
}

$ma->registerLS;

while(1) {
	my ($n, $request, $error);

	$n = $ma->receive(\$request, \$error);

	if (defined $error and $error ne "") {
		print "Error in receive call: $error");
	}

	next if (!defined $request);

	if ($n == 0) {
		print "Received already handled request\n";
	} else {
		$ma->handleRequest($request);
	}

	$request->finish();
}

=head1 API

The offered API is simple, but offers the key functions needed in a measurement archive.

=head2 getDefaultConfig

	Returns a reference to a hash containing default configuration options

=head2 getDefaultNamespaces

	Returns a reference to a hash containing the set of namespaces used by
	the MA

=head2 init 

       Initializes the MA and validates the entries in the
       configuration file. Returns 0 on success and -1 on failure.

=head2 registerLS($self)

	Registers the data contained in the MA with the configured LS.

=head2 receive($self)

	Grabs an incoming message from transport object to begin processing. It
	completes the processing if the message was handled by a lower layer.
	If not, it returns the Request structure.

=head2 handleRequest($self, $request)

	Handles the specified request returned from receive()

=head2 __handleRequest($self)

	Validates that the message is one that we can handle, calls the
	appropriate function for the message type and builds the response
	message. 

=head2 handleMessage($self, $messageType, $message)
	Handles the specific message. This should entail iterating through the
	metadata/data pairs and handling each one.

=head2 handleMetadataPair($$$$) {
	Handles a specific metadata/data request.


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

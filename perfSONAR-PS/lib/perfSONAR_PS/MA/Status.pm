#!/usr/bin/perl -w

package perfSONAR_PS::MA::Status;

use warnings;
use strict;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::MA::Status::Client::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	$self->SUPER::init;

	if (!defined $self->{CONF}->{"STATUS_DB_TYPE"} or $self->{CONF}->{"STATUS_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if ($self->{CONF}->{"STATUS_DB_TYPE"} eq "SQLite") {
		if (!defined $self->{CONF}->{"STATUS_DB_FILE"} or $self->{CONF}->{"STATUS_DB_FILE"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(STATUS_DB_FILE)");
			return -1;
		}

		$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"STATUS_DB_FILE"});
		if (!defined $self->{CLIENT}) {
			my $msg = "No database to dump";
			$logger->error($msg);
			return (-1, $msg);
		}

	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	return 0;
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $readValue = $self->{LISTENER}->acceptCall;
	if($readValue == 0) {
		$logger->debug("Received 'shadow' request from below; no action required.");
		$self->{RESPONSE} = $self->{LISTENER}->getResponse();
	} elsif($readValue == 1) {
		$logger->debug("Received request to act on.");
		handleRequest($self);
	} else {
		my $msg = "Sent Request was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
		$logger->error($msg);
		$self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg);
	}
	return;
}

sub handleRequest {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	delete $self->{RESPONSE};
	my $messageIdReturn = genuid();
	my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");

	my ($status, $response);

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling lookup request.");
		($status, $response) = $self->parseLookupRequest($self->{LISTENER}->getRequestDOM());
	} elsif ($messageType eq "MeasurementArchiveStoreRequest") {
		$logger->debug("Handling store request.");
		($status, $response) = $self->parseStoreRequest($self->{LISTENER}->getRequestDOM());
	} else {
		$status = "error.common.action_not_supported";
		$response = "Message type \"".$messageType."\" is not yet supported";
	}

	if ($status ne "") {
		$logger->error("Error handling request: $status/$response");
		$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", $status, $response);
	} else {

		my %all_namespaces = ();

		my $request_namespaces = $self->{LISTENER}->getRequestNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, $messageType."Response", $response, \%all_namespaces);
	}

	open(RESP, ">out.resp");
	print RESP $self->{RESPONSE};
	close(RESP);

	return $self->{RESPONSE};
}

sub parseStoreRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $link_id = $m->findvalue('./nmwg:subject/*[local-name()=\'link\']/@id');
				my $knowledge = $m->findvalue('./nmwg:parameters/nmwg:parameter[@name="knowledge"]');
				my $time = $d->findvalue('./ifevt:datum/@timeValue');
				my $time_type = $d->findvalue('./ifevt:datum/@timeType');
				my $adminState = $d->findvalue('./ifevt:datum/ifevt:stateAdmin');
				my $operState = $d->findvalue('./ifevt:datum/ifevt:operAdmin');

				if (!defined $link_id) {
					my $msg = "Metadata ".$m->getAttribute("id")." is missing the link id";
					$logger->error($msg);
					return ("error.ma.query.incomplete_metadata", $msg);
				}

				if (!defined $knowledge) {
					my $msg = "Metadata ".$m->getAttribute("id")." is missing knowledge parameter";
					$logger->error($msg);
					return ("error.ma.query.incomplete_metadata", $msg);
				}

				if (!defined $time or !defined $time_type or !defined $adminState or !defined $operState) {
					my $msg = "Data ".$d->getAttribute("id")." is incomplete";
					$logger->error($msg);
					return ("error.ma.query.incomplete_data", $msg);
				}

				if ($time_type ne "unix") {
					my $msg = "Time type must be unix timestamp";
					$logger->error($msg);
					return ("error.ma.query.invalid_timestamp_type", $msg);
				}

				my ($status, $res) = $self->handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState);
				if ($status ne "") {
					my $msg = "Couldn't handle store request: $res";
					$logger->error($msg);
					return ($status, $res);
				}

				# give them back what they gave us?

				$localContent .= $m->toString;
				$localContent .= $d->toString;
			}
		}
	}

	return ("", $localContent);
}

sub handleStoreRequest($$$$$) {
	my ($self, $link_id, $knowledge, $time, $operState, $adminState) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my ($status, $res);

	$logger->debug("handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState)");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $link_id, $knowledge, $operState, $adminState, 0);
	if ($status != 0) {
		my $msg = "Database update failed: $res";
		$logger->error($msg);
		return ("error.common.storage.update", $msg);
	}

	return ("", "");
}

sub parseLookupRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				if ($eventType eq "Database.Dump") {
					my ($status, $res) = $self->lookupAllRequest($m, $d);
					if ($status ne "") {
						$logger->error("Couldn't dump status information");
						return ($status, $res);
					}

					$localContent .= $res;
				} elsif ($eventType eq "Link.History") {
					my ($status, $res) = $self->lookupLinkHistoryRequest($m, $d);
					if ($status != 0) {
						$logger->error("Couldn't dump link history information");
						return ($status, $res);
					}

					$localContent .= $res;
				} elsif ($eventType eq "Link.Status") {
					my ($status, $res) = $self->lookupLinkStatusRequest($m, $d);
					if ($status ne "") {
						$logger->error("Couldn't dump link information");
						return ($status, $res);
					}

					$localContent .= $res;
				} else {
					$logger->error("Unknown event type: ".$eventType);
					return ( -1, "Unknown event type: ".$eventType )
				}
			}
		}
	}

	open(OUT, ">out.res");
	print OUT $localContent;
	close OUT;

	return ("", $localContent);
}

sub lookupAllRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";
	my ($status, $res);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->getAll;
	if ($status != 0) {
		my $msg = "Couldn't get information from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	my %links = %{ $res };

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	my $i = genuid();
	foreach my $link_id (keys %links) {
		$localContent .= "<nmwg:metadata id=\"meta$i\" metadataIdRef=\"$mdid\">\n";
		$localContent .= "  <nmwg:subject id=\"sub$i\">\n";
		$localContent .= "    <nmtopo:link id=\"$link_id\" />\n";
		$localContent .= "  </nmwg:subject>\n";
		$localContent .= "</nmwg:metadata>\n";
		$localContent .= "<nmwg:data metadataIdRef=\"meta$i\">\n";
		foreach my $link (@{ $links{$link_id} }) {
			$localContent .= $self->writeoutLinkState($link);
		}
		$localContent .= "</nmwg:data>\n";

		$i++;
	}

	return ("", $localContent);
}

sub lookupLinkHistoryRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my ($status, $res);
	my $localContent = "";

	$logger->debug("lookupLinkHistoryRequest()");

	my $link_id = $m->findvalue('./nmwg:subject/*[local-name()=\'link\']/@id');

	$logger->debug("got link $link_id");

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return ("error.ma.status.no_link_id", $msg);
	}

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	my @tmp_array = ( $link_id );

	($status, $res) = $self->{CLIENT}->getLinkHistory(\@tmp_array);
	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data metadataIdRef=\"$mdid\">\n";
	foreach my $link_id (%{ $res }) {
		foreach my $link (@{ $res->{$link_id} }) {
			$localContent .= $self->writeoutLinkState($link);
		}
	}

	$localContent .= "</nmwg:data>\n";

	return ("", $localContent);
}

sub lookupLinkStatusRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";
	my ($status, $res);

	my $link_id = $m->findvalue('./nmwg:subject/*[local-name()=\'link\']/@id');
	my $time = $m->findvalue('./nmwg:parameters/nmwg:parameter[@name="time"]');

	if (!defined $time or $time eq "now") {
		# no time simply grabs the most recent information
		$time = "";
	}

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return ("error.ma.status.no_link_id", $msg);
	}

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	my @tmp_array = ( $link_id );

	($status, $res) = $self->{CLIENT}->getLinkStatus(\@tmp_array, $time);
	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data metadataIdRef=\"$mdid\">\n";
	$localContent .= $self->writeoutLinkState(pop(@{ $res->{$link_id} }));
	$localContent .= "</nmwg:data>\n";

	return ("", $localContent);
}

sub writeoutLinkState($$$) {
	my ($self, $link, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	if (!defined $time or $time eq "") {
	$localContent .= "<ifevt:datum timeType=\"unix\" timeValue=\"".$link->getEndTime."\" knowledge=\"".$link->getKnowledge."\"\n";
	$localContent .= "	startTime=\"".$link->getStartTime."\" startTimeType=\"unix\" endTime=\"".$link->getEndTime."\" endTimeType=\"unix\">\n";
	} else {
	$localContent .= "<ifevt:datum knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"$time\">\n";
	}
	$localContent .= "	<ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
	$localContent .= "	<ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
	$localContent .= "</ifevt:datum>\n";

	return $localContent;
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::Status - A module that provides methods for the Status MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::MA::Status;

my %conf = ();
$conf{"METADATA_DB_TYPE"} = "xmldb";
$conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Status/xmldb";
$conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
$conf{"PING"} = "/bin/ping";

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
		select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
	 );

my $ma = perfSONAR_PS::MA::Status->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Status->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

$ma->init;
while(1) {
	$ma->receive;
	$ma->respond;
}


=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed nn an MA.
Additional logic is needed to address issues such as different backend storage facilities.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive.

=head2 receive($self)

	Grabs message from transport object to begin processing.

=head2 handleRequest($self)

	Functions as the 'gatekeeper' the the MA.  Will either reject or accept
	requets.  will also 'do nothing' in the event that a request has been
	acted on by the lower layer.

=head2 parseLookupRequest($self, $messageId, $messageIdRef, $type)

	Processes both the the MetadataKeyRequest and SetupDataRequest messages, which
	preturn either metadata or data to the user.

=head2 setupDataKeyRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

	Runs the specific needs of a SetupDataRequest when a key is presented to
	the service.

=head2 setupDataRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

	Runs the specific needs of a SetupDataRequest when a key is NOT presented to
	the service.

=head2 handleData($self, $id, $dataString, $localContent)

	Helper function to extract data from the backed storage.

=head2 retrieveSQL($did)

	The data is extracted from the backed storage (in this case SQL).

=head2 retrieveRRD($did)

	The data is extracted from the backed storage (in this case RRD).

	=head1 SEE ALSO

	L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
	L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>,
	L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::RRD>

	To join the 'perfSONAR-PS' mailing list, please visit:

	https://mail.internet2.edu/wws/info/i2-perfsonar

	The perfSONAR-PS subversion repository is located at:

	https://svn.internet2.edu/svn/perfSONAR-PS

	Questions and comments can be directed to the author, or the mailing list.

	=head1 VERSION

	$Id: Status.pm 242 2007-06-19 21:22:24Z zurawski $

	=head1 AUTHOR

	Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

	=head1 COPYRIGHT AND LICENSE

	Copyright (C) 2007 by Internet2

	This library is free software; you can redistribute it and/or modify
	it under the same terms as Perl itself, either Perl version 5.8.8 or,
	at your option, any later version of Perl 5 you may have available.

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

	$self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling status request.");
		my ($status, $response) = $self->parseRequest($self->{LISTENER}->getRequestDOM());
		if ($status != 0) {
			$logger->error("Unable to handle status request");
			$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.content", $response);
		} else {
			$self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "SetupDataRequest", $response);
		}
	} else {
		my $msg = "Message type \"".$messageType."\" is not yet supported";
		$logger->error($msg);
		$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.type", $msg);
	}

	return $self->{RESPONSE};
}

sub parseRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				if ($eventType eq "Database.Dump") {
					my ($status, $res) = $self->lookupAllRequest($m, $d);
					if ($status != 0) {
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
				} elsif ($eventType eq "Link.Recent") {
					my ($status, $res) = $self->lookupLinkRecentRequest($m, $d);
					if ($status != 0) {
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

	return (0, $localContent);
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
		return (-1, $msg);
	}

	($status, $res) = $self->{CLIENT}->getAll;
	if ($status != 0) {
		my $msg = "Couldn't get information from database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	print "STUFF: ".Dumper($res);

	my %links = %{ $res };

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\" metadataIdRef=\"$mdid\">\n";

	foreach my $link_id (keys %links) {
		print "LINK_ID: $link_id\n";
		foreach my $link (@{ $links{$link_id} }) {
			$localContent .= $self->writeoutLinkState($link);
		}
	}
	$localContent .= "</nmwg:data>\n";

	return (0, $localContent);
}

sub lookupLinkHistoryRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my ($status, $res);
	my $localContent = "";

	my $link_id = $m->findvalue("./nmwg:parameters/nmwg:parameter[\@name=\"linkId\"]");

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return (-1, $msg);
	}

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my @tmp_array = ( $link_id );

	($status, $res) = $self->{CLIENT}->getLinkHistory(\@tmp_array);
	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\" metadataIdRef=\"$mdid\">\n";
	foreach my $link (@{ $res }) {
		$localContent .= $self->writeoutLinkState($link);
	}
	$localContent .= "</nmwg:data>\n";

	return (0, $localContent);
}

sub lookupLinkRecentRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";
	my ($status, $res);

	my $link_id = $m->findvalue("./nmwg:parameters/nmwg:parameter[\@name=\"linkId\"]");

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return (0, $msg);
	}

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my @tmp_array = ( $link_id );

	($status, $res) = $self->{CLIENT}->getLastLinkStatus(\@tmp_array);
	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\" metadataIdRef=\"$mdid\">\n";
	$localContent .= $self->writeoutLinkState($res);
	$localContent .= "</nmwg:data>\n";

	return (0, $localContent);
}

sub writeoutLinkState($$) {
	my ($self, $link) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	$logger->debug("writing out ". $link->getID);
	$localContent .= "<nmtopo:linkStatus linkID=\"".$link->getID."\" knowledge=\"".$link->getKnowledge."\" startTime=\"".$link->getStartTime."\" endTime=\"".$link->getEndTime."\">\n";
	$localContent .= "	<nmtopo:operStatus>".$link->getOperStatus."</nmtopo:operStatus>\n";
	$localContent .= "	<nmtopo:adminStatus>".$link->getAdminStatus."</nmtopo:adminStatus>\n";
	$localContent .= "</nmtopo:linkStatus>\n";

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

=head2 parseRequest($self, $messageId, $messageIdRef, $type)

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

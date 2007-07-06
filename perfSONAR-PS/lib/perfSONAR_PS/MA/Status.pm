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
use perfSONAR_PS::DB::SQL;

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

		$self->{DATADB} = new perfSONAR_PS::DB::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"STATUS_DB_FILE"});
		if (!defined $self->{DATADB}) {
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
					my ($status, $res) = $self->pathStatusRequest($m, $d);
					if ($status != 0) {
						$logger->error("Couldn't dump status information");
						return ($status, $res);
					}

					$localContent .= $res;
				} elsif ($eventType eq "Link.History") {
					my ($status, $res) = $self->linkHistoryRequest($m, $d);
					if ($status != 0) {
						$logger->error("Couldn't dump link history information");
						return ($status, $res);
					}

					$localContent .= $res;
				} elsif ($eventType eq "Link.Recent") {
					my ($status, $res) = $self->linkRecentRequest($m, $d);
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

	return (0, $localContent);
}

sub pathStatusRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";

	$localContent .= $m->toString();

	$localContent .= "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
	my ($status, $res) = $self->dumpDatabase;
	if ($status == 0) {
		$localContent .= $res;
	} else {
		$logger->error("Couldn't dump status structure: $res");
		return ($status, $res);
	}
	$localContent .= "  </nmwg:data>\n";

	return (0, $localContent);
}

sub linkRecentRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";

	my $link_id = $m->findvalue("./nmwg:parameters/nmwg:parameter[\@name=\"linkId\"]");

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return (0, $msg);
	}

	$localContent .= $m->toString();

	$localContent .= "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
	my ($status, $res) = $self->dumpLastLinkState($link_id);
	if ($status == 0) {
		$localContent .= $res;
	} else {
		$logger->error("Couldn't dump link status: $res");
		return ($status, $res);
	}
	$localContent .= "  </nmwg:data>\n";

	return (0, $localContent);
}

sub linkHistoryRequest($$$) {
	my($self, $m, $d) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $localContent = "";

	my $link_id = $m->findvalue("./nmwg:parameters/nmwg:parameter[\@name=\"linkId\"]");

	if (!defined $link_id or $link_id eq "") {
		my $msg = "No link id specified in request";
		$logger->error($msg);
		return (-1, $msg);
	}

	$localContent .= $m->toString();

	$localContent .= "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
	my ($status, $res) = $self->dumpLinkStatus($link_id, "");
	if ($status == 0) {
		$localContent .= $res;
	} else {
		$logger->error("Couldn't dump link status: $res");
		return ($status, $res);
	}
	$localContent .= "  </nmwg:data>\n";

	return (0, $localContent);
}

sub dumpDatabase {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my ($status, $res);

	if ($self->{CONF}->{"STATUS_DB_TYPE"} eq "SQLite") {
		($status, $res) = $self->dumpSQLDatabase;
	} else {
		my $msg = "Unknown status database type: ".$self->{CONF}->{"STATUS_DB_TYPE"};
		$logger->error($msg);
		$self->{DATADB}->closeDB;
		return (-1, $msg);
	}

	$self->{DATADB}->closeDB;

	return ($status, $res);
}

sub dumpSQLDatabase($$$) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $links = $self->{DATADB}->query("select distinct link_id from link_status");
	if ($links == -1) {
		$logger->error("Couldn't grab list of links");
		return (-1, "Couldn't grab list of links");
	}

	my $localContent = "";

	foreach my $link_ref (@{ $links }) {
		my @link = @{ $link_ref };

		my $states = $self->{DATADB}->query("select link_knowledge, start_time, end_time, oper_status, admin_status from link_status where link_id=\'".$link[0]."\' order by end_time");
		if ($states == -1) {
			$logger->error("Couldn't grab information for link ".$link[0]);
			return (-1, "Couldn't grab information for link ".$link[0]);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };

			$localContent .= $self->__dumpLinkState($link[0], $state[0], $state[1], $state[2], $state[3], $state[4]);
		}
	}

	return (0, $localContent);
}

sub dumpLinkStatus($$$) {
	my ($self, $link_id, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	my $query = "select link_knowledge, start_time, end_time, oper_status, admin_status from link_status where link_id=\'".$link_id."\'";
	if (defined $time and $time ne "") {
		$query .= "where end_time => $time and start_time <= $time";
	}

	my $status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open status database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $states = $self->{DATADB}->query($query);
	if ($states == -1) {
		$logger->error("Couldn't grab information for node ".$link_id);
		return (-1, "Couldn't grab information for node ".$link_id);
	}

	foreach my $state_ref (@{ $states }) {
		my @state = @{ $state_ref };

		$localContent .= $self->__dumpLinkState($link_id, $state[0], $state[1], $state[2], $state[3], $state[4]);
	}

	return (0, $localContent);
}

sub __dumpLinkState($$$$$) {
	my ($self, $link_id, $knowledge, $start_time, $end_time, $oper_status, $admin_status) = @_;

	my $localContent = "";
	$localContent .= "<nmtopo:linkStatus linkID=\"".$link_id."\" knowledge=\"".$knowledge."\" startTime=\"".$start_time."\" endTime=\"".$end_time."\">\n";
	$localContent .= "	<nmtopo:operStatus>".$oper_status."</nmtopo:operStatus>\n";
	$localContent .= "	<nmtopo:adminStatus>".$admin_status."</nmtopo:adminStatus>\n";
	$localContent .= "</nmtopo:linkStatus>\n";

	return $localContent;
}

sub dumpLastLinkState($$$) {
	my ($self, $link_id) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	my $localContent = "";

	my $states = $self->{DATADB}->query("select link_knowledge, start_time, end_time, oper_status, admin_status from link_status where link_id=\'".$link_id."\' order by end_time desc limit 1");
	if ($states == -1) {
		$logger->error("Couldn't grab information for node ".$link_id);
		return (-1, "Couldn't grab information for node ".$link_id);
	}

	foreach my $state_ref (@{ $states }) {
		my @state = @{ $state_ref };

		$localContent .= $self->__dumpLinkState($link_id, $state[0], $state[1], $state[2], $state[3], $state[4]);
	}

	return (0, $localContent);
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

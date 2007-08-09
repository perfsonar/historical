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
use perfSONAR_PS::LS::Register;
use perfSONAR_PS::MA::Status::Client::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	if ($self->SUPER::init != 0) {
		$logger->error("Couldn't initialize MA parent class");
		return -1;
	}

	if (!defined $self->{CONF}->{"STATUS_DB_TYPE"} or $self->{CONF}->{"STATUS_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if (lc($self->{CONF}->{"STATUS_DB_TYPE"}) eq "sqlite") {
		if (!defined $self->{CONF}->{"STATUS_DB_FILE"} or $self->{CONF}->{"STATUS_DB_FILE"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(STATUS_DB_FILE)");
			return -1;
		}

		$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"STATUS_DB_FILE"}, $self->{CONF}->{"STATUS_DB_TABLE"});
		if (!defined $self->{CLIENT}) {
			my $msg = "No database to dump";
			$logger->error($msg);
			return (-1, $msg);
		}
	} elsif (lc($self->{CONF}->{"STATUS_DB_TYPE"}) eq "mysql") {
		my $dbi_string = "dbi:mysql";

		if (!defined $self->{CONF}->{"STATUS_DB_NAME"} or $self->{CONF}->{"STATUS_DB_NAME"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database (STATUS_DB_NAME)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"STATUS_DB_NAME"};

		if (!defined $self->{CONF}->{"STATUS_DB_HOST"} or $self->{CONF}->{"STATUS_DB_HOST"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database host (STATUS_DB_HOST)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"STATUS_DB_HOST"};

		if (defined $self->{CONF}->{"STATUS_DB_PORT"} and $self->{CONF}->{"STATUS_DB_PORT"} ne "") {
			$dbi_string .= ":".$self->{CONF}->{"STATUS_DB_PORT"};
		}

		$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL($dbi_string, $self->{CONF}->{"STATUS_DB_USERNAME"}, $self->{CONF}->{"STATUS_DB_PASSWORD"});
		if (!defined $self->{CLIENT}) {
			my $msg = "Couldn't create SQL client";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	if (defined $self->{CONF}->{"LS_INSTANCE"} and $self->{CONF}->{"LS_INSTANCE"} ne "") {
		if (!defined $self->{CONF}->{"SERVICE_ACCESSPOINT"} or $self->{CONF}->{"SERVICE_ACCESSPOINT"} eq "") {
			my $msg = "You specified to specify a SERVICE_ACCESSPOINT so that people consulting the LS know how to get to this service.";
			$logger->error($msg);
			return -1;
		}

		# fill in sane defaults if the user does not

		if (!defined $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} or $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} eq "") {
			$self->{CONF}->{"LS_REGISTRATION_INTERVAL"} = 5; # 5 minutes
		}

		if (!defined $self->{CONF}->{SERVICE_TYPE} or $self->{CONF}->{SERVICE_TYPE}) {
			$self->{CONF}->{SERVICE_TYPE} = "MA";
		}

		if (!defined $self->{CONF}->{SERVICE_DESCRIPTION} or $self->{CONF}->{SERVICE_DESCRIPTION}) {
			$self->{CONF}->{SERVICE_DESCRIPTION} = "Link Status Measurement Archive";
		}

		my $reg_pid = fork();
		if ($reg_pid == 0) {
			$self->registerLS();
			exit(0);
		} elsif ($reg_pid < 0) {
			$logger->error("Couldn't start LS registration process");
			return -1;
		}
	}

	return 0;
}

sub registerLS {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my $ls = new perfSONAR_PS::LS::Register($self->{CONF}, $self->{NAMESPACES});
	my ($status, $res);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open from database: $res";
		$logger->error($msg);
		exit(-1);
	}

	($status, $res) = $self->{CLIENT}->getAll;
	if ($status != 0) {
		my $msg = "Couldn't get link nformation from database: $res";
		$logger->error($msg);
		exit(-1);
	}

	my @link_mds = ();
	my $i = 0;
	foreach my $link_id (keys %{ $res }) {
		my $md = "";

		$md .= "<nmwg:metadata id=\"meta$i\">\n";
		$md .= "<nmwg:subject id=\"sub$i\">\n";
		$md .= " <nmtopo:link xmlns:nmtopo=\"http://ogf.org/schema/network/topology/base/20070707/\" id=\"$link_id\" />\n";
		$md .= "</nmwg:subject>\n";
		$md .= "<nmwg:eventType>status</nmwg:eventType>\n";
		$md .= "</nmwg:metadata>\n";
		push @link_mds, $md;
		$i++;
	}

	$res = "";

	while(1) {
		$ls->register_withData(\@link_mds);
		sleep($self->{CONF}->{"LS_REGISTRATION_INTERVAL"} * 60);
	}
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	eval {
		my $readValue = $self->{LISTENER}->acceptCall;
		if($readValue == 0) {
			$logger->debug("Received 'shadow' request from below; no action required.");
			$self->{RESPONSE} = $self->{LISTENER}->getResponse();
		} elsif($readValue == 1) {
			$logger->debug("Received request to act on.");
			handleRequest($self);
		}
	};
	if ($@) {
		my $msg = "Unhandled exception or crash: $@";
		$logger->error($msg);

		$self->{RESPONSE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", "An internal error occurred");  

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
				my $do_update = $m->findvalue('./nmwg:parameters/nmwg:parameter[@name="update"]');
				my $time = $d->findvalue('./ifevt:datum/@timeValue');
				my $time_type = $d->findvalue('./ifevt:datum/@timeType');
				my $adminState = $d->findvalue('./ifevt:datum/ifevt:stateAdmin');
				my $operState = $d->findvalue('./ifevt:datum/ifevt:stateOper');

				if (!defined $link_id or $link_id eq "") {
					my $msg = "Metadata ".$m->getAttribute("id")." is missing the link id";
					$logger->error($msg);
					return ("error.ma.query.incomplete_metadata", $msg);
				}

				if (!defined $knowledge or $knowledge eq "") {
					my $msg = "Metadata ".$m->getAttribute("id")." is missing knowledge parameter";
					$logger->error($msg);
					return ("error.ma.query.incomplete_metadata", $msg);
				}

				if (!defined $time or $time eq "" or !defined $time_type or $time_type eq "" or !defined $adminState or $adminState eq "" or !defined $operState or $operState eq "") {
					my $msg = "Data ".$d->getAttribute("id")." is incomplete";
					$logger->error($msg);
					return ("error.ma.query.incomplete_data", $msg);
				}

				if ($time_type ne "unix") {
					my $msg = "Time type must be unix timestamp";
					$logger->error($msg);
					return ("error.ma.query.invalid_timestamp_type", $msg);
				}

				if (defined $do_update and $do_update ne "") {
					if (lc($do_update) eq "yes") {
						$do_update = 1;
					} elsif (lc($do_update) eq "no") {
						$do_update = 0;
					} else {
						my $msg = "Update must be 'yes' or 'no'";
						$logger->error($msg);
						return ("error.ma.query.invalid_update", $msg);
					}
				} else {
					$do_update = 0;
				}

				my ($status, $res) = $self->handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update);
				if ($status ne "") {
					my $mdID = "metadata.".genuid();

					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res);
				} else {
					$localContent .= $m->toString;
					$localContent .= $d->toString;
				}
			}
		}
	}

	return ("", $localContent);
}

sub handleStoreRequest($$$$$$) {
	my ($self, $link_id, $knowledge, $time, $operState, $adminState, $do_update) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");
	my ($status, $res);

	$logger->debug("handleStoreRequest($link_id, $knowledge, $time, $operState, $adminState, $do_update)");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return ("error.common.storage.open", $msg);
	}

	($status, $res) = $self->{CLIENT}->updateLinkStatus($time, $link_id, $knowledge, $operState, $adminState, $do_update);
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

				my ($status, $res);

				if ($eventType eq "Database.Dump") {
					($status, $res) = $self->lookupAllRequest($m, $d);
				} elsif ($eventType eq "Link.Status") {
					($status, $res) = $self->lookupLinkStatusRequest($m, $d);
				} else {
					$status = "error.ma.eventtype_not_supported";
					$res = "Unknown event type: ".$eventType;
				}

				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");

					my $mdID = "metadata.".genuid();

					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res);
				} else {
					$localContent .= $res;
				}
			}
		}
	}

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
			$localContent .= $self->writeoutLinkState_range($link);
		}
		$localContent .= "</nmwg:data>\n";

		$i++;
	}

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

	if ($time eq "all") {
		($status, $res) = $self->{CLIENT}->getLinkHistory(\@tmp_array);
	} else {
		($status, $res) = $self->{CLIENT}->getLinkStatus(\@tmp_array, $time);
	}

	if ($status != 0) {
		my $msg = "Couldn't get information about link $link_id from database: $res";
		$logger->error($msg);
		return ("error.common.storage.fetch", $msg);
	}

	my $mdid = $m->getAttribute("id");

	$localContent .= $m->toString()."\n";

	$localContent .= "<nmwg:data metadataIdRef=\"$mdid\">\n";
	if ($time eq "all") {
		foreach my $link (@{ $res->{$link_id} }) {
			$localContent .= $self->writeoutLinkState_range($link);
		}
	} else {
		$localContent .= $self->writeoutLinkState(pop(@{ $res->{$link_id} }), $time);
	}
	$localContent .= "</nmwg:data>\n";

	return ("", $localContent);
}

sub writeoutLinkState_range($$$) {
	my ($self, $link) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	return "" if (!defined $link);

	my $localContent = "";

	$localContent .= "<ifevt:datum timeType=\"unix\" timeValue=\"".$link->getEndTime."\" knowledge=\"".$link->getKnowledge."\"\n";
	$localContent .= "	startTime=\"".$link->getStartTime."\" startTimeType=\"unix\" endTime=\"".$link->getEndTime."\" endTimeType=\"unix\">\n";
	$localContent .= "	<ifevt:stateOper>".$link->getOperStatus."</ifevt:stateOper>\n";
	$localContent .= "	<ifevt:stateAdmin>".$link->getAdminStatus."</ifevt:stateAdmin>\n";
	$localContent .= "</ifevt:datum>\n";

	return $localContent;
}

sub writeoutLinkState($$$) {
	my ($self, $link, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status");

	return "" if (!defined $link);

	my $localContent = "";

	if (!defined $time or $time eq "") {
	$localContent .= "<ifevt:datum knowledge=\"".$link->getKnowledge."\" timeType=\"unix\" timeValue=\"".$link->getEndTime."\">\n";
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

#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
#use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	$self->SUPER::init;

	if (!defined $self->{CONF}->{"TOPO_DB_FILE"} or $self->{CONF}->{"TOPO_DB_FILE"} eq "") {
		$logger->error("No database specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPO_DB_TYPE"} or $self->{CONF}->{"TOPO_DB_TYPE"} eq "") {
		$logger->error("No database type specified");
		return -1;
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "SQL") {
		$self->{DATADB} = new perfSONAR_PS::DB::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"TOPO_DB_FILE"});
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	return 0;
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

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
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	delete $self->{RESPONSE};
	my $messageIdReturn = genuid();
	my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");

	$self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling topology request.");
		my $response = $self->parseRequest($messageIdReturn, $messageId, $messageType);
		if (!defined $response) {
			$logger->error("Unable to handle topology request");
			$self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.content", "Unable to handle topology request");
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
	my($self, $messageId, $messageIdRef, $type) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $localContent = "";
	foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = $m->findvalue("nmwg:eventType");

				if ($eventType eq "Path.Status") {
					$localContent = $self->topologyRequest($m, $d, $localContent, $messageId, $messageIdRef);
				} else {
					$logger->error("Unknown event type: " .  $eventType);
					return undef;
				}
			}
		}
	}

	return $localContent;
}


sub topologyRequest {
	my($self, $m, $d, $localContent, $messageId, $messageIdRef) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	$localContent .= "<nmwg:parameters id=\"storeId\"><nmwg:parameter name=\"DomainName\">";
	if (defined $self->{CONF}->{"domain"}) {
		$localContent .= $self->{CONF}->{"domain"};
	} else {
		$localContent .= "UNKNOWN";
	}
	$localContent .= "</nmwg:parameter></nmwg:parameters>";

	$localContent .= $m->toString();

	$localContent .= "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
	my $res = $self->dumpDatabase;
	if (defined $res) {
		$localContent .= $res;
	} else {
		$logger->error("Couldn't dump topology structure");
		return undef;
	}
	$localContent .= "  </nmwg:data>\n";

	open(OUTPUT, ">results");
	print OUTPUT $localContent;
	close(OUTPUT);

	return $localContent;
}

sub dumpDatabase {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	if (!defined $self->{DATADB}) {
		$logger->error("No database to dump");
		return undef;
	}

	my $res = $self->{DATADB}->openDB;
	if ($res == -1) {
		$logger->error("Couldn't open topology database");
		return undef;
	}

	if ($self->{CONF}->{"TOPO_DB_TYPE"} eq "SQL") {
		$res = $self->dumpSQLDatabase;
	} elsif ($self->{CONF}->{"TOPO_DB_TYPE"} eq "XMLDB") {
		$res = $self->dumpXMLDatabase;
	} else {
		$logger->error("Unknown topology database type: ".$self->{CONF}->{"TOPO_DB_TYPE"});
	}

	$self->{DATADB}->closeDB;

	return $res;
}

sub dumpSQLDatabase {
	my ($self, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");

	my $nodes = $self->{DATADB}->query("select id, name, country, city, institution, latitude, longitude from nodes");
	if ($nodes == -1) {
		$logger->error("Couldn't grab list of nodes");
		return undef;
	}

	$localContent = "";

	foreach $node_ref (@{ $nodes }) {
		my @node = @{ $node_ref };

		# dump the node information in XML format

		$localContent .= "<nmwgt:node id=\"".$node[0]."\">\n";
		$localContent .= "	<nmwgt:type>TopologyPoint</nmwgt:type>\n";
  		$localContent .= "	<nmwgt:name type=\"logical\">".$node[1]."</nmwgt:name>\n";
  		$localContent .= "	<nmwgt:country>".$node[2]."</nmwgt:country>\n";
  		$localContent .= "	<nmwgt:city>".$node[3]."</nmwgt:city>\n";
  		$localContent .= "	<nmwgt:institution>".$node[4]."</nmwgt:institution>\n";
  		$localContent .= "	<nmwgt:latitude>".$node[5]."</nmwgt:latitude>\n";
  		$localContent .= "	<nmwgt:longitude>".$node[6]."</nmwgt:longitude>\n";
		$localContent .= "</nmwgt:node>\n";
	}

	my $links = $self->{DATADB}->query("select id, name, globalName, type from links");
	if ($links == -1) {
		$logger->error("Couldn't grab list of links");
		return undef;
	}

	foreach $link_ref (@{ $links }) {
		my @link = @{ $link_ref };

		$link_node_query = "select node_id, role, link_index from link_nodes where link_id=\'".$link[0]."\'";
		if ($time ne "") {
			$link_node_query .= " and start_time <= $time and end_time >= $time";
		}

		my $nodes = $self->{DATADB}->query("select node_id, role, link_index from link_nodes where link_id=\'".$link[0]."\'");
		if ($nodes == -1) {
			$logger->error("Couldn't grab list of nodes associated with link ".$link[0]);
		}

		# dump the link information in XML format
		$localContent .= "<nmwgt:link id=\"".$link[0]."\">\n";
  		$localContent .= "	<nmwgt:name type=\"logical\">".$link[1]."</nmwgt:name>\n";
  		$localContent .= "	<nmwgt:globalName type=\"logical\">".$link[2]."</nmwgt:globalName>\n";
		$localContent .= "	<nmwgt:type>".$link[3]."</nmwgt:type>\n";

		foreach $node_ref (@{ $nodes }) {
			my @node = @{ $node_ref };
			$localContent .= "	<nmwgt:node nodeIdRef=\"".$node[0]."\">\n";
			$localContent .= "		<nmwgt:role>".$node[1]."</nmwgt:role>\n";
			$localContent .= "		<nmwgt:link_index>".$node[2]."</nmwgt:link_index>\n";
			$localContent .= "	</nmwgt:node>\n";
		}

		$localContent .= "</nmwgt:link>\n";
	}

	return $localContent;
}

sub dumpXMLDatabase {
	return undef;
}

1;


__END__
=head1 NAME

perfSONAR_PS::MA::Topology - A module that provides methods for the Topology MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::MA::Topology;

my %conf = ();
$conf{"METADATA_DB_TYPE"} = "xmldb";
$conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Topology/xmldb";
$conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
$conf{"PING"} = "/bin/ping";

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
		select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
	 );

my $ma = perfSONAR_PS::MA::Topology->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Topology->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

$ma->init;
while(1) {
	$ma->receive;
	$ma->respond;
}


=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
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

	$Id: Topology.pm 242 2007-06-19 21:22:24Z zurawski $

	=head1 AUTHOR

	Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

	=head1 COPYRIGHT AND LICENSE

	Copyright (C) 2007 by Internet2

	This library is free software; you can redistribute it and/or modify
	it under the same terms as Perl itself, either Perl version 5.8.8 or,
	at your option, any later version of Perl 5 you may have available.

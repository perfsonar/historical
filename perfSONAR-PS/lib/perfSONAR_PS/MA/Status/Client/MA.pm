package perfSONAR_PS::MA::Status::Client::MA;

use strict;
use perfSONAR_PS::MA::Status::Link;
use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use Data::Dumper;

sub new {
	my ($package, $uri_string) = @_;

	my %hash;

	if (defined $uri_string and $uri_string ne "") { 
		$hash{"URI_STRING"} = $uri_string;

	}

	$hash{"DATA_MA"} = "";

	bless \%hash => $package;
}

sub open($) {
	my ($self) = @_;

	return (0, "");
}

sub close($) {
	my ($self) = @_;

	return 0;
}

sub setURIString($$) {
	my ($self, $uri_string) = @_;

	$self->{URI_STRING} = $uri_string;
}

sub dbIsOpen($) {
	return 1;
}

sub getDBIString($$) {
	my ($self) = @_;

	return $self->{URI_STRING};
}

sub buildGetAllRequest() {
	my $request = "";

	$request .= "<nmwg:message type=\"SetupDataRequest\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$request .= "<nmwg:metadata id=\"meta0\">\n";
	$request .= "  <nmwg:eventType>Database.Dump</nmwg:eventType>\n";
	$request .= "</nmwg:metadata>\n";
	$request .= "<nmwg:data id=\"data0\" metadataIdRef=\"meta0\" />\n";
	$request .= "</nmwg:message>\n";

	my @metadata_ids = ( 'meta0' );

	return ($request, \@metadata_ids);
}

sub buildLinkRequest($$$) {
	my ($links, $type, $time) = @_;
	my $request = "";

	if ($type ne "Link.History" and $type ne "Link.Status") {
		my $msg = "Request type must be either Link.History or Link.Recent";
		return (-1, $msg);
	}

	$request .= "<nmwg:message type=\"SetupDataRequest\"\n";
	$request .= "  xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
	$request .= "  xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/base/3.0/\">\n";

	my @metadata_ids = ();
	my $i = 0;

	foreach my $link_id (@{ $links }) {
		$request .= "<nmwg:metadata id=\"meta$i\">\n";
		$request .= "  <nmwg:eventType>$type</nmwg:eventType>\n";
		$request .= "  <nmwg:subject id=\"sub$i\">\n";
		$request .= "    <nmtopo:link id=\"$link_id\" />\n";
		$request .= "  </nmwg:subject>\n";
		$request .= "  <nmwg:parameters>\n";
		$request .= "    <nmwg:parameter name=\"time\">$time</nmwg:parameter>\n" if defined $time;
		$request .= "  </nmwg:parameters>\n";
		$request .= "</nmwg:metadata>\n";
		$request .= "<nmwg:data id=\"data$i\" metadataIdRef=\"meta$i\" />\n";

		push @metadata_ids, "meta$i";

		$i++;
	}

	$request .= "</nmwg:message>\n";

	return ($request, \@metadata_ids);
}

sub buildUpdateRequest($$$$$$) {
	my ($link_id, $time, $knowledge_level, $oper_value, $admin_value, $do_update) = @_;
	my $request = "";

	$request .= "<nmwg:message type=\"MeasurementArchiveStoreRequest\"\n";
	$request .= "        xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
	$request .= "        xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/base/3.0/\"\n";
	$request .= "        xmlns:ifevt=\"http://ggf.org/ns/nmwg/event/status/base/2.0/\">\n";
	$request .= "<nmwg:metadata id=\"meta0\">\n";
	$request .= "  <nmwg:subject id=\"sub0\">\n";
	$request .= "    <nmtopo:link id=\"$link_id\" />\n";
	$request .= "  </nmwg:subject>\n";
	$request .= "  <nmwg:parameters>\n";
	$request .= "    <nmwg:parameter name=\"knowledge\">$knowledge_level</nmwg:parameter>\n";
	$request .= "  </nmwg:parameters>\n";
	$request .= "</nmwg:metadata>\n";
	$request .= "<nmwg:data id=\"data0\" metadataIdRef=\"meta0\">\n";
	$request .= "<ifevt:datum timeType=\"unix\" timeValue=\"$time\">\n";
	$request .= "  <ifevt:stateAdmin>$admin_value</ifevt:stateAdmin>\n";
	$request .= "  <ifevt:stateOper>$oper_value</ifevt:stateOper>\n";
	$request .= "</ifevt:datum>\n";
	$request .= "</nmwg:data>\n";
	$request .= "</nmwg:message>\n";

	my @metadata_ids = ( 'meta0' );

	return ($request, \@metadata_ids);
}

sub getStatusArchive($$$) {
	my ($self, $meta_ids, $request) = @_;
	my ($status, $res);

	my ($host, $port, $endpoint) = &perfSONAR_PS::Transport::splitURI( $self->{URI_STRING} );
	if (!defined $host && !defined $port && !defined $endpoint) {
		my $msg = "Specified argument is not a URI";
		return (-1, $msg);
	}

	($status, $res) = consultArchive($host, $port, $endpoint, $request);
	if ($status != 0) {
		my $msg = "Error consulting archive: $res";
		return (-1, $msg);
	}

	my $stat_msg = $res;

	my %links = ();

	my %metas = ();

	foreach my $meta (@{ $meta_ids }) {
		$metas{$meta} = "";
	}

	foreach my $data ($stat_msg->getElementsByLocalName("data")) {
		foreach my $metadata ($stat_msg->getElementsByLocalName("metadata")) {
			my $mdidref = $metadata->getAttribute("metadataIdRef");
			my $mdid = $metadata->getAttribute("id");

			next if (!defined $mdidref or !defined $metas{$mdidref}) and (!defined $mdid or !defined $metas{$mdid});

			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
				my $link_id = $metadata->findvalue('./nmwg:subject/nmtopo:link/@id');
				if (!defined $link_id or $link_id eq "") {
					my $msg = "Response does not contain a link id";
					return (-1, $msg);
				}

				($status, $res) = parseResponse($link_id, $data, \%links);
				if ($status != 0) {
					my $msg = "Error parsing archive response: $res";
					return (-1, $msg);
				}
			}
		}
	}

	return (0, \%links);
}

sub parseResponse($$$) {
	my ($link_id, $data, $links) = @_;

	foreach my $link ($data->getElementsByLocalName("datum")) {
		my $time = $link->getAttribute("timeValue");
		my $time_type = $link->getAttribute("timeType");
		my $start_time = $link->getAttribute("startTime");
		my $start_time_type = $link->getAttribute("startTimeType");
		my $end_time = $link->getAttribute("endTime");
		my $end_time_type = $link->getAttribute("endTimeType");
		my $knowledge = $link->getAttribute("knowledge");
		my $operStatus = $link->findvalue("./ifevt:stateOper");
		my $adminStatus = $link->findvalue("./ifevt:stateAdmin");

		if (!defined $knowledge or !defined $operStatus or !defined $adminStatus or $adminStatus eq "" or $operStatus eq "" or $knowledge eq "") {
			my $msg = "Response from server contains incomplete link status: ".$link->toString;
			return (-1, $msg);
		}

		if ((!defined $time or !defined $time_type) and (!defined $start_time or !defined $start_time_type or !defined $end_time or !defined $end_time_type)) {
			my $msg = "Response from server contains incomplete link status: ".$link->toString;
			return (-1, $msg);
		}

		if (defined $time_type and $time_type ne "unix") {
			my $msg = "Response from server contains invalid time type \"".$time_type."\": ".$link->toString;
			return (-1, $msg);
		}

		if (defined $start_time_type and $start_time_type ne "unix") {
			my $msg = "Response from server contains invalid time type \"".$start_time_type."\": ".$link->toString;
			return (-1, $msg);
		}

		if (defined $end_time_type and $end_time_type ne "unix") {
			my $msg = "Response from server contains invalid time type \"".$end_time_type."\": ".$link->toString;
			return (-1, $msg);
		}

		my $new_link;

		if (!defined $start_time) {
		$new_link = new perfSONAR_PS::MA::Status::Link($link_id, $knowledge, $time, $time, $operStatus, $adminStatus);
		} else {
		$new_link = new perfSONAR_PS::MA::Status::Link($link_id, $knowledge, $start_time, $end_time, $operStatus, $adminStatus);
		}

		if (!defined $links->{$link_id}) {
			$links->{$link_id} = ();
		}

		push @{ $links->{$link_id} }, $new_link;
	}

	return (0, "");
}

sub getAll($) {
	my ($self) = @_;

	my ($request, $metas) = buildGetAllRequest;

	my ($status, $res) = $self->getStatusArchive($metas, $request);

	return ($status, $res);
}

sub getLinkHistory($$$) {
	my ($self, $link_ids) = @_;

	my ($request, $metas) = buildLinkRequest($link_ids, "Link.History", "");

	my ($status, $res) = $self->getStatusArchive($metas, $request);

	return ($status, $res);
}

sub getLinkStatus($$$) {
	my ($self, $link_ids, $time) = @_;

	my ($request, $metas) = buildLinkRequest($link_ids, "Link.Status", $time);

	my ($status, $res) = $self->getStatusArchive($metas, $request);

	return ($status, $res);
}


sub updateLinkStatus($$$$$$$) {
	my($self, $time, $link_id, $knowledge_level, $oper_value, $admin_value, $do_update) = @_;
	my $prev_end_time;

	my $request = buildUpdateRequest($link_id, $time, $knowledge_level, $oper_value, $admin_value, $do_update);

	my ($host, $port, $endpoint) = &perfSONAR_PS::Transport::splitURI( $self->{URI_STRING} );
	if (!defined $host && !defined $port && !defined $endpoint) {
		my $msg = "Specified argument is not a URI";
		return (-1, $msg);
	}

	my ($status, $res) = consultArchive($host, $port, $endpoint, $request);
	if ($status != 0) {
		my $msg = "Error consulting archive: $res";
		return (-1, $msg);
	}

# XXX this should make sure we didn't get back an error message

	return 0;

#	foreach my $data ($nmwg_msg->getElementsByLocalName("data")) {
#		foreach my $metadata ($nmwg_msg->getElementsByLocalName("metadata")) {
#			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
#				my $eventType = $metadata->findvalue("nmwg:eventType");
#				if ($eventType ne $type) {
#					my $msg = "Invalid response eventType received: $eventType";
#					$logger->error($msg);
#					return (-1, $msg);
#				}
#
#				($status, $res) = parseResponse($data, \%links);
#				if ($status != 0) {
#					my $msg = "Error parsing archive response: $res";
#					$logger->error($msg);
#					return (-1, $msg);
#				}
#			}
#		}
#	}


}

1;

__END__

=head1 NAME

perfSONAR_PS::MA::Status::Client::MA - A module that provides methods for
dealing interacting with Status MA servers.

=head1 DESCRIPTION

This modules allows one to interact with the Status MA via its Web Services
interface. The API provided is identical to the API for interacting with the
MA database directly. Thus, a client written to read from or update a Status MA
can be easily modified to interact directly with its underlying database
allowing more efficient interactions if required.

The module is to be treated as an object, where each instance of the object
represents a connection to a single database. Each method may then be invoked
on the object for the specific database.  

=head1 SYNOPSIS

	use perfSONAR_PS::MA::Status::Client::MA;

	my $status_client = new perfSONAR_PS::MA::Status::Client::MA("http://localhost:4801/axis/services/status");
	if (!defined $status_client) {
		print "Problem creating client for status MA\n";
		exit(-1);
	}

	my ($status, $res) = $status_client->open;
	if ($status != 0) {
		print "Problem opening status MA: $res\n";
		exit(-1);
	}

	($status, $res) = $status_client->getAll();
	if ($status != 0) {
		print "Problem getting complete database: $res\n";
		exit(-1);
	}

	my @links = (); 
	
	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";

		foreach my $link ( @{ $res->{$id} }) {
			print "\t" . $link->getStartTime . " - " . $link->getEndTime . "\n";
			print "\t-Knowledge Level: " . $link->getKnowledge . "\n";
			print "\t-operStatus: " . $link->getOperStatus . "\n";
			print "\t-adminStatus: " . $link->getAdminStatus . "\n";
		}
	
		push @links, $id;
	}
	
	($status, $res) = $status_client->getLinkStatus(\@links, "");
	if ($status != 0) {
		print "Problem obtaining most recent link status: $res\n";
		exit(-1);
	}

	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";
	
		foreach my $link ( @{ $res->{$id} }) {
			print "-operStatus: " . $link->getOperStatus . "\n";
			print "-adminStatus: " . $link->getAdminStatus . "\n";
		}
	}
	
	($status, $res) = $status_client->getLinkHistory(\@links);
	if ($status != 0) {
		print "Problem obtaining link history: $res\n";
		exit(-1);
	}

	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";
	
		foreach my $link ( @{ $res->{$id} }) {
			print "-operStatus: " . $link->getOperStatus . "\n";
			print "-adminStatus: " . $link->getAdminStatus . "\n";
		}
	}

=head1 DETAILS

=head1 API

The API os perfSONAR_PS::MA::Status::Client::MA is rather simple and greatly
resembles the messages types received by the server. It is also identical to
the perfSONAR_PS::MA::Status::Client::SQL API allowing easy construction of
programs that can interface via the MA server or directly with the database.

=head2 new($package, $uri_string)

The new function takes a URI connection string as its first argument. This
specifies which MA to interact with.

=head2 open($self)

The open function could be used to open a persistent connection to the MA.
However, currently, it is simply a stub function.

=head2 close($self)

The close function could close a persistent connection to the MA. However,
currently, it is simply a stub function.

=head2 setURIString($self, $uri_string)

The setURIString function changes the MA that the instance uses.

=head2 dbIsOpen($self)

This function is a stub function that always returns 1.

=head2 getURIString($)

The getURIString function returns the current URI string

=head2 getAll($self)

The getAll function gets the full contents of the MA. It returns the results as
a hash with the key being the link id. Each element of the hash is an array of
perfSONAR_PS::MA::Status::Link structures containing a the status of the
specified link at a certain point in time.

=head2 getLinkHistory($self, $link_ids)

The getLinkHistory function returns the complete history of a set of links. The
$link_ids parameter is a reference to an array of link ids. It returns the
results as a hash with the key being the link id. Each element of the hash is
an array of perfSONAR_PS::MA::Status::Link structures containing a the status
of the specified link at a certain point in time.

=head2 getLinkStatus($self, $link_ids, $time)

The getLinkStatus function returns the link status at the specified time. The
$link_ids parameter is a reference to an array of link ids. $time is the time
at which you'd like to know each link's status. If $time is an empty string, it
returns the most recent information it has about each link. It returns the
results as a hash with the key being the link id. Each element of the hash is
an array of perfSONAR_PS::MA::Status::Link structures containing a the status
of the specified link at a certain point in time.

=head2 updateLinkStatus($self, $time, $link_id, $knowledge_level, $oper_value, $admin_value, $do_update) 

The updateLinkStatus function adds a new data point for the specified link.
$time is the time at which the measurement occured. $link_id is the link to
update. $knowledge_level says whether or not this measurement can tell us
everything about a given link ("full") or whether the information only
corresponds to one side of the link("partial"). $oper_value is the current
operational status and $admin_value is the current administrative status.
$do_update is currently unused in this context, meaning that all intervals
added have cover the second that the measurement occurred.

=head1 SEE ALSO

L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::MA::Status::Link>, L<perfSONAR_PS::MA::Status::Client::SQL>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=


package perfSONAR_PS::MA::Status::Client::MA;

use strict;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::MA::Status::Link;
use perfSONAR_PS::Common;

sub new {
	my ($package, $uri_string) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");

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

	return ("", $request);
}

sub buildLinkRequest($$$) {
	my ($links, $type, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");
	my $request = "";

	if ($type ne "Link.History" and $type ne "Link.Recent") {
		my $msg = "Request type must be either Link.History or Link.Recent";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (defined $time and $time ne "" and $type eq "Link.Recent") {
		my $msg = "Time parameter is incompatible with Link.Recent type";
		$logger->error($msg);
		return (-1, $msg);
	}

	$request .= "<nmwg:message type=\"SetupDataRequest\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";

	my $i = 0;

	foreach my $link_id (@{ $links }) {
		$request .= "<nmwg:metadata id=\"meta$i\">\n";
		$request .= "  <nmwg:eventType>$type</nmwg:eventType>\n";
		$request .= "  <nmwg:parameters>\n";
		$request .= "    <nmwg:parameter name=\"linkId\">".$link_id."</nmwg:parameter>\n";
		$request .= "    <nmwg:parameter name=\"time\">$time</nmwg:parameter>\n" if defined $time;
		$request .= "  </nmwg:parameters>\n";
		$request .= "</nmwg:metadata>\n";
		$request .= "<nmwg:data id=\"data$i\" metadataIdRef=\"meta$i\" />\n";
		$i++;
	}

	$request .= "</nmwg:message>\n";

	return ("", $request);
}

sub getStatusArchive($$$) {
	my ($self, $type, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");
	my ($status, $res);

	my ($host, $port, $endpoint) = &perfSONAR_PS::Transport::splitURI( $self->{URI_STRING} );
	if (!defined $host && !defined $port && !defined $endpoint) {
		my $msg = "Specified argument is not a URI";
		my $logger->error($msg);
		return (-1, $msg);
	}

	($status, $res) = consultArchive($host, $port, $endpoint, $request);
	if ($status != 0) {
		my $msg = "Error consulting archive: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $stat_msg = $res;

	my @links = ();

	foreach my $data ($stat_msg->getElementsByLocalName("data")) {
		foreach my $metadata ($stat_msg->getElementsByLocalName("metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
				my $eventType = $metadata->findvalue("nmwg:eventType");
				if ($eventType ne $type) {
					my $msg = "Invalid response eventType received: $eventType";
					$logger->error($msg);
					return (-1, $msg);
				}

				($status, $res) = dataToLinkStatus($data);
				if ($status != 0) {
					my $msg = "Error parsing archive response: $res";
					$logger->error($msg);
					return (-1, $msg);
				}

				push @links, @{ $res };
			}
		}
	}

	return (0, \@links);

}

sub getAll($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");

	my $request = buildGetAllRequest;

	my ($status, $res) = $self->getStatusArchive("Database.Dump", $request);

	return ($status, $res);
}

sub getLinkHistory($$$) {
	my ($self, $link_ids, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");

	my $request = buildLinkRequest($link_ids, "Link.History", $time);

	my ($status, $res) = $self->getStatusArchive("Link.History", $request);

	return ($status, $res);
}

sub getLastLinkStatus($$) {
	my ($self, $link_ids) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");

	my $request = buildLinkRequest($link_ids, "Link.Recent", "");

	my ($status, $res) = $self->getStatusArchive("Link.Recent", $request);

	return ($status, $res);
}

sub dataToLinkStatus($) {
	my ($data) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::MA");

	my @links = ();

	foreach my $link ($data->getElementsByLocalName("linkStatus")) {
		my $id = $link->getAttribute("linkID");
		my $start_time = $link->getAttribute("startTime");
		my $end_time = $link->getAttribute("endTime");
		my $knowledge = $link->getAttribute("knowledge");
		my $operStatus = $link->findvalue("./nmtopo:operStatus");
		my $adminStatus = $link->findvalue("./nmtopo:adminStatus");

		if (!defined $id or !defined $start_time or !defined $end_time or !defined $knowledge or !defined $operStatus or !defined $adminStatus) {
			my $msg = "Response from server contains incomplete link status: $id $start_time $end_time $knowledge $operStatus $adminStatus: ".$link->toString;
			$logger->error($msg);
			return (-1, $msg);
		}

		my $new_link = new perfSONAR_PS::MA::Status::Link($id, $knowledge, $start_time, $end_time, $operStatus, $adminStatus);
		push @links, $new_link;
	}

	return (0, \@links);
}

1;

#!/usr/bin/perl -w

package perfSONAR_PS::MA::Topology::Client::MA;

use strict;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::Common;
use Data::Dumper;

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

sub getURIString($$) {
	my ($self) = @_;

	return $self->{URI_STRING};
}

sub buildGetAllRequest() {
	my $request = "";

	$request .= "<nmwg:message type=\"SetupDataRequest\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$request .= "<nmwg:metadata id=\"meta0\">\n";
	$request .= "  <nmwg:eventType>topology.lookup.all</nmwg:eventType>\n";
	$request .= "</nmwg:metadata>\n";
	$request .= "<nmwg:data id=\"data0\" metadataIdRef=\"meta0\" />\n";
	$request .= "</nmwg:message>\n";

	return ("", $request);
}

sub buildXqueryRequest($) {
	my ($xquery);
	my $request = "";

	$request .= "<nmwg:message type=\"SetupDataRequest\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$request .= "<nmwg:metadata id=\"meta0\">\n";
	$request .= "  <nmwg:eventType>topology.lookup.xquery</nmwg:eventType>\n";
	$request .= "  <xquery:subject id=\"sub1\" xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
	$request .= $xquery;
	$request .= "  </xquery:subject>\n";
	$request .= "</nmwg:metadata>\n";
	$request .= "<nmwg:data id=\"data0\" metadataIdRef=\"meta0\" />\n";
	$request .= "</nmwg:message>\n";

	return ("", $request);

}

sub xQuery($$) {
	my ($self, $xquery) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my $localContent = "";
	my $error;
	my ($status, $res);

	my $request = buildXqueryRequest($xquery);

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

	my $topo_msg = $res;

	foreach my $data ($topo_msg->getElementsByLocalName("data")) {
		foreach my $metadata ($topo_msg->getElementsByLocalName("metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
				my $topology = $data->find('./nmtopo:topology')->get_node(1);
				if (defined $topology) {
					return (0, $topology->toString);
				} 
			}
		}
	}

	my $msg = "Response does not contain a topology";
	$logger->error($msg);
	return (-1, $msg);
}

sub getAll {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Topology");
	my @results;
	my $error;
	my ($status, $res);

	my $request = buildGetAllRequest();

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

	my $topo_msg = $res;

	foreach my $data ($topo_msg->getElementsByLocalName("data")) {
		foreach my $metadata ($topo_msg->getElementsByLocalName("metadata")) {
			if ($data->getAttribute("metadataIdRef") eq $metadata->getAttribute("id")) {
				my $topology = $data->find('./nmtopo:topology')->get_node(1);
				if (defined $topology) {
					return (0, $topology);
				} 
			}
		}
	}

	my $msg = "Response does not contain a topology";
	$logger->error($msg);
	return (-1, $msg);
}

1;

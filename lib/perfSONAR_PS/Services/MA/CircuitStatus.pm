#!/usr/bin/perl -w

package perfSONAR_PS::Services::MA::CircuitStatus;

use base 'perfSONAR_PS::Services::Base';

use fields
    'LOCAL_MA_CLIENT',
    'TOPOLOGY_CLIENT',
    'STORE',
    'LS_HOST',
    'LS_PORT',
    'LS_ENDPOINT',
    'DOMAIN',
    'CIRCUITS',
    'INCOMPLETE_NODES',
    'TOPOLOGY_LINKS',
    'NODES';

use version; our $VERSION = qv("0.01");

use warnings;
use strict;
use Exporter;
use Log::Log4perl qw(get_logger);
use Module::Load;
use Fcntl qw (:flock);
use Fcntl;
use Data::Dumper;

use perfSONAR_PS::Services::Base;
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Time;

use perfSONAR_PS::Client::Status::MA;
use perfSONAR_PS::Client::Topology::MA;

sub init($$) {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	if (!defined $self->{CONF}->{"circuitstatus"}->{"status_ma_type"} or $self->{CONF}->{"circuitstatus"}->{"status_ma_type"} eq "") {
		if (!defined $self->{CONF}->{"circuitstatus"}->{"ls_instance"} or $self->{CONF}->{"circuitstatus"}->{"ls_instance"} eq "") {
			$logger->error("No LS nor Status MA specified");
			return -1;
		} else {
			$self->{CONF}->{"circuitstatus"}->{"status_ma_type"} = "ls";
		}
	}

	if (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "ls") {
		($self->{LS_HOST}, $self->{LS_PORT}, $self->{LS_ENDPOINT}) = &perfSONAR_PS::Transport::splitURI($self->{CONF}->{"circuitstatus"}->{"ls_instance"});
		if (!defined $self->{LS_HOST} or !defined $self->{LS_PORT} or !defined $self->{LS_ENDPOINT}) {
			$logger->error("Specified LS is not a URI: ".$self->{CONF}->{"circuitstatus"}->{"ls_instance"});
			return -1;
		}
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "ma") {
		if (!defined $self->{CONF}->{"circuitstatus"}->{"status_ma_uri"} or $self->{CONF}->{"circuitstatus"}->{"status_ma_uri"} eq "") {
			$logger->error("You specified an MA for the status, but did not specify the URI(status_ma_uri)");
			return -1;
		}
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "sqlite") {
		load perfSONAR_PS::Client::Status::SQL;

		if (!defined $self->{CONF}->{"circuitstatus"}->{"status_ma_file"} or $self->{CONF}->{"circuitstatus"}->{"status_ma_file"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(status_ma_file)");
			return -1;
		}

		my $file = $self->{CONF}->{"circuitstatus"}->{"status_ma_file"};
		if (defined $self->{DIRECTORY}) {
			if (!($file =~ "^/")) {
				$file = $self->{DIRECTORY}."/".$file;
			}
		}

		$self->{LOCAL_MA_CLIENT} = perfSONAR_PS::Client::Status::SQL->new("DBI:SQLite:dbname=".$file, $self->{CONF}->{"circuitstatus"}->{"status_ma_table"});
		if (!defined $self->{LOCAL_MA_CLIENT}) {
			my $msg = "No database to dump";
			$logger->error($msg);
			return (-1, $msg);
		}
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "mysql") {
		load perfSONAR_PS::Client::Status::SQL;

		my $dbi_string = "dbi:mysql";

		if (!defined $self->{CONF}->{"circuitstatus"}->{"status_ma_name"} or $self->{CONF}->{"circuitstatus"}->{"status_ma_name"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database (status_ma_name)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"circuitstatus"}->{"status_ma_name"};

		if (!defined $self->{CONF}->{"circuitstatus"}->{"status_ma_host"} or $self->{CONF}->{"circuitstatus"}->{"status_ma_host"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database host (status_ma_host)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"circuitstatus"}->{"status_ma_host"};

		if (defined $self->{CONF}->{"circuitstatus"}->{"status_ma_port"} and $self->{CONF}->{"circuitstatus"}->{"status_ma_port"} ne "") {
			$dbi_string .= ":".$self->{CONF}->{"circuitstatus"}->{"status_ma_port"};
		}

		$self->{LOCAL_MA_CLIENT} = perfSONAR_PS::Client::Status::SQL->new($dbi_string, $self->{CONF}->{"circuitstatus"}->{"status_ma_username"}, $self->{CONF}->{"circuitstatus"}->{"status_ma_password"});
		if (!defined $self->{LOCAL_MA_CLIENT}) {
			my $msg = "Couldn't create SQL client";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid MA type specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"circuitstatus"}->{"circuits_file_type"} or $self->{CONF}->{"circuitstatus"}->{"circuits_file_type"} eq "") {
		$logger->error("No circuits file type specified");
		return -1;
	}

	if($self->{CONF}->{"circuitstatus"}->{"circuits_file_type"} eq "file") {
		if (!defined $self->{CONF}->{"circuitstatus"}->{"circuits_file"} or $self->{CONF}->{"circuitstatus"}->{"circuits_file"} eq "") {
			$logger->error("No circuits file specified");
			return -1;
		}

		my ($status, $res1, $res2, $res3, $res4, $res5) = parseCircuitsFile($self->{CONF}->{"circuitstatus"}->{"circuits_file"});
		if ($status ne "") {
			my $msg = "Error parsing circuits file: $res1";
			$logger->error($msg);
			return -1;
		}

		$self->{DOMAIN} = $res1;
		$self->{CIRCUITS} = $res2;
		$self->{INCOMPLETE_NODES} = $res3;
		$self->{TOPOLOGY_LINKS} = $res4;
		$self->{NODES} = $res5;

		my $have_keys = 0;
		foreach my $key (keys %{ $res3 }) {
			$logger->debug("Key: $key");
			$have_keys++;
		}

		if ($self->{"CONF"}->{"circuitstatus"}->{"topology_ma_type"} eq "none" and scalar keys %{ $res3 } > 0) {
			my $msg = "You specified no topology MA, but there are incomplete nodes";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid circuits file type specified: ".$self->{CONF}->{"circuitstatus"}->{"link_file_type"});
		return -1;
	}

	if (!defined $self->{CONF}->{"circuitstatus"}->{"topology_ma_type"} or $self->{CONF}->{"circuitstatus"}->{"topology_ma_type"} eq "") {
		$logger->error("No topology MA type specified");
		return -1;
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"topology_ma_type"}) eq "xml") {
		load perfSONAR_PS::Client::Topology::XMLDB;

		if (!defined $self->{CONF}->{"circuitstatus"}->{"topology_ma_file"} or $self->{CONF}->{"circuitstatus"}->{"topology_ma_file"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file(topology_ma_file)");
			return -1;
		}

		if (!defined $self->{CONF}->{"circuitstatus"}->{"topology_ma_environment"} or $self->{CONF}->{"circuitstatus"}->{"topology_ma_environment"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name(topology_ma_environment)");
			return -1;
		}

		my $environment = $self->{CONF}->{"circuitstatus"}->{"topology_ma_environment"};
		if (defined $self->{DIRECTORY}) {
			if (!($environment =~ "^/")) {
				$environment = $self->{DIRECTORY}."/".$environment;
			}
		}

		my $file = $self->{CONF}->{"circuitstatus"}->{"topology_ma_file"};
		my %ns = &perfSONAR_PS::Topology::Common::getTopologyNamespaces();

		$self->{TOPOLOGY_CLIENT} = perfSONAR_PS::Client::Topology::XMLDB->new($environment, $file, \%ns, 1);
		if (!defined $self->{TOPOLOGY_CLIENT}) {
			$logger->error("Couldn't initialize topology client");
			return -1;
		}
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"topology_ma_type"}) eq "none") {
		$logger->warn("Ignoring the topology MA. Everything must be specified explicitly in the circuits.conf file");
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"topology_ma_type"}) eq "ma") {
		if (!defined $self->{CONF}->{"circuitstatus"}->{"topology_ma_uri"} or $self->{CONF}->{"circuitstatus"}->{"topology_ma_uri"} eq "") {
			$logger->error("You specified that you want a Topology MA, but did not specify the URI (topology_ma_uri)");
			return -1;
		}

		$self->{TOPOLOGY_CLIENT} = perfSONAR_PS::Client::Topology::MA->new($self->{CONF}->{"circuitstatus"}->{"topology_ma_uri"});
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	if (lc($self->{CONF}->{"circuitstatus"}->{"topology_ma_type"}) ne "none" and 
		defined $self->{INCOMPLETE_NODES} and keys %{ $self->{INCOMPLETE_NODES} } != 0) {
		my ($status, $res);

		($status, $res) = $self->{TOPOLOGY_CLIENT}->open;
		if ($status != 0) {
			my $msg = "Problem opening topology MA: $res";
			$logger->error($msg);
			return -1;
		}

		($status, $res) = $self->{TOPOLOGY_CLIENT}->getAll;
		if ($status != 0) {
			my $msg = "Error getting topology information: $res";
			$logger->error($msg);
			return -1;
		}

		my $topology = $res;

		($status, $res) = parseTopology($topology, $self->{INCOMPLETE_NODES}, $self->{DOMAIN});
		if ($status ne "") {
			my $msg = "Error parsing topology: $res";
			$logger->error($msg);
			return -1;
		}
	}

	$self->{STORE} = $self->createMetadataStore($self->{NODES}, $self->{CIRCUITS});

	$logger->debug("Store: ".$self->{STORE}->toString);

	if (defined $self->{CONF}->{"circuitstatus"}->{"cache_length"} and $self->{CONF}->{"circuitstatus"}->{"cache_length"} > 0) {
		if (!defined $self->{CONF}->{"circuitstatus"}->{"cache_file"} or $self->{CONF}->{"circuitstatus"}->{"cache_file"} eq "") {
			my $msg = "If you specify a cache time period, you need to specify a file to cache to \"cache_file\"";
			$logger->error($msg);
			return -1;
		}

		my $file = $self->{CONF}->{"circuitstatus"}->{"cache_file"};
		if (defined $self->{DIRECTORY}) {
			if (!($file =~ "^/")) {
				$file = $self->{DIRECTORY}."/".$file;
			}
		}

		$self->{CONF}->{"circuitstatus"}->{"cache_file"} = $file;

		$logger->debug("Using \"$file\" to cache current results");
	}

	$handler->addEventHandler("SetupDataRequest", "Path.Status", $self);
	$handler->addEventHandler_Regex("SetupDataRequest", ".*select.*", $self);
	$handler->addEventHandler("MetadataKeyRequest", "Path.Status", $self);

	return 0;
}

sub needLS() {
	return 0;
}

sub handleEvent($$$$$$$$$) {
	my ($self, $output, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");
	my ($status, $res1, $res2);

	($status, $res1, $res2) = $self->resolveSelectChain($md, $request);
	if ($status ne "") {
		return ($status, $res1);
	}

	my $selectTime = $res1;
	my $subject_md = $res2;

	$eventType = undef;
	my $eventTypes = find($subject_md, "./nmwg:eventType", 0);
	foreach my $e ($eventTypes->get_nodelist) {
		my $value = extract($e, 1);
		$logger->debug("Found: \"$value\"");
		if ($value eq "Path.Status") {
			$eventType = $value;
			last;
		}
	}

	if (!defined $eventType) {
		return ("error.ma.event_type", "No supported event types for message of type \"$messageType\"");
	}

	if (defined $selectTime and $selectTime->getType("point") and $selectTime->getTime() eq "now") {
		$selectTime = undef;
	}

	my @circuits;
	if (find($subject_md, "./nmwg:key", 1)) {
		my $circuit_name = findvalue(find($subject_md, "./nmwg:key", 1), "./nmwg:parameters/nmwg:parameter[\@name=\"linkId\"]");

		if (!defined $circuit_name or !defined $self->{CIRCUITS}->{$circuit_name}) {
			my $msg = "The specified key is invalid";
			$logger->error($msg);
			return ("error.ma.invalid_key", "The specified key is invalid");
		}

		push @circuits, $circuit_name;
	} elsif (find($subject_md, "./nmwg:subject", 1)) {
		my ($status, $res) = $self->compatParseSubject(find($subject_md, "./nmwg:subject", 1));
		if ($status ne "") {
			return ($status, $res);
		}

		push @circuits, $res;
	} else {
		@circuits = keys %{ $self->{CIRCUITS} };
	}

	$self->handlePathStatus($output, \@circuits, $selectTime);

	return ("", "");
}

sub compatParseSubject($$) {
	my ($self, $subject) = @_;
	my $circuit_name;

	if (!find($subject, "./nmtl2:link", 1)) {
		return ("error.ma.invalid_subject", "The specified subject does not contain a link element");
	}

	my $circuit_name = findvalue($subject, "./nmtl2:link/nmtl2:name");
	if (defined $circuit_name and defined $self->{CIRCUITS}->{$circuit_name}) {
		return ("", $circuit_name);
	}

	my $nodes = find($subject, "./nmtl2:link/nmwgtopo3:node", 0);
	my $count = 0;
	my ($node1, $node2);
	foreach my $node ($nodes->get_nodelist) {
		my $node_name = findvalue($node, "./nmwgtopo3:name");
		if (!defined $node_name) {
			return ("error.ma.invalid_subject", "The specified subject contains an unfinished node");
		}
	}

	return ("", $circuit_name);
}

sub generateMDXpath($) {
	my ($subject) = @_;

	return "";
}

sub createMetadataStore($$$) {
	my ($self, $nodes, $circuits) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	my $doc = perfSONAR_PS::XML::Document_string->new();

	$doc->startElement(prefix => "nmwg", tag => "store", namespace => "http://ggf.org/ns/nmwg/base/2.0/");
	foreach my $node_id (keys %{ $nodes }) {
		my $node = $nodes->{$node_id};

		outputNodeElement($doc, $node);
	}

	foreach my $circuit_id (keys %{ $circuits }) {
		my $circuit = $circuits->{$circuit_id};

		outputCircuitElement($doc, $circuit);
	}
	$doc->endElement("store");

	my $parser = XML::LibXML->new();
	my $xmlDoc;
	eval {
		$xmlDoc = $parser->parse_string($doc->getValue);
	};
	if ($@ or !defined $xmlDoc) {
		my $msg = "Couldn't parse metadata store: $@";
		$logger->error($msg);
		return ("error.configuration", $msg);
	}

	return $xmlDoc->documentElement;
}

sub resolveSelectChain($$$) {
	my ($self, $md, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	if (!$request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
		$logger->debug("No select namespace means there is no select chain");
	}

	if (!find($md, "./select:subject", 1)) {
		$logger->debug("No select subject means there is no select chain");
	}

	if ($request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and find($md, "./select:subject", 1)) {
		my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".find($md, "./select:subject", 1)->getAttribute("metadataIdRef")."\"]", 1);
		if(!$other_md) {
			return ("error.ma.chaining", "Cannot resolve supposed subject chain in metadata.");
		}

		if (!find($md, "./select:subject/select:parameters", 1)) {
			return ("error.ma.select", "No select parameters specified in given chain.");
		}

		my $time = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"time\"]");
		my $startTime = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"startTime\"]");
		my $endTime = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"endTime\"]");
		my $duration = findvalue($md, "./select:subject/select:parameters/select:parameter[\@name=\"duration\"]");

		if (defined $time and (defined $startTime or defined $endTime or defined $duration)) {
			return ("error.ma.select", "Ambiguous select parameters");
		}

		if (defined $time) {
			return ("", perfSONAR_PS::Time->new("point", $time), $other_md);
		}

		if (!defined $startTime) {
			return ("error.ma.select", "No start time specified");
		} elsif (!defined $endTime and !defined $duration) {
			return ("error.ma.select", "No end time specified");
		} elsif (defined $endTime) {
			return ("", perfSONAR_PS::Time->new("range", $startTime, $endTime), $other_md);
		} else {
			return ("", perfSONAR_PS::Time->new("duration", $startTime, $duration), $other_md);
		}
	} else {
		# No select subject means they didn't specify one which results in "now"
		$logger->debug("No select chain");

		my $ret_time;
		my $time = findvalue($md, "./nmwg:parameters/nmwg:parameter[\@name=\"time\"]");
		if (defined $time and lc($time) ne "now" and $time ne "") {
			$ret_time = perfSONAR_PS::Time->new("point", $time);
		}

		return ("", $ret_time, $md);
	}
}

sub getLinkStatus($$$) {
	my ($self, $link_ids, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	my %clients = ();

	if (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "ma") {
		my %client;
		my @children;

		foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
			push @children, $link_id;
		}

		$client{"CLIENT"} = perfSONAR_PS::Client::Status::MA->new($self->{CONF}->{"circuitstatus"}->{"status_ma_uri"});
		$client{"LINKS"} = $link_ids;

		my ($status, $res) = $client{"CLIENT"}->open;
		if ($status != 0) {
			my $msg = "Problem opening status MA ".$self->{CONF}->{"circuitstatus"}->{"status_ma_uri"}.": $res";
			$logger->warn($msg);
		} else {
			$clients{$self->{CONF}->{"circuitstatus"}->{"status_ma_uri"}} = \%client;
		}
	} elsif (lc($self->{CONF}->{"circuitstatus"}->{"status_ma_type"}) eq "ls") {
		# Consult the LS to find the Status MA for each link

		my %queries = ();

		foreach my $link_id (@{ $link_ids }) {
			my $xquery = "";
			$xquery .= "        declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
			$xquery .= "        for \$data in /nmwg:store/nmwg:data\n";
			$xquery .= "          let \$metadata_id := \$data/\@metadataIdRef\n";
			$xquery .= "          where \$data//*:link[\@id=\"$link_id\"] and \$data//nmwg:eventType[text()=\"http://ggf.org/ns/nmwg/characteristic/link/status/20070809\"]\n";
			$xquery.= "          return /nmwg:store/nmwg:metadata[\@id=\$metadata_id]\n";

			$queries{$link_id} = $xquery;
		}

		my ($status, $res) = queryLS($self->{LS_HOST}, $self->{LS_PORT}, $self->{LS_ENDPOINT}, \%queries);
		if ($status != 0) {
			my $msg = "Couldn't lookup Link Status MAs from LS: $res";
			$logger->warn($msg);
		} else {
			foreach my $link_id (@{ $link_ids }) {
				if (!defined $res->{$link_id}) {
					$logger->warn("Couldn't find any information on link $link_id");
					next;
				}

				my ($link_status, $link_res) = @{ $res->{$link_id} };

				if ($link_status != 0) {
					$logger->warn("Couldn't find any information on link $link_id");
					next;
				}

				my $accessPoint;

				$accessPoint = findvalue($link_res, "./psservice:datum/nmwg:metadata/perfsonar:subject/psservice:service/psservice:accessPoint");

				if (!defined $accessPoint or $accessPoint eq "") {
					my $msg = "Received response with no access point for link: $link_id";
					$logger->warn($msg);
					next;
				}

				if (!defined $clients{$accessPoint}) {
					my %client = ();
					my @children = ();
					my $new_client;

					push @children, $link_id;

					$client{"CLIENT"} = perfSONAR_PS::Client::Status::MA->new($accessPoint);
					$client{"LINKS"} = \@children;

					my ($status, $res) = $client{"CLIENT"}->open;
					if ($status != 0) {
						my $msg = "Problem opening status MA $accessPoint: $res";
						$logger->warn($msg);
						next;
					}

					$clients{$accessPoint} = \%client;
				} else {
					push @{ $clients{$accessPoint}->{"LINKS"} }, $link_id;
				}
			}
		}
	} else {
		my %client;

		$client{"CLIENT"} = $self->{LOCAL_MA_CLIENT};
		$client{"LINKS"} = $link_ids;

		my ($status, $res) = $client{"CLIENT"}->open;
		if ($status != 0) {
			my $msg = "Problem opening status MA ".$self->{CONF}->{"circuitstatus"}->{"status_ma_uri"}.": $res";
			$logger->warn($msg);
		} else {
			$clients{"local"} = \%client;
		}
	}

	my %response = ();

	foreach my $ap_id (keys %clients) {
		my $ma = $clients{$ap_id};

		my ($status, $res) = $ma->{"CLIENT"}->getLinkStatus($ma->{"LINKS"}, $time);
		if ($status != 0) {
			my $msg = "Error getting link status: $res";
			$logger->warn($msg);
		} else {
			foreach my $link_id (keys %{ $res }) {
				$response{$link_id} = $res->{$link_id};
			}
		}
	}

	return ("", \%response);
}

sub handlePathStatus($$$$) {
	my ($self, $output, $circuits, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");
	my ($status, $res);
	
	if (defined $self->{CONF}->{"circuitstatus"}->{"cache_length"} and $self->{CONF}->{"circuitstatus"}->{"cache_length"} > 0 and !defined $time) {
		my $mtime = (stat $self->{CONF}->{"circuitstatus"}->{"cache_file"})[9];

		if (time - $mtime < $self->{CONF}->{"circuitstatus"}->{"cache_length"}) {
			$logger->debug("Using cached results in ".$self->{CONF}->{"circuitstatus"}->{"cache_file"});
			if (open(CACHEFILE, $self->{CONF}->{"circuitstatus"}->{"cache_file"})) {
				my $response;
				local $/;
				flock CACHEFILE, LOCK_SH;
				$response = <CACHEFILE>;
				close CACHEFILE;
				$output->addOpaque($response);
				return;
			} else {
				$logger->warn("Unable to open cached results in ".$self->{CONF}->{"circuitstatus"}->{"cache_file"});
			}
		}
	}

	# get the list of topology link IDs to lookup	
	my %link_ids = ();
	foreach my $circuit_name (@{ $circuits }) {
		my $circuit = $self->{CIRCUITS}->{$circuit_name};

		foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
			$link_ids{$sublink_id} = "";
		}
	}

	# Lookup the link status
	my @links = keys %link_ids;

	($status, $res) = $self->getLinkStatus(\@links, $time);

	# Fill in any missing links
	foreach my $link_id (@links) {
		if (!defined $res->{$link_id}) {
			my $msg = "Did not receive any information about link $link_id";
			$logger->warn($msg);

			my $link;
			if (!defined $time) {
			my $curr_time = time;
			$link = perfSONAR_PS::Status::Link->new($link_id, "full", $curr_time, $curr_time, "unknown", "unknown");
			} else {
			$link = perfSONAR_PS::Status::Link->new($link_id, "full", $time->getStartTime(), $time->getEndTime(), "unknown", "unknown");
			}

			$res->{$link_id} = [ $link ];
		}
	}

	my %circuit_status = ();

	foreach my $circuit_name (@{ $circuits }) {
		my $circuit = $self->{CIRCUITS}->{$circuit_name};

		my @data_points = ();

		if (defined $time and $time->getType() ne "point") {
			foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
				foreach my $link_status (@{ $res->{$sublink_id} }) {
					push @data_points, $link_status;
				}
			}
		} else {
			my $circuit_admin_value = "unknown";
			my $circuit_oper_value = "unknown";
			my $circuit_time;

			foreach my $sublink_id (@{ $circuit->{"sublinks"} }) {
				foreach my $link_status (@{ $res->{$sublink_id} }) {
					$logger->debug("Sublink: $sublink_id");
					my $oper_value = $link_status->getOperStatus;
					my $admin_value = $link_status->getAdminStatus;
					my $end_time = $link_status->getEndTime;

					$circuit_time = $end_time if (!defined $circuit_time or $end_time > $circuit_time);

					if ($circuit_oper_value eq "down" or $oper_value eq "down")  {
						$circuit_oper_value = "down";
					} elsif ($circuit_oper_value eq "degraded" or $oper_value eq "degraded")  {
						$circuit_oper_value = "degraded";
					} elsif ($circuit_oper_value eq "up" or $oper_value eq "up")  {
						$circuit_oper_value = "up";
					} else {
						$circuit_oper_value = "unknown";
					}

					if ($circuit_admin_value eq "maintenance" or $admin_value eq "maintenance") {
						$circuit_admin_value = "maintenance";
					} elsif ($circuit_admin_value eq "troubleshooting" or $admin_value eq "troubleshooting") {
						$circuit_admin_value = "troubleshooting";
					} elsif ($circuit_admin_value eq "underrepair" or $admin_value eq "underrepair") {
						$circuit_admin_value = "underrepair";
					} elsif ($circuit_admin_value eq "normaloperation" or $admin_value eq "normaloperation") {
						$circuit_admin_value = "normaloperation";
					} else {
						$circuit_admin_value = "unknown";
					}
				}
			}

			if (!defined $time and defined $self->{CONF}->{"circuitstatus"}->{"max_recent_age"} and $self->{CONF}->{"circuitstatus"}->{"max_recent_age"} ne "") {
				my $curr_time = time;

				if ($curr_time - $circuit_time > $self->{CONF}->{"circuitstatus"}->{"max_recent_age"}) {
					$logger->info("Old link time: $circuit_time Current Time: ".$curr_time.": ".($curr_time - $circuit_time));
					$circuit_time = $curr_time;
					$circuit_oper_value = "unknown";
					$circuit_admin_value = "unknown";
				}
			} else {
				$circuit_time = $time->getTime();
			}

			my $link = perfSONAR_PS::Status::Link->new("", "", $circuit_time, $circuit_time, $circuit_oper_value, $circuit_admin_value);
			push @data_points, $link;
		}

		$circuit_status{$circuit_name} = \@data_points;
	}

	my $doc = perfSONAR_PS::XML::Document_string->new();

	startParameters($doc, "params.0");
	 addParameter($doc, "DomainName", $self->{DOMAIN});
	endParameters($doc);
	$self->outputResults($doc, \%circuit_status, $time);

	if (!defined $time and defined $self->{CONF}->{"circuitstatus"}->{"cache_length"} and $self->{CONF}->{"circuitstatus"}->{"cache_length"} > 0) {
		$logger->debug("Caching results in ".$self->{CONF}->{"circuitstatus"}->{"cache_file"});

		unlink($self->{CONF}->{"circuitstatus"}->{"cache_file"});

		if (sysopen(CACHEFILE, $self->{CONF}->{"circuitstatus"}->{"cache_file"}, O_WRONLY | O_CREAT, 0600)) {
			flock CACHEFILE, LOCK_EX;
			print CACHEFILE $doc->getValue();
			close CACHEFILE;
		} else {
			$logger->warn("Unable to cache results");
		}
	}

	$output->addOpaque($doc->getValue());

	return ("", "");
}

sub outputResults($$$) {
	my ($self, $output, $results, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	my %output_endpoints = ();
	my $i = 0;

	foreach my $circuit_name (keys %{ $results }) {
		my $circuit = $self->{CIRCUITS}->{$circuit_name};
		foreach my $endpoint (@{ $circuit->{"endpoints"} }) {
			next if (!defined $self->{NODES}->{$endpoint->{name}});
			next if (defined $output_endpoints{$endpoint->{name}});

			startMetadata($output, "metadata.".genuid(), "", undef);
			 $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub-".$endpoint->{name} });
			  outputNodeElement($output, $self->{NODES}->{$endpoint->{name}});
			 $output->endElement("subject");
			endMetadata($output);

			$output_endpoints{$endpoint->{name}} = 1;
		}

		my $mdid = "metadata.".genuid();

		startMetadata($output, $mdid, "", undef);
		 $output->startElement(prefix => "nmwg", tag => "subject", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id => "sub$i" });
		  outputCircuitElement($output, $circuit);
		 $output->endElement("subject");
		endMetadata($output);

		my @data = @{ $results->{$circuit_name} };
		startData($output, "data.$i", $mdid, undef);
		foreach my $datum (@data) {
			my %attrs = ();

			$attrs{"timeType"} = "unix";
			$attrs{"timeValue"} = $datum->getEndTime();
			if (defined $time and $time ne "point") {
				$attrs{"startTime"} = $datum->getStartTime();
				$attrs{"endTime"} = $datum->getEndTime();
			}

			$output->startElement(prefix => "ifevt", tag => "datum", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", attributes => \%attrs);
			$output->createElement(prefix => "ifevt", tag => "stateAdmin", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $datum->getAdminStatus);
			$output->createElement(prefix => "ifevt", tag => "stateOper", namespace => "http://ggf.org/ns/nmwg/event/status/base/2.0/", content => $datum->getOperStatus);
			$output->endElement("datum");
		}
		endData($output);

		$i++;
	}
}

sub outputNodeElement($$) {
	my ($output, $node) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	$logger->debug("Outputing Node Element: ".Dumper($node));

	$output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/");
	  $output->createElement(prefix => "nmwgtopo3", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => "TopologyPoint");
	  $output->createElement(prefix => "nmwgtopo3", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { type => "logical" }, content => $node->{"name"});
	if (defined $node->{"city"} and $node->{"city"} ne "") {
		$output->createElement(prefix => "nmwgtopo3", tag => "city", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"city"});
	}
	if (defined $node->{"country"} and $node->{"country"} ne "") {
		$output->createElement(prefix => "nmwgtopo3", tag => "country", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"country"});
	}
	if (defined $node->{"latitude"} and $node->{"latitude"} ne "") {
		$output->createElement(prefix => "nmwgtopo3", tag => "latitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"latitude"});
	}
	if (defined $node->{"longitude"} and $node->{"longitude"} ne "") {
		$output->createElement(prefix => "nmwgtopo3", tag => "longitude", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $node->{"longitude"});
	}
	if (defined $node->{"institution"} and $node->{"institution"} ne "") {
		$output->createElement(prefix => "nmwgtopo3", tag => "institution", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", , content => $node->{"institution"});
	}
	$output->endElement("node");
}

sub outputCircuitElement($$) {
	my ($output, $circuit) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	$output->startElement(prefix => "nmtl2", tag => "link", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/");
	  $output->createElement(prefix => "nmtl2", tag => "name", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $circuit->{"name"});
	  $output->createElement(prefix => "nmtl2", tag => "globalName", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", attributes => { type => "logical" }, content => $circuit->{"globalName"});
	  $output->createElement(prefix => "nmtl2", tag => "type", namespace => "http://ggf.org/ns/nmwg/topology/l2/3.0/", content => $circuit->{"type"});
	  foreach my $endpoint (@{ $circuit->{"endpoints"} }) {
	  $output->startElement(prefix => "nmwgtopo3", tag => "node", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", attributes => { nodeIdRef => $endpoint->{"name"} });
	  $output->createElement(prefix => "nmwgtopo3", tag => "role", namespace => "http://ggf.org/ns/nmwg/topology/base/3.0/", content => $endpoint->{"type"});
	  $output->endElement("node");
	  }
	  startParameters($output, "params.0");
	    addParameter($output, "supportedEventType", "Path.Status");
	  endParameters($output);
	$output->endElement("link");
}

sub parseCircuitsFile($) {
	my ($file) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");

	my %nodes = ();
	my %incomplete_nodes = ();
	my %topology_links = ();
	my %circuits = ();

	my $parser = XML::LibXML->new();
	my $doc;
	eval {
		$doc = $parser->parse_file($file);
	};
	if ($@ or !defined $doc) {
		my $msg = "Couldn't parse circuits file $file: $@";
		$logger->error($msg);
		return ("error.configuration", $msg);
	}

	my $conf = $doc->documentElement;

	my $domain = findvalue($conf, "domain");
	if (!defined $domain) {
		my $msg = "No domain specified in configuration";
		$logger->error($msg);
		return ("error.configuration", $msg);
	}

	foreach my $endpoint ($conf->getChildrenByLocalName("node")) {
		my $node_id = $endpoint->getAttribute("id");
		my $node_type = $endpoint->getAttribute("type");
		my $node_name = $endpoint->getAttribute("name");
		my $city = findvalue($endpoint, "city");
		my $country = findvalue($endpoint, "country");
		my $longitude = findvalue($endpoint, "longitude");
		my $institution = findvalue($endpoint, "institution");
		my $latitude = findvalue($endpoint, "latitude");

		if (!defined $node_name or $node_name eq "") {
			my $msg = "Node needs to have a name";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (defined $nodes{$node_name}) {
			my $msg = "Multiple endpoints have the name \"$node_name\"";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (!defined $node_type or $node_type eq "") {
			my $msg = "Node with unspecified type found";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (lc($node_type) ne "demarcpoint" and lc($node_type) ne "endpoint") {
			my $msg = "Node found with invalid type $node_type. Must be \"DemarcPoint\" or \"EndPoint\"";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		my %tmp = ();
		my $new_node = \%tmp;

		$new_node->{"id"} = $node_id if (defined $node_id and $node_id ne "");
		$new_node->{"name"} = $node_name if (defined $node_name and $node_name ne "");
		$new_node->{"city"} = $city if (defined $city and $city ne "");
		$new_node->{"country"} = $country if (defined $country and $country ne "");
		$new_node->{"longitude"} = $longitude if (defined $longitude and $longitude ne "");
		$new_node->{"latitude"} = $latitude if (defined $latitude and $latitude ne "");
		$new_node->{"institution"} = $institution if (defined $institution and $institution ne "");

		if (defined $node_id and
			(!defined $city or !defined $country or !defined $longitude or !defined $latitude or !defined $institution)) {
			$incomplete_nodes{$node_id} = $new_node;
		}

		$nodes{$node_name} = $new_node;
	}

	foreach my $circuit ($conf->getChildrenByLocalName("circuit")) {
		my $global_name = findvalue($circuit, "globalName");
		my $local_name = findvalue($circuit, "localName");
		my $knowledge = $circuit->getAttribute("knowledge");
		my $circuit_type;

		if (!defined $global_name or $global_name eq "") {
			my $msg = "Circuit has no global name";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		if (!defined $knowledge or $knowledge eq "") {
			$logger->warn("Don't know the knowledge level of circuit \"$global_name\". Assuming full");
			$knowledge = "full";
		} else {
			$knowledge = lc($knowledge);
		}

		if (!defined $local_name or $local_name eq "") {
			$local_name = $global_name;
		}

		my %sublinks = ();

		foreach my $topo_id ($circuit->getChildrenByLocalName("linkID")) {
			my $id = $topo_id->textContent;

			if (defined $sublinks{$id}) {
				my $msg = "Link $id appears multiple times in circuit $global_name";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			$sublinks{$id} = "";
			$topology_links{$id} = "";
		}

		my @endpoints = ();

		my $num_endpoints = 0;

		my $prev_domain;

		foreach my $endpoint ($circuit->getChildrenByLocalName("endpoint")) {
			my $node_type = $endpoint->getAttribute("type");
			my $node_name = $endpoint->getAttribute("name");

			if (!defined $node_type or $node_type eq "") {
				my $msg = "Node with unspecified type found";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if (!defined $node_name or $node_name eq "") {
				my $msg = "Endpint needs to specify a node name";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if (lc($node_type) ne "demarcpoint" and lc($node_type) ne "endpoint") {
				my $msg = "Node found with invalid type $node_type. Must be \"DemarcPoint\" or \"EndPoint\"";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			my ($domain, @junk) = split(/-/, $node_name);
			if (!defined $prev_domain) {
				$prev_domain = $domain;
			} else {
				if ($domain eq $prev_domain) {
					$circuit_type = "DOMAIN_Link";
				} else {
					if ($knowledge eq "full") {
						$circuit_type = "ID_Link";
					} else {
						$circuit_type = "ID_LinkPartialInfo";
					}
				}
			}

			my %new_endpoint = ();

			$new_endpoint{"type"} = $node_type;
			$new_endpoint{"name"} = $node_name;

			push @endpoints, \%new_endpoint;

			$num_endpoints++;
		}

		if ($num_endpoints != 2) {
			my $msg = "Invalid number of endpoints, $num_endpoints, must be 2";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		my @sublinks = keys %sublinks;

		my %new_circuit = ();

		$new_circuit{"globalName"} = $global_name;
		$new_circuit{"name"} = $local_name;
		$new_circuit{"sublinks"} = \@sublinks;
		$new_circuit{"endpoints"} = \@endpoints;
		$new_circuit{"type"} = $circuit_type;

		if (defined $circuits{$local_name}) {
			my $msg = "Error: existing circuit of name $local_name";
			$logger->error($msg);
			return ("error.configuration", $msg);
		} else {
			$circuits{$local_name} = \%new_circuit;
		}
	}

	return ("", $domain, \%circuits, \%incomplete_nodes, \%topology_links, \%nodes);
}

sub parseTopology($$$$) {
	my ($topology, $incomplete_nodes, $domain_name) = @_;
	my $logger = get_logger("perfSONAR_PS::Services::MA::CircuitStatus");
	my %ids = ();

	foreach my $node ($topology->getElementsByLocalName("node")) {
		my $id = $node->getAttribute("id");
		$logger->debug("node: ".$id);

		next if !defined $incomplete_nodes->{$id};

		$logger->debug("found node ".$id." in here");

		my $longitude = findvalue($node, "./*[local-name()='longitude']");
		$logger->debug("searched for longitude");
		my $institution = findvalue($node, "./*[local-name()='institution']");
		$logger->debug("searched for institution");
		my $latitude = findvalue($node, "./*[local-name()='latitude']");
		$logger->debug("searched for latitude");
		my $city = findvalue($node, "./*[local-name()='city']");
		$logger->debug("searched for city");
		my $country = findvalue($node, "./*[local-name()='country']");
		$logger->debug("searched for country");

		$incomplete_nodes->{$id}->{"type"} = "TopologyPoint";

		if (!defined $incomplete_nodes->{$id}->{"longitude"} and defined $longitude and $longitude ne "") {
			# conversions may need to be made
			$incomplete_nodes->{$id}->{"longitude"} = $longitude;
		}

		if (!defined $incomplete_nodes->{$id}->{"latitude"} and defined $latitude and $latitude ne "") {
			# conversions may need to be made
			$incomplete_nodes->{$id}->{"latitude"} = $latitude;
		}

		if (!defined $incomplete_nodes->{$id}->{"institution"}) {
			if ( defined $institution and $institution ne "") {
				# conversions may need to be made
				$incomplete_nodes->{$id}->{"institution"} = $institution;
			} else {
				$incomplete_nodes->{$id}->{"institution"} = $domain_name;
			}
		}

		if (!defined $incomplete_nodes->{$id}->{"city"} and defined $city and $city ne "") {
			$incomplete_nodes->{$id}->{"city"} = $city;
		}

		if (!defined $incomplete_nodes->{$id}->{"country"} and defined $country and $country ne "") {
			$incomplete_nodes->{$id}->{"country"} = $country;
		}
	}

	return ("", "");
}

1;

__END__
=head1 NAME

perfSONAR_PS::Services::MA::CircuitStatus - A module that provides methods for an E2EMon Compatible MP.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::Services::MA::CircuitStatus;

my %conf = readConfiguration();

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtm => "http://ggf.org/ns/nmwg/time/2.0/",
		nmwgtopo3 => "http://ggf.org/ns/nmwg/topology/base/3.0/",
		nmtl2 => "http://ggf.org/ns/nmwg/topology/l2/3.0/",
		nmtl3 => "http://ggf.org/ns/nmwg/topology/l3/3.0/",
	 );

my $ma = perfSONAR_PS::Services::MA::CircuitStatus->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::Services::MA::CircuitStatus->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

if ($ma->init != 0) {
	print "Error: couldn't initialize measurement archive\n";
	exit(-1);
}

while(1) {
	my $request = $ma->receive;
	$ma->handleRequest($request);
}

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive.

=head2 init 

       Initializes the MP and validates or fills in entries in the
	configuration file. Returns 0 on success and -1 on failure.

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

=head2 parseRequest($self, $request)

	Goes through each metadata/data pair, extracting the eventType and
	calling the function associated with that eventType.

=head2 handlePathStatusRequest($self, $time) 

	Performs the required steps to handle a path status message: contacts
	the topology service to resolve node information, contacts the LS if
	needed to find the link status service, contacts the link status
	service and munges the results.

=head2 outputNodes($nodes) 

	Takes the set of nodes and outputs them in an E2EMon compatiable
	format.

=head2 outputCircuits($circuits) 

	Takes the set of links and outputs them in an E2EMon compatiable
	format.

=head2 parseCircuitsFile($file) 

	Parses the links configuration file. It returns an array containg up to
	five values. The first value is the status and can be one of 0 or -1.
	If it is -1, parsing the configuration file failed and the error
	message is in the next value. If the status is 0, the next 4 values are
	the domain name, a pointer to the set of links, a pointer to a hash
	containg the set of nodes to lookup in the topology service and a
	pointer to a hash containing the set of links to lookup in the status
	service.
	
=head2 parseTopology($topology, $nodes, $domain_name)

	Parses the output from the topology service and fills in the details
	for the nodes. The domain name is passed so that when a node has no
	name specified in the configuration file, it can be constructd based on
	the domain name and the node's name in the topology service.

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Transport>,
L<perfSONAR_PS::Client::Status::MA>, L<perfSONAR_PS::Client::Topology::MA>


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

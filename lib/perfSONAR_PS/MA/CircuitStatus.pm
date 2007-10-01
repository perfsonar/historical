#!/usr/bin/perl -w

package perfSONAR_PS::MA::CircuitStatus;

use warnings;
use strict;
use Exporter;
use Log::Log4perl qw(get_logger);
use Module::Load;
use Fcntl qw (:flock);
use Fcntl;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Transport;

use perfSONAR_PS::MA::Status::Client::MA;
use perfSONAR_PS::MA::Topology::Client::MA;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	if ($self->SUPER::init != 0) {
		$logger->error("Couldn't initialize parent class");
		return -1;
	}

	if (!defined $self->{CONF}->{"STATUS_MA_TYPE"} or $self->{CONF}->{"STATUS_MA_TYPE"} eq "") {
		if (!defined $self->{CONF}->{"LS"} or $self->{CONF}->{"LS"} eq "") {
			$logger->error("No LS nor Status MA specified");
			return -1;
		} else {
			$self->{CONF}->{"STATUS_MA_TYPE"} = "ls";
		}
	}

	if (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "ls") {
		($self->{LS_HOST}, $self->{LS_PORT}, $self->{LS_ENDPOINT}) = &perfSONAR_PS::Transport::splitURI($self->{CONF}->{"LS"});
		if (!defined $self->{LS_HOST} or !defined $self->{LS_PORT} or !defined $self->{LS_ENDPOINT}) {
			$logger->error("Specified LS is not a URI: ".$self->{CONF}->{"LS"});
			return -1;
		}
	} elsif (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "ma") {
		if (!defined $self->{CONF}->{"STATUS_MA_URI"} or $self->{CONF}->{"STATUS_MA_URI"} eq "") {
			$logger->error("You specified an MA for the status, but did not specify the URI(STATUS_MA_URI)");
			return -1;
		}
	} elsif (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "sqlite") {
		load perfSONAR_PS::MA::Status::Client::SQL;

		if (!defined $self->{CONF}->{"STATUS_MA_FILE"} or $self->{CONF}->{"STATUS_MA_FILE"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(STATUS_MA_FILE)");
			return -1;
		}

		my $file = $self->{CONF}->{"STATUS_MA_FILE"};
		if (defined $self->{DIRECTORY}) {
			if (!($file =~ "^/")) {
				$file = $self->{DIRECTORY}."/".$file;
			}
		}

		$self->{LOCAL_MA_CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$file, $self->{CONF}->{"STATUS_MA_TABLE"});
		if (!defined $self->{LOCAL_MA_CLIENT}) {
			my $msg = "No database to dump";
			$logger->error($msg);
			return (-1, $msg);
		}
	} elsif (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "mysql") {
		load perfSONAR_PS::MA::Status::Client::SQL;

		my $dbi_string = "dbi:mysql";

		if (!defined $self->{CONF}->{"STATUS_MA_NAME"} or $self->{CONF}->{"STATUS_MA_NAME"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database (STATUS_MA_NAME)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"STATUS_MA_NAME"};

		if (!defined $self->{CONF}->{"STATUS_MA_HOST"} or $self->{CONF}->{"STATUS_MA_HOST"} eq "") {
			$logger->error("You specified a MySQL Database, but did not specify the database host (STATUS_MA_HOST)");
			return -1;
		}

		$dbi_string .= ":".$self->{CONF}->{"STATUS_MA_HOST"};

		if (defined $self->{CONF}->{"STATUS_MA_PORT"} and $self->{CONF}->{"STATUS_MA_PORT"} ne "") {
			$dbi_string .= ":".$self->{CONF}->{"STATUS_MA_PORT"};
		}

		$self->{LOCAL_MA_CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL($dbi_string, $self->{CONF}->{"STATUS_MA_USERNAME"}, $self->{CONF}->{"STATUS_MA_PASSWORD"});
		if (!defined $self->{LOCAL_MA_CLIENT}) {
			my $msg = "Couldn't create SQL client";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid MA type specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"TOPOLOGY_MA_TYPE"} or $self->{CONF}->{"TOPOLOGY_MA_TYPE"} eq "") {
		$logger->error("No topology MA type specified");
		return -1;
	} elsif (lc($self->{CONF}->{"TOPOLOGY_MA_TYPE"}) eq "xml") {
		load perfSONAR_PS::MA::Topology::Client::XMLDB;

		if (!defined $self->{CONF}->{"TOPOLOGY_MA_FILE"} or $self->{CONF}->{"TOPOLOGY_MA_FILE"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database file(TOPOLOGY_MA_FILE)");
			return -1;
		}

		if (!defined $self->{CONF}->{"TOPOLOGY_MA_ENVIRONMENT"} or $self->{CONF}->{"TOPOLOGY_MA_ENVIRONMENT"} eq "") {
			$logger->error("You specified a Sleepycat XML DB Database, but then did not specify a database name(TOPOLOGY_MA_ENVIRONMENT)");
			return -1;
		}

		my $environment = $self->{CONF}->{"TOPOLOGY_MA_ENVIRONMENT"};
		if (defined $self->{DIRECTORY}) {
			if (!($environment =~ "^/")) {
				$environment = $self->{DIRECTORY}."/".$environment;
			}
		}

		my $file = $self->{CONF}->{"TOPOLOGY_MA_FILE"};
		my %ns = &perfSONAR_PS::MA::Topology::Topology::getTopologyNamespaces();

		$self->{TOPOLOGY_CLIENT} = new perfSONAR_PS::MA::Topology::Client::XMLDB($environment, $file, \%ns, 1);
	} elsif (lc($self->{CONF}->{"TOPOLOGY_MA_TYPE"}) eq "none") {
		$logger->warn("Ignoring the topology MA. Everything must be specified explicitly in the circuits.conf file");
	} elsif (lc($self->{CONF}->{"TOPOLOGY_MA_TYPE"}) eq "ma") {
		if (!defined $self->{CONF}->{TOPOLOGY_MA_URI} or $self->{CONF}->{TOPOLOGY_MA_URI} eq "") {
			$logger->error("You specified that you want a Topology MA, but did not specify the URI (TOPOLOGY_MA_URI)");
			return -1;
		}

		$self->{TOPOLOGY_CLIENT} = new perfSONAR_PS::MA::Topology::Client::MA($self->{CONF}->{TOPOLOGY_MA_URI});
	} else {
		$logger->error("Invalid database type specified");
		return -1;
	}

	if (!defined $self->{CONF}->{"CIRCUITS_FILE_TYPE"} or $self->{CONF}->{"CIRCUITS_FILE_TYPE"} eq "") {
		$logger->error("No circuits file type specified");
		return -1;
	}

	if($self->{CONF}->{"CIRCUITS_FILE_TYPE"} eq "file") {
		if (!defined $self->{CONF}->{"CIRCUITS_FILE"} or $self->{CONF}->{"CIRCUITS_FILE"} eq "") {
			$logger->error("No circuits file specified");
			return -1;
		}

		my ($status, $res1, $res2, $res3, $res4, $res5) = parseCircuitsFile($self->{CONF}->{"CIRCUITS_FILE"});
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
		if ($self->{"CONF"}->{"TOPOLOGY_MA_TYPE"} eq "none" and scalar keys %{ $res3 } > 0) {
			my $msg = "You specified no topology MA, but there are incomplete nodes";
			$logger->error($msg);
			return -1;
		}
	} else {
		$logger->error("Invalid circuits file type specified: ".$self->{CONF}=>{"LINK_FILE_TYPE"});
		return -1;
	}

	if (defined $self->{CONF}->{"CACHE_LENGTH"} and $self->{CONF}->{"CACHE_LENGTH"} > 0) {
		if (!defined $self->{CONF}->{"CACHE_FILE"} or $self->{CONF}->{"CACHE_FILE"} eq "") {
			my $msg = "If you specify a cache time period, you need to specify a file to cache to \"CACHE_FILE\"";
			$logger->error($msg);
			return -1;
		}

		my $file = $self->{CONF}->{"CACHE_FILE"};
		if (defined $self->{DIRECTORY}) {
			if (!($file =~ "^/")) {
				$file = $self->{DIRECTORY}."/".$file;
			}
		}

		$self->{CONF}->{"CACHE_FILE"} = $file;

		$logger->debug("Using \"$file\" to cache current results");
	}

	return 0;
}

sub receive {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	my $n;
	my $request;
	my $error;

	do {
		$request = undef;

		$n = $self->{LISTENER}->acceptCall(\$request, \$error);
		if ($n == 0) {
			$logger->debug("Received 'shadow' request from below; no action required.: " . $request);
			$request->finish;
		}

		if (defined $error and $error ne "") {
			$logger->error("Error in accept call: $error");
		}
	} while ($n == 0);

	return $request;
}

sub handleRequest($$) {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	$logger->debug("Handling request");

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

sub __handleRequest {
	my($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	my $messageIdReturn = genuid();
	my $messageId = $request->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageType = $request->getRequestDOM()->getDocumentElement->getAttribute("type");

	$self->{REQUESTNAMESPACES} = $request->getNamespaces();

	my ($status, $response);

	if($messageType eq "SetupDataRequest") {
		$logger->debug("Handling status request.");
		($status, $response) = $self->parseRequest($request->getRequestDOM());
	} else {
		$status = "error.ma.message.type";
		$response ="Message type \"".$messageType."\" is not yet supported";

		$logger->error($response);
	}

	if ($status ne "") {
		$logger->error("Error handling request: $status/$response");

		$request->setResponse(getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", $status, $response, 1));
	} else {
		my %all_namespaces = ();

		my $request_namespaces = $request->getNamespaces();

		foreach my $uri (keys %{ $request_namespaces }) {
			$all_namespaces{$request_namespaces->{$uri}} = $uri;
		}

		foreach my $prefix (keys %{ $self->{NAMESPACES} }) {
			$all_namespaces{$prefix} = $self->{NAMESPACES}->{$prefix};
		}

		$request->setResponse(getResultMessage($messageIdReturn, $messageId, "E2E_Link_status_information", $response, \%all_namespaces));
	}

	return;
}

sub parseRequest {
	my ($self, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my $localContent = "";

	my $found_match = 0;

	foreach my $d ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
		foreach my $m ($request->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
			if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
				my $eventType = findvalue($m, "./nmwg:eventType");

				$found_match = 1;

				my ($status, $res);

				if (!defined $eventType or $eventType eq "") {
					$status = "error.ma.no_eventtype";
					$res = "No event type specified for metadata: ".$m->getAttribute("id");
				} elsif ($eventType eq "Path.Status") {
					my $time = findvalue($m, './nmwg:parameters/nmwg:parameter[@name="time"]');

					($status, $res) = $self->handlePathStatusRequest($time);
				} else {
					$status = "error.ma.eventtype_not_supported";
					$res = "Unknown event type: ".$eventType;
					$logger->error($res);
				}

				if ($status ne "") {
					$logger->error("Couldn't handle requested metadata: $res");

					my $mdID = "metadata.".genuid();

					$localContent .= getResultCodeMetadata($mdID, $m->getAttribute("id"), $status);
					$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
				} else {
					$localContent .= $res;
				}

			}
		}
	}

	if ($found_match == 0) {
		my $status = "error.ma.no_metadata_data_pair";
		my $res = "There was no data/metadata pair found";

		my $mdID = "metadata.".genuid();

		$localContent .= getResultCodeMetadata($mdID, "", $status);
		$localContent .= getResultCodeData("data.".genuid(), $mdID, $res, 1);
	}

	return ("", $localContent);
}

sub handlePathStatusRequest($$) {
	my ($self, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	my ($status, $res);

	if (!defined $time or $time eq "now") {
		$time = "";
	}

	if (defined $self->{CONF}->{"CACHE_LENGTH"} and $self->{CONF}->{CACHE_LENGTH} > 0 and $time eq "") {
		my $mtime = (stat $self->{CONF}->{CACHE_FILE})[9];

		if (time - $mtime < $self->{CONF}->{CACHE_LENGTH}) {
			$logger->debug("Using cached results in ".$self->{CONF}->{CACHE_FILE});
			if (open(CACHEFILE, $self->{CONF}->{CACHE_FILE})) {
				my $response;
				local $/;
				flock CACHEFILE, LOCK_SH;
				$response = <CACHEFILE>;
				close CACHEFILE;
				return ("", $response);
			} else {
				$logger->warn("Unable to open cached results in ".$self->{CONF}->{CACHE_FILE});
			}
		}
	}

	if (lc($self->{CONF}->{"TOPOLOGY_MA_TYPE"}) ne "none") {
		($status, $res) = $self->{TOPOLOGY_CLIENT}->open;
		if ($status != 0) {
			my $msg = "Problem opening topology MA: $res";
			$logger->error($msg);
			return ("error.ma", $msg);
		}

		($status, $res) = $self->{TOPOLOGY_CLIENT}->getAll;
		if ($status != 0) {
			my $msg = "Error getting topology information: $res";
			$logger->error($msg);
			return ("error.ma", $msg);
		}

		my $topology = $res;

		($status, $res) = parseTopology($topology, $self->{INCOMPLETE_NODES}, $self->{DOMAIN});
		if ($status ne "") {
			my $msg = "Error parsing topology: $res";
			$logger->error($msg);
			return ("error.ma", $msg);
		}
	}

	my %clients = ();

	if (lc($self->{CONF}->{STATUS_MA_TYPE}) eq "ma") {
		my %client;
		my @children;

		foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
			push @children, $link_id;
		}

		$client{"CLIENT"} = new perfSONAR_PS::MA::Status::Client::MA($self->{CONF}->{STATUS_MA_URI});
		$client{"LINKS"} = \@children;

		my ($status, $res) = $client{"CLIENT"}->open;
		if ($status != 0) {
			my $msg = "Problem opening status MA ".$self->{CONF}->{STATUS_MA_URI}.": $res";
			$logger->warn($msg);
		} else {
			$clients{$self->{CONF}->{STATUS_MA_URI}} = \%client;
		}
	} elsif (lc($self->{CONF}->{STATUS_MA_TYPE}) eq "ls") {
		# Consult the LS to find the Status MA for each link

		my %queries = ();

		foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
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
			foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
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

					$client{"CLIENT"} = new perfSONAR_PS::MA::Status::Client::MA($accessPoint);
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
		my @children;

		foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
			push @children, $link_id;
		}

		$client{"CLIENT"} = $self->{LOCAL_MA_CLIENT};
		$client{"LINKS"} = \@children;

		my ($status, $res) = $client{"CLIENT"}->open;
		if ($status != 0) {
			my $msg = "Problem opening status MA ".$self->{CONF}->{STATUS_MA_URI}.": $res";
			$logger->warn($msg);
		} else {
			$clients{"local"} = \%client;
		}
	}

	foreach my $ap_id (keys %clients) {
		my $ma = $clients{$ap_id};

		my ($status, $res) = $ma->{"CLIENT"}->getLinkStatus($ma->{"LINKS"}, $time);
		if ($status != 0) {
			my $msg = "Error getting link status: $res";
			$logger->warn($msg);
		} else {
			foreach my $id (keys %{ $res }) {
				my $link = pop(@{ $res->{$id} });

				if (!defined $self->{TOPOLOGY_LINKS}->{$id}) {
					$logger->warn("Response from server contains a link we didn't ask for");
					next;
				}

				$self->{TOPOLOGY_LINKS}->{$id} = $link;
			}
		}
	}

	foreach my $link_id (keys %{ $self->{TOPOLOGY_LINKS} }) {
		if ($self->{TOPOLOGY_LINKS}->{$link_id} eq "") {
			my $msg = "Did not receive any information about link $link_id";
			$logger->warn($msg);

			my $curr_time = time;
			$self->{TOPOLOGY_LINKS}->{$link_id} = new perfSONAR_PS::MA::Status::Link($link_id, "full", $curr_time, $curr_time, "unknown", "unknown");
		}
	}

	foreach my $circuit (@{ $self->{CIRCUITS} }) {
		my $mdid = "metadata.".genuid();

		my $circuit_admin_value = "unknown";
		my $circuit_oper_value = "unknown";
		my $knowledge;
		my $bidi_knowledge;
		my $circuit_time;

		foreach my $sublink_id (keys %{ $circuit->{"sublinks"} }) {
			my $sublink = $self->{TOPOLOGY_LINKS}->{$sublink_id};
			$logger->debug("Sublink: $sublink_id");
			my $oper_value = $sublink->getOperStatus;
			my $admin_value = $sublink->getAdminStatus;
			my $end_time = $sublink->getEndTime;

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

		my $prev_domain = "";
		my $circuit_type = "";

		foreach my $node (@{ $circuit->{"endpoints"} }) {
			my ($domain, @junk) = split(/-/, $node->{"node"}->{"name"});
			if ($prev_domain ne "") {
				if ($domain eq $prev_domain) {
					$circuit_type = "DOMAIN_Link";
				} else {
					if ($circuit->{"knowledge"} eq "full") {
						$circuit_type = "ID_Link";
					} else {
						$circuit_type = "ID_LinkPartialInfo";
					}
				}
			} else {
				$prev_domain = $domain;
			}
		}

		if ($time eq "" and defined $self->{CONF}->{"MAX_RECENT_AGE"} and $self->{CONF}->{"MAX_RECENT_AGE"} ne "") {
			my $curr_time = time;

			if ($curr_time - $circuit_time > $self->{CONF}->{"MAX_RECENT_AGE"}) {
				$logger->info("Old link time: $circuit_time Current Time: ".$curr_time.": ".($curr_time - $circuit_time));
				$circuit_time = $curr_time;
				$circuit_oper_value = "unknown";
				$circuit_admin_value = "unknown";
			}
		}

		$circuit->{"time"} = $circuit_time;
		$circuit->{"operState"} = $circuit_oper_value;
		$circuit->{"adminState"} = $circuit_admin_value;
		$circuit->{"type"} = $circuit_type;
	}

	my $localContent = "";
	$localContent .= "  <nmwg:parameters id=\"storeId\">\n";
	$localContent .= "     <nmwg:parameter name=\"DomainName\">".$self->{DOMAIN}."</nmwg:parameter>\n";
	$localContent .= "  </nmwg:parameters>\n";
	$localContent .= outputNodes($self->{NODES});
	$localContent .= outputCircuits($self->{CIRCUITS});

	if (defined $self->{CONF}->{"CACHE_LENGTH"} and $self->{CONF}->{CACHE_LENGTH} > 0) {
		$logger->debug("Caching results in ".$self->{CONF}->{CACHE_FILE});

		unlink($self->{CONF}->{CACHE_FILE});

		if (sysopen(CACHEFILE, $self->{CONF}->{CACHE_FILE}, O_WRONLY | O_CREAT, 0600)) {
			flock CACHEFILE, LOCK_EX;
			print CACHEFILE $localContent;
			close CACHEFILE;
		} else {
			$logger->warn("Unable to cache results");
		}
	}

	return ("", $localContent);
}

sub outputNodes($) {
	my ($nodes) = @_;

	my $content = "";

	foreach my $id (keys %{ $nodes }) {
		my $node = $nodes->{$id};
		my $mdid = "metadata.".genuid();

		next if (!defined $node->{"city"} and !defined $node->{"country"} and !defined $node->{"latitude"} and !defined $node->{"longitude"});

		$content .= "<nmwg:metadata id=\"".$mdid."\">\n";
		$content .= "  <nmwg:subject id=\"sub-".$node->{"name"}."\">\n";
		$content .= "    <nmwgtopo3:node id=\"".$node->{"name"}."\">\n";
		$content .= "      <nmwgtopo3:type>TopologyPoint</nmwgtopo3:type>\n";
		$content .= "      <nmwgtopo3:name type=\"logical\">".$node->{"name"}."</nmwgtopo3:name>\n";
		if (defined $node->{"city"} and $node->{"city"} ne "") {
		$content .= "      <nmwgtopo3:city>".$node->{"city"}."</nmwgtopo3:city>\n";
		}
		if (defined $node->{"country"} and $node->{"country"} ne "") {
		$content .= "      <nmwgtopo3:country>".$node->{"country"}."</nmwgtopo3:country>\n";
		}
		if (defined $node->{"latitude"} and $node->{"latitude"} ne "") {
		$content .= "      <nmwgtopo3:latitude>".$node->{"latitude"}."</nmwgtopo3:latitude>\n";
		}
		if (defined $node->{"longitude"} and $node->{"longitude"} ne "") {
		$content .= "      <nmwgtopo3:longitude>".$node->{"longitude"}."</nmwgtopo3:longitude>\n";
		}
		if (defined $node->{"institution"} and $node->{"institution"} ne "") {
		$content .= "      <nmwgtopo3:institution>".$node->{"institution"}."</nmwgtopo3:institution>\n";
		}

		$content .= "    </nmwgtopo3:node>\n";
		$content .= "  </nmwg:subject>\n";
		$content .= "</nmwg:metadata>\n";
	}

	return $content;
}

sub outputCircuits($) {
	my ($circuits) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my $content = "";

	my $i = 0;

	foreach my $circuit (@{ $circuits }) {
		my $mdid = "metadata.".genuid();

		$content .= "<nmwg:metadata id=\"$mdid\">\n";
		$content .= "  <nmwg:subject id=\"sub$i\">\n";
		$content .= "    <nmtl2:link >\n";
		$content .= "      <nmtl2:name type=\"logical\">".$circuit->{"name"}."</nmtl2:name>\n";
		$content .= "      <nmtl2:globalName type=\"logical\">".$circuit->{"globalName"}."</nmtl2:globalName>\n";
		$content .= "      <nmtl2:type>".$circuit->{"type"}."</nmtl2:type>\n";
		foreach my $endpoint (@{ $circuit->{"endpoints"} }) {
			$content .= "      <nmwgtopo3:node nodeIdRef=\"".$endpoint->{"node"}->{"name"}."\">\n";
			$content .= "        <nmwgtopo3:role>".$endpoint->{"type"}."</nmwgtopo3:role>\n";
			$content .= "      </nmwgtopo3:node>\n";
		}
		$content .= "    </nmtl2:link>\n";
		$content .= "  </nmwg:subject>\n";
		$content .= "  <nmwg:parameters>\n";
		$content .= "    <nmwg:parameter name=\"supportedEventType\">Path.Status</nmwg:parameter>\n";
		$content .= "  </nmwg:parameters>\n";
		$content .= "</nmwg:metadata>\n";

		$content .= "<nmwg:data id=\"data$i\" metadataIdRef=\"$mdid\">\n";
		$content .= "  <ifevt:datum timeType=\"unix\" timeValue=\"".$circuit->{"time"}."\">\n";
		$content .= "    <ifevt:stateAdmin>".$circuit->{"adminState"}."</ifevt:stateAdmin>\n";
		$content .= "    <ifevt:stateOper>".$circuit->{"operState"}."</ifevt:stateOper>\n";
		$content .= "  </ifevt:datum>\n";
		$content .= "</nmwg:data>\n";
		$i++;
	}

	return $content;
}

sub parseCircuitsFile($) {
	my ($file) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");

	my %nodes = ();
	my %incomplete_nodes = ();
	my %topology_links = ();
	my @links = ();

	my $parser = XML::LibXML->new();
	my $doc;
	eval {
		$doc = $parser->parse_file($file);
	};
	if ($@ or !defined $doc) {
		my $msg = "Couldn't parse links file $file: $@";
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

	foreach my $circuit ($conf->getChildrenByLocalName("circuit")) {
		my $global_name = findvalue($circuit, "globalName");
		my $local_name = findvalue($circuit, "localName");
		my $knowledge = $circuit->getAttribute("knowledge");

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

		my $prev_endpoint;

		foreach my $endpoint ($circuit->getChildrenByLocalName("endpoint")) {
			my $node_id = $endpoint->getAttribute("id");
			my $node_type = $endpoint->getAttribute("type");
			my $node_name = $endpoint->getAttribute("name");
			my $city = findvalue($endpoint, "city");
			my $country = findvalue($endpoint, "country");
			my $longitude = findvalue($endpoint, "longitude");
			my $institution = findvalue($endpoint, "institution");
			my $latitude = findvalue($endpoint, "latitude");

			if (!defined $node_type or $node_type eq "") {
				my $msg = "Node with unspecified type found";
				$logger->error($msg);
				return ("error.configuration", $msg);
			}

			if ((!defined $node_id or $node_id eq "") and (!defined $node_name or $node_name eq "")) {
				my $msg = "Node needs to have either a topology id or a name";
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

			if (defined $node_id and $node_id ne "" and defined $incomplete_nodes{"$node_id"}) {
				$new_node = $incomplete_nodes{"$node_id"};
			} elsif (defined $node_name and $node_name ne "" and defined $nodes{$node_name}) {
				$new_node = $nodes{"$node_name"};
			} elsif (defined $node_id and $node_id ne "" and defined $nodes{$node_id}) {
				$new_node = $nodes{"$node_id"};
			}

			$new_node->{"id"} = $node_id if (defined $node_id and $node_id ne "");
			$new_node->{"name"} = $node_name if (defined $node_name and $node_name ne "");
			$new_node->{"city"} = $city if (defined $city and $city ne "");
			$new_node->{"country"} = $country if (defined $country and $country ne "");
			$new_node->{"longitude"} = $longitude if (defined $longitude and $longitude ne "");
			$new_node->{"latitude"} = $latitude if (defined $latitude and $latitude ne "");
			$new_node->{"institution"} = $institution if (defined $institution and $institution ne "");

			if (defined $node_id and $node_id ne "") {
				if (!defined $new_node->{"name"} or !defined $new_node->{"city"}
					or !defined $new_node->{"country"} or !defined $new_node->{"longitude"}
					or !defined $new_node->{"latitude"} or !defined $new_node->{"institution"}) {
					$incomplete_nodes{"$node_id"} = $new_node;
				} elsif (defined $incomplete_nodes{"$node_id"}) {
					delete ($incomplete_nodes{"$node_id"});
				}
			}

			if (defined $new_node->{"name"}) {
				$nodes{$new_node->{"name"}} = $new_node;
			} else {
				$nodes{$new_node->{"id"}} = $new_node;
			}

			my %new_endpoint = ();

			$new_endpoint{"type"} = $node_type;
			$new_endpoint{"node"} = $new_node;

			push @endpoints, \%new_endpoint;

			$num_endpoints++;
		}

		if ($num_endpoints != 2) {
			my $msg = "Invalid number of endpoints, $num_endpoints, must be 2";
			$logger->error($msg);
			return ("error.configuration", $msg);
		}

		my %new_link = ();

		$new_link{"globalName"} = $global_name;
		$new_link{"name"} = $local_name;
		$new_link{"sublinks"} = \%sublinks;
		$new_link{"endpoints"} = \@endpoints;

		push @links, \%new_link;
	}

	return ("", $domain, \@links, \%incomplete_nodes, \%topology_links, \%nodes);
}

sub parseTopology($$$) {
	my ($topology, $nodes, $domain_name) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::CircuitStatus");
	my %ids = ();

	foreach my $node ($topology->getElementsByLocalName("node")) {
		my $id = $node->getAttribute("id");
		$logger->debug("node: ".$id);

		next if !defined $nodes->{$id};

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
		my $name = findvalue($node, "./*[local-name()='name']");
		$logger->debug("searched for name");

		$nodes->{$id}->{"type"} = "TopologyPoint";

		if (!defined $name and !defined $nodes->{$id}->{"name"}) {
			my $msg = "No name for node $id";
			$logger->error($msg);
			return ("error.ma", $msg);
		}

		if (!defined $nodes->{$id}->{"name"} or $nodes->{$id}->{"name"} ne "") {
			my $new_name = uc($name);
			$new_name =~ s/[^A-Z0-9_]//g;
			$nodes->{$id}->{"name"} = $domain_name."-".$new_name;
		}

		if (!defined $nodes->{$id}->{"longitude"} and defined $longitude and $longitude ne "") {
			# conversions may need to be made
			$nodes->{$id}->{"longitude"} = $longitude;
		}

		if (!defined $nodes->{$id}->{"latitude"} and defined $latitude and $latitude ne "") {
			# conversions may need to be made
			$nodes->{$id}->{"latitude"} = $latitude;
		}

		if (!defined $nodes->{$id}->{"institution"}) {
			if ( defined $institution and $institution ne "") {
				# conversions may need to be made
				$nodes->{$id}->{"institution"} = $institution;
			} else {
				$nodes->{$id}->{"institution"} = $domain_name;
			}
		}

		if (!defined $nodes->{$id}->{"city"} and defined $city and $city ne "") {
			$nodes->{$id}->{"city"} = $city;
		}

		if (!defined $nodes->{$id}->{"country"} and defined $country and $country ne "") {
			$nodes->{$id}->{"country"} = $country;
		}
	}

	foreach my $id (keys %{ $nodes }) {
		if (!defined $nodes->{$id}->{"name"}) {
			my $msg = "Lookup failed for node $id";
			$logger->error($msg);
			return ("error.ma", $msg);
		}
	}

	return ("", "");
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::CircuitStatus - A module that provides methods for an E2EMon Compatible MP.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

use perfSONAR_PS::MA::CircuitStatus;

my %conf = readConfiguration();

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtm => "http://ggf.org/ns/nmwg/time/2.0/",
		nmwgtopo3 => "http://ggf.org/ns/nmwg/topology/base/3.0/",
		nmtl2 => "http://ggf.org/ns/nmwg/topology/l2/3.0/",
		nmtl3 => "http://ggf.org/ns/nmwg/topology/l3/3.0/",
	 );

my $ma = perfSONAR_PS::MA::CircuitStatus->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::CircuitStatus->new;
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

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Transport>,
L<perfSONAR_PS::MA::Status::Client::MA>, L<perfSONAR_PS::MA::Topology::Client::MA>


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

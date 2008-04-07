package perfSONAR_PS::MP::Status;

use strict;
use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use Time::HiRes qw( gettimeofday );
use Module::Load;

use perfSONAR_PS::Transport;
use perfSONAR_PS::MP::Base;
use perfSONAR_PS::MP::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::Client::Status::MA;
use perfSONAR_PS::Status::Common;

use perfSONAR_PS::SNMPWalk;

our @ISA = qw(perfSONAR_PS::MP::Base);

my %link_prev_update_status = ();

sub init($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");

	$logger->debug("init()");

	if ($self->parseLinkFile != 0) {
		$logger->error("couldn't load links to measure");
		return -1;
	}

	if (defined $self->{CONF}->{"STATUS_MA_TYPE"}) {
		if (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "sqlite") {
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

			$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$file, $self->{CONF}->{"STATUS_MA_TABLE"});
		} elsif (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "ma") {
			load perfSONAR_PS::MA::Status::Client::SQL;

			if (!defined $self->{CONF}->{"STATUS_MA_URI"} or $self->{CONF}->{"STATUS_MA_URI"} eq "") {
				$logger->error("You specified to use an MA, but did not specify which one(STATUS_MA_URI)");
				return -1;
			}

			$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::MA($self->{CONF}->{"STATUS_MA_URI"});
		} elsif (lc($self->{CONF}->{"STATUS_MA_TYPE"}) eq "mysql") {
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

			$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL($dbi_string, $self->{CONF}->{"STATUS_MA_USERNAME"}, $self->{CONF}->{"STATUS_MA_PASSWORD"});
			if (!defined $self->{CLIENT}) {
				my $msg = "Couldn't create SQL client";
				$logger->error($msg);
				return (-1, $msg);
			}
		}
	} elsif (defined $self->{CONF}->{"STATUS_DB_TYPE"}) {
		if (lc($self->{CONF}->{"STATUS_DB_TYPE"}) eq "sqlite") {
			if (!defined $self->{CONF}->{"STATUS_DB_FILE"} or $self->{CONF}->{"STATUS_DB_FILE"} eq "") {
				$logger->error("You specified a SQLite Database, but then did not specify a database file(STATUS_DB_FILE)");
				return -1;
			}

			my $file = $self->{CONF}->{"STATUS_DB_FILE"};
			if (defined $self->{DIRECTORY}) {
				if (!($file =~ "^/")) {
					$file = $self->{DIRECTORY}."/".$file;
				}
			}

			$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$file, $self->{CONF}->{"STATUS_DB_TABLE"});
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
	} else {
		$logger->error("Need to specify a location to store the status reports");
		return -1;
	}

	my ($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open newly created client: $res";
		$logger->error($msg);
		return -1;
	}

	$self->{CLIENT}->close;

	return 0;
}

sub parseLinkFile($) {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");
	my $links_config;

	if (!defined $self->{CONF}->{"LINK_FILE_TYPE"} or $self->{CONF}->{"LINK_FILE_TYPE"} eq "") {
		$logger->error("no link file type specified");
		return -1;
	}

	if($self->{CONF}->{"LINK_FILE_TYPE"} eq "file") {
		if (!defined $self->{CONF}->{"LINK_FILE"} or $self->{CONF}->{"LINK_FILE"} eq "") {
			$logger->error("No link file specified");
			return -1;
		}

		my $file = $self->{CONF}->{"LINK_FILE"};
		if (defined $self->{DIRECTORY}) {
			if (!($file =~ "^/")) {
				$file = $self->{DIRECTORY}."/".$file;
			}
		}


		my $filedb = new perfSONAR_PS::DB::File( { file => $file });
		$filedb->openDB;
		$links_config = $filedb->getDOM();
	} else {
		$logger->error($self->{CONF}->{"LINK_FILE_TYPE"}." is not supported.");
		return -1;
	}

	my %links = ();

	foreach my $link ($links_config->getElementsByTagName("link")) {
		my $knowledge = $link->getAttribute("knowledge");

		if (!defined $knowledge) {
			$logger->error("It is not stated whether or knowledge is full or partial");
			return -1;
		}

		my %link_properties = ();
		my @link_agents = ();

		foreach my $agent ($link->getElementsByTagName("agent")) {
			my %link_agent = ();
			my ($oper_agent_ref, $admin_agent_ref);
			my $status;

			my %agents_info = ();

			my $oper_info = $agent->find('operStatus')->shift;
			if (defined $oper_info) {
				($status, $oper_agent_ref) = $self->readAgent($oper_info, "oper");
				if ($status != 0) {
					$logger->error("Problem parsing operational status agent for link");
					return -1;
				}

				$agents_info{"oper"} = $oper_agent_ref;
			}

			my $admin_info = $agent->find('adminStatus')->shift;
			if (defined $admin_info) {
				($status, $admin_agent_ref) = $self->readAgent($admin_info, "admin");
				if ($status != 0) {
					$logger->error("Problem parsing adminstrative status agent for link");
					return -1;
				}

				$agents_info{"admin"} = $admin_agent_ref;
			}

			if (!defined $agents_info{"admin"} and !defined $agents_info{"oper"}) {
				my $msg = "Empty agent specified for link";
				$logger->error($msg);
				return -1;
			}

			push @link_agents, \%agents_info;
		}

		if ($#link_agents == -1) {
			$logger->error("Didn't specify any agents for link");
			return -1;
		}

		$link_properties{"agents"} = \@link_agents;
		$link_properties{"knowledge"} = $knowledge;

		my $have_id;

		foreach my $id_elm ($link->getElementsByTagName("id")) {
			my $id = $id_elm->textContent;

			if (defined $links{"$id"}) {
				$logger->error("Attempting to redefine link $id");
				return -1;
			}
			
			$link_properties{"primary"} = $id;
			$links{"$id"} = \%link_properties;
			$have_id = 1;
		}

		if (!defined $have_id or $have_id != 1) {
			$logger->error("No ids associated with specified link");
			return -1;
		}
	}

	$self->{LINKS} = \%links;

	return 0;
}

sub readAgent($$$) {
	my ($self, $agent, $agent_type) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");

	$logger->debug("readAgent()");

	my %agent_info;

	my $type = $agent->findvalue('@type');
	if (!defined $type or $type eq "") {
		my $msg = "Agent has no type information";
		$logger->debug($msg);
		return (-1, $msg);
	} 

	if ($type eq "script") {
		my $script_name = $agent->findvalue("script_name");
		if (!defined $script_name or $script_name eq "") {
			my $msg = "Agent of type 'script' has no script name defined";
			$logger->debug($msg);
			return (-1, $msg);
		}

		if (defined $self->{DIRECTORY}) {
			if (!($script_name =~ "^/")) {
				$script_name = $self->{DIRECTORY}."/".$script_name;
			}
		}

		if (!-x $script_name) {
			my $msg = "Agent of type 'script' has non-executable script: \"$script_name\"";
			$logger->debug($msg);
			return (-1, $msg);
		}

		my $script_params = $agent->findvalue("script_parameters");

		$agent_info{"type"} = $type;
		$agent_info{"script"} = $script_name;
		if (defined $script_params and $script_params ne "") {
			$agent_info{"parameters"} = $script_params;
		}
	} elsif ($type eq "constant") {
		my $value = $agent->findvalue("constant");
		if (!defined $value or $value eq "") {
			my $msg = "Agent of type 'constant' has no value defined";
			$logger->debug($msg);
			return (-1, $msg);
		}

		$agent_info{"type"} = $type;
		$agent_info{"constant"} = $value;
	} elsif ($type eq "snmp") {
		my $oid = $agent->findvalue("oid");
		if (!defined $oid or $oid eq "") {
			if ($agent_type eq "oper") {
				$oid = "1.3.6.1.2.1.2.2.1.8";
			} elsif ($agent_type eq "admin") {
				$oid = "1.3.6.1.2.1.2.2.1.7";
			}
		}

		my $hostname = $agent->findvalue('hostname');
		if (!defined $hostname or $hostname eq "") {
			my $msg = "Agent of type 'SNMP' has no hostname";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $ifName = $agent->findvalue('ifName');
		my $ifIndex = $agent->findvalue('ifIndex');

		if ((!defined $ifIndex or $ifIndex eq "") and (!defined $ifName or $ifName eq "")) {
			my $msg = "Agent of type 'SNMP' has no name or index specified";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $version = $agent->findvalue("version");
		if (!defined $version or $version eq "") {
			my $msg = "Agent of type 'SNMP' has no snmp version";
			$logger->error($msg);
			return (-1, $msg);
		}

		my $community = $agent->findvalue("community");
		if (!defined $community or $community eq "") {
			my $msg = "Agent of type 'SNMP' has no community string";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (!defined $self->{AGENT}->{$hostname}) {
			$self->{AGENT}->{$hostname} = new perfSONAR_PS::MP::Status::SNMPAgent( $hostname, "" , $version, $community, "");
		}

		if (!defined $ifIndex or $ifIndex eq "") {
			$logger->debug("Looking up $ifName from $hostname");

			my ($status, $res) = snmpwalk($hostname, undef, "1.3.6.1.2.1.31.1.1.1.1", $community, $version);
			if ($status != 0) {
				my $msg = "Error occurred while looking up ifIndex for specified ifName $ifName: $res";
				$logger->error($msg);
				return (-1, $msg);
			}

			foreach my $oid_ref ( @{ $res } ) {
				my $oid = $oid_ref->[0];
				my $type = $oid_ref->[1];
				my $value = $oid_ref->[2];

				$logger->debug("$oid = $type: $value($ifName)");
				if ($value eq $ifName) {
					if ($oid =~ /1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.(\d+)/) {
						$ifIndex = $1;
					}
				}
			}

			if (!defined $ifIndex or $ifIndex eq "") {
				my $msg = "Didn't find ifName $ifName in host $hostname";
				$logger->error($msg);
				return (-1, $msg);
			}
		}

		$self->{AGENT}->{$hostname}->addVariable($oid.".".$ifIndex);

		$agent_info{"type"} = $type;
		$agent_info{"oid"} = $oid;
		$agent_info{"hostname"} = $hostname;
		$agent_info{"index"} = $ifIndex;
		$agent_info{"version"} = $version;
		$agent_info{"community"} = $community;
		$agent_info{"snmp_agent"} = $self->{AGENT}->{$hostname};
	} else {
		my $msg = "Unknown agent type: \"$type\"";
		$logger->error($msg);
		return (-1, $msg);
	}

	# here is where we could pull in the possibility of a mapping from the
	# output of the SNMP/script/whatever to "up, down, degraded, unknown"

	$agent_info{"status_type"} = $agent_type;

	return (0, \%agent_info);
}

sub runAgent($$) {
	my ($self, $agent_ref) = @_;
	my %agent = %{ $agent_ref };
	my $logger = get_logger("perfSONAR_PS::MP::Status");
	my ($measurement_time, $measurement_value);

	$logger->debug("runAgent()");

	if ($agent{'type'} eq "none") {
		return (0, "", "unknown");
	} elsif ($agent{'type'} eq "script") {
		my $cmd .= $agent{'script'}." ".$agent{'status_type'};

		if (defined $agent{'parameters'}) {
			$cmd .= " ".$agent{'parameters'};
		}

		$logger->debug("cmd: $cmd");

		open(SCRIPT, $cmd . " |");
		my @lines = <SCRIPT>;
		close(SCRIPT);

		if ($#lines < 0) {
			my $msg = "script returned no output";
			$logger->error($msg);
			return (-1, $msg);
		}

		if ($#lines > 0) {
			my $msg = "script returned invalid output: more than one line";
			$logger->error($msg);
			return (-1, $msg);
		}

		chomp($lines[0]);
		($measurement_time, $measurement_value) = split(',', $lines[0]);

		$logger->debug("Script returned: ".$lines[0]);

		if (!defined $measurement_time or $measurement_time eq "") {
 			my $msg = "script returned invalid output: does not contain measurement time";
			$logger->error($msg);
			return (-1, $msg);
		}

		if (!defined $measurement_value or $measurement_value eq "") {
 			my $msg = "script returned invalid output: does not contain link status";
			$logger->error($msg);
			return (-1, $msg);
		}

		$measurement_value = lc($measurement_value);

		if ($agent{'status_type'} eq "oper") {
			if (isValidOperState($measurement_value) == 0) {
				$logger->warn("Unknown operational state: \"$measurement_value\", setting to \"unknown\"");
				$measurement_value = "unknown";
			}
		} else {
			if (isValidAdminState($measurement_value) == 0) {
				$logger->warn("Unknown administrative state: \"$measurement_value\", setting to \"unknown\"");
				$measurement_value = "unknown";
			}
		}
	} elsif ($agent{'type'} eq "constant") {
		$measurement_value = $agent{'constant'};
		$measurement_time = time;
	} elsif ($agent{'type'} eq "snmp") { # SNMP
		$agent{'snmp_agent'}->setSession;
		$measurement_value = $agent{'snmp_agent'}->getVar($agent{'oid'}.".".$agent{'index'});
		$measurement_time = $agent{'snmp_agent'}->getHostTime;
		$agent{'snmp_agent'}->closeSession;

		if (defined $measurement_value) {
			if ($agent{'oid'} eq "1.3.6.1.2.1.2.2.1.8") {
				if ($measurement_value eq "2") {
					$measurement_value = "down";
				} elsif ($measurement_value eq "1") {
					$measurement_value = "up";
				} else {
					$measurement_value = "unknown";
				}
			} elsif ($agent{'oid'} eq "1.3.6.1.2.1.2.2.1.7") {
				if ($measurement_value eq "2") {
					$measurement_value = "down";
				} elsif ($measurement_value eq "1") {
					$measurement_value = "normaloperation";
				} elsif ($measurement_value eq "3") {
					$measurement_value = "troubleshooting";
				} else {
					$measurement_value = "unknown";
				}
			} else {
				# XXX I'm not sure what they actually spit out here...we may need a mapping...
			}
		}
	} else {
		my $msg;
		$msg = "got an unknown method for obtaining the operational status: ".$agent{'type'};
		$logger->error($msg);
		return (-1, $msg);
	}

	if (!defined $measurement_value or $measurement_value eq "") {
		my $msg = "Received no measurement value";
		$logger->error($msg);
		return (-1, $msg);
	}

	if (!defined $measurement_time or $measurement_time eq "") {
		my $msg = "Received no measurement time";
		$logger->error($msg);
		return (-1, $msg);
	}

	return (0, $measurement_time, $measurement_value);
}

sub collectLinkMeasurements($$) {
	my($self, $link_id) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");

	$logger->debug("collectLinkMeasurements()");

	my $link_oper_value = "unknown";
	my $link_admin_value = "unknown";
	my $set_oper_value = 0;
	my $oper_time = time;
	my $admin_time = time;
	my %link_properties = %{ $self->{LINKS}->{$link_id} };

	foreach my $agent_ref (@{ $link_properties{"agents"} }) {
		my $oper_value = "";
		my $admin_value = "";
		my ($status, $oper_time, $admin_time);
		my %agent = %{ $agent_ref };

		if (defined $agent{"admin"}) {
			$logger->debug("Grabbing admin information");

			($status, $admin_time, $admin_value) = $self->runAgent($agent{"admin"});
			if ($status != 0) {
				$logger->error("Couldn't run administrative agent on link $link_id");
				return (-1, $oper_time);
			}

			if ($link_admin_value eq "maintenance" or $admin_value eq "maintenance") {
				$link_admin_value = "maintenance";
			} elsif ($link_admin_value eq "troubleshooting" or $admin_value eq "troubleshooting") {
				$link_admin_value = "troubleshooting";
			} elsif ($link_admin_value eq "underrepair" or $admin_value eq "underrepair") {
				$link_admin_value = "underrepair";
			} elsif ($link_admin_value eq "normaloperation" or $admin_value eq "normaloperation") {
				$link_admin_value = "normaloperation";
			} else {
				$link_admin_value = "unknown";
			}
		}

		if (defined $agent{"oper"}) {
			($status, $oper_time, $oper_value) = $self->runAgent($agent{"oper"});
			if ($status != 0) {
				$logger->error("Couldn't run operation agent on link $link_id");
				return (-1, $oper_time);
			}

			if ($link_oper_value eq "down" or $oper_value eq "down")  {
				$link_oper_value = "down";
			} elsif ($link_oper_value eq "degraded" or $oper_value eq "degraded")  {
				$link_oper_value = "degraded";
			} elsif ($link_oper_value eq "up" or $oper_value eq "up")  {
				$link_oper_value = "up";
			} else {
				$link_oper_value = "unknown";
			}
		}

		if (!defined $oper_time or $oper_time eq "") {
			$oper_time = time; # substitute the MPs time since we don't know the agent's time
		}

		if (!defined $admin_time or $admin_time eq "") {
			$admin_time = time; # substitute the MPs time since we don't know the agent's time
		}
	}

	return (0, $oper_time, $link_oper_value, $admin_time, $link_admin_value);
}

sub collectMeasurements($$) {
	my($self, $interval_number) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");
	my ($status, $res);

	$logger->debug("collectMeasurements()");

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $link_id (keys %{$self->{LINKS}}) {
		my ($oper_time, $link_oper_value, $admin_time, $link_admin_value, $do_update);

		my $link = $self->{LINKS}->{$link_id};

		next if ($link_id ne $self->{LINKS}->{$link_id}->{"primary"});

		($status, $oper_time, $link_oper_value, $admin_time, $link_admin_value) = $self->collectLinkMeasurements($link_id);

		if ($status != 0) {
			$link->{"primary_results"}->{"success"} = 0;
			$logger->warn("Couldn't get information on link $link_id");
			next;
		}

		# cache the results
		$link->{"primary_results"}->{"success"} = 1;
		$link->{"primary_results"}->{"oper_time"} = $oper_time;
		$link->{"primary_results"}->{"oper_value"} = $link_oper_value;
		$link->{"primary_results"}->{"admin_time"} = $admin_time;
		$link->{"primary_results"}->{"admin_value"} = $link_admin_value;

		if (defined $link_prev_update_status{$link_id} and $link_prev_update_status{$link_id} == 0) {
			$do_update = 1;
		} else {
			$do_update = 0;
		}

		($status, $res) = $self->{CLIENT}->updateLinkStatus($oper_time, $link_id, $self->{LINKS}->{$link_id}->{"knowledge"}, $link_oper_value, $link_admin_value, $do_update);
		if ($status != 0) {
			$logger->error("Couldn't store link status for link $link_id: $res");
		}

		$link_prev_update_status{$link_id} = $status;
	}

	foreach my $link_id (keys %{$self->{LINKS}}) {
		my ($oper_time, $link_oper_value, $admin_time, $link_admin_value, $do_update);

		next if ($link_id eq $self->{LINKS}->{$link_id}->{"primary"});

		my $link = $self->{LINKS}->{$link_id};

		next if ($link->{"primary_results"}->{"success"} == 0);

		# use the cached the results
		$oper_time = $link->{"primary_results"}->{"oper_time"};
		$link_oper_value = $link->{"primary_results"}->{"oper_value"};
		$admin_time = $link->{"primary_results"}->{"admin_time"};
		$link_admin_value = $link->{"primary_results"}->{"admin_value"};

		if (defined $link_prev_update_status{$link_id} and $link_prev_update_status{$link_id} == 0) {
			$do_update = 1;
		}

		($status, $res) = $self->{CLIENT}->updateLinkStatus($oper_time, $link_id, $self->{LINKS}->{$link_id}->{"knowledge"}, $link_oper_value, $link_admin_value, $do_update);
		if ($status != 0) {
			$logger->error("Couldn't store link status for link $link_id: $res");
		}

		$link_prev_update_status{$link_id} = $status;
	}
}

# ================ Internal Package perfSONAR_PS::MP::Status::SNMPAgent ================

package perfSONAR_PS::MP::Status::SNMPAgent;

use Net::SNMP;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;

sub new {
	my ($package, $host, $port, $ver, $comm, $vars, $cache_length) = @_;
	my %hash = ();

	if(defined $host and $host ne "") {
		$hash{"HOST"} = $host;
	}
	if(defined $port and $port ne "") {
		$hash{"PORT"} = $port;
	} else {
		$hash{"PORT"} = 161;
	}
	if(defined $ver and $ver ne "") {
		$hash{"VERSION"} = $ver;
	}
	if(defined $comm and $comm ne "") {
		$hash{"COMMUNITY"} = $comm;
	}
	if(defined $vars and $vars ne "") {
		$hash{"VARIABLES"} = \%{$vars};
	} else {
		$hash{"VARIABLES"} = ();
	}
	if (defined $cache_length and $cache_length ne "") {
		$hash{"CACHE_LENGTH"} = $cache_length;
	} else {
		$hash{"CACHE_LENGTH"} = 1;
	}

	$hash{"VARIABLES"}->{"1.3.6.1.2.1.1.3.0"} = ""; # add the host ticks so we can track it
	$hash{"HOSTTICKS"} = 0;

	bless \%hash => $package;
}

sub setHost {
	my ($self, $host) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $host and $host ne "") {
		$self->{HOST} = $host;
		$self->{HOSTTICKS} = 0;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setPort {
	my ($self, $port) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $port and $port ne "") {
		$self->{PORT} = $port;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setVersion {
	my ($self, $ver) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $ver and $ver ne "") {
		$self->{VERSION} = $ver;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setCommunity {
	my ($self, $comm) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $comm and $comm ne "") {
		$self->{COMMUNITY} = $comm;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setVariables {
	my ($self, $vars) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $vars and $vars ne "") {
		$self->{"VARIABLES"} = \%{$vars};
	} else {
		$logger->error("Missing argument.");
	}
	return;
}

sub setCacheLength($$) {
	my ($self, $cache_length) = @_;

	if (defined $cache_length and $cache_length ne "") {
		$self->{"CACHE_LENGTH"} = $cache_length;
	}
}

sub addVariable {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(!defined $var or $var eq "") {
		$logger->error("Missing argument.");
	} else {
		$self->{VARIABLES}->{$var} = "";
	}
	return;
}

sub getVar {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(!defined $var or $var eq "") {
		$logger->error("Missing argument.");
		return undef;
	} 

	if (!defined $self->{VARIABLES}->{$var} || !defined $self->{CACHED_TIME} || time() - $self->{CACHED_TIME} > $self->{CACHE_LENGTH}) {
		$self->{VARIABLES}->{$var} = "";

		my ($status, $res) = $self->collectVariables();
		if ($status != 0) {
			return undef;
		}

		my %results = %{ $res };

		$self->{CACHED} = \%results;
		$self->{CACHED_TIME} = time();
	}

	return $self->{CACHED}->{$var};
}

sub getHostTime {
	my ($self) = @_;
	return $self->{REFTIME};
}

sub refreshVariables {
	my ($self) = @_;
	my ($status, $res) = $self->collectVariables();

	if ($status != 0) {
		return;
	}

	my %results = %{ $res };

	$self->{CACHED} = \%results;
	$self->{CACHED_TIME} = time();
}

sub getVariableCount {
	my ($self) = @_;

	my $num = 0;
	foreach my $oid (keys %{$self->{VARIABLES}}) {
		$num++;
	}
	return $num;
}

sub removeVariables {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	undef $self->{VARIABLES};
	if(defined $self->{VARIABLES}) {
		$logger->error("Remove failure.");
	}
	return;
}

sub removeVariable {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $var and $var ne "") {
		delete $self->{VARIABLES}->{$var};
	} else {
		$logger->error("Missing argument.");
	}
	return;
}

sub setSession {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if((defined $self->{COMMUNITY} and $self->{COMMUNITY} ne "") and
			(defined $self->{VERSION} and $self->{VERSION} ne "") and
			(defined $self->{HOST} and $self->{HOST} ne "") and
			(defined $self->{PORT} and $self->{PORT} ne "")) {

		($self->{SESSION}, $self->{ERROR}) = Net::SNMP->session(
									-community     => $self->{COMMUNITY},
									-version       => $self->{VERSION},
									-hostname      => $self->{HOST},
									-port          => $self->{PORT},
									-translate     => [
									-timeticks => 0x0
									]) or $logger->error("Couldn't open SNMP session to \"".$self->{HOST}."\".");

		if(!defined($self->{SESSION})) {
			$logger->error("SNMP error: ".$self->{ERROR});
		}
	}
	else {
		$logger->error("Session requires arguments 'host', 'version', and 'community'.");
	}
	return;
}

sub closeSession {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $self->{SESSION}) {
		$self->{SESSION}->close;
	} else {
		$logger->error("Cannont close undefined session.");
	}
	return;
}

sub collectVariables {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $self->{SESSION}) {
		my @oids = ();

		foreach my $oid (keys %{$self->{VARIABLES}}) {
			push @oids, $oid;
		}

		my $res = $self->{SESSION}->get_request(-varbindlist => \@oids) or $logger->error("SNMP error.");

		if(!defined($res)) {
			my $msg = "SNMP error: ".$self->{SESSION}->error;
			$logger->error($msg);
			return (-1, $msg);
		} else {
			my %results;

			%results = %{ $res };

			if (!defined $results{"1.3.6.1.2.1.1.3.0"}) {
				$logger->warn("No time values, getTime may be screwy");
			} else {
				my $new_ticks = $results{"1.3.6.1.2.1.1.3.0"} / 100;

				if ($self->{HOSTTICKS} == 0) {
					my($sec, $frac) = Time::HiRes::gettimeofday;
					$self->{REFTIME} = $sec.".".$frac;
				} else {
					$self->{REFTIME} += $new_ticks - $self->{HOSTTICKS};
				}

				$self->{HOSTTICKS} = $new_ticks;
			}

			return (0, $res);
		}
	} else {
		my $msg = "Session to \"".$self->{HOST}."\" not found.";
		$logger->error($msg);
		return (-1, $msg);
	}
}

sub collect {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status::SNMPAgent");

	if(defined $var and $var ne "") {
		if(defined $self->{SESSION}) {
			my $results = $self->{SESSION}->get_request(-varbindlist => [$var]) or $logger->error("SNMP error: \"".$self->{ERROR}."\".");
			if(!defined($results)) {
				$logger->error("SNMP error: \"".$self->{ERROR}."\".");
				return -1;
			} else {
				return $results->{"$var"};
			}
		} else {
			$logger->error("Session to \"".$self->{HOST}."\" not found.");
			return -1;
		}
	} else {
		$logger->error("Missing argument.");
	}
	return;
}

1;

__END__


=head1 NAME

perfSONAR_PS::MP::Status - A module that will collect link status information and
store the results into a Link Status MA.

=head1 DESCRIPTION

This module loads a set of links and can be used to collect status information
on those links and store the results into a Link Status MA.

=head1 SYNOPSIS

=head1 DETAILS

This module is meant to be used to periodically collect information about Link
Status. It can do this by running scripts or consulting SNMP servers directly.
It reads a configuration file that contains the set of links to track. It can
then be used to periodically obtain the status and then store the results into
a measurement archive. 

It includes a submodule SNMPAgent that provides a caching SNMP poller allowing
easier interaction with SNMP servers.

=head1 API

=head2 init($self)
	This function initializes the collector. It returns 0 on success and -1
	on failure.

=head2 collectLinkMeasurements($self, $link_id)
	This function can be called by external users to collect and store the
	status of a single link.

=head2 collectMeasurements($self, $interval_number)
	This function is called by external users to collect and store the
	status for all links.

=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, E<lt>aaron@internet2.eduE<gt>, Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

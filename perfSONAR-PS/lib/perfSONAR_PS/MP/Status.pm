#!/usr/bin/perl -w

package perfSONAR_PS::MP::Status;

use strict;
use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);
use Data::Dumper;
use Time::HiRes qw( gettimeofday );

use perfSONAR_PS::Transport;
use perfSONAR_PS::MP::Base;
use perfSONAR_PS::MP::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::MA::Status::Client::SQL;
use perfSONAR_PS::MA::Status::Client::MA;

our @ISA = qw(perfSONAR_PS::MP::Base);

sub init($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");

	$logger->debug("init()");

	if ($self->parseLinkFile != 0) {
		$logger->error("couldn't load links to measure");
		return -1;
	}

	if (!defined $self->{CONF}->{"STATUS_MA_TYPE"} or $self->{CONF}->{"STATUS_MA_TYPE"} eq "") {
		$logger->error("No status MA type specified");
		return -1;
	}

	if ($self->{CONF}->{"STATUS_MA_TYPE"} eq "SQLite") {
		if (!defined $self->{CONF}->{"STATUS_MA_FILE"} or $self->{CONF}->{"STATUS_MA_FILE"} eq "") {
			$logger->error("You specified a SQLite Database, but then did not specify a database file(STATUS_MA_FILE)");
			return -1;
		}

		$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::SQL("DBI:SQLite:dbname=".$self->{CONF}->{"STATUS_MA_FILE"}, $self->{CONF}->{"STATUS_MA_TABLE"});
	} elsif ($self->{CONF}->{"STATUS_MA_TYPE"} eq "MA") {
		if (!defined $self->{CONF}->{"STATUS_MA_URI"} or $self->{CONF}->{"STATUS_MA_URI"} eq "") {
			$logger->error("You specified to use an MA, but did not specify which one(STATUS_MA_URI)");
			return -1;
		}

		$self->{CLIENT} = new perfSONAR_PS::MA::Status::Client::MA($self->{CONF}->{"STATUS_MA_URI"});
	} elsif ($self->{CONF}->{"STATUS_MA_TYPE"} eq "MySQL") {
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
	} else {
		$logger->error("Invalid status MA type specified");
		return -1;
	}

	return 0;
}

sub parseLinkFile($) {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MP::Status");
	my $links_config;

	$logger->debug("parseLinkFile()");

	if (!defined $self->{CONF}->{"LINK_FILE_TYPE"} or $self->{CONF}->{"LINK_FILE_TYPE"} eq "") {
		$logger->error("no link file type specified");
		return -1;
	}

	if($self->{CONF}->{"LINK_FILE_TYPE"} eq "file") {
		if (!defined $self->{CONF}->{"LINK_FILE"} or $self->{CONF}->{"LINK_FILE"} eq "") {
			$logger->error("No link file specified");
			return -1;
		}

		my $filedb = new perfSONAR_PS::DB::File($self->{CONF}->{"LINK_FILE"});
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

		my $ifIndex = $agent->findvalue('ifIndex');
		if (!defined $ifIndex or $ifIndex eq "") {
			my $msg = "Agent of type 'SNMP' has no index specified";
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
		my $cmd = $agent{'script'};
		if (defined $agent{'parameters'}) {
			$cmd .= " ".$agent{'parameters'};
		}

		$logger->debug("cmd: $cmd");

		open(SCRIPT, $cmd . " |");
		my @lines = <SCRIPT>;
		close(SCRIPT);

		if ($#lines == 0) {
			chomp($lines[0]);
			my ($time, $status) = split(',', $lines[0]);
			if (lc($status) ne "up" and lc($status) ne "degraded" and lc($status) ne "down") {
				$measurement_value = "unknown";
			} else {
				$measurement_value = lc($status);
			}
			$measurement_time = $time;
		} else {
			my $msg = "script returned invalid output: more than one line";
			$logger->error($msg);
			return (-1, $msg);
		}
	} elsif ($agent{'type'} eq "constant") {
		$measurement_value = $agent{'constant'};
		$measurement_time = time;
	} elsif ($agent{'type'} eq "snmp") { # SNMP
		$agent{'snmp_agent'}->setSession;
		$measurement_value = $agent{'snmp_agent'}->getVar($agent{'oid'}.".".$agent{'index'});
		$measurement_time = $agent{'snmp_agent'}->getHostTime;
		$agent{'snmp_agent'}->closeSession;

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

	} else {
		my $msg;
		$msg = "got an unknown method for obtaining the operational status: ".$agent{'type'};
		$logger->error($msg);
		return (-1, $msg);
	}

	$logger->info("Measurement Value: $measurement_value");
	$logger->info("Measurement Time: $measurement_time");

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

	my $do_update = 0;

	$do_update = 1 if ($interval_number > 0);

	($status, $res) = $self->{CLIENT}->open;
	if ($status != 0) {
		my $msg = "Couldn't open connection to database: $res";
		$logger->error($msg);
		return (-1, $msg);
	}

	foreach my $link_id (keys %{$self->{LINKS}}) {
		my ($oper_time, $link_oper_value, $admin_time, $link_admin_value);

		my $link = $self->{LINKS}->{$link_id};

		next if ($link_id ne $self->{LINKS}->{$link_id}->{"primary"});

		($status, $oper_time, $link_oper_value, $admin_time, $link_admin_value) = $self->collectLinkMeasurements($link_id);

		if ($status != 0) {
			$logger->error("Couldn't get information on link $link_id");
			return (-1, $oper_time);
		}

		# cache the results
		$link->{"primary_results"}->{"oper_time"} = $oper_time;
		$link->{"primary_results"}->{"oper_value"} = $link_oper_value;
		$link->{"primary_results"}->{"admin_time"} = $admin_time;
		$link->{"primary_results"}->{"admin_value"} = $link_admin_value;

		($status, $res) = $self->{CLIENT}->updateLinkStatus($oper_time, $link_id, $self->{LINKS}->{$link_id}->{"knowledge"}, $link_oper_value, $link_admin_value, $do_update);
		if ($status != 0) {
			$logger->error("Couldn't store link status for link $link_id: $res");
		}
	}

	foreach my $link_id (keys %{$self->{LINKS}}) {
		my ($oper_time, $link_oper_value, $admin_time, $link_admin_value);

		next if ($link_id eq $self->{LINKS}->{$link_id}->{"primary"});

		my $link = $self->{LINKS}->{$link_id};

		# use the cached the results
		$oper_time = $link->{"primary_results"}->{"oper_time"};
		$link_oper_value = $link->{"primary_results"}->{"oper_value"};
		$admin_time = $link->{"primary_results"}->{"admin_time"};
		$link_admin_value = $link->{"primary_results"}->{"admin_value"};

		($status, $res) = $self->{CLIENT}->updateLinkStatus($oper_time, $link_id, $self->{LINKS}->{$link_id}->{"knowledge"}, $link_oper_value, $link_admin_value, $do_update);
		if ($status != 0) {
			$logger->error("Couldn't store link status for link $link_id: $res");
		}
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
		my %results = %{ $self->collectVariables() };
		if (defined $results{"error"} and $results{"error"} ne "") {
			return undef;
		}

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
	my %results = $self->collectVariables();

	if (defined $results{"error"} and $results{"error"} ne "") {
		return;
	}

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

		$logger->info(join(', ', @oids));

		my $res = $self->{SESSION}->get_request(-varbindlist => \@oids) or $logger->error("SNMP error.");

		if(!defined($res)) {
			$logger->error("SNMP error: ".$self->{SESSION}->error);
			return ('error' => -1);
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

			return $res;
		}
	} else {
		$logger->error("Session to \"".$self->{HOST}."\" not found.");
		return ('error' => -1);
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

perfSONAR_PS::MP::Status - A module that provides methods for creating structures to gather
and store data from SNMP sources.  The submodule, 'perfSONAR_PS::MP::Status::SNMPAgent', is
responsible for the polling of SNMP data from a resource.

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to poll SNMP data from a specific resource.  The objects can then be re-used with minimal
effort.

=head1 SYNOPSIS

use perfSONAR_PS::MP::Status;
use Time::HiRes qw( gettimeofday );

my %conf = ();
$conf{"METADATA_DB_TYPE"} = "xmldb";
$conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
$conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
$conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
$conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
		nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
		snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"
	 );

my $mp = new perfSONAR_PS::MP::Status(\%conf, \%ns, "", "");
$mp->load_measurement_info;
$mp->prepareData;
$mp->prepareCollectors;

my($sec, $frac) = Time::HiRes::gettimeofday;
$mp->prepareTime($sec.".".$frac);

$mp->collectMeasurements;

=head1 DETAILS

The Net::SNMP API is rich with features, and does offer lots of functionality we choose not
to re-package here.  perfSONAR-PS for the most part is not interested in writing SNMP data,
   and currently only supports versions 1 and 2 of the spec.  As such we only provide simple
   methods that accomplish our goals.  We do recognize the importance of these other functions,
   and they may be provided in the future.

   This module contains a submodule that is not meant to act as a standalone, but rather as
   a specialized structure for use only in this module.  The functions include:


new($log, $host, $port, $version, $community, \%variables)

	The 'log' argument is the name of the log file where error or warning information may be
	recorded.  The second argument is a string representing the 'host' from which to collect
	SNMP data.  The third argument is a numerical 'port' number (will default to 161 if unset).
	It is also possible to supply the port number via the host name, as in 'hostname:port'.
	The fourth argument, 'version', is a string that represents the version of snmpd that is
	running on the target host, currently this module supports versions 1 and 2 only.  The
	fifth argument is a string representing the 'community' that allows snmp reading on the
	target host.  The final argument is a hash of oids representing the variables to be
	polled from the target.  All of these arguments are optional, and may be set or
	re-set with the other functions.

setLog($log)

	(Re-)Sets the log file for the SNMP object.

setHost($host)

	(Re-)Sets the target host for the SNMP object.

setPort($port)

	(Re-)Sets the port for the target host on the SNMP object.

setVersion($version)

	(Re-)Sets the version of snmpd running on the target host.

setCommunity($community)

	(Re-)Sets the community that snmpd is allowing ot be read on the target host.

setSession()

	Establishes a connection to the target host with the supplied information.  It is
	necessary to have the host, community, and version set for this to work; port will
	default to 161 if unset.  If changes are made to any of the above variables, the
	session will need to be re-set from this function

setVariables(\%variables)

	Passes a hash of 'oid' encoded variables to the object; these oids will be used
	when the 'collectVariables' routine is called to gather the proper values.

addVariable($variable)

	Adds $variable to the hash of oids to be collected when the 'collectVariables'
	routine is called.

removeVariables()

	Removes all variables from the hash of oids.

removeVariable($variable)

	Removes $variable from the hash of oids to be collected when the 'collectVariables'
	routine is called.

collectVariables()

	Collects all variables from the target host that are specified in the hash of oids.  The
	results are returned in a hash with keys representing each oid.  Will return -1
	on error.

collect($variable)

	Collects the oid represented in $variable, and returns this value.  Will return -1
	on error.

closeSession()

	Closes the session to the target host.

error($msg, $line)	

	A 'message' argument is used to print error information to the screen and log files
	(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.
	Meant to be used internally.

	A brief description using the API:


	my %vars = (
			'.1.3.6.1.2.1.2.2.1.10.2' => ""
		   );

	my $snmp = new perfSONAR_PS::MP::Status::SNMPAgent(
			"./error.log", "lager", 161, "1", "public",
			\%vars
			);

# or also:
#
# my $snmp = new perfSONAR_PS::MP::Status::SNMPAgent;
# $snmp->setLog("./error.log");
# $snmp->setHost("lager");
# $snmp->setPort(161);
# $snmp->setVersion("1");
# $snmp->setCommunity("public");
# $snmp->setVariables(\%vars);

	$snmp->setSession;

	my $single_result = $snmp->collect(".1.3.6.1.2.1.2.2.1.16.2");

	$snmp->addVariable(".1.3.6.1.2.1.2.2.1.16.2");

	my %results = $snmp->collectVariables;
	foreach my $var (sort keys %results) {
		print $var , "\t-\t" , $results{$var} , "\n";
	}

$snmp->removeVariable(".1.3.6.1.2.1.2.2.1.16.2");

# to remove ALL variables
#
# $snmp->removeVariables;

$snmp->closeSession;


=head1 API

The offered API is simple, but offers the key functions we need in a measurement point.

=head2 new(\%conf, \%ns, $store)

	The first argument represents the 'conf' hash from the calling MP.  The second argument
	is a hash of namespace values.  The final value is an LibXML DOM object representing
	a store.

=head2 setConf(\%conf)

	(Re-)Sets the value for the 'conf' hash.

=head2 setNamespaces(\%ns)

	(Re-)Sets the value for the 'namespace' hash.

=head2 setStore($store)

	(Re-)Sets the value for the 'store' object, which is really just a XML::LibXML::Document

=head2 load_measurement_info()

	Parses the metadata database (specified in the 'conf' hash) and loads the values for the
	data and metadata objects.

=head2 prepareData()

	Prepares data db objects that relate to each of the valid data values in the data object.

=head2 prepareCollectors()

	Prepares the 'perfSONAR_PS::MP::Status::SNMPAgent' objects for each of the metadata values in
	the metadata object.

=head2 prepareTime($time)

	Starts the objects that will keep track of time (in relation to the remote sites).

=head2 collectMeasurements()

	Cycles through each of the 'perfSONAR_PS::MP::Status::SNMPAgent' objects and gathers the
	necessary values.

	=head1 SEE ALSO

	L<Net::SNMP>, L<perfSONAR_PS::MP::Base>,  L<perfSONAR_PS::MP::General>,
	L<perfSONAR_PS::Common>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>,
	L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>, L<XML::LibXML>

	To join the 'perfSONAR-PS' mailing list, please visit:

	https://mail.internet2.edu/wws/info/i2-perfsonar

	The perfSONAR-PS subversion repository is located at:

	https://svn.internet2.edu/svn/perfSONAR-PS

	Questions and comments can be directed to the author, or the mailing list.

	=head1 VERSION

	$Id:$

	=head1 AUTHOR

	Aaron Brown, E<lt>aaron@internet2.eduE<gt>, Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

	=head1 COPYRIGHT AND LICENSE

	Copyright (C) 2007 by Internet2

	This library is free software; you can redistribute it and/or modify
	it under the same terms as Perl itself, either Perl version 5.8.8 or,
	at your option, any later version of Perl 5 you may have available.

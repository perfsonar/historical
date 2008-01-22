package perfSONAR_PS::Collectors::LinkStatus::Agent::SNMP;

our $VERSION = 0.06;

use strict;

sub new($$$$$$$$$) {
	my ($package, $type, $hostname, $ifIndex, $version, $community, $oid, $agent) = @_;

	my %hash = ();

	if ($agent ne "") {
		$hash{"AGENT"} = $agent;
	} else {
		$hash{"AGENT"} = new perfSONAR_PS::Collectors::LinkStatus::SNMPAgent( $hostname, "" , $version, $community, "");
	}

	$hash{"TYPE"} = $type;
	$hash{"HOSTNAME"} = $hostname;
	$hash{"IFINDEX"} = $ifIndex;
	$hash{"COMMUNITY"} = $community;
	$hash{"VERSION"} = $version;
	$hash{"OID"} = $oid;

	bless \%hash => $package;
}

sub getType($) {
	my ($self) = @_;

	return $self->{TYPE};
}

sub setType($$) {
	my ($self, $type) = @_;

	$self->{TYPE} = $type;
}

sub setHostname($$) {
	my ($self, $hostname) = @_;

	$self->{HOSTNAME} = $hostname;
}

sub getHostname($) {
	my ($self) = @_;

	return $self->{HOSTNAME};
}

sub setifIndex($$) {
	my ($self, $ifIndex) = @_;

	$self->{IFINDEX} = $ifIndex;
}

sub getifIndex($) {
	my ($self) = @_;

	return $self->{IFINDEX};
}

sub setCommunity($$) {
	my ($self, $community) = @_;
	
	$self->{COMMUNITY} = $community;
}

sub getCommunity($) {
	my ($self) = @_;
	
	return $self->{COMMUNITY};
}

sub setVersion($$) {
	my ($self, $version) = @_;
	
	$self->{VERSION} = $version;
}

sub getVersion($) {
	my ($self) = @_;
	
	return $self->{VERSION};
}

sub setOID($$) {
	my ($self, $oid) = @_;
	
	$self->{OID} = $oid;
}

sub getOID($) {
	my ($self) = @_;
	
	return $self->{OID};
}

sub setAgent($$) {
	my ($self, $agent) = @_;
	
	$self->{AGENT} = $agent;
}

sub getAgent($) {
	my ($self) = @_;
	
	return $self->{AGENT};
}

sub run {
	my ($self) = @_;

	$self->{AGENT}->setSession;
	my $measurement_value = $self->{AGENT}->getVar($self->{OID}.".".$self->{IFINDEX});
	my $measurement_time = $self->{AGENT}->getHostTime;
	$self->{AGENT}->closeSession;

	if (defined $measurement_value) {
		if ($self->{OID} eq "1.3.6.1.2.1.2.2.1.8") {
			if ($measurement_value eq "2") {
				$measurement_value = "down";
			} elsif ($measurement_value eq "1") {
				$measurement_value = "up";
			} else {
				$measurement_value = "unknown";
			}
		} elsif ($self->{OID} eq "1.3.6.1.2.1.2.2.1.7") {
			if ($measurement_value eq "2") {
				$measurement_value = "down";
			} elsif ($measurement_value eq "1") {
				$measurement_value = "normaloperation";
			} elsif ($measurement_value eq "3") {
				$measurement_value = "troubleshooting";
			} else {
				$measurement_value = "unknown";
			}
		}
	}

	return (0, $measurement_time, $measurement_value);
}

1;

# ================ Internal Package perfSONAR_PS::Collectors::LinkStatus::SNMPAgent ================

package perfSONAR_PS::Collectors::LinkStatus::Agent::SNMP::Host;

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(defined $port and $port ne "") {
		$self->{PORT} = $port;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setVersion {
	my ($self, $ver) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(defined $ver and $ver ne "") {
		$self->{VERSION} = $ver;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setCommunity {
	my ($self, $comm) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(defined $comm and $comm ne "") {
		$self->{COMMUNITY} = $comm;
	} else {
		$logger->error("Missing argument.");
	}
	return;
}


sub setVariables {
	my ($self, $vars) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(!defined $var or $var eq "") {
		$logger->error("Missing argument.");
	} else {
		$self->{VARIABLES}->{$var} = "";
	}
	return;
}

sub getVar {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	undef $self->{VARIABLES};
	if(defined $self->{VARIABLES}) {
		$logger->error("Remove failure.");
	}
	return;
}

sub removeVariable {
	my ($self, $var) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(defined $var and $var ne "") {
		delete $self->{VARIABLES}->{$var};
	} else {
		$logger->error("Missing argument.");
	}
	return;
}

sub setSession {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

	if(defined $self->{SESSION}) {
		$self->{SESSION}->close;
	} else {
		$logger->error("Cannont close undefined session.");
	}
	return;
}

sub collectVariables {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::SNMPAgent");

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

package perfSONAR_PS::Collectors::Status;

use warnings;
use strict;

use English qw( -no_match_vars );

use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::Status;
use perfSONAR_PS::Utils::ParameterValidation;

use perfSONAR_PS::Collectors::Status::SNMP;
use perfSONAR_PS::Collectors::Status::CoreDirector;
#use perfSONAR_PS::Collectors::Status::OME;
#use perfSONAR_PS::Collectors::Status::HDXc;

sub create_workers {
	my ($class, @args) = @_;
    my $args = validateParams(@args, 
            {
                conf => 1,
                directory_offset => 0,
            });

	my $config = $args->{conf};

	unless ($config->{"switch"} or $config->{"element"}) {
		my $msg = "Nothing to measure";
		return (-1, $msg);
	}

	my @workers = ();

	if ($config->{"switch"}) {
		if (ref($config->{"switch"}) ne "ARRAY") {
			my @tmp = ();
			push @tmp, $config->{"switch"};
			$config->{"switch"} = \@tmp;
		}

		foreach my $switch (@{ $config->{"switch"} }) {
			my $switch_config = mergeHash( $config, $switch, ());

			my ($status, $res) = create_switch_worker($switch_config, $args->{directory_offset});
			if ($status != 0) {
				return (-1, $res);
			}

			push @workers, $res;
		}
	}

	return (0, \@workers);
}

sub create_database_client {
	my ($config, $directory_offset) = @_;

	unless ($config->{"db_type"}) {
		my $msg = "No database type specified. (db_type)";
		return (-1, $msg);
	}

	if (lc($config->{"db_type"}) eq "sqlite") {

		unless ($config->{"db_file"}) {
			my $msg = "You specified a SQLite Database, but then did not specify a database file(db_file)";
			return (-1, $msg);
		}

		my $file = $config->{"db_file"};
		if ($directory_offset) {
			if (!($file =~ "^/")) {
				$file = $directory_offset."/".$file;
			}
		}

		my $database_client = perfSONAR_PS::DB::Status->new("DBI:SQLite:dbname=".$file, undef, undef, $config->{"db_table"});

		if (not $database_client) {
			my $msg = "Problem creating database client";
			return (-1, $msg);
		}

		return (0, $database_client);
	} elsif (lc($config->{"db_type"}) eq "mysql") {
		my $dbi_string = "dbi:mysql";

		unless ($config->{"db_name"}) {
			my $msg = "Specified a MySQL Database, but did not specify which database (db_name)";
			return (-1, $msg);
		}

		$dbi_string .= ":".$config->{"db_name"};

		unless ($config->{"db_host"}) {
			my $msg = "Specified a MySQL Database, but did not specify which database host (db_host)";
			return (-1, $msg);
		}

		$dbi_string .= ":".$config->{"db_host"};

		if ($config->{"db_port"}) {
			$dbi_string .= ":".$config->{"db_port"};
		}

		my $database_client = perfSONAR_PS::DB::Status->new($dbi_string, $config->{"db_username"}, $config->{"db_password"}, $config->{"db_table"});
		if (not $database_client) {
			my $msg = "Problem creating database client";
			return (-1, $msg);
		}

		return (0, $database_client);
	}
	else {
		my $msg = "Unknown database type: ".$config->{db_type};
		return (-1, $msg);
	}
}

sub create_switch_worker {
	my ($config, $directory_offset) = @_;

	unless ($config->{type}) {
		my $msg = "Switch does not have a type element";
		return (-1, $msg);
	}

	if (lc($config->{type}) eq "snmp") {
		return create_switch_worker_snmp($config, $directory_offset);
	} elsif (lc($config->{type} eq "tl1")) {
		return create_switch_worker_tl1($config, $directory_offset);
	}
}

sub create_switch_worker_tl1 {
	my ($config, $directory_offset) = @_;

	unless ($config->{model}) {
		my $msg = "TL1 switch does not a 'model'";
		return (-1, $msg);
	}

	if (lc($config->{model}) eq "coredirector") {
		return create_switch_worker_coredirector($config, $directory_offset);
	} else {
		return (-1, "Unknown switch model: ".$config->{model});
	}
}

sub create_switch_worker_snmp {
	my ($config, $directory_offset) = @_;

	unless ($config->{address}) {
		my $msg = "SNMP switch has no address";
#		$self->{LOGGER}->error($msg);
		return (-1, $msg);

	}

	my ($status, $res) = create_database_client($config, $directory_offset);
	if ($status != 0) {
		return ($status, $res);
	}

	my $database_client = $res;

	my $address = $config->{address};
	my $port = $config->{port};
	my $version = $config->{version};
	my $community = $config->{community};
	my $check_all_interfaces = $config->{check_all_interfaces};
	my $identifier_pattern = $config->{identifier_pattern};
	my $polling_interval = $config->{polling_interval};

	my @interfaces = ();
	if ($config->{"interface"}) {	
		if (ref($config->{"interface"}) ne "ARRAY") {
			my @tmp = ();
			push @tmp, $config->{"interface"};
			$config->{"interface"} = \@tmp;
		}

		foreach my $interface (@{ $config->{"interface"} }) {
			my %iface = ();
			$iface{name} = $interface->{name};
			$iface{id} = $interface->{id};
			$iface{admin_status} = $interface->{admin_status};
			push @interfaces, \%iface;
		}
	}

	my $worker = perfSONAR_PS::Collectors::Status::SNMP->new();
	($status, $res) = $worker->init({
						database_client => $database_client,
						address => $address,
						port => $port,
						community => $community,
						version => $version,
						check_all_interfaces => $check_all_interfaces,
						polling_interval => $polling_interval,
						identifier_pattern => $identifier_pattern,
						interfaces => \@interfaces,
					});
	if ($status != 0) {
		return (-1, $res);
	}

	return (0, $worker);
}

sub create_switch_worker_coredirector {
	my ($config, $directory_offset) = @_;

	unless ($config->{address}) {
		my $msg = "CoreDirector switch has no address";
		return (-1, $msg);
	}

	unless ($config->{username}) {
		my $msg = "CoreDirector switch has no username";
		return (-1, $msg);
	}

	unless ($config->{password}) {
		my $msg = "CoreDirector switch has no password";
		return (-1, $msg);
	}

	my ($status, $res) = create_database_client($config, $directory_offset);
	if ($status != 0) {
		return ($status, $res);
	}

	my $database_client = $res;

	my $address = $config->{address};
	my $port = $config->{port};
	my $username = $config->{username};
	my $password = $config->{password};

	my $check_all_optical_ports = $config->{check_all_optical_ports};
	my $check_all_ethernet_ports = $config->{check_all_ethernet_ports};
	my $check_all_vlans = $config->{check_all_vlans};
	my $check_all_crossconnects = $config->{check_all_crossconnects};
	my $check_all_eflows = $config->{check_all_eflows};
	my $check_all_vcgs = $config->{check_all_vcgs};

	my $identifier_pattern = $config->{identifier_pattern};
	my $polling_interval = $config->{polling_interval};

	my $admin_status = $config->{admin_status};

	my @facilities = ();
	if ($config->{"facility"}) {
		if (ref($config->{"facility"}) ne "ARRAY") {
			my @tmp = ();
			push @tmp, $config->{"facility"};
			$config->{"facility"} = \@tmp;
		}

		foreach my $facility (@{ $config->{"facility"} }) {
			my %fac = ();
			$fac{type} = lc($facility->{type});
			$fac{id} = $facility->{id};
			$fac{name} = $facility->{name};
			$fac{admin_status} = $facility->{admin_status};

			push @facilities, \%fac;
		}
	}

	my $worker = perfSONAR_PS::Collectors::Status::CoreDirector->new();
	($status, $res) = $worker->init({
						database_client => $database_client,

						address => $address,
						port => $port,
						username => $username,
						password => $password,

						check_all_optical_ports => $check_all_optical_ports,
						check_all_crossconnects => $check_all_crossconnects,
						check_all_ethernet_ports => $check_all_ethernet_ports,
						check_all_eflows => $check_all_eflows,
						check_all_vcgs => $check_all_vcgs,
						check_all_vlans => $check_all_vlans,

						polling_interval => $polling_interval,
						identifier_pattern => $identifier_pattern,

						facilities => \@facilities,
					});
	if ($status != 0) {
		return (-1, $res);
	}

	return (0, $worker);
}

1;

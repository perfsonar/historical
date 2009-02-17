package perfSONAR_PS::Collectors::Status;

use warnings;
use strict;

use POSIX ":sys_wait_h";
use English qw( -no_match_vars );
use Log::Log4perl qw(get_logger :levels);

use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::ParameterValidation;

use perfSONAR_PS::DB::Status;
use perfSONAR_PS::DB::Facilities;
use perfSONAR_PS::DB::TopologyID;

use perfSONAR_PS::Collectors::Status::SNMP;
use perfSONAR_PS::Collectors::Status::CoreDirector;

#use perfSONAR_PS::Collectors::Status::OME;
#use perfSONAR_PS::Collectors::Status::HDXc;

use fields 'CHILDREN', 'WORKERS', 'CONF', 'DIRECTORY', 'LOGGER';

our $VERSION = 0.09;

sub new {
    my ($class, $conf, $directory) = @_;

    my $self = fields::new($class);

    $self->{LOGGER} = get_logger($class);
    $self->{CHILDREN} = ();
    $self->{WORKERS} = ();

    return $self;
}

sub init {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            conf             => 1,
            directory_offset => 0,
        }
    );

	my ($status, $res)  = $self->create_workers({ conf => $args->{conf}, directory_offset => $args->{directory_offset} });
	if ($status != 0) {
		return ($status, $res);
	}

	if (scalar(@{ $res }) == 0) {
		my $msg = "No elements to measure";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	$self->{CONF} = $args->{conf};
	$self->{DIRECTORY} = $args->{directory_offset};
	$self->{WORKERS} = $res;

	return (0, "");
}

sub run {
    my ( $self, @args ) = @_;
    my $args = validateParams(@args, { });

	foreach my $worker (@{ $self->{WORKERS} }) {
		my $pid = fork();
		if ($pid == 0) {
			$SIG{INT} = 'DEFAULT';
			$SIG{TERM} = 'DEFAULT';

			$worker->run();
			exit(0);
		}

		$self->{CHILDREN}->{$pid} = $worker;
	}

	foreach my $pid (keys %{ $self->{CHILDREN} }) {
		waitpid($pid, 0);
	}

	return;
}

=head2 exit
	Kills all the children for this process off. 
=cut
sub quit {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, { });

	foreach my $pid (keys %{ $self->{CHILDREN} }) {
		kill("SIGINT", $pid);
	}

	sleep(1);

	my $pid;
	while(($pid = waitpid(-1,WNOHANG)) > 0) {
		delete($self->{CHILDREN}->{$pid}) if ($self->{CHILDREN}->{$pid});
	}

	# If children are still around.
	if ($pid != -1) {
		foreach my $pid (keys %{ $self->{CHILDREN} }) {
			kill("SIGTERM", $pid);
		}
	}

	exit(0);
}

sub create_workers {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            conf             => 1,
            directory_offset => 0,
        }
    );

    my $config = $args->{conf};

    unless ( $config->{"switch"} or $config->{"element"} ) {
        my $msg = "Nothing to measure";
        return ( -1, $msg );
    }

    my @workers = ();

    if ( $config->{"switch"} ) {
        if ( ref( $config->{"switch"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"switch"};
            $config->{"switch"} = \@tmp;
        }

        foreach my $switch ( @{ $config->{"switch"} } ) {
            my $switch_config = mergeHash( $config, $switch, () );

            my ( $status, $res ) = create_switch_worker( $switch_config, $args->{directory_offset} );
            if ( $status != 0 ) {
                return ( -1, $res );
            }

            push @workers, $res;
        }
    }

    return ( 0, \@workers );
}

sub create_database_client {
    my ( $config, $directory_offset ) = @_;

    unless ( $config->{"db_type"} ) {
        my $msg = "No database type specified. (db_type)";
        return ( -1, $msg );
    }

	my ($dbistring, $username, $password, $prefix);

    if ( lc( $config->{"db_type"} ) eq "sqlite" ) {

        unless ( $config->{"db_file"} ) {
            my $msg = "You specified a SQLite Database, but then did not specify a database file(db_file)";
            return ( -1, $msg );
        }

        my $file = $config->{"db_file"};
        if ( $directory_offset ) {
            if ( !( $file =~ "^/" ) ) {
                $file = $directory_offset . "/" . $file;
            }
        }

		$dbistring = "DBI:SQLite:dbname=" . $file;
    }
    elsif ( lc( $config->{"db_type"} ) eq "mysql" ) {
        my $dbi_string = "dbi:mysql";

        unless ( $config->{"db_name"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database (db_name)";
            return ( -1, $msg );
        }

        $dbi_string .= ":" . $config->{"db_name"};

        unless ( $config->{"db_host"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database host (db_host)";
            return ( -1, $msg );
        }

        $dbi_string .= ":" . $config->{"db_host"};

        if ( $config->{"db_port"} ) {
            $dbi_string .= ":" . $config->{"db_port"};
        }
    }
    else {
        my $msg = "Unknown database type: " . $config->{db_type};
        return ( -1, $msg );
    }

	$prefix = $config->{db_prefix};

	my $facilities_client = perfSONAR_PS::DB::Facilities->new();
	unless ($facilities_client->init({ dbistring => $dbistring, username => $username, password => $password, table_prefix => $prefix })) {
		my $msg = "Problem creating database client";
		return ( -1, $msg );
	}

	my $topology_id_client = perfSONAR_PS::DB::TopologyID->new();
	unless ($topology_id_client->init({ dbistring => $dbistring, username => $username, password => $password, table_prefix => $prefix })) {
		my $msg = "Problem creating database client";
		return ( -1, $msg );
	}

	my $data_client = perfSONAR_PS::DB::Status->new();
	unless ($data_client->init({ dbistring => $dbistring, username => $username, password => $password, table_prefix => $prefix})) {
		my $msg = "Problem creating database client";
		return ( -1, $msg );
	}

	return ( 0, $facilities_client, $data_client, $topology_id_client );
}

sub create_switch_worker {
    my ( $config, $directory_offset ) = @_;

    unless ( $config->{type} ) {
        my $msg = "Switch does not have a type element";
        return ( -1, $msg );
    }

    if ( lc( $config->{type} ) eq "snmp" ) {
        return create_switch_worker_snmp( $config, $directory_offset );
    }
    elsif ( lc( $config->{type} eq "tl1" ) ) {
        return create_switch_worker_tl1( $config, $directory_offset );
    }
}

sub create_switch_worker_tl1 {
    my ( $config, $directory_offset ) = @_;

    unless ( $config->{model} ) {
        my $msg = "TL1 switch does not a 'model'";
        return ( -1, $msg );
    }

    if ( lc( $config->{model} ) eq "coredirector" ) {
        return create_switch_worker_coredirector( $config, $directory_offset );
    }
    else {
        return ( -1, "Unknown switch model: " . $config->{model} );
    }
}

sub create_switch_worker_snmp {
    my ( $config, $directory_offset ) = @_;

    unless ( $config->{address} ) {
        my $msg = "SNMP switch has no address";

        #		$self->{LOGGER}->error($msg);
        return ( -1, $msg );

    }

    my ( $status, $res1, $res2, $res3 ) = create_database_client( $config, $directory_offset );
    if ( $status != 0 ) {
        return ( $status, $res1 );
    }

    my $facilities_client = $res1;
    my $data_client = $res2;
    my $topology_id_client = $res3;

    my $address              = $config->{address};
    my $port                 = $config->{port};
    my $version              = $config->{version};
    my $community            = $config->{community};
    my $check_all_interfaces = $config->{check_all_interfaces};
    my $identifier_pattern   = $config->{identifier_pattern};
    my $polling_interval     = $config->{polling_interval};

    my @interfaces = ();
    if ( $config->{"interface"} ) {
        if ( ref( $config->{"interface"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"interface"};
            $config->{"interface"} = \@tmp;
        }

        foreach my $interface ( @{ $config->{"interface"} } ) {
            my %iface = ();
            $iface{name}         = $interface->{name};
            $iface{id}           = $interface->{id};
            $iface{admin_status} = $interface->{admin_status};
            push @interfaces, \%iface;
        }
    }

    my $worker = perfSONAR_PS::Collectors::Status::SNMP->new();
    ( $status, $res1 ) = $worker->init(
        {
            facilities_client      => $facilities_client,
            topology_id_client      => $topology_id_client,
            data_client      => $data_client,
            address              => $address,
            port                 => $port,
            community            => $community,
            version              => $version,
            check_all_interfaces => $check_all_interfaces,
            polling_interval     => $polling_interval,
            identifier_pattern   => $identifier_pattern,
            interfaces           => \@interfaces,
        }
    );
    if ( $status != 0 ) {
        return ( -1, $res1 );
    }

    return ( 0, $worker );
}

sub create_switch_worker_coredirector {
    my ( $config, $directory_offset ) = @_;

    unless ( $config->{address} ) {
        my $msg = "CoreDirector switch has no address";
        return ( -1, $msg );
    }

    unless ( $config->{username} ) {
        my $msg = "CoreDirector switch has no username";
        return ( -1, $msg );
    }

    unless ( $config->{password} ) {
        my $msg = "CoreDirector switch has no password";
        return ( -1, $msg );
    }

    my ( $status, $res1, $res2, $res3 ) = create_database_client( $config, $directory_offset );
    if ( $status != 0 ) {
        return ( $status, $res1 );
    }

    my $facilities_client = $res1;
    my $data_client = $res2;
    my $topology_id_client = $res3;

    my $address  = $config->{address};
    my $port     = $config->{port};
    my $username = $config->{username};
    my $password = $config->{password};

    my $check_all_optical_ports  = $config->{check_all_optical_ports};
    my $check_all_ethernet_ports = $config->{check_all_ethernet_ports};
    my $check_all_vlans          = $config->{check_all_vlans};
    my $check_all_crossconnects  = $config->{check_all_crossconnects};
    my $check_all_eflows         = $config->{check_all_eflows};
    my $check_all_vcgs           = $config->{check_all_vcgs};

    my $identifier_pattern = $config->{identifier_pattern};
    my $polling_interval   = $config->{polling_interval};

    my $admin_status = $config->{admin_status};

    my @facilities = ();
    if ( $config->{"facility"} ) {
        if ( ref( $config->{"facility"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"facility"};
            $config->{"facility"} = \@tmp;
        }

        foreach my $facility ( @{ $config->{"facility"} } ) {
            my %fac = ();
            $fac{type}         = lc( $facility->{type} );
            $fac{id}           = $facility->{id};
            $fac{name}         = $facility->{name};
            $fac{admin_status} = $facility->{admin_status};

            push @facilities, \%fac;
        }
    }

    my $worker = perfSONAR_PS::Collectors::Status::CoreDirector->new();
    ( $status, $res1 ) = $worker->init(
        {
            facilities_client      => $facilities_client,
            topology_id_client      => $topology_id_client,
            data_client      => $data_client,

            address  => $address,
            port     => $port,
            username => $username,
            password => $password,

            check_all_optical_ports  => $check_all_optical_ports,
            check_all_crossconnects  => $check_all_crossconnects,
            check_all_ethernet_ports => $check_all_ethernet_ports,
            check_all_eflows         => $check_all_eflows,
            check_all_vcgs           => $check_all_vcgs,
            check_all_vlans          => $check_all_vlans,

            polling_interval   => $polling_interval,
            identifier_pattern => $identifier_pattern,

            facilities => \@facilities,
        }
    );
    if ( $status != 0 ) {
        return ( -1, $res1 );
    }

    return ( 0, $worker );
}

1;

package perfSONAR_PS::Collectors::TL1Collector;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::TL1Collector

=head1 DESCRIPTION

TBD

=cut

use POSIX ":sys_wait_h";
use English qw( -no_match_vars );
use Log::Log4perl qw(get_logger :levels);
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::SNMPWalk;

use perfSONAR_PS::DB::TL1Counters;

use perfSONAR_PS::Collectors::TL1Collector::StoreFileGenerationWorker;
use perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::SNMP;
use perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::CoreDirector;
use perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::OME;
use perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::HDXc;

use fields 'CHILDREN', 'WORKERS', 'CONF', 'LOGGER', 'IS_EXITING';

=head2 new( $class )

TBD

=cut

sub new {
    my ( $class ) = @_;

    my $self = fields::new( $class );

    $self->{LOGGER}   = get_logger( $class );
    $self->{CHILDREN} = ();
    $self->{WORKERS}  = ();

    return $self;
}

=head2 init( $self, { \%conf, $directory_offset  } )

A function to initializes the status collector. $conf is a hash from a
Config::General.  Directory offset is the path to the configuration file. Any
paths from to files used by the TL1Collector collector will be offset to this
directory if they are relative paths.

=cut

sub init {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            conf             => 1,
            directory_offset => 0,
        }
    );

    # Creates the database client object that will be used by all the status collector agents
    my ( $status, $res ) = $self->create_database_client( { config => $args->{conf}, directory_offset => $args->{directory_offset} } );
    if ( $status != 0 ) {
        return ( $status, $res );
    }

    my $database_client = $res;

    $self->{LOGGER}->debug( "Creating workers" );
    ( $status, $res ) = $self->create_workers( { conf => $args->{conf}, database_client => $database_client, directory_offset => $args->{directory_offset} } );
    $self->{LOGGER}->debug( "Done creating workers" );
    if ( $status != 0 ) {
        return ( $status, $res );
    }

    if ( scalar( @{$res} ) == 0 ) {
        my $msg = "No elements to measure";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    $self->{CONF}    = $args->{conf};
    $self->{WORKERS} = $res;

    return ( 0, q{} );
}

=head2 run( $self )

A function called by the collector daemon script. It forks off the collector
agents and executes them.

=cut

sub run {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, {} );

    foreach my $worker ( @{ $self->{WORKERS} } ) {
        my $pid = fork();
        if ( $pid == 0 ) {
            $SIG{INT}  = 'DEFAULT';
            $SIG{TERM} = 'DEFAULT';

            $worker->run();
            exit( 0 );
        }

        $self->{CHILDREN}->{$pid} = $worker;
    }

    # This loop tracks the children, and restarts any that exit.
    while ( scalar( keys %{ $self->{CHILDREN} } ) > 0 ) {
        last if ( $self->{IS_EXITING} );

        my $pid;
        do {
            $pid = waitpid( -1, WNOHANG );
            if ( $pid > 0 ) {
                my $worker = $self->{CHILDREN}->{$pid};
                delete( $self->{CHILDREN}->{$pid} );

                $self->{LOGGER}->warn( "Process $pid exited. Restarting worker" );

                my $new_pid = fork();
                if ( $new_pid == 0 ) {
                    $SIG{INT}  = 'DEFAULT';
                    $SIG{TERM} = 'DEFAULT';

                    $worker->run();
                    exit( 0 );
                }

                $self->{CHILDREN}->{$new_pid} = $worker;
            }
        } while ( $pid > 0 );

        sleep( 1 );
    }

    return;
}

=head2 quit($self)

Kills all the collector agents for this process off, and then exits.

=cut

sub quit {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, {} );

    $self->{IS_EXITING} = 1;

    foreach my $pid ( keys %{ $self->{CHILDREN} } ) {
        kill( "SIGINT", $pid );
    }

    sleep( 1 );

    my $pid;
    while ( ( $pid = waitpid( -1, WNOHANG ) ) > 0 ) {
        delete( $self->{CHILDREN}->{$pid} ) if ( $self->{CHILDREN}->{$pid} );
    }

    # If children are still around.
    if ( $pid != -1 ) {
        foreach my $pid ( keys %{ $self->{CHILDREN} } ) {
            kill( "SIGTERM", $pid );
        }
    }

    exit( 0 );
}

=head2 create_workers( $self, { conf, database_client } )

A function that reads the configuration and returns worker agents for each of
the elements to be monitored. It calls two function to create the different
types of workers: device workers and element workers. 

=cut

sub create_workers {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            conf             => 1,
            directory_offset => 0,
            database_client  => 1,
        }
    );

    my $config          = $args->{conf};
    my $database_client = $args->{database_client};

    my @workers = ();

    $self->{LOGGER}->debug( "Creating device workers" );
    my ( $status, $res ) = $self->create_device_workers( { config => $config, database_client => $database_client } );
    $self->{LOGGER}->debug( "Done creating device workers" );
    if ( $status == -1 ) {
        return ( $status, $res );
    }

    foreach my $worker ( @$res ) {
        push @workers, $worker;
    }

    if ( scalar( @workers ) == 0 ) {
        return ( -1, "No elements or devices to measure" );
    }

    unless ( $config->{store_file} ) {
        my $msg = "No store file specified (store_file)";
        return ( -1, $msg );
    }

    my $store_file_regeneration_period = 30;
    $store_file_regeneration_period = $config->{store_file_regeneration_period} if ( $config->{store_file_regeneration_period} );

    unless ( $config->{store_file} =~ /^\// ) {
        $config->{store_file} = $args->{directory_offset} . "/" . $config->{store_file} if ( $args->{directory_offset} );
    }

    my $store_file_worker = perfSONAR_PS::Collectors::TL1Collector::StoreFileGenerationWorker->new();
    $status = $store_file_worker->init( { store_file => $config->{store_file}, data_client => $database_client, regeneration_period => $store_file_regeneration_period } );
    unless ( $status == 0 ) {
        my $msg = "Couldn't create store file worker";
        return ( -1, $msg );
    }

    push @workers, $store_file_worker;

    return ( 0, \@workers );
}

=head2 create_device_workers( $self, { config, database_client } )

A function to read and allocate worker agents for each configured device. It
reads through the configured devices and calls the specific function for
parsing the device.

=cut

sub create_device_workers {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            config           => 1,
            directory_offset => 0,
            database_client  => 1,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    my @workers = ();

    unless ( $config->{"switch"} or $cofng->{"device"} ) {
        return ( 0, \@workers );
    }

    if ( $config->{"switch"} ) {
        if ( ref( $config->{"switch"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"switch"};
            $config->{"switch"} = \@tmp;
        }

        foreach my $switch ( @{ $config->{"switch"} } ) {
            my $switch_config = mergeHash( $config, $switch, () );

            $self->{LOGGER}->debug( "Creating switch workers" );
            my ( $status, $res ) = $self->create_switch_worker( { config => $switch_config, database_client => $database_client } );
            $self->{LOGGER}->debug( "Done creating switch workers" );
            if ( $status != 0 ) {
                return ( -1, $res );
            }

            push @workers, $res;
        }
    }

    if ( $config->{"device"} ) {
        if ( ref( $config->{"device"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"device"};
            $config->{"device"} = \@tmp;
        }

        foreach my $device ( @{ $config->{"device"} } ) {
            my $device_config = mergeHash( $config, $device, () );

            $self->{LOGGER}->debug( "Creating device workers" );
            my ( $status, $res ) = $self->create_switch_worker( { config => $device_config, database_client => $database_client } );
            $self->{LOGGER}->debug( "Done creating device workers" );
            if ( $status != 0 ) {
                return ( -1, $res );
            }

            push @workers, $res;
        }
    }

    return ( 0, \@workers );
}

=head2 create_database_client( $self, { config } )

A function to read the database configuration from the config and create a
database client.

=cut

sub create_database_client {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};

    unless ( $config->{"rrd_directory"} ) {
        my $msg = "No RRD location specified. (rrd_directory)";
        return ( -1, $msg );
    }

    unless ( $config->{"metadata_db_type"} ) {
        my $msg = "No type specified for the metadata database. (metadata_db_type)";
        return ( -1, $msg );
    }

    my ( $dbistring, $username, $password );

    if ( lc( $config->{"metadata_db_type"} ) eq "sqlite" ) {

        unless ( $config->{"metadata_db_file"} ) {
            my $msg = "You specified a SQLite Database, but then did not specify a database file(db_file)";
            return ( -1, $msg );
        }

        my $file = $config->{"metadata_db_file"};
        if ( $directory_offset ) {
            if ( !( $file =~ "^/" ) ) {
                $file = $directory_offset . "/" . $file;
            }
        }

        $dbistring = "DBI:SQLite:dbname=" . $file;
    }
    elsif ( lc( $config->{"metadata_db_type"} ) eq "mysql" ) {
        $dbistring = "dbi:mysql";

        unless ( $config->{"metadata_db_name"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database (db_name)";
            return ( -1, $msg );
        }

        $dbistring .= ":" . $config->{"metadata_db_name"};

        unless ( $config->{"metadata_db_host"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database host (db_host)";
            return ( -1, $msg );
        }

        $dbistring .= ":" . $config->{"metadata_db_host"};

        if ( $config->{"metadata_db_port"} ) {
            $dbistring .= ":" . $config->{"metadata_db_port"};
        }

        $username = $config->{metadata_db_username};
        $password = $config->{metadata_db_password};
    }
    else {
        my $msg = "Unknown database type: " . $config->{metadata_db_type};
        return ( -1, $msg );
    }

    my $max_timeout = $config->{"collection_interval"} * 3;
    $max_timeout = $config->{"max_timeout"} if ( $config->{"max_timeout"} );

    my $data_client = perfSONAR_PS::DB::TL1Counters->new();
    my ( $status, $res ) = $data_client->init( { data_directory => $config->{"rrd_directory"}, metadata_dbistring => $dbistring, metadata_username => $username, metadata_password => $password, max_timeout => $max_timeout } );
    if ( $status != 0 ) {
        my $msg = "Problem creating database client: $res";
        $self->{LOGGER}->debug( $msg );
        return ( -1, $msg );
    }

    return ( 0, $data_client );
}

=head2 create_switch_worker( $self, { database_client, config } )

A function which parses the device type and calls the parsing function for each
element type.

=cut

sub create_switch_worker {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

    unless ( $config->{type} ) {
        my $msg = "Switch does not have a type element";
        return ( -1, $msg );
    }

    if ( lc( $config->{type} ) eq "snmp" ) {
        return $self->create_switch_worker_snmp( { config => $config, database_client => $database_client } );
    }
    elsif ( lc( $config->{type} eq "tl1" ) ) {
        $self->{LOGGER}->debug( "Creating tl1 worker" );
        return $self->create_switch_worker_tl1( { config => $config, database_client => $database_client } );
        $self->{LOGGER}->debug( "Done creating tl1 worker" );
    }
    else {
        return ( -1, "Unknown switch type" );
    }
}

=head2 create_switch_worker_tl1( $self, { database_client, config } )

A function which reads the type of TL1 device and passes it to the appropriate
parsing function.

=cut

sub create_switch_worker_tl1 {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

    unless ( $config->{model} ) {
        my $msg = "TL1 switch does not a 'model'";
        return ( -1, $msg );
    }

    if ( lc( $config->{model} ) eq "coredirector" ) {
        $self->{LOGGER}->debug( "Creating coredirector worker" );
        return $self->create_switch_worker_coredirector( { config => $config, database_client => $database_client } );
        $self->{LOGGER}->debug( "Done creating coredirector worker" );
    }
    elsif ( lc( $config->{model} ) eq "ome" ) {
        return $self->create_switch_worker_ome( { config => $config, database_client => $database_client } );
    }
    elsif ( lc( $config->{model} ) eq "hdxc" ) {
        return $self->create_switch_worker_hdxc( { config => $config, database_client => $database_client } );
    }
    else {
        return ( -1, "Unknown switch model: " . $config->{model} );
    }
}

=head2 create_switch_worker_snmp( $self,  { database_client, config } )

A function that parses the attributes of an SNMP device and creates a worker
that will query that device.

=cut

sub create_switch_worker_snmp {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

    unless ( $config->{address} ) {
        my $msg = "SNMP switch has no address";

        #		$self->{LOGGER}->error($msg);
        return ( -1, $msg );

    }

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

    my $worker = perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::SNMP->new();
    my $status = $worker->init(
        {
            data_client          => $database_client,
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
        return ( -1, "Couldn't initialize SNMP client" );
    }

    return ( 0, $worker );
}

=head2 create_switch_worker_coredirector( $self, { database_client, config } )

A function that parses the attributes of a CoreDirector device and creates a worker
that will query that device.

=cut

sub create_switch_worker_coredirector {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

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

    my $worker = perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::CoreDirector->new();
    my $status = $worker->init(
        {
            data_client => $database_client,

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

            vlan_facilities     => $config->{vlan},
            vcg_facilities      => $config->{vcg},
            ethernet_facilities => $config->{ethernet},
            optical_facilities  => $config->{optical},

            polling_interval   => $polling_interval,
            identifier_pattern => $identifier_pattern,
        }
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize CoreDirector module" );
    }

    $self->{LOGGER}->debug( "Created coredirector worker" );

    return ( 0, $worker );
}

=head2 create_switch_worker_ome( $self,  { database_client, config } )

A function that parses the attributes of a OME6500 device and creates a worker
that will query that device.

=cut

sub create_switch_worker_ome {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

    unless ( $config->{address} ) {
        my $msg = "OME switch has no address";
        return ( -1, $msg );
    }

    unless ( $config->{username} ) {
        my $msg = "OME switch has no username";
        return ( -1, $msg );
    }

    unless ( $config->{password} ) {
        my $msg = "OME switch has no password";
        return ( -1, $msg );
    }

    my $address  = $config->{address};
    my $port     = $config->{port};
    my $username = $config->{username};
    my $password = $config->{password};

    my $check_all_optical_ports  = $config->{check_all_optical_ports};
    my $check_all_ethernet_ports = $config->{check_all_ethernet_ports};
    my $check_all_wan_ports      = $config->{check_all_wan_ports};

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

    my $worker = perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::OME->new();
    my $status = $worker->init(
        {
            data_client => $database_client,

            address  => $address,
            port     => $port,
            username => $username,
            password => $password,

            check_all_optical_ports  => $check_all_optical_ports,
            check_all_ethernet_ports => $check_all_ethernet_ports,
            check_all_wan_ports      => $check_all_wan_ports,

            polling_interval   => $polling_interval,
            identifier_pattern => $identifier_pattern,

            facilities => \@facilities,
        }
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize OME module" );
    }

    return ( 0, $worker );
}

=head2 create_switch_worker_hdxc( $self, { database_client, config } )

A function that parses the attributes of a HDXc device and creates a worker
that will query that device.

=cut

sub create_switch_worker_hdxc {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client => 1,
            config          => 1,
        }
    );

    my $config          = $args->{config};
    my $database_client = $args->{database_client};

    unless ( $config->{address} ) {
        my $msg = "HDXc switch has no address";
        return ( -1, $msg );
    }

    unless ( $config->{username} ) {
        my $msg = "HDXc switch has no username";
        return ( -1, $msg );
    }

    unless ( $config->{password} ) {
        my $msg = "HDXc switch has no password";
        return ( -1, $msg );
    }

    my $address  = $config->{address};
    my $port     = $config->{port};
    my $username = $config->{username};
    my $password = $config->{password};

    my $check_all_optical_ports = $config->{check_all_optical_ports};

    #    my $check_all_ethernet_ports = $config->{check_all_ethernet_ports};

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

    my $worker = perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::HDXc->new();
    my $status = $worker->init(
        {
            data_client => $database_client,

            address  => $address,
            port     => $port,
            username => $username,
            password => $password,

            check_all_optical_ports => $check_all_optical_ports,

            #            check_all_ethernet_ports => $check_all_ethernet_ports,

            polling_interval   => $polling_interval,
            identifier_pattern => $identifier_pattern,

            facilities => \@facilities,
        }
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize HDXc module" );
    }

    return ( 0, $worker );
}

1;

__END__

=head1 SEE ALSO

L<POSIX>, L<English>, L<Log::Log4perl>, 
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::ParameterValidation>,
L<perfSONAR_PS::DB::TL1Collector>,
L<perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::SNMP>, 
L<perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::CoreDirector>, 
L<perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::OME>, 
L<perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::HDXc>, 

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2

All rights reserved.

=cut

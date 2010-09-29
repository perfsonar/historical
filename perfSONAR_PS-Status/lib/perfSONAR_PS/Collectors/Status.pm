package perfSONAR_PS::Collectors::Status;

use strict;
use warnings;

our $VERSION = 3.2;

=head1 NAME

perfSONAR_PS::Collectors::Status

=head1 DESCRIPTION

TBD

=cut

use POSIX ":sys_wait_h";
use English qw( -no_match_vars );
use Log::Log4perl qw(get_logger :levels);
use Data::Dumper;

use perfSONAR_PS::DB::File;
use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::SNMPWalk;

use perfSONAR_PS::DB::Status;

use perfSONAR_PS::Collectors::Status::ElementsWorker;
use perfSONAR_PS::Collectors::Status::DeviceAgents::SNMP;
use perfSONAR_PS::Collectors::Status::DeviceAgents::CoreDirector;
use perfSONAR_PS::Collectors::Status::DeviceAgents::OME;
use perfSONAR_PS::Collectors::Status::DeviceAgents::HDXc;

use perfSONAR_PS::Collectors::Status::ElementAgents::Constant;
use perfSONAR_PS::Collectors::Status::ElementAgents::SNMP;
use perfSONAR_PS::Collectors::Status::ElementAgents::Script;

use fields 'CHILDREN', 'WORKERS', 'CONF', 'DIRECTORY', 'LOGGER';

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

=head2 init( $self, { \%conf, $directory_offset } )

A function to initializes the status collector. $conf is a hash from a
Config::General.  Directory offset is the path to the configuration file. Any
paths from to files used by the Status collector will be offset to this
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

    ( $status, $res ) = $self->create_workers( { conf => $args->{conf}, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    if ( $status != 0 ) {
        return ( $status, $res );
    }

    if ( scalar( @{$res} ) == 0 ) {
        my $msg = "No elements to measure";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    $self->{CONF}      = $args->{conf};
    $self->{DIRECTORY} = $args->{directory_offset};
    $self->{WORKERS}   = $res;

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

    foreach my $pid ( keys %{ $self->{CHILDREN} } ) {
        waitpid( $pid, 0 );
    }

    return;
}

=head2 quit($self)

Kills all the collector agents for this process off, and then exits.

=cut

sub quit {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, {} );

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

=head2 create_workers( $self, { conf, directory_offset, database_client } )

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

    my $config           = $args->{conf};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    my @workers = ();

    if ( $config->{elements_file} ) {
        my ( $status, $res ) = $self->parse_elements_file( { elements_file => $config->{elements_file}, directory_offset => $args->{directory_offset}, database_client => $database_client } );
        if ( $status == -1 ) {
            return ( $status, $res );
        }

        foreach my $worker ( @$res ) {
            push @workers, $worker;
        }
    }

    my ( $status, $res ) = $self->create_element_workers( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    if ( $status == -1 ) {
        return ( $status, $res );
    }

    foreach my $worker ( @$res ) {
        push @workers, $worker;
    }

    ( $status, $res ) = $self->create_device_workers( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    if ( $status == -1 ) {
        return ( $status, $res );
    }

    foreach my $worker ( @$res ) {
        push @workers, $worker;
    }

    if ( scalar( @workers ) == 0 ) {
        return ( -1, "No elements or devices to measure" );
    }

    return ( 0, \@workers );
}

=head2 create_device_workers( $self, { config, database_client, directory_offset } )

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
            database_client  => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    my @workers = ();

    unless ( $config->{"switch"} ) {
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

            my ( $status, $res ) = $self->create_switch_worker( { config => $switch_config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
            if ( $status != 0 ) {
                return ( -1, $res );
            }

            push @workers, $res;
        }
    }

    return ( 0, \@workers );
}

=head2 create_database_client( $self, { config, directory_offset } )

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

    unless ( $config->{"db_type"} ) {
        my $msg = "No database type specified. (db_type)";
        return ( -1, $msg );
    }

    my ( $dbistring, $username, $password, $prefix );

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
        $dbistring = "dbi:mysql";

        unless ( $config->{"db_name"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database (db_name)";
            return ( -1, $msg );
        }

        $dbistring .= ":" . $config->{"db_name"};

        unless ( $config->{"db_host"} ) {
            my $msg = "Specified a MySQL Database, but did not specify which database host (db_host)";
            return ( -1, $msg );
        }

        $dbistring .= ":" . $config->{"db_host"};

        if ( $config->{"db_port"} ) {
            $dbistring .= ":" . $config->{"db_port"};
        }

	$username = $config->{db_username};
	$password = $config->{db_password};
    }
    else {
        my $msg = "Unknown database type: " . $config->{db_type};
        return ( -1, $msg );
    }

    $prefix = $config->{db_prefix};

    $self->{LOGGER}->debug("DBISTRING: $dbistring");

    my $data_client = perfSONAR_PS::DB::Status->new();
    if ( $data_client->init( { dbistring => $dbistring, username => $username, password => $password, table_prefix => $prefix } ) ) {
        my $msg = "Problem creating database client";
        return ( -1, $msg );
    }

    return ( 0, $data_client );
}

=head2 create_switch_worker( $self, { database_client, config, directory_offset } )

A function which parses the device type and calls the parsing function for each
element type.

=cut

sub create_switch_worker {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    unless ( $config->{type} ) {
        my $msg = "Switch does not have a type element";
        return ( -1, $msg );
    }

    if ( lc( $config->{type} ) eq "snmp" ) {
        return $self->create_switch_worker_snmp( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    }
    elsif ( lc( $config->{type} eq "tl1" ) ) {
        return $self->create_switch_worker_tl1( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    }
}

=head2 create_switch_worker_tl1( $self, { database_client, config, directory_offset } )

A function which reads the type of TL1 device and passes it to the appropriate
parsing function.

=cut

sub create_switch_worker_tl1 {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    unless ( $config->{model} ) {
        my $msg = "TL1 switch does not a 'model'";
        return ( -1, $msg );
    }

    if ( lc( $config->{model} ) eq "coredirector" ) {
        return $self->create_switch_worker_coredirector( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    }
    elsif ( lc( $config->{model} ) eq "ome" ) {
        return $self->create_switch_worker_ome( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    }
    elsif ( lc( $config->{model} ) eq "hdxc" ) {
        return $self->create_switch_worker_hdxc( { config => $config, directory_offset => $args->{directory_offset}, database_client => $database_client } );
    }
    else {
        return ( -1, "Unknown switch model: " . $config->{model} );
    }
}

=head2 create_switch_worker_snmp( $self,  { database_client, config, directory_offset } )

A function that parses the attributes of an SNMP device and creates a worker
that will query that device.

=cut

sub create_switch_worker_snmp {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

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

    my $worker = perfSONAR_PS::Collectors::Status::DeviceAgents::SNMP->new();
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

=head2 create_switch_worker_coredirector( $self, { database_client, config, directory_offset } )

A function that parses the attributes of a CoreDirector device and creates a worker
that will query that device.

=cut

sub create_switch_worker_coredirector {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

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

    my $worker = perfSONAR_PS::Collectors::Status::DeviceAgents::CoreDirector->new();
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

            polling_interval   => $polling_interval,
            identifier_pattern => $identifier_pattern,

            facilities => \@facilities,
        }
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize CoreDirector module" );
    }

    return ( 0, $worker );
}

=head2 create_switch_worker_ome( $self,  { database_client, config, directory_offset } )

A function that parses the attributes of a OME6500 device and creates a worker
that will query that device.

=cut

sub create_switch_worker_ome {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

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

    my $worker = perfSONAR_PS::Collectors::Status::DeviceAgents::OME->new();
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

=head2 create_switch_worker_hdxc( $self, { database_client, config, directory_offset } )

A function that parses the attributes of a HDXc device and creates a worker
that will query that device.

=cut

sub create_switch_worker_hdxc {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            config           => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

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

    my $worker = perfSONAR_PS::Collectors::Status::DeviceAgents::HDXc->new();
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

=head2 create_element_workers( $self, { config, database_client, directory_offset } )

A function to read and allocate worker agents for each configured element. It
reads through the configured elements and calls the specific function for
parsing the element.

=cut

sub create_element_workers {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            config           => 1,
            database_client  => 1,
            directory_offset => 0,
        }
    );

    my $config           = $args->{config};
    my $directory_offset = $args->{directory_offset};
    my $database_client  = $args->{database_client};

    my @elements = ();

    if ( $config->{"element"} ) {
        if ( ref( $config->{"element"} ) ne "ARRAY" ) {
            my @tmp = ();
            push @tmp, $config->{"element"};
            $config->{"element"} = \@tmp;
        }

        my %snmp_clients = ();
        foreach my $element ( @{ $config->{"element"} } ) {
            my $element_config = mergeHash( $config, $element, () );

            my ( $status, $res ) = $self->create_element_agents( { config => $element_config, directory_offset => $args->{directory_offset}, snmp_clients => \%snmp_clients } );
            if ( $status != 0 ) {
                return ( -1, $res );
            }

            push @elements, $res;
        }
    }

    my $worker = perfSONAR_PS::Collectors::Status::ElementsWorker->new();
    my $status = $worker->init(
        data_client      => $args->{database_client},
        polling_interval => $args->{polling_interval},
        elements         => \@elements,
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize Elements worker" );
    }

    my @workers = ();
    push @workers, $worker;

    return ( 0, \@workers );
}

=head2 create_element_agent( $self, { config, \%snmp_clients } )

A function to allocate an agent for measuring the specified element. $config is
a reference to a hash describing the element. \%snmp_clients is a reference to
a hash which will be filled in with SNMP clients. This is used to enable bulk
SNMP grabs if users configure multiple elements on a single SNMP device.

=cut

sub create_element_agents {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            config           => 1,
            directory_offset => 1,
            snmp_clients     => 1,
        }
    );

    my $config = $args->{config};

    # the raw SNMP clients are aggregated so that if individuals use SNMP
    # clients, we can use bulk pulls to grab the stats and cache them.

    unless ( $config->{id} ) {
        my $msg = "No ids associated with specified element";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    unless ( $config->{agent} ) {
        my $msg = "No agents associated with specified element";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    if ( ref( $config->{id} ) ne "ARRAY" ) {
        my @tmp = ();
        push @tmp, $config->{id};
        $config->{id} = \@tmp;
    }

    if ( ref( $config->{agent} ) ne "ARRAY" ) {
        $self->{LOGGER}->debug( "Converting to array: " . ref( $config->{agent} ) );

        my @tmp = ();
        push @tmp, $config->{agent};
        $config->{agent} = \@tmp;
    }

    my @ids = ();
    foreach my $id ( @{ $config->{id} } ) {
        push @ids, $id;
    }

    my @agents = ();

    $self->{LOGGER}->debug( Dumper( $config ) );
    foreach my $agent ( @{ $config->{agent} } ) {
        my ( $status, $res );

        $self->{LOGGER}->debug( Dumper( $agent ) );
        ( $status, $res ) = $self->create_element_agent( { config => $agent, directory_offset => $args->{directory_offset}, snmp_clients => $args->{snmp_clients} } );
        if ( $status != 0 ) {
            my $msg = "Problem parsing operational status agent for element: $res";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        push @agents, $res;
    }

    my %element = ();
    $element{ids}    = \@ids;
    $element{agents} = \@agents;

    return ( 0, \%element );
}

=head2 parse_element_agent( $self, { config, snmp_clients, directory_offset } )

A function which parses an agent configuration, and creates an appropriate
Agent object. An agent can monitor by running a script, querying an SNMP
interface or simply returning a constant value. For an SNMP device, this
routine will query for the ifIndex if it is not specified.

=cut

sub create_element_agent {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            config           => 1,
            snmp_clients     => 1,
            directory_offset => 1,
        }
    );

    my $agent = $args->{config};

    my $new_agent;

    $self->{LOGGER}->debug( Dumper( $agent ) );

    my $status_type = $agent->{status_type};
    if ( not $status_type ) {
        my $msg = "Agent does not contain a status_type attribute stating which status (operational or administrative) it returns";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    if ( $status_type ne "oper" and $status_type ne "operational" and $status_type ne "admin" and $status_type ne "administrative" and $status_type ne "oper/admin" and $status_type ne "admin/oper" ) {
        my $msg = "Agent's stated status_type is neither 'oper' nor 'admin'";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $type = $agent->{type};
    unless ( $type ) {
        my $msg = "Agent has no type information";
        $self->{LOGGER}->debug( $msg );
        return ( -1, $msg );
    }

    if ( $type eq "script" ) {
        my $script_name = $agent->{script_name};
        unless ( $script_name ) {
            my $msg = "Agent of type 'script' has no script name defined";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        if ( $script_name !~ "^/" ) {
            $script_name = $args->{directory_offset} . "/" . $script_name;
        }

        unless ( -x $script_name ) {
            my $msg = "Agent of type 'script' has non-executable script: \"$script_name\"";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        my $script_params = $agent->{"script_parameters"};

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::Script->new( $status_type, $script_name, $script_params );
    }
    elsif ( $type eq "constant" ) {
        my $value = $agent->{constant};
        unless ( $value ) {
            my $msg = "Agent of type 'constant' has no value defined";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::Constant->new( $status_type, $value );
    }
    elsif ( $type eq "snmp" ) {
        my $oid = $agent->{oid};
        unless ( $oid ) {
            if ( $status_type eq "oper" ) {
                $oid = "1.3.6.1.2.1.2.2.1.8";
            }
            elsif ( $status_type eq "admin" ) {
                $oid = "1.3.6.1.2.1.2.2.1.7";
            }
            else {
                my $msg = "Agent of type 'snmp' must be of type 'oper' or 'admin'";
                $self->{LOGGER}->debug( $msg );
                return ( -1, $msg );
            }
        }

        my $address = $agent->{address};
        unless ( $address ) {
            my $msg = "Agent of type 'SNMP' has no address";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $ifName  = $agent->{ifName};
        my $ifIndex = $agent->{ifIndex};

        unless ( $ifIndex or $ifName ) {
            my $msg = "Agent of type 'SNMP' has no name or index specified";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $version = $agent->{version};
        unless ( $version ) {
            my $msg = "Agent of type 'SNMP' has no snmp version";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $community = $agent->{community};
        unless ( $community ) {
            my $msg = "Agent of type 'SNMP' has no community string";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        unless ( $ifIndex ) {
            $self->{LOGGER}->debug( "Looking up $ifName from $address" );

            my ( $status, $res ) = snmpwalk( $address, undef, "1.3.6.1.2.1.31.1.1.1.1", $community, $version );
            if ( $status != 0 ) {
                my $msg = "Error occurred while looking up ifIndex for specified ifName $ifName in ifName table: $res";
                $self->{LOGGER}->warn( $msg );
            }
            else {
                foreach my $oid_ref ( @{$res} ) {
                    my $oid   = $oid_ref->[0];
                    my $type  = $oid_ref->[1];
                    my $value = $oid_ref->[2];

                    $self->{LOGGER}->debug( "$oid = $type: $value($ifName)" );
                    if ( $value eq $ifName and $oid =~ /1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.(\d+)/x ) {
                        $ifIndex = $1;
                    }
                }
            }

            unless ( $ifIndex ) {
                my ( $status, $res ) = snmpwalk( $address, undef, "1.3.6.1.2.1.2.2.1.2", $community, $version );
                if ( $status != 0 ) {
                    my $msg = "Error occurred while looking up ifIndex for ifName $ifName in ifDescr table: $res";
                    $self->{LOGGER}->warn( $msg );
                }
                else {
                    foreach my $oid_ref ( @{$res} ) {
                        my $oid   = $oid_ref->[0];
                        my $type  = $oid_ref->[1];
                        my $value = $oid_ref->[2];

                        $self->{LOGGER}->debug( "$oid = $type: $value($ifName)" );
                        if ( $value eq $ifName and $oid =~ /1\.3\.6\.1\.2\.1\.2\.2\.1\.2\.(\d+)/x ) {
                            $ifIndex = $1;
                        }
                    }
                }
            }

            unless ( $ifIndex ) {
                my $msg = "Didn't find ifName $ifName in host $address";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }
        }

        unless ( $args->{snmp_clients}->{$address} ) {
            $args->{snmp_clients}->{$address} = perfSONAR_PS::Collectors::Status::ElementAgents::SNMP::Host->new( $address, q{}, $version, $community, q{} );
        }

        my $host_agent = $args->{snmp_clients}->{$address};

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::SNMP->new( $status_type, $address, $ifIndex, $version, $community, $oid, $host_agent );
    }
    else {
        my $msg = "Unknown agent type: \"$type\"";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    return ( 0, $new_agent );
}

=head2 parse_elements_file ( $self, { database_client, elements_file, directory_offset } )

A function which parses a file containing descriptions of individual elements
to monitor. This is included for backwards compatibility purposes. These
elements can be monitored using a combination of scripts, SNMP interfaces or
constant values. It iterates through the element descriptions in the file and
calls a function to parse each element.

=cut

sub parse_elements_file {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            database_client  => 1,
            elements_file    => 1,
            directory_offset => 0,
        }
    );

    my $file = $args->{elements_file};

    if ( $file !~ /^\// ) {
        $file = $args->{directory_offset} . "/" . $file;
    }

    my $filedb = perfSONAR_PS::DB::File->new( { file => $file } );
    $filedb->openDB;
    my $elements_config = $filedb->getDOM();

    my %defined_elements = ();
    my @elements         = ();
    foreach my $element ( $elements_config->getElementsByTagName( "element" ) ) {
        my ( $status, $res ) = $self->parse_elements_file_element( { xml_desc => $element, directory_offset => $args->{directory_offset} } );
        if ( $status != 0 ) {
            my $msg = "Failure parsing element: $res";
            $self->{LOGGER}->error( $msg );
            return ( -1, $res );
        }

        my $element = $res;

        foreach my $id ( @{ $element->{ids} } ) {
            if ( $defined_elements{$id} ) {
                my $msg = "Tried to redefine element $id";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }

            $defined_elements{$id} = 1;
        }

        push @elements, $element;
    }

    my $worker = perfSONAR_PS::Collectors::Status::ElementsWorker->new();
    my $status = $worker->init(
        data_client      => $args->{database_client},
        polling_interval => $args->{polling_interval},
        elements         => \@elements,
    );
    if ( $status != 0 ) {
        return ( -1, "Couldn't initialize Elements worker" );
    }

    return ( 0, [$worker] );
}

=head2 parse_element( $self, { xml_desc, directory_offset } )

A function to parse an XML representation of an element and create an hash
representation of that element.

=cut

sub parse_elements_file_element {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            xml_desc         => 1,
            directory_offset => 1,
        }
    );

    my $element_desc = $args->{xml_desc};

    # the raw SNMP clients are aggregated so that if individuals use SNMP
    # clients, we can use bulk pulls to grab the stats and cache them.
    my %snmp_clients = ();

    my @ids = ();

    foreach my $id_elm ( $element_desc->getElementsByTagName( "id" ) ) {
        my $id = $id_elm->textContent;

        push @ids, $id;
    }

    if ( scalar( @ids ) == 0 ) {
        my $msg = "No ids associated with specified element";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my @agents = ();

    foreach my $agent ( $element_desc->getElementsByTagName( "agent" ) ) {
        my ( $status, $res );

        ( $status, $res ) = $self->parse_elements_file_element_agent( { xml_desc => $agent, directory_offset => $args->{directory_offset}, snmp_clients => \%snmp_clients } );
        if ( $status != 0 ) {
            my $msg = "Problem parsing operational status agent for element: $res";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        push @agents, $res;
    }

    if ( scalar( @agents ) == 0 ) {
        my $msg = "Didn't specify any agents for link";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my %element = ();
    $element{ids}    = \@ids;
    $element{agents} = \@agents;

    return ( 0, \%element );
}

=head2 parse_element_agent( $self, { xml_desc, snmp_clients, directory_offset } )

A function which parses an XML representation of an agent. An agent can be
monitor by running a script, querying an SNMP interface or simply returning a
constant value. For an SNMP device, this routine will query for the ifIndex if
it is not specified.

=cut

sub parse_elements_file_element_agent {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            xml_desc         => 1,
            snmp_clients     => 1,
            directory_offset => 1,
        }
    );

    my $agent = $args->{xml_desc};

    my $new_agent;

    my $status_type = $agent->getAttribute( "status_type" );
    if ( not defined $status_type ) {
        my $msg = "Agent does not contain a status_type attribute stating which status (operational or administrative) it returns";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    if ( $status_type ne "oper" and $status_type ne "operational" and $status_type ne "admin" and $status_type ne "administrative" and $status_type ne "oper/admin" and $status_type ne "admin/oper" ) {
        my $msg = "Agent's stated status_type is neither 'oper' nor 'admin'";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    my $type = $agent->getAttribute( "type" );
    unless ( $type ) {
        my $msg = "Agent has no type information";
        $self->{LOGGER}->debug( $msg );
        return ( -1, $msg );
    }

    if ( $type eq "script" ) {
        my $script_name = $agent->findvalue( "script_name" );
        unless ( $script_name ) {
            my $msg = "Agent of type 'script' has no script name defined";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        if ( $script_name !~ "^/" ) {
            $script_name = $args->{directory_offset} . "/" . $script_name;
        }

        unless ( -x $script_name ) {
            my $msg = "Agent of type 'script' has non-executable script: \"$script_name\"";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        my $script_params = $agent->findvalue( "script_parameters" );

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::Script->new( $status_type, $script_name, $script_params );
    }
    elsif ( $type eq "constant" ) {
        my $value = $agent->findvalue( "constant" );
        unless ( $value ) {
            my $msg = "Agent of type 'constant' has no value defined";
            $self->{LOGGER}->debug( $msg );
            return ( -1, $msg );
        }

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::Constant->new( $status_type, $value );
    }
    elsif ( $type eq "snmp" ) {
        my $oid = $agent->findvalue( "oid" );
        unless ( $oid ) {
            if ( $status_type eq "oper" ) {
                $oid = "1.3.6.1.2.1.2.2.1.8";
            }
            elsif ( $status_type eq "admin" ) {
                $oid = "1.3.6.1.2.1.2.2.1.7";
            }
        }

        my $hostname = $agent->findvalue( 'hostname' );
        unless ( $hostname ) {
            my $msg = "Agent of type 'SNMP' has no hostname";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $ifName  = $agent->findvalue( 'ifName' );
        my $ifIndex = $agent->findvalue( 'ifIndex' );

        if ( ( not defined $ifIndex or $ifIndex eq q{} ) and ( not defined $ifName or $ifName eq q{} ) ) {
            my $msg = "Agent of type 'SNMP' has no name or index specified";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $version = $agent->findvalue( "version" );
        unless ( $version ) {
            my $msg = "Agent of type 'SNMP' has no snmp version";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        my $community = $agent->findvalue( "community" );
        unless ( $community ) {
            my $msg = "Agent of type 'SNMP' has no community string";
            $self->{LOGGER}->error( $msg );
            return ( -1, $msg );
        }

        unless ( $ifIndex ) {
            $self->{LOGGER}->debug( "Looking up $ifName from $hostname" );

            my ( $status, $res ) = snmpwalk( $hostname, undef, "1.3.6.1.2.1.31.1.1.1.1", $community, $version );
            if ( $status != 0 ) {
                my $msg = "Error occurred while looking up ifIndex for specified ifName $ifName in ifName table: $res";
                $self->{LOGGER}->warn( $msg );
            }
            else {
                foreach my $oid_ref ( @{$res} ) {
                    my $oid   = $oid_ref->[0];
                    my $type  = $oid_ref->[1];
                    my $value = $oid_ref->[2];

                    $self->{LOGGER}->debug( "$oid = $type: $value($ifName)" );
                    if ( $value eq $ifName and $oid =~ /1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.(\d+)/x ) {
                        $ifIndex = $1;
                    }
                }
            }

            if ( not $ifIndex ) {
                my ( $status, $res ) = snmpwalk( $hostname, undef, "1.3.6.1.2.1.2.2.1.2", $community, $version );
                if ( $status != 0 ) {
                    my $msg = "Error occurred while looking up ifIndex for ifName $ifName in ifDescr table: $res";
                    $self->{LOGGER}->warn( $msg );
                }
                else {
                    foreach my $oid_ref ( @{$res} ) {
                        my $oid   = $oid_ref->[0];
                        my $type  = $oid_ref->[1];
                        my $value = $oid_ref->[2];

                        $self->{LOGGER}->debug( "$oid = $type: $value($ifName)" );
                        if ( $value eq $ifName and $oid =~ /1\.3\.6\.1\.2\.1\.2\.2\.1\.2\.(\d+)/x ) {
                            $ifIndex = $1;
                        }
                    }
                }
            }

            if ( not $ifIndex ) {
                my $msg = "Didn't find ifName $ifName in host $hostname";
                $self->{LOGGER}->error( $msg );
                return ( -1, $msg );
            }
        }

        unless ( $args->{snmp_clients}->{$hostname} ) {
            $args->{snmp_clients}->{$hostname} = perfSONAR_PS::Collectors::Status::ElementAgents::SNMP::Host->new( $hostname, q{}, $version, $community, q{} );
        }

        my $host_agent = $args->{snmp_clients}->{$hostname};

        $new_agent = perfSONAR_PS::Collectors::Status::ElementAgents::SNMP->new( $status_type, $hostname, $ifIndex, $version, $community, $oid, $host_agent );
    }
    else {
        my $msg = "Unknown agent type: \"$type\"";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    return ( 0, $new_agent );
}

1;

__END__

=head1 SEE ALSO

L<POSIX>, L<English>, L<Log::Log4perl>, L<perfSONAR_PS::DB::File>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::ParameterValidation>,
L<perfSONAR_PS::DB::Status>,
L<perfSONAR_PS::Collectors::Status::ElementsWorker>, 
L<perfSONAR_PS::Collectors::Status::DeviceAgents::SNMP>, 
L<perfSONAR_PS::Collectors::Status::DeviceAgents::CoreDirector>, 
L<perfSONAR_PS::Collectors::Status::DeviceAgents::OME>, 
L<perfSONAR_PS::Collectors::Status::DeviceAgents::HDXc>, 
L<perfSONAR_PS::Collectors::Status::ElementAgents::Constant>, 
L<perfSONAR_PS::Collectors::Status::ElementAgents::SNMP>, 
L<perfSONAR_PS::Collectors::Status::ElementAgents::Script>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

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

Copyright (c) 2004-2010, Internet2

All rights reserved.

=cut

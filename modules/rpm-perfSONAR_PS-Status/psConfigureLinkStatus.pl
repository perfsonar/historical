#!/usr/bin/perl -w

#use strict;
use warnings;
use Config::General qw(ParseConfig SaveConfig);
use Sys::Hostname;
use English qw( -no_match_vars );
use Module::Load;
use File::Temp qw(tempfile);

my %enabled_services = (
    snmp => 0,
    ls => 0,
    perfsonarbuoy => 0,
    pingerma => 0,
    pingermp => 0,
    status => 1,
    circuitstatus => 0,
    topology => 0,    
);

=head1 NAME

psConfigureDaemon - Ask a series of questions to generate a configuration file.

=head1 DESCRIPTION

Ask questions based on a service to generate a configuration file.

=cut

my $was_installed = 0;
my $DEFAULT_FILE;
my $confdir;
my $conffile;

if ($was_installed) {
    $confdir = "XXX_CONFDIR_XXX";
    $conffile = "XXX_CONFFILE_XXX";
}
else {
    $confdir = ".";
    $conffile = "daemon.conf";
}

$DEFAULT_FILE = $confdir ."/". $conffile;

print " -- perfSONAR-PS Daemon Configuration --\n";
print " - [press enter for the default choice] -\n\n";

my $file = shift;

if ( not $file ) {
    $file = &ask( "What file should I write the configuration to? ", $DEFAULT_FILE, undef, '.+' );
}

my $tmp;
my $default_hostname = hostname();
my $hostname;

my %config = ();
if ( -f $file ) {
    %config = ParseConfig($file);
}

# make sure all the endpoints start with a "/".
if ( defined $config{"port"} ) {
    foreach my $port ( keys %{ $config{"port"} } ) {
        if ( defined $config{"port"}->{$port}->{"endpoint"} ) {
            foreach my $endpoint ( keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                my $new_endpoint = $endpoint;

                if ( $endpoint =~ /^[^\/]/mx ) {
                    $new_endpoint = "/" . $endpoint;
                }

                if ( $endpoint ne $new_endpoint ) {
                    $config{"port"}->{$port}->{"endpoint"}->{$new_endpoint} = $config{"port"}->{$port}->{"endpoint"}->{$endpoint};
                    delete( $config{"port"}->{$port}->{"endpoint"}->{$endpoint} );
                }
            }
        }
    }
}

while (1) {
    my $input;

    print "1) Add/Edit endpoint\n";
    print "2) Enable/Disable port/endpoint\n";
    print "3) Set global values\n";
    print "4) Save configuration\n";
    print "5) Exit\n";
    $input = &ask( "? ", q{}, undef, '[12345]' );

    if ( $input == 5 ) {
        exit(0);
    }
    elsif ( $input == 4 ) {
        if ( -f $file ) {
            system("mv $file $file~");
        }

        SaveConfig_mine( $file, \%config );
        print "\n";
        print "Saved config to $file\n";
        print "\n";
    }
    elsif ( $input == 3 ) {
        $config{"max_worker_processes"}     = &ask( "Enter the maximum number of children processes (0 means infinite) ",                   "0",                                                          $config{"max_worker_processes"},     '^\d+$' );
        $config{"max_worker_lifetime"}      = &ask( "Enter number of seconds a child can process before it is stopped (0 means infinite) ", "0",                                                          $config{"max_worker_lifetime"},      '^\d+$' );
        $config{"disable_echo"}             = &ask( "Disable echo by default (0 for yes, 1 for now) ",                                      0,                                                            $config{"disable_echo"},             '^[01]$' );
        $config{"ls_instance"}              = &ask( "The LS for MAs to register with ",                                                     "http://packrat.internet2.edu:8005/perfSONAR_PS/services/LS", $config{"ls_instance"},              '(^http|^$)' );
        $config{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ",                           60,                                                           $config{"ls_registration_interval"}, '^\d+$' );
        $config{"reaper_interval"}          = &ask( "Interval between when children are repeaed [in seconds] ",                             20,                                                           $config{"reaper_interval"},          '^\d+$' );
        $config{"pid_dir"}                  = &ask( "Enter pid dir location ",                                                              "/var/run",                                                   $config{"pid_dir"},                  q{} );
        $config{"pid_file"}                 = &ask( "Enter pid filename ",                                                                  "ps.pid",                                                     $config{"pid_file"},                 q{} );
    }
    elsif ( $input == 2 ) {
        my @elements = ();
        my %status   = ();

        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next if ( !defined $config{"port"}->{$port}->{"endpoint"} );
            push @elements, $port;

            if ( defined $config{"port"}->{$port}->{"disabled"} and $config{"port"}->{$port}->{"disabled"} == 1 ) {
                $status{$port} = 1;
            }
        }

        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next if ( !defined $config{"port"}->{$port}->{"endpoint"} );
            foreach my $endpoint ( sort keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                push @elements, "$port$endpoint";
                if ( defined $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"disabled"}
                    and $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"disabled"} == 1 )
                {
                    $status{"$port$endpoint"} = 1;
                }
            }
        }

        if ( $#elements > -1 ) {
            print "\n";
            print "Select element to enable/disable: \n";
            my $len = $#elements;
            for my $i ( 0 .. $len ) {
                print " $i) $elements[$i] ";
                print " *" if ( defined $status{ $elements[$i] } );
                print "\n";
            }
            print "\n";
            print " * element is disabled\n";
            print "\n";

            do {
                $input = &ask( "Select a number from the above ", q{}, undef, '^\d+$' );
            } while ( $input > $#elements );

            my $new_status;

            if ( defined $status{ $elements[$input] } ) {
                $new_status = 0;
            }
            else {
                $new_status = 1;
            }

            print "\n";
            if ($new_status) {
                print "Disabling";
            }
            else {
                print "Enabling";
            }

            if ( $elements[$input] =~ /^(\d+)(\/.*)$/mx ) {
                print " endpoint " . $elements[$input] . "\n";
                $config{"port"}->{$1}->{"endpoint"}->{$2}->{"disabled"} = $new_status;
            }
            elsif ( $elements[$input] =~ /^(\d+)$/mx ) {
                print " port " . $elements[$input] . "\n";
                $config{"port"}->{$1}->{"disabled"} = $new_status;
            }
            print "\n";
        }
    }
    elsif ( $input == 1 ) {
        my @endpoints = ();
        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next if ( !defined $config{"port"}->{$port}->{"endpoint"} );
            foreach my $endpoint ( sort keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                push @endpoints, "$port$endpoint";
            }
        }

        if ( $#endpoints > -1 ) {
            print "\n";
            print "Existing Endpoints: \n";
            my $len = $#endpoints;
            for my $i ( 0 .. $len ) {
                print " $i) $endpoints[$i]\n";
            }
            print "\n";
        }

        do {
            $input = &ask( "Enter endpoint in form 'port/endpoint_path' (e.g. 8080/perfSONAR_PS/services/SERVICE_NAME) or select from a number from the above ", q{}, undef, '^(\d+[\/].*|\d+)$' );
            if ( $input =~ /^\d+$/mx ) {
                $input = $endpoints[$input];
            }
        } while ( !( $input =~ /\d+[\/].*/mx ) );

        my ( $port, $endpoint );
        if ( $input =~ /(\d+)([\/].*)/mx ) {
            $port     = $1;
            $endpoint = $2;
        }

        if ( !defined $config{"port"} ) {
            my %hash = ();
            $config{"port"} = \%hash;
        }

        if ( !defined $config{"port"}->{$port} ) {
            my %hash = ();
            $config{"port"}->{$port} = \%hash;
            $config{"port"}->{$port}->{"endpoint"} = ();
        }

        if ( !defined $config{"port"}->{$port}->{"endpoint"}->{$endpoint} ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint} = ();
        }

        my $valid_module = 0;
        my $module       = $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"};
        if ( defined $module ) {
            if ( $module eq "perfSONAR_PS::Services::MA::SNMP" ) {
                $module = "snmp";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::Status" ) {
                $module = "status";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::CircuitStatus" ) {
                $module = "circuitstatus";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::Topology" ) {
                $module = "topology";
            }
            elsif ( $module eq "perfSONAR_PS::Services::LS::LS" ) {
                $module = "ls";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::perfSONARBUOY" ) {
                $module = "perfsonarbuoy";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::PingER" ) {
                $module = "pingerma";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MP::PingER" ) {
                $module = "pingermp";
            }
        }

        my %opts;
        do {
            my $module_list = q{};
            my $default_module_name;

            foreach my $module_name (keys %enabled_services) {
                 if ($enabled_services{$module_name}) {
                     $module_list .= ", " if ($module_list ne q{});
                     $module_list .= $module_name;

		     # if there's only one enabled service, it will be set here
		     # and become the default for new endpoints.
                     if ($default_module_name) {
                         $default_module_name = q{};
                     } else {
                         $default_module_name = $module_name;
                     }
                 }
            }

            if ($module) {
                $default_module_name = $module;
            }

            $module = &ask( "Enter endpoint module [$module_list] ", q{}, $default_module_name, q{} );
            $module = lc($module);

            if ($enabled_services{$module}) {
                $valid_module = 1;
            }
        } while ( $valid_module == 0 );

        if ( !defined $hostname ) {
            $hostname = &ask( "Enter the external host or IP for this machine ", $hostname, $default_hostname, '.+' );
        }

        my $accesspoint = &ask( "Enter the accesspoint for this service ", "http://$hostname:$port$endpoint", undef, '^http' );

        if ( $module eq "snmp" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::SNMP";
            config_snmp_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "status" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::Status";
            config_status_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "circuitstatus" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::CircuitStatus";
            config_circuitstatus_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "topology" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::Topology";
            config_topology_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "ls" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::LS::LS";
            config_ls( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "perfsonarbuoy" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::perfSONARBUOY";
            config_perfsonarbuoy_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ($module eq "pingerma") {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::PingER";
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"service_type"} = "MA";
            config_pinger($config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config, "pingerma");
        }
        elsif ($module eq "pingermp") {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MP::PingER";
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"service_type"} = "MP";
            config_pinger($config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config, "pingermp");
        }
    }
}

sub config_ls {
    my ( $config, $accesspoint, $def_config ) = @_;

    if ( !defined $config->{"ls"} ) {
        $config->{"ls"} = ();
    }

    $config->{"ls"}->{"ls_ttl"}           = &ask( "Enter default TTL for registered data [in minutes] ",                                   "60",                $config->{"ls"}->{"ls_ttl"},           '\d+' );
    $config->{"ls"}->{"metadata_db_name"} = &ask( "Enter the directory of the XML database ",                                              $confdir . "/xmldb", $config->{"ls"}->{"metadata_db_name"}, '^\/' );
    $config->{"ls"}->{"metadata_db_file"} = &ask( "Enter the name of the container inside of the XML database ",                           "store.dbxml",       $config->{"ls"}->{"metadata_db_file"}, '.+' );
    $config->{"ls"}->{"reaper_interval"}  = &ask( "Should the LS periodically remove old registration information (0 for no, 1 for yes) ", "0",                 $config->{"ls"}->{"reaper_interval"},  '^[01]$' );
    if ( $config->{"ls"}->{"reaper_interval"} ) {
        $config->{"ls"}->{"reaper_interval"} = &ask( "Enter the time between LS removal [in minutes] ", "30", "30", '^\d+$' );
    }

    $config->{"ls"}->{"service_name"} = &ask( "Enter a name for this service ", "Lookup Service", $config->{"ls"}->{"service_name"}, '.+' );

    $config->{"ls"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"ls"}->{"service_type"}, '.+' );

    $config->{"ls"}->{"service_description"} = &ask( "Enter a service description ", "Lookup Service", $config->{"ls"}->{"service_description"}, '.+' );

    $config->{"ls"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"ls"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_perfsonarbuoy_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    my $amiconfdir = $confdir;

    $config->{"perfsonarbuoy"}->{"owmesh"} = &ask( "Enter the directory *LOCATION* of the 'owmesh.conf' file: ", $amiconfdir, $config->{"perfsonarbuoy"}->{"owmesh"}, '.+' );
    $amiconfdir = $config->{"perfsonarbuoy"}->{"owmesh"};

    $config->{"perfsonarbuoy"}->{"metadata_db_type"} = &ask( "Enter the database type to read from (file or xmldb) ", "file", $config->{"perfsonarbuoy"}->{"metadata_db_type"}, '(file|xmldb)' );

    if ( $config->{"perfsonarbuoy"}->{"metadata_db_type"} eq "file" ) {
        delete $config->{"perfsonarbuoy"}->{"metadata_db_file"} if $config->{"perfsonarbuoy"}->{"metadata_db_file"} and $config->{"perfsonarbuoy"}->{"metadata_db_file"} =~ m/dbxml$/mx;
        $config->{"perfsonarbuoy"}->{"metadata_db_file"} = &ask( "Enter the filename of the XML file ", $amiconfdir . "/store.xml", $config->{"perfsonarbuoy"}->{"metadata_db_file"}, '\.xml$' );
    }
    elsif ( $config->{"perfsonarbuoy"}->{"metadata_db_type"} eq "xmldb" ) {
        $config->{"perfsonarbuoy"}->{"metadata_db_name"} = &ask( "Enter the directory of the XML database ", $amiconfdir . "/xmldb", $config->{"perfsonarbuoy"}->{"metadata_db_name"}, '.+' );
        delete $config->{"perfsonarbuoy"}->{"metadata_db_file"} if $config->{"perfsonarbuoy"}->{"metadata_db_file"} and $config->{"perfsonarbuoy"}->{"metadata_db_file"} =~ m/\.xml$/mx;
        $config->{"perfsonarbuoy"}->{"metadata_db_file"} = &ask( "Enter the name of the container inside of the XML database ", "store.dbxml", $config->{"perfsonarbuoy"}->{"metadata_db_file"}, '.+' );
    }

    $config->{"perfsonarbuoy"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes)", "0", $config->{"perfsonarbuoy"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"perfsonarbuoy"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"perfsonarbuoy"}->{"ls_registration_interval"} if ( defined $config->{"perfsonarbuoy"}->{"ls_registration_interval"} );
        $config->{"perfsonarbuoy"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"perfsonarbuoy"}->{"ls_instance"} if ( defined $config->{"perfsonarbuoy"}->{"ls_instance"} );
        $config->{"perfsonarbuoy"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );
    }

    $config->{"perfsonarbuoy"}->{"service_name"} = &ask( "Enter a name for this service ", "perfSONARBUOY MA", $config->{"perfsonarbuoy"}->{"service_name"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"perfsonarbuoy"}->{"service_type"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_description"} = &ask( "Enter a service description ", "perfSONARBUOY MA", $config->{"perfsonarbuoy"}->{"service_description"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"perfsonarbuoy"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_snmp_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    my $rrdtool = q{};
    if ( open( RRDTOOL, "which rrdtool |" ) ) {
        $rrdtool = <RRDTOOL>;
        $rrdtool =~ s/rrdtool:\s+//mx;
        $rrdtool =~ s/\n//gmx;
        unless ( close(RRDTOOL) ) {
            return -1;
        }
    }

    unless ($rrdtool) {
        return -1;
    }

    $config->{"snmp"}->{"rrdtool"} = &ask( "Enter the location of the RRD binary ", $rrdtool, $config->{"snmp"}->{"rrdtool"}, '.+' );

    $config->{"snmp"}->{"default_resolution"} = &ask( "Enter the default resolution of RRD queries ", "300", $config->{"snmp"}->{"default_resolution"}, '^\d+$' );

    $config->{"snmp"}->{"metadata_db_type"} = &ask( "Enter the database type to read from (file or xmldb) ", "file", $config->{"snmp"}->{"metadata_db_type"}, '(file|xmldb)' );

    my $makeStore = &ask( "Automatically generate a 'test' metadata database (0 for no, 1 for yes) ", "0", "0", '^[01]$' );
    if ( $makeStore ) {
        eval { 
#            load RRDp; 
            use RRDp; 
            $RRDp::error_mode = 'catch';
            RRDp::start $config->{"snmp"}->{"rrdtool"};
            my $cmd .= "create ".$confdir."/localhost.rrd --start N --step 1 ";
            $cmd .= "DS:ifinoctets:COUNTER:10:U:U ";
            $cmd .= "DS:ifoutoctets:COUNTER:10:U:U ";
            $cmd .= "DS:ifinerrors:COUNTER:10:U:U ";
            $cmd .= "DS:ifouterrors:COUNTER:10:U:U ";
            $cmd .= "DS:ifindiscards:COUNTER:10:U:U ";
            $cmd .= "DS:ifoutdiscards:COUNTER:10:U:U ";
            $cmd .= "RRA:AVERAGE:0.5:1:241920 ";
            $cmd .= "RRA:AVERAGE:0.5:2:120960 ";
            $cmd .= "RRA:AVERAGE:0.5:6:40320 ";
            $cmd .= "RRA:AVERAGE:0.5:12:20160 ";
            $cmd .= "RRA:AVERAGE:0.5:24:10080 "; 
            $cmd .= "RRA:AVERAGE:0.5:36:6720 ";
            $cmd .= "RRA:AVERAGE:0.5:48:5040 ";
            $cmd .= "RRA:AVERAGE:0.5:60:4032 ";
            $cmd .= "RRA:AVERAGE:0.5:120:2016";
            RRDp::cmd $cmd;
            my $answer = RRDp::read;
        };
        if ($EVAL_ERROR) {
            return -1;
        }

        my($fileHandle, $fileName) = tempfile();
        $makeStore = $fileName;
        print $fileHandle "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
        print $fileHandle "<nmwg:store  xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
        print $fileHandle "             xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
        print $fileHandle "             xmlns:neterr=\"http://ggf.org/ns/nmwg/characteristic/errors/2.0/\"\n";
        print $fileHandle "             xmlns:netdisc=\"http://ggf.org/ns/nmwg/characteristic/discards/2.0/\"\n";
        print $fileHandle "             xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"\n";
        print $fileHandle "             xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\"\n";
        print $fileHandle "             xmlns:nmtm=\"http://ggf.org/ns/nmwg/time/2.0/\">\n\n";
        foreach my $et (("netutil", "neterr", "netdisc")) {
            foreach my $dir (("in", "out")) {
                print $fileHandle "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"m-".$dir."-".$et."-1\">\n";
                if($et eq "netutil") {
                    print $fileHandle "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s-".$dir."-".$et."-1\">\n";
                }
                elsif($et eq "neterr") {
                    print $fileHandle "    <neterr:subject xmlns:neterr=\"http://ggf.org/ns/nmwg/characteristic/errors/2.0/\" id=\"s-".$dir."-".$et."-1\">\n";
                }
                elsif($et eq "netdisc") {
                    print $fileHandle "    <netdisc:subject xmlns:netdisc=\"http://ggf.org/ns/nmwg/characteristic/discards/2.0/\" id=\"s-".$dir."-".$et."-1\">\n";
                }
                print $fileHandle "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
                print $fileHandle "        <nmwgt:ifAddress type=\"ipv4\">127.0.0.1</nmwgt:ifAddress>\n";
                print $fileHandle "        <nmwgt:hostName>localhost</nmwgt:hostName>\n";
                print $fileHandle "        <nmwgt:ifName>eth0</nmwgt:ifName>\n";
                print $fileHandle "        <nmwgt:ifIndex>2</nmwgt:ifIndex>\n";
                print $fileHandle "        <nmwgt:direction>".$dir."</nmwgt:direction>\n";
                print $fileHandle "        <nmwgt:capacity>1000000000</nmwgt:capacity>\n";
                print $fileHandle "      </nmwgt:interface>\n";
                if($et eq "netutil") {
                    print $fileHandle "    </netutil:subject>\n";
                    print $fileHandle "    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>\n";
                }
                elsif($et eq "neterr") {
                    print $fileHandle "    </neterr:subject>\n";
                    print $fileHandle "    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/errors/2.0</nmwg:eventType>\n";
                }      
                elsif($et eq "netdisc") {
                    print $fileHandle "    </netdisc:subject>\n";
                    print $fileHandle "    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/discards/2.0</nmwg:eventType>\n";
                }     
                print $fileHandle "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:eventType>\n";
                print $fileHandle "  </nmwg:metadata>\n\n";
 
                print $fileHandle "  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"d-".$dir."-".$et."-1\" metadataIdRef=\"m-".$dir."-".$et."-1\">\n";
                print $fileHandle "    <nmwg:key id=\"k-".$dir."-".$et."-1\">\n";
                print $fileHandle "      <nmwg:parameters id=\"pk-".$dir."-".$et."-1\">\n";
                print $fileHandle "        <nmwg:parameter name=\"eventType\">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>\n";
                if($et eq "netutil") {
                    print $fileHandle "        <nmwg:parameter name=\"eventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>\n";             
                }
                elsif($et eq "neterr") {
                    print $fileHandle "        <nmwg:parameter name=\"eventType\">http://ggf.org/ns/nmwg/characteristic/errors/2.0</nmwg:parameter>\n";             
                }     
                elsif($et eq "netdisc") {
                    print $fileHandle "        <nmwg:parameter name=\"eventType\">http://ggf.org/ns/nmwg/characteristic/discards/2.0</nmwg:parameter>\n";             
                }    
                print $fileHandle "        <nmwg:parameter name=\"type\">rrd</nmwg:parameter>\n";
                print $fileHandle "        <nmwg:parameter name=\"file\">".$confdir."/localhost.rrd</nmwg:parameter>\n";
                if($et eq "netutil") {        
                    print $fileHandle "        <nmwg:parameter name=\"valueUnits\">Bps</nmwg:parameter>\n";
                    print $fileHandle "        <nmwg:parameter name=\"dataSource\">if".$dir."octets</nmwg:parameter>\n";
                }
                elsif($et eq "neterr") {
                    print $fileHandle "        <nmwg:parameter name=\"valueUnits\">Eps</nmwg:parameter>\n";
                    print $fileHandle "        <nmwg:parameter name=\"dataSource\">if".$dir."errors</nmwg:parameter>\n";
                }                
                elsif($et eq "netdisc") {
                    print $fileHandle "        <nmwg:parameter name=\"valueUnits\">Dps</nmwg:parameter>\n";
                    print $fileHandle "        <nmwg:parameter name=\"dataSource\">if".$dir."discards</nmwg:parameter>\n";
                }   
                print $fileHandle "      </nmwg:parameters>\n";
                print $fileHandle "    </nmwg:key>\n";
                print $fileHandle "  </nmwg:data>\n\n";
            }
        }
        print $fileHandle "</nmwg:store>\n";
        close($fileHandle);
    }

    if ( $config->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        delete $config->{"snmp"}->{"metadata_db_file"} if $config->{"snmp"}->{"metadata_db_file"} and $config->{"snmp"}->{"metadata_db_file"} =~ m/dbxml$/mx;
        $config->{"snmp"}->{"metadata_db_file"} = &ask( "Enter the filename of the XML file ", $confdir . "/store.xml", $config->{"snmp"}->{"metadata_db_file"}, '\.xml$' );
        if ( $makeStore ) {
            if ( -f $config->{"snmp"}->{"metadata_db_file"} ) {
                system("mv " . $config->{"snmp"}->{"metadata_db_file"} . " " . $config->{"snmp"}->{"metadata_db_file"} . "~");
            }
            system( "mv " . $makeStore . " " . $config->{"snmp"}->{"metadata_db_file"});
        }
        delete $config->{"snmp"}->{"db_autoload"}               if $config->{"snmp"}->{"db_autoload"};
        delete $config->{"snmp"}->{"autoload_metadata_db_file"} if $config->{"snmp"}->{"autoload_metadata_db_file"};
        delete $config->{"snmp"}->{"metadata_db_name"}          if $config->{"snmp"}->{"metadata_db_name"};
    }
    elsif ( $config->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        $config->{"snmp"}->{"metadata_db_name"} = &ask( "Enter the directory of the XML database ", $confdir . "/xmldb", $config->{"snmp"}->{"metadata_db_name"}, '.+' );
        delete $config->{"snmp"}->{"metadata_db_file"} if $config->{"snmp"}->{"metadata_db_file"} and $config->{"snmp"}->{"metadata_db_file"} =~ m/\.xml$/mx;
        $config->{"snmp"}->{"metadata_db_file"} = &ask( "Enter the name of the container inside of the XML database ", "store.dbxml", $config->{"snmp"}->{"metadata_db_file"}, '.+' );

        if ( $makeStore ) {
            $config->{"snmp"}->{"db_autoload"} = 1;
            $config->{"snmp"}->{"autoload_metadata_db_file"} = &ask( "Enter the filename of the base XML file to load ", $confdir . "/store.xml", $config->{"snmp"}->{"autoload_metadata_db_file"}, '\.xml$' );
            if ( -f $config->{"snmp"}->{"autoload_metadata_db_file"} ) {
                system("mv " . $config->{"snmp"}->{"autoload_metadata_db_file"} . " " . $config->{"snmp"}->{"autoload_metadata_db_file"} . "~");
            }
            system( "mv " . $makeStore . " " . $config->{"snmp"}->{"metadata_db_file"});
        }
        else {
            $config->{"snmp"}->{"db_autoload"} = &ask( "Would you like to auto-load the database [non-destructive] ? (0 for no, 1 for yes) ", "1", $config->{"snmp"}->{"db_autoload"}, '^[01]$' );
            if ( $config->{"snmp"}->{"db_autoload"} eq "1" ) {
                $config->{"snmp"}->{"autoload_metadata_db_file"} = &ask( "Enter the filename of the base XML file to load ", $confdir . "/store.xml", $config->{"snmp"}->{"autoload_metadata_db_file"}, '\.xml$' );            
            }
        }
    }

    $config->{"snmp"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes) ", "0", $config->{"snmp"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"snmp"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"snmp"}->{"ls_registration_interval"} if ( defined $config->{"snmp"}->{"ls_registration_interval"} );
        $config->{"snmp"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"snmp"}->{"ls_instance"} if ( defined $config->{"snmp"}->{"ls_instance"} );
        $config->{"snmp"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );
    }

    $config->{"snmp"}->{"service_name"} = &ask( "Enter a name for this service ", "SNMP MA", $config->{"snmp"}->{"service_name"}, '.+' );

    $config->{"snmp"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"snmp"}->{"service_type"}, '.+' );

    $config->{"snmp"}->{"service_description"} = &ask( "Enter a service description ", "SNMP MA", $config->{"snmp"}->{"service_description"}, '.+' );

    $config->{"snmp"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"snmp"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_pinger {
	my ($config, $accesspoint, $def_config, $modulename) = @_;
	my $moduletype = ($modulename =~ /ma$/ ? "MA" : "MP");

	$config->{$modulename}->{"db_type"} = &ask("Enter the database type to read from (sqlite,mysql) ", "mysql", $config->{$modulename}->{"db_type"}, '^(sqlite|mysql)$');

	if ($config->{$modulename}->{"db_type"} eq "sqlite") {
		$config->{$modulename}->{"db_file"} = &ask("Enter the filename of the SQLite database ", "pinger.db", $config->{$modulename}->{"db_file"}, '.+');
	} elsif ($config->{$modulename}->{"db_type"} eq "mysql") {
		$config->{$modulename}->{"db_name"} = &ask("Enter the name of the MySQL database ", "", $config->{$modulename}->{"db_name"}, '.+');
		$config->{$modulename}->{"db_host"} = &ask("Enter the host for the MySQL database ", "localhost", $config->{$modulename}->{"db_host"}, '.+');
		$tmp = &ask("Enter the port for the MySQL database (leave blank for the default) ", "", $config->{$modulename}->{"db_port"}, '^\d*$');
		$config->{$modulename}->{"db_port"} = $tmp if ($tmp ne "");
		$tmp = &ask("Enter the username for the MySQL database (leave blank for none) ", "", $config->{$modulename}->{"db_username"}, '');
		$config->{$modulename}->{"db_username"} = $tmp if ($tmp ne "");
		$tmp  = &ask("Enter the password for the MySQL database (leave blank for none) ", "", $config->{$modulename}->{"db_password"}, '');
		$config->{$modulename}->{"db_password"} = $tmp if ($tmp ne "");
	}

	if($modulename eq "pingermp") {
		$config->{$modulename}->{"configuration_file"} = &ask("Name of XML configuration file for landmarks and schedules ", "/etc/perfsonar/pinger-landmarks.xml", $config->{$modulename}->{"configuration_file"}, '.+');
	}
	
	if($modulename eq "pingerma") {
	  $config->{$modulename}->{"query_size_limit"} = &ask("Enter the limit on query size ", "100000", $config->{$modulename}->{"query_size_limit"}, '^\d*$');
  }

	$config->{$modulename}->{"enable_registration"} = &ask("Will this service register with an LS (0,1) ", "0", $config->{$modulename}->{"enable_registration"}, '^[01]$');

	if($config->{$modulename}->{"enable_registration"} eq "1") {
		my $registration_interval = $def_config->{"ls_registration_interval"};
		$registration_interval = $config->{$modulename}->{"ls_registration_interval"} if (defined $config->{$modulename}->{"ls_registration_interval"});
		$config->{$modulename}->{"ls_registration_interval"} = &ask("Enter the number of minutes between LS registrations ", "30", $registration_interval, '^\d+$');

		$config->{$modulename}->{"service_name"} = &ask("Enter a name for this service ", "PingER $moduletype", $config->{$modulename}->{"service_name"}, '.+');

#		$config->{$modulename}->{"service_type"} = &ask("Enter the service type ", $moduletype, $config->{$modulename}->{"service_type"}, '.+');

		$config->{$modulename}->{"service_description"} = &ask("Enter a service description ", "PingER $moduletype", $config->{$modulename}->{"service_description"}, '.+');

		$config->{$modulename}->{"service_accesspoint"} = &ask("Enter the service's URI ", $accesspoint, $config->{$modulename}->{"service_accesspoint"}, '^http:\/\/');
	}
}

sub config_status_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"status"}->{"read_only"} = &ask( "Is this service read-only  (0 for no, 1 for yes) ", "0", $config->{"status"}->{"read_only"}, '^[01]$' );

    $config->{"status"}->{"db_type"} = &ask( "Enter the database type to read from ", "sqlite|mysql", $config->{"status"}->{"db_type"}, '(sqlite|mysql)' );

    if ( $config->{"status"}->{"db_type"} eq "sqlite" ) {
        $config->{"status"}->{"db_file"} = &ask( "Enter the filename of the SQLite database ", "$confdir/status.db", $config->{"status"}->{"db_file"}, '.+' );
        $tmp = &ask( "Enter the table in the database to use ", "link_status", $config->{"status"}->{"db_table"}, '.+' );
        $config->{"status"}->{"db_table"} = $tmp if ($tmp);
    }
    elsif ( $config->{"status"}->{"db_type"} eq "mysql" ) {
        $config->{"status"}->{"db_name"} = &ask( "Enter the name of the MySQL database ",                               "linkstatus", $config->{"status"}->{"db_name"}, '.+' );
        $config->{"status"}->{"db_host"} = &ask( "Enter the host for the MySQL database ",                              "localhost",  $config->{"status"}->{"db_host"}, '.+' );
        $tmp                             = &ask( "Enter the port for the MySQL database (leave blank for the default)", q{},          $config->{"status"}->{"db_port"}, '^\d*$' );
        $config->{"status"}->{"db_port"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the username for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"db_username"}, q{} );
        $config->{"status"}->{"db_username"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the password for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"db_password"}, q{} );
        $config->{"status"}->{"db_password"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the table in the database to use (leave blank for the default) ", "link_status", $config->{"status"}->{"db_table"}, q{} );
        $config->{"status"}->{"db_table"} = $tmp if ($tmp);
    }

    $config->{"status"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes) ", "0", $config->{"status"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"status"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"status"}->{"ls_registration_interval"} if ( defined $config->{"status"}->{"ls_registration_interval"} );
        $config->{"status"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"status"}->{"ls_instance"} if ( defined $config->{"status"}->{"ls_instance"} );
        $config->{"status"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );

        $config->{"status"}->{"service_name"} = &ask( "Enter a name for this service ", "Link Status MA", $config->{"status"}->{"service_name"}, '.+' );

        $config->{"status"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"status"}->{"service_type"}, '.+' );

        $config->{"status"}->{"service_description"} = &ask( "Enter a service description ", "Link Status MA", $config->{"status"}->{"service_description"}, '.+' );

        $config->{"status"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"status"}->{"service_accesspoint"}, '^http:\/\/' );
    }

    $config->{"status"}->{"enable_e2emon_compatibility"} = &ask( "Enable E2EMon compatibility? (0 for no, 1 for yes) ", "0", $config->{"status"}->{"enable_e2emon_compatibility"}, '^[01]$' );

    if ( $config->{"status"}->{"enable_e2emon_compatibility"} eq "1" ) {
        $config->{"status"}->{"e2emon_definitions_file"} = &ask("Enter the file to read the E2EMon compatibility information from", "$confdir/e2emon_compat.conf", $config->{"status"}->{"e2emon_definitions_file"}, '^.+$');
    }

    return;
}

sub config_circuitstatus_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"circuitstatus"}->{"circuits_file_type"} = "file";

    $config->{"circuitstatus"}->{"circuits_file"} = &ask( "Enter the file to get link information from ", q{}, $config->{"circuitstatus"}->{"circuits_file"}, '.+' );

    $config->{"circuitstatus"}->{"status_ma_type"} = &ask( "Enter the MA to get status information from ", "sqlite|mysql", $config->{"circuitstatus"}->{"status_ma_type"}, '(sqlite|mysql|ma|ls)' );

    if ( $config->{"circuitstatus"}->{"status_ma_type"} eq "ma" ) {
        $config->{"circuitstatus"}->{"status_ma_uri"} = &ask( "Enter the URI of the Status MA ", q{}, $config->{"circuitstatus"}->{"status_ma_uri"}, '^http' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "ls" ) {
        my $ls = $def_config->{"ls_instance"};
        $ls = $config->{"circuitstatus"}->{"ls_instance"} if ( defined $config->{"circuitstatus"}->{"ls_instance"} );
        $config->{"circuitstatus"}->{"ls_instance"} = &ask( "Enter the URI of the LS to get MA information from ", q{}, $ls, '^http' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "sqlite" ) {
        $config->{"circuitstatus"}->{"status_ma_name"}  = &ask( "Enter the filename of the SQLite database ", q{},           $config->{"status"}->{"status_ma_name"},  '.+' );
        $config->{"circuitstatus"}->{"status_ma_table"} = &ask( "Enter the table in the database to use ",    "link_status", $config->{"status"}->{"status_ma_table"}, '.+' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "mysql" ) {
        $config->{"status"}->{"status_ma_name"} = &ask( "Enter the name of the MySQL database ",                               q{},         $config->{"status"}->{"status_ma_name"}, '.+' );
        $config->{"status"}->{"status_ma_host"} = &ask( "Enter the host for the MySQL database ",                              "localhost", $config->{"status"}->{"status_ma_host"}, '.+' );
        $tmp                                    = &ask( "Enter the port for the MySQL database (leave blank for the default)", q{},         $config->{"status"}->{"status_ma_port"}, '^\d*$' );
        $config->{"status"}->{"status_ma_port"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the username for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"status_ma_username"}, q{} );
        $config->{"status"}->{"status_ma_username"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the password for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"status_ma_password"}, q{} );
        $config->{"status"}->{"status_ma_password"} = $tmp if ($tmp);
        $config->{"circuitstatus"}->{"status_ma_table"} = &ask( "Enter the table in the database to use ", "link_status", $config->{"status"}->{"status_ma_table"}, '.+' );
    }

    $config->{"circuitstatus"}->{"topology_ma_type"} = &ask( "Enter the MA to get Topology information from ", "sqlite|mysql", $config->{"circuitstatus"}->{"topology_ma_type"}, '(xml|ma|none)' );

    $config->{"circuitstatus"}->{"topology_ma_type"} = lc( $config->{"circuitstatus"}->{"topology_ma_type"} );

    if ( $config->{"circuitstatus"}->{"topology_ma_type"} eq "xml" ) {
        $config->{"topology"}->{"topology_ma_name"} = &ask( "Enter the directory of the XML database ", q{}, $config->{"topology"}->{"topology_ma_name"}, '.+' );
        $config->{"topology"}->{"topology_ma_file"} = &ask( "Enter the filename of the XML database ",  q{}, $config->{"topology"}->{"topology_ma_file"}, '.+' );
    }
    elsif ( $config->{"circuitstatus"}->{"topology_ma_type"} eq "ma" ) {
        $config->{"circuitstatus"}->{"topology_ma_uri"} = &ask( "Enter the URI of the Status MA ", q{}, $config->{"circuitstatus"}->{"topology_ma_uri"}, '^http' );
    }

    $config->{"circuitstatus"}->{"cache_length"} = &ask( "Enter length of time to cache 'current' results ", q{}, $config->{"circuitstatus"}->{"cache_length"}, '^\d+$' );
    if ( $config->{"circuitstatus"}->{"cache_length"} > 0 ) {
        $config->{"circuitstatus"}->{"cache_file"} = &ask( "Enter file to cache 'current' results in ", q{}, $config->{"circuitstatus"}->{"cache_file"}, '.+' );
    }

    $config->{"circuitstatus"}->{"max_recent_age"} = &ask( "Enter age in seconds at which a result is considered stale ", q{}, $config->{"circuitstatus"}->{"max_recent_age"}, '^\d+$' );
    return;
}

sub config_topology_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"topology"}->{"db_type"} = "xml";

    $config->{"topology"}->{"read_only"} = &ask( "Is this service read-only (0 for no, 1 for yes) ", "1", $config->{"topology"}->{"read_only"}, '^[01]$' );

    $config->{"topology"}->{"db_environment"} = &ask( "Enter the directory of the XML database ", q{}, $config->{"topology"}->{"db_environment"}, '.+' );

    $config->{"topology"}->{"db_file"} = &ask( "Enter the filename of the XML database ", q{}, $config->{"topology"}->{"db_file"}, '.+' );

    $config->{"topology"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes) ", "0", $config->{"topology"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"topology"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"topology"}->{"ls_registration_interval"} if ( defined $config->{"topology"}->{"ls_registration_interval"} );
        $config->{"topology"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"topology"}->{"ls_instance"} if ( defined $config->{"topology"}->{"ls_instance"} );
        $config->{"topology"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );

        $config->{"topology"}->{"service_name"} = &ask( "Enter a name for this service ", "Topology MA", $config->{"topology"}->{"service_name"}, '.+' );

        $config->{"topology"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"topology"}->{"service_type"}, '.+' );

        $config->{"topology"}->{"service_description"} = &ask( "Enter a service description ", "Topology MA", $config->{"topology"}->{"service_description"}, '.+' );

        $config->{"topology"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"topology"}->{"service_accesspoint"}, '^http:\/\/' );
    }
    return;
}

sub ask {
    my ( $prompt, $value, $prev_value, $regex ) = @_;

    my $result;
    do {
        print $prompt;
        if ( defined $prev_value ) {
            print "[", $prev_value, "]";
        }
        elsif ( defined $value ) {
            print "[", $value, "]";
        }
        print ": ";
        local $| = 1;
        local $_ = <STDIN>;
        chomp;
        if ( defined $_ and $_ ne q{} ) {
            $result = $_;
        }
        elsif ( defined $prev_value ) {
            $result = $prev_value;
        }
        elsif ( defined $value ) {
            $result = $value;
        }
        else {
            $result = q{};
        }
    } while ( $regex and ( not $result =~ /$regex/mx ) );

    return $result;
}

sub SaveConfig_mine {
    my ( $file, $hash ) = @_;

    my $fh;

    if ( open( $fh, ">", $file ) ) {
        printValue( $fh, q{}, $hash, -4 );
        if ( close($fh) ) {
            return 0;
        }
    }
    return -1;
}

sub printSpaces {
    my ( $fh, $count ) = @_;
    while ( $count > 0 ) {
        print $fh " ";
        $count--;
    }
    return;
}

sub printScalar {
    my ( $fileHandle, $name, $value, $depth ) = @_;

    printSpaces( $fileHandle, $depth );
    if ( $value =~ /\n/mx ) {
        my @lines = split( $value, '\n' );
        print $fileHandle "$name     <<EOF\n";
        foreach my $line (@lines) {
            printSpaces( $fileHandle, $depth );
            print $fileHandle $line . "\n";
        }
        printSpaces( $fileHandle, $depth );
        print $fileHandle "EOF\n";
    }
    else {
        print $fileHandle "$name     " . $value . "\n";
    }
    return;
}

sub printValue {
    my ( $fileHandle, $name, $value, $depth ) = @_;

    if ( ref $value eq "" ) {
        printScalar( $fileHandle, $name, $value, $depth );

        return;
    }
    elsif ( ref $value eq "ARRAY" ) {
        foreach my $elm ( @{$value} ) {
            printValue( $fileHandle, $name, $elm, $depth );
        }

        return;
    }
    elsif ( ref $value eq "HASH" ) {
        if ( $name eq "endpoint" or $name eq "port" ) {
            foreach my $elm ( sort keys %{$value} ) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "<$name $elm>\n";
                printValue( $fileHandle, q{}, $value->{$elm}, $depth + 4 );
                printSpaces( $fileHandle, $depth );
                print $fileHandle "</$name>\n";
            }
        }
        else {
            if ($name) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "<$name>\n";
            }
            foreach my $elm ( sort keys %{$value} ) {
                printValue( $fileHandle, $elm, $value->{$elm}, $depth + 4 );
            }
            if ($name) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "</$name>\n";
            }
        }

        return;
    }
}

__END__
	
=head1 SEE ALSO

L<Config::General>, L<Sys::Hostname>, L<Data::Dumper>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu
Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

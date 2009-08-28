package perfSONAR_PS::DB::TL1Counters;

use strict;
use warnings;

use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::Utils::DNS qw(query_location);
use perfSONAR_PS::Common qw(genuid);

use Log::Log4perl qw(get_logger);
use Storable qw(freeze thaw lock_store lock_nstore lock_retrieve);
use Data::Dumper;
use Cache::FastMmap;

use fields 'LOGGER', 'METADATA', 'METADATA_FILE', 'DATA_DIRECTORY', 'STORE_FILE', 'DATA_TYPES', 'RRD_PATH', 'RRD_CREATE_PARAMETERS', 'RRD_STEP', 'MAX_TIMEOUT';

my %defaults = (
        rrd_path => "/usr/bin/rrdtool",
        rrd_create_parameters => 'RRA:%consolidation%:0.5:1:241920 RRA:%consolidation%:0.5:2:120960 RRA:%consolidation%:0.5:6:40320 RRA:%consolidation%:0.5:12:20160 RRA:%consolidation%:0.5:24:10080 RRA:%consolidation%:0.5:36:6720 RRA:%consolidation%:0.5:48:5040 RRA:%consolidation%:0.5:60:4032 RRA:%consolidation%:0.5:120:2016',
        rrd_step => 30,
);

my %data_types = (
        "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" => {
                values => { "utilization" => "COUNTER" },
                consolidation => [ "AVERAGE" ],
                units => "Bps",
        },
        "http://ggf.org/ns/nmwg/characteristic/errors/2.0" => {
                values => { "errors" => "COUNTER" },
                consolidation => [ "AVERAGE" ],
                units => "Pps",
        },
        "http://ggf.org/ns/nmwg/characteristic/discards/2.0" => {
                values => { "discards" => "COUNTER" },
                consolidation => [ "AVERAGE" ],
                units => "Pps",
        },
        "http://ggf.org/ns/nmwg/characteristic/packets/2.0" => {
                values => { "packets" => "COUNTER" },
                consolidation => [ "AVERAGE" ],
                units => "Pps",
        },
        "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0" => {
                values => { "oper_status" => "GAUGE" },
                consolidation => [ "MAX" ],
        },
        "http://ggf.org/ns/nmwg/characteristic/interface/status/administrative/2.0" => {
                values => { "admin_status" => "GAUGE" },
                consolidation => [ "MAX" ],
        },
        "http://ggf.org/ns/nmwg/characteristic/interface/capacity/provisioned/2.0" => {
                values => { "capacity" => "GAUGE" },
                consolidation => [ "MAX" ],
                units => "bps",
        },
        "http://ggf.org/ns/nmwg/characteristic/interface/capacity/actual/2.0" => {
                values => { "capacity" => "GAUGE" },
                consolidation => [ "MAX" ],
                units => "bps",
        },
);

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { } );

    my $self = fields::new( $package );
    $self->{LOGGER} = get_logger( $package );
    return $self;
}

sub init {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { data_directory => 1, data_types => 0, rrd_path => 0, rrd_create_parameters => 0, rrd_step => 0, max_timeout => 1 } );

    my ($status, $error);

    # defaults
    $self->{DATA_TYPES} = \%data_types;  
    $self->{RRD_PATH} = $defaults{rrd_path}; 
    $self->{RRD_STEP} = $defaults{rrd_step};
    $self->{RRD_CREATE_PARAMETERS} = $defaults{rrd_create_parameters};

    $self->{DATA_DIRECTORY} = $parameters->{data_directory};
    $self->{MAX_TIMEOUT} = $parameters->{max_timeout};
    $self->{DATA_TYPES} = $parameters->{data_types} if ($parameters->{data_types});

    $self->{METADATA_FILE} = $self->{DATA_DIRECTORY}."/metadata.dat";

    $self->{METADATA} = Cache::FastMmap->new({ share_file => $self->{METADATA_FILE}, unlink_on_exit => 0 });

    return (0, "");
}

sub add_metadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { urn => 1, data_type => 1, direction => 0, host_name => 0, port_name => 0, capacity => 0, description => 0 });

    my ($status, $res);

    return unless ($self->{DATA_TYPES}->{$parameters->{data_type}});

    $self->{LOGGER}->debug("Looking up metadata");
    my $found_key = $self->lookup_metadata({ urn => $parameters->{urn}, data_type => $parameters->{data_type}, direction => $parameters->{direction} });
    if ($found_key) {
        $self->{LOGGER}->debug("Returning found key: $found_key");
        return $found_key;
    }
    $self->{LOGGER}->debug("Existing instance not found");

    $self->{LOGGER}->debug("Generating new key");
    my $key;
    do {
        $key = genuid();
    } while ($self->{METADATA}->get($key));
    $self->{LOGGER}->debug("Done generating new key: $key");

    my %metadata = ();
    $metadata{urn} = $parameters->{urn};
    $metadata{data_type} = $parameters->{data_type};
    $metadata{direction} = $parameters->{direction};
    $metadata{host_name} = $parameters->{host_name};
    $metadata{port_name} = $parameters->{port_name};
    $metadata{capacity} = $parameters->{capacity};
    $metadata{description} = $parameters->{description};

    # Spread the data out across directories
    my $directory_prefix = int(rand(100));

    mkdir($self->{DATA_DIRECTORY}."/".$directory_prefix);

    $metadata{rrd_file} = $self->{DATA_DIRECTORY}."/".$directory_prefix."/".$key.".rrd";

    my $data_type = $self->{DATA_TYPES}->{$parameters->{data_type}};

    unless (-f $metadata{rrd_file}) {
        $self->{LOGGER}->debug("Creating RRD file");
        my $cmd = $self->{RRD_PATH}." create";
        $cmd .= " ".$metadata{rrd_file};
        $cmd .= " --step ".$self->{RRD_STEP};
        foreach my $data_source (keys %{ $data_type->{values} }) {
            $cmd .= " DS:".$data_source.":".$data_type->{values}->{$data_source}.":".$self->{MAX_TIMEOUT}.":U:U";

        }

        if ($data_type->{consolidation}) {
            foreach my $consolidation (@{ $data_type->{consolidation} }) {
                my $rrd_create_parameters = $self->{RRD_CREATE_PARAMETERS};
                $rrd_create_parameters =~ s/%consolidation%/$consolidation/g;
                $cmd .= " ".$rrd_create_parameters;
            }
        }

        $self->{LOGGER}->debug("RRD create cmd: '$cmd'");
        if (system($cmd) != 0) {
            return;
        }
        $self->{LOGGER}->debug("Done creating RRD file");
    }

    $self->{LOGGER}->debug("Adding metadata to store");
    $self->{METADATA}->set($key, \%metadata);
    $self->{LOGGER}->debug("Done adding metadata $key to store");

    return $key;
}

sub lookup_metadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { urn => 1, data_type => 1, direction => 0 });

    $self->{LOGGER}->debug("Looking up metadata");
    # Need a better way of doing this to avoid duplicate elements.
    foreach my $key ($self->{METADATA}->get_keys()) {
        my $metadata = $self->{METADATA}->get($key);

        next if ($parameters->{urn} ne $metadata->{urn});
        next if ($parameters->{data_type} ne $metadata->{data_type});
        next if ($metadata->{direction} and not defined $parameters->{direction});
        next if (not defined $metadata->{direction} and $parameters->{direction});
        next if (defined $metadata->{direction} and defined $parameters->{direction} and $metadata->{direction} ne $parameters->{direction});

        $self->{LOGGER}->debug("Done looking up metadata: $key");

        return $key;
    }

    $self->{LOGGER}->debug("Done looking up metadata: nothing");

    return;
}

sub add_data {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { metadata_key => 1, time => 1, values => 1 });

    my $metadata_info = $self->{METADATA}->get($parameters->{metadata_key});

    return (-1, "Invalid metadata") unless ($metadata_info);

    my $rrd = perfSONAR_PS::DB::RRD->new({ path => $self->{RRD_PATH}, name => $metadata_info->{rrd_file}, error => 1 });
    if ($rrd->openDB == -1) {
        print "Error opening database\n";
        next;
    }

    $self->{LOGGER}->debug("Values(".$metadata_info->{data_type}."): ".Dumper($parameters->{values}));

    foreach my $source (keys %{ $self->{DATA_TYPES}->{$metadata_info->{data_type}}->{values} }) {
        $rrd->insert({ time => $parameters->{time}, ds => $source, value => $parameters->{values}->{$source} });
    }

    $rrd->insertCommit({});
    if($rrd->getErrorMessage) {
        $rrd->closeDB;

        my $error_msg = "Insert failed: ".$rrd->getErrorMessage;
        $self->{LOGGER}->error($error_msg);
        return (-1, $error_msg);
    }

    $rrd->closeDB;

    return (0, "");
}

sub generate_store_file {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { });

    my $content = "";
$content .= qq(<?xml version="1.0" encoding="UTF-8"?>
<nmwg:store  xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/"
             xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/"
             xmlns:neterr="http://ggf.org/ns/nmwg/characteristic/errors/2.0/"
             xmlns:netdisc="http://ggf.org/ns/nmwg/characteristic/discards/2.0/"
             xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/"
             xmlns:snmp="http://ggf.org/ns/nmwg/tools/snmp/2.0/"
             xmlns:nmtm="http://ggf.org/ns/nmwg/time/2.0/">
);

    # The keys are sorted so that the ordering is the same from iteration to
    # iteration. This makes it easy to check if the store file has changed by
    # doing a simple md5 checksum.
    foreach my $key (sort $self->{METADATA}->get_keys()) {
        my $metadata = $self->{METADATA}->get($key);
        my $data_type = $self->{DATA_TYPES}->{$metadata->{data_type}};

        $content .= '  <nmwg:metadata xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="m-' . $key . '">';
        $content .= '    <nmwg:subject id="s-' . $key . '-1">';
        $content .= '      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">';
        $content .= '        <nmwgt:urn>'.$metadata->{urn}.'</nmwgt:urn>';
        $content .= '        <nmwgt:hostName>'.$metadata->{host_name}.'</nmwgt:hostName>' if ($metadata->{host_name});
        $content .= '        <nmwgt:ifName>'.$metadata->{port_name}.'</nmwgt:ifName>' if ($metadata->{port_name});
        $content .= '        <nmwgt:ifDescription>'.$metadata->{description}.'</nmwgt:ifDescription>' if ($metadata->{description});
        $content .= '        <nmwgt:direction>'.$metadata->{direction}.'</nmwgt:direction>' if ($metadata->{direction});
        $content .= '        <nmwgt:capacity>'.$metadata->{capacity}.'</nmwgt:capacity>' if ($metadata->{capacity});
        $content .= '      </nmwgt:interface>';
        $content .= '    </nmwg:subject>';
        $content .= '    <nmwg:parameters>';
        $content .= '      <nmwg:parameter name="supportedEventType">'.$metadata->{data_type}.'</nmwg:parameter>';
        $content .= '    </nmwg:parameters>';
        $content .= '    <nmwg:eventType>'.$metadata->{data_type}.'</nmwg:eventType>';
        $content .= '  </nmwg:metadata>';

        $content .= '  <nmwg:data xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="d-' . $key . '" metadataIdRef="m-' . $key . '">';
        $content .= '    <nmwg:key>';
        $content .= '      <nmwg:parameters>';
        $content .= '        <nmwg:parameter name="eventType">'.$metadata->{data_type}.'</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="type">rrd</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="file">' . $metadata->{rrd_file} . '</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="valueUnits">'.$data_type->{units}.'</nmwg:parameter>' if ($data_type->{units});
        $content .= '        <nmwg:parameter name="dataSource">'.(keys %{ $data_type->{values} })[0]. '</nmwg:parameter>'; # only supports a single data source per data type
        $content .= '      </nmwg:parameters>';
        $content .= '    </nmwg:key>';
        $content .= '  </nmwg:data>';
    }

    $content .= qq(</nmwg:store>);

    return $content;
}

1;

package perfSONAR_PS::DB::TL1Counters;

use strict;
use warnings;

use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::Utils::DNS qw(query_location);
use perfSONAR_PS::Common qw(genuid);

use Log::Log4perl qw(get_logger);
use Storable qw(freeze thaw lock_store lock_nstore lock_retrieve);
use Data::Dumper;
use Cache::FastMmap;

use fields 'LOGGER', 'METADATA_PORTS_TABLE', 'DB_CLIENT', 'DATA_DIRECTORY', 'STORE_FILE', 'DATA_TYPES', 'RRD_PATH', 'RRD_CREATE_PARAMETERS', 'RRD_STEP', 'MAX_TIMEOUT';

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
    my $parameters = validateParams( @args, { metadata_dbistring => 1, metadata_table_prefix => 0, metadata_username => 0, metadata_password => 0, data_directory => 1, data_types => 0, rrd_path => 0, rrd_create_parameters => 0, rrd_step => 0, max_timeout => 1 } );

    # defaults
    $self->{DATA_TYPES} = \%data_types;  
    $self->{RRD_PATH} = $defaults{rrd_path}; 
    $self->{RRD_STEP} = $defaults{rrd_step};
    $self->{RRD_CREATE_PARAMETERS} = $defaults{rrd_create_parameters};

    $self->{DATA_DIRECTORY} = $parameters->{data_directory};
    $self->{MAX_TIMEOUT} = $parameters->{max_timeout};
    $self->{DATA_TYPES} = $parameters->{data_types} if ($parameters->{data_types});

    $self->{METADATA_PORTS_TABLE} = "ps_metadata_ports";
    if ( $parameters->{metadata_table_prefix} ) {
        $self->{METADATA_PORTS_TABLE} = $parameters->{metadata_table_prefix} . "_metadata_ports";
    }

    $self->{DB_CLIENT} = perfSONAR_PS::DB::SQL->new( { name => $parameters->{metadata_dbistring}, user => $parameters->{metadata_username}, pass => $parameters->{metadata_password} } );

    return (0, "");
}

sub add_port_metadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { urn => 1, data_type => 1, host_name => 1, port_name => 1, direction => 0, capacity => 0, description => 0 });

    my ($status, $res);

    my $data_type = $self->{DATA_TYPES}->{$parameters->{data_type}};
    unless ($data_type) {
        my $msg = "Unknown data type: ".$parameters->{data_type};
        $self->{LOGGER}->error( $msg );
        return (-1, $msg);
    }

    $self->{LOGGER}->debug("Looking up metadata");
    # the only 'unique' bits are hostname, port, data_type and direction. The rest could conceivably change.
    my ($status, $res) = $self->__lookup_port_metadata({ urn => $parameters->{urn}, data_type => $parameters->{data_type}, host_name => $parameters->{host_name}, port_name => $parameters->{port_name}, direction => $parameters->{direction} });
    if ($status != 0) {
        my $msg = "Error checking for existing metdata: $res";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) > 1) {
        my $msg = "Ambiguous port metadata specified";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) == 1) {
        my $md = $res->[0];
        $self->{LOGGER}->debug("Found existing instance: ".$md->{id});
        return (0, $md);
    }

    $self->{LOGGER}->debug("Existing instance not found");

    my ($rrd_filename, $rrd_directory);
    do {
       # Find a file to write to
       my $directory_prefix = int(rand(100));
       my $nonce = int(rand(100));

       $rrd_directory = $self->{DATA_DIRECTORY}."/".$directory_prefix;
       $rrd_filename = $parameters->{host_name}."_".$parameters->{port_name}.".".$nonce.".rrd";
       $rrd_filename =~ s/[^a-zA-Z0-9_.]/_/;
    } while (-f $rrd_directory."/".$rrd_filename);

    $self->{LOGGER}->debug("New RRD directory: ".$rrd_directory);
    $self->{LOGGER}->debug("New RRD filename: ".$rrd_filename);

    unless (-d $rrd_directory) {
        $status = mkdir($rrd_directory);
        unless ($status) {
            my $msg = "Couldn't create directory for RRD file";
            $self->{LOGGER}->error( $msg );
            return (-1, $msg);
        }
    }

    $self->{LOGGER}->debug("Creating RRD file");
    my $cmd = $self->{RRD_PATH}." create";
    $cmd .= " ".$rrd_directory."/".$rrd_filename;
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
        my $msg = "Couldn't create RRD file";
        $self->{LOGGER}->error( $msg );
        return (-1, $msg);
    }
    $self->{LOGGER}->debug("Done creating RRD file");

    my %metadata = ();
    $metadata{urn} = $parameters->{urn};
    $metadata{data_type} = $parameters->{data_type};
    $metadata{direction} = $parameters->{direction};
    $metadata{host_name} = $parameters->{host_name};
    $metadata{port_name} = $parameters->{port_name};
    $metadata{capacity} = $parameters->{capacity};
    $metadata{description} = $parameters->{description};
    $metadata{rrd_file} = $rrd_directory."/".$rrd_filename;

    $self->{DB_CLIENT}->openDB;
    if ($self->{DB_CLIENT}->openDB == -1) {
        my $msg = "Error opening connection to metadata db";
        $self->{LOGGER}->debug($msg);
        return (-1, $msg);
    }

    if ( $self->{DB_CLIENT}->insert( { table => $self->{METADATA_PORTS_TABLE}, argvalues => \%metadata } ) == -1 ) {
        my $msg = "Problem adding new metadata to database";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    $self->{DB_CLIENT}->closeDB;

    ($status, $res) = $self->__lookup_port_metadata({ urn => $parameters->{urn}, data_type => $parameters->{data_type}, host_name => $parameters->{host_name}, port_name => $parameters->{port_name}, capacity => $parameters->{capacity}, direction => $parameters->{direction}, description => $parameters->{description} });
    if ($status != 0) {
        my $msg = "Error checking for just-added metdata: $res";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) > 1) {
        my $msg = "Ambiguous port metadata result";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) == 0) {
        my $msg = "Couldn't find just-added metdata";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    my $key = $res->[0];
    $self->{LOGGER}->debug("Newly added key: ".$key);
    return (0, $key);
}

sub lookup_port_metadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 0, urn => 0, data_type => 0, host_name => 0, port_name => 0, direction => 0, capacity => 0, description => 0 });

    my ($status, $res);

    $self->{DB_CLIENT}->openDB;
    if ($self->{DB_CLIENT}->openDB == -1) {
        my $msg = "Error opening connection to metadata db";
        $self->{LOGGER}->debug($msg);
        return (-1, $msg);
    }

    ($status, $res) = $self->__lookup_port_metadata({ id => $parameters->{id}, urn => $parameters->{urn}, host_name => $parameters->{host_name}, port_name => $parameters->{port_name}, direction => $parameters->{direction}, capacity => $parameters->{capacity}, description => $parameters->{description} });

    $self->{DB_CLIENT}->closeDB;

    return ($status, $res);
}

sub __lookup_port_metadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 0, urn => 0, data_type => 0, host_name => 0, port_name => 0, direction => 0, capacity => 0, description => 0 });

    my $query = "select id, urn, data_type, host_name, port_name, direction, capacity, description, rrd_file from " . $self->{METADATA_PORTS_TABLE};

    my $connector = "where";

    foreach my $parameter (keys %$parameters) {
        if (defined $parameters->{$parameter}) {
            $query .= " ".$connector." $parameter='".$parameters->{$parameter}."'";
            $connector = "and"
        }
    }

    $self->{DB_CLIENT}->openDB;
    if ($self->{DB_CLIENT}->openDB == -1) {
        my $msg = "Error opening connection to metadata db";
        $self->{LOGGER}->debug($msg);
        return (-1, $msg);
    }

    my $metadata = $self->{DB_CLIENT}->query( { query => $query } );
    if ( $metadata == -1 ) {
        my $msg = "Problem looking up metadata";
        $self->{LOGGER}->error( $msg );
        return ( -1, $msg );
    }

    $self->{DB_CLIENT}->closeDB;

    my @md_results = ();

    if ($metadata) {
        foreach my $m (@$metadata) {
            my %md = ();
            $md{id} = $m->[0];
            $md{urn} = $m->[1];
            $md{data_type} = $m->[2];
            $md{host_name} = $m->[3];
            $md{port_name} = $m->[4];
            $md{direction} = $m->[5];
            $md{capacity} = $m->[6];
            $md{description} = $m->[7];
            $md{rrd_file} = $m->[8];

            push @md_results, \%md;
        }
    }

    return (0, \@md_results);
}

sub add_data {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { metadata_key => 1, time => 1, values => 1 });

    my ($status, $res) = $self->__lookup_port_metadata({ id => $parameters->{metadata_key} });
    if ($status != 0) {
        my $msg = "Error checking for specified metdata: $res";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) > 1) {
        my $msg = "Ambiguous port metadata result";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    if (scalar(@$res) == 0) {
        my $msg = "Couldn't find metadata matching the requested key";
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    my $rrd_file = $res->[0]->{rrd_file};
    my $data_type = $res->[0]->{data_type};

    my $rrd = perfSONAR_PS::DB::RRD->new({ path => $self->{RRD_PATH}, name => $rrd_file, error => 1 });
    if ($rrd->openDB == -1) {
        my $msg = "Error opening RRD file: ".$rrd_file;
        $self->{LOGGER}->debug($msg);
        return (-1, $res);
    }

    $self->{LOGGER}->debug("Values(".$data_type."): ".Dumper($parameters->{values}));

    foreach my $source (keys %{ $self->{DATA_TYPES}->{$data_type}->{values} }) {
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

    my ($status, $res) = $self->lookup_port_metadata({}); # grab everything
    if ($status != 0) {
        my $msg = "Couldn't obtain port metadata: $res";
        $self->{LOGGER}->debug($msg);
        return (-1, $msg);
    }

    # The keys are sorted so that the ordering is the same from iteration to
    # iteration. This makes it easy to check if the store file has changed by
    # doing a simple md5 checksum.

    foreach my $metadata (sort { $a->{id} <=> $b->{id} } @$res) {
        my $data_type = $self->{DATA_TYPES}->{$metadata->{data_type}};
        
        $content .= '  <nmwg:metadata xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="m-' . $metadata->{id} . '">';
        $content .= '    <nmwg:subject id="s-' . $metadata->{id}. '-1">';
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

        $content .= '  <nmwg:data xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="d-' . $metadata->{id} . '" metadataIdRef="m-' . $metadata->{id} . '">';
        $content .= '    <nmwg:key>';
        $content .= '      <nmwg:parameters>';
        $content .= '        <nmwg:parameter name="eventType">'.$metadata->{data_type}.'</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="type">rrd</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="file">' . $metadata->{rrd_file} . '</nmwg:parameter>';
        $content .= '        <nmwg:parameter name="valueUnits">'.$data_type->{units}.'</nmwg:parameter>' if ($data_type->{units});
        $content .= '        <nmwg:parameter name="dataSource">'.(keys %{ $data_type->{values} })[0]. '</nmwg:parameter>'; # XXX only supports a single data source per data type
        $content .= '      </nmwg:parameters>';
        $content .= '    </nmwg:key>';
        $content .= '  </nmwg:data>';
    }

    $content .= qq(</nmwg:store>);

    return $content;
}

1;

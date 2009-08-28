#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../../../Shared/lib";
my $confdir = "$Bin/../etc";

use Cwd;
use JSON::XS;
use Data::Dumper;

use Log::Log4perl qw(:easy get_logger);
use Cache::FastMmap;
use CGI;
use Config::General;

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw(find);

Log::Log4perl->easy_init($DEBUG);

my $logger = get_logger("web_admin");

my $CONFIG_FILE = $confdir . "/dcn_status.conf";

# Read in configuration information
my %conf = new Config::General( $CONFIG_FILE )->getall();

unless ($conf{"cache_file"}) {
    $logger->error("Must specify which file to use to cache the data. e.g. cache_file=/var/lib/dcn_web_interface/cache.dat");
    exit( -1 );
}

unless ($conf{"ma_url"}) {
    $logger->error("Must specify which measurement archive to use to query for stats. e.g. ma_url=http://localhost:8083/perfSONAR_PS/services/SNMPMA");
    exit( -1 );
}


my $cache = Cache::FastMmap->new({ share_file => $conf{cache_file}, unlink_on_exit => 0, compress => 1 });

my $cgi = CGI->new();
my $function = $cgi->param("function");

unless ($function) {
    die("No function specified");
}

if ($function eq "test") {
        my %vars = $cgi->Vars;

        die("Parameters: ".Dumper(\%vars));
}

if ($function eq "get_topology") {
    my $topology = $cache->get("dcn_status_page.topology");
    print "Content-type: text/json\n\n";
    print encode_json($topology);
    exit;
} elsif ($function eq "get_users") {
    my %used_users = ();
    my @users = ();

    foreach my $key ($cache->get_keys) {
        if ($key =~ /^dcn_status_page.reservation/) {
                my $reservation = $cache->get($key);

                next if ($used_users{$reservation->{login}});

                push @users, { value => $reservation->{login}, name => $reservation->{login}, label => $reservation->{login} };

                $used_users{$reservation->{login}} = 1;
        }
    }

    print "Content-type: text/json\n\n";
    print encode_json({ identifier => 'value', items => \@users });
} elsif ($function eq "get_descriptions") {
    my %used_descriptions = ();
    my @descriptions = ();

    foreach my $key ($cache->get_keys) {
        if ($key =~ /^dcn_status_page.reservation/) {
                my $reservation = $cache->get($key);

                next if ($used_descriptions{$reservation->{description}});

                push @descriptions, { value => $reservation->{description}, name => $reservation->{description}, label => $reservation->{description} };

                $used_descriptions{$reservation->{description}} = 1;
        }
    }

    print "Content-type: text/json\n\n";
    print encode_json({ identifier => 'value', items => \@descriptions });
} elsif ($function eq "get_identifiers") {
    my %used_identifiers= ();
    my @identifiers = ();

    foreach my $key ($cache->get_keys) {
        if ($key =~ /^dcn_status_page.reservation/) {
                my $reservation = $cache->get($key);

                next if ($used_identifiers{$reservation->{id}});

                push @identifiers, { value => $reservation->{id}, name => $reservation->{id}, label => $reservation->{id} };

                $used_identifiers{$reservation->{id}} = 1;
        }
    }

    print "Content-type: text/json\n\n";
    print encode_json({ identifier => 'value', items => \@identifiers });
} elsif ($function eq "get_reservations") {
    my %vars = $cgi->Vars;

    $logger->debug("Parameters: ".Dumper(\%vars));

    my $identifier = $cgi->param("identifier");
    my $start_time     = $cgi->param("start_time");
    my $end_time       = $cgi->param("end_time");
    my $status       = $cgi->param("status");
    my $user           = $cgi->param("user");
    my $description    = $cgi->param("description");

#    my %statuses = ();
#    if ($statuses) {
#        foreach my $status (split(',', $statuses)) {
#            $statuses{$status} = 1;
#        }
#    }

    my @reservations = ();

    foreach my $key ($cache->get_keys) {
        if ($key =~ /^dcn_status_page.reservation/) {
                my $reservation = $cache->get($key);

                next if ($identifier and $reservation->{id} ne $identifier);
                next if ($start_time and $reservation->{startTime} > $start_time);
                next if ($end_time and $reservation->{endTime} < $end_time);
                next if ($status and $reservation->{status} ne $status);
                next if ($user and $reservation->{login} ne $user);
                next if ($description and $reservation->{description} !~ /$description/);

                push @reservations, $reservation;
        }
    }

    print "Content-type: text/json\n\n";
    print encode_json(\@reservations);
} elsif ($function eq "get_circuit_statistics") {
    my $reservation_id = $cgi->param("reservation_id");
    my $event_type   = $cgi->param("event_type");

    $event_type = "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" unless ($event_type);

    die("No reservation in parameters") unless ($reservation_id);

    my $topology = $cache->get('dcn_status_page.topology');
    my $reservation = $cache->get('dcn_status_page.reservations.'.$reservation_id);

    die("No reservation found at: dcn_status_page.reservations.".$reservation_id) unless ($reservation);

    my $start_time = $reservation->{startTime};
    my $end_time = $reservation->{endTime};
    my $capacity = $reservation->{bandwidth};
    my $resolution = 60;

    my $ma = perfSONAR_PS::Client::MA->new( { instance => $conf{ma_url} } );

    # Convert the information we know about the reservation into what we know
    # is being monitored.
    my ($ingress_host, $ingress_iface);
    my ($egress_host, $egress_iface);

    if ($topology->{$reservation->{local_source}}) {
        my $link = $topology->{$reservation->{local_source}};
        my $port = $topology->{$link->{parent}};
        my $node = $topology->{$port->{parent}};

        $ingress_host = $node->{name};
        $ingress_iface = $port->{name};
        if ($reservation->{local_source_tag}) {
            $ingress_iface .= ".".$reservation->{local_source_tag};
        } else {
            $ingress_iface .= ".ALL";
        }
    }
    
    if ($topology->{$reservation->{local_destination}}) {
        my $link = $topology->{$reservation->{local_destination}};
        my $port = $topology->{$link->{parent}};
        my $node = $topology->{$port->{parent}};

        $egress_host = $node->{name};
        $egress_iface = $port->{name};
        if ($reservation->{local_destination_tag}) {
            $egress_iface .= ".".$reservation->{local_destination_tag};
        } else {
            $egress_iface .= ".ALL";
        }
    }

    my $subject = qq(
            <nmwg:subject>
                <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
                <nmwgt:hostName>HOST</nmwgt:hostName>
                <nmwgt:ifName>INTERFACE</nmwgt:ifName>
                <nmwgt:direction>DIRECTION</nmwgt:direction>
                </nmwgt:interface>
            </nmwg:subject> 
);

    my %results = ();

    foreach my $piece ("ingress", "egress") {
        my ($host, $iface);

        if ($piece eq "ingress") {
            $host = $ingress_host;
            $iface = $ingress_iface;
        }
        else {
            $host = $egress_host;
            $iface = $egress_iface;
        }

        my $in_subject = $subject;
        $in_subject =~ s/HOST/$host/g;
        $in_subject =~ s/INTERFACE/$iface/g;
        $in_subject =~ s/DIRECTION/in/g;

        my $out_subject = $subject;
        $out_subject =~ s/HOST/$host/g;
        $out_subject =~ s/INTERFACE/$iface/g;
        $out_subject =~ s/DIRECTION/out/g;

        my $in_result = $ma->setupDataRequest(
                {
                start                 => $start_time,
                end                   => $end_time,
                resolution            => $resolution,
                consolidationFunction => "AVERAGE",
                subject               => $in_subject,
                eventTypes            => [ $event_type ],
                }
                );

        my $out_result = $ma->setupDataRequest(
                {
                start                 => $start_time,
                end                   => $end_time,
                resolution            => $resolution,
                consolidationFunction => "AVERAGE",
                subject               => $out_subject,
                eventTypes            => [ $event_type ],
                }
                );

        my $parser     = XML::LibXML->new();

        my $in_doc = $parser->parse_string( $in_result->{"data"}->[0] );
        my $in_datum = find( $in_doc->getDocumentElement, "./*[local-name()='datum']", 0 );

        my $out_doc = $parser->parse_string( $out_result->{"data"}->[0] );
        my $out_datum = find( $out_doc->getDocumentElement, "./*[local-name()='datum']", 0 );

        my %store = ();
        if ( $in_datum and $out_datum ) {
            foreach my $dt ( $in_datum->get_nodelist ) {
                $store{ $dt->getAttribute("timeValue") }{"in"} = eval( $dt->getAttribute("value") ) if ($dt->getAttribute("value") and $dt->getAttribute("value") ne "nan");
            }
            foreach my $dt ( $out_datum->get_nodelist ) {
                $store{ $dt->getAttribute("timeValue") }{"out"} = eval( $dt->getAttribute("value") ) if ($dt->getAttribute("value") and $dt->getAttribute("value") ne "nan");
            }
        }

        my @results = ();
        foreach my $ts (sort { $a <=> $b} keys %store) {
            push @results, { time => $ts, in => $store{$ts}{in}, out => $store{$ts}{out} };
        }

        $results{$piece} = \@results;
    }

    my $json = JSON::XS->new();

    print "Content-type: text/json\n\n";
    print encode_json(\%results);
} elsif ($function eq "get_circuit_status") {
    my $reservation_id = $cgi->param("reservation_id");
    my $event_type   = "http://ggf.org/ns/nmwg/characteristic/interface/status/operational/2.0";

    die("No reservation in parameters") unless ($reservation_id);

    my $topology = $cache->get('dcn_status_page.topology');
    my $reservation = $cache->get('dcn_status_page.reservations.'.$reservation_id);

    die("No reservation found at: dcn_status_page.reservations.".$reservation_id) unless ($reservation);

    my $start_time = $reservation->{startTime};
    my $end_time = $reservation->{endTime};
    my $capacity = $reservation->{bandwidth};
    my $resolution = 60;

    my $ma = perfSONAR_PS::Client::MA->new( { instance => $conf{ma_url} } );

    # Convert the information we know about the reservation into what we know
    # is being monitored.
    my ($ingress_host, $ingress_iface);
    my ($egress_host, $egress_iface);

    if ($topology->{$reservation->{local_source}}) {
        my $link = $topology->{$reservation->{local_source}};
        my $port = $topology->{$link->{parent}};
        my $node = $topology->{$port->{parent}};

        $ingress_host = $node->{name};
        $ingress_iface = $port->{name};
        if ($reservation->{local_source_tag}) {
            $ingress_iface .= ".".$reservation->{local_source_tag};
        } else {
            $ingress_iface .= ".ALL";
        }
    }
    
    if ($topology->{$reservation->{local_destination}}) {
        my $link = $topology->{$reservation->{local_destination}};
        my $port = $topology->{$link->{parent}};
        my $node = $topology->{$port->{parent}};

        $egress_host = $node->{name};
        $egress_iface = $port->{name};
        if ($reservation->{local_destination_tag}) {
            $egress_iface .= ".".$reservation->{local_destination_tag};
        } else {
            $egress_iface .= ".ALL";
        }
    }

    my $subject = qq(
            <nmwg:subject>
                <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
                <nmwgt:hostName>HOST</nmwgt:hostName>
                <nmwgt:ifName>INTERFACE</nmwgt:ifName>
                </nmwgt:interface>
            </nmwg:subject> 
);

    my %results = ();

    foreach my $piece ("ingress", "egress") {
        my ($host, $iface);

        if ($piece eq "ingress") {
            $host = $ingress_host;
            $iface = $ingress_iface;
        }
        else {
            $host = $egress_host;
            $iface = $egress_iface;
        }

        my $in_subject = $subject;
        $in_subject =~ s/HOST/$host/g;
        $in_subject =~ s/INTERFACE/$iface/g;

        my $in_result = $ma->setupDataRequest(
                {
                start                 => $start_time,
                end                   => $end_time,
                resolution            => $resolution,
                consolidationFunction => "MAX",
                subject               => $in_subject,
                eventTypes            => [ $event_type ],
                }
                );

        my $parser     = XML::LibXML->new();

        my $in_doc = $parser->parse_string( $in_result->{"data"}->[0] );
        my $in_datum = find( $in_doc->getDocumentElement, "./*[local-name()='datum']", 0 );

        my %store = ();
        if ( $in_datum ) {
            foreach my $dt ( $in_datum->get_nodelist ) {
                $store{ $dt->getAttribute("timeValue") } = eval( $dt->getAttribute("value") ) if ($dt->getAttribute("value") and $dt->getAttribute("value") ne "nan");
            }
        }

        my @results = ();
        foreach my $ts (sort { $a <=> $b} keys %store) {
            push @results, { time => $ts, value => $store{$ts} };
        }

        $results{$piece} = \@results;
    }

    my $json = JSON::XS->new();

    print "Content-type: text/json\n\n";
    print encode_json(\%results);
}

die("Invalid function specified");

#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

use Config::General;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use JSON::XS;

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Client::OSCARS;
use perfSONAR_PS::Utils::ParameterValidation;

Log::Log4perl->easy_init($DEBUG);
my $output_level = $DEBUG;

my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
        file   => "/tmp/wmap.output",
        );


Log::Log4perl->easy_init( \%logger_opts );
my $logger = get_logger( "perfSONAR_PS::WeatherMap" );

my $file = shift;

$file = $confdir."/dcn_configuration.conf" unless ($file);

my %conf = Config::General->new($file)->getall;

unless ($conf{colors} and $conf{colors}->{value}) {
        die("No colors specified");
}

unless ($conf{'dcn-links'} and $conf{'dcn-links'}->{'dcn-link'}) {
        die("No dcn links specified");
}

unless ($conf{endpoints}->{endpoint}) {
        die("No endpoints specified");
}

unless ($conf{background}) {
        die("No background specified");
}

my ($status, $res);

($status, $res) = parse_background($conf{'background'});
if ($status != 0) {
        die($res);
}

my $background = $res;

($status, $res) = parse_colors($conf{'colors'}->{'value'});
if ($status != 0) {
        die($res);
}

my $colors = $res;

my $icons;
if ($conf{'icons'}) {
    ($status, $res) = parse_icons($conf{'icons'});
    if ($status != 0) {
        die($res);
    }

    $icons = $conf{'icons'};
}

($status, $res) = parse_dcn_links($conf{'dcn-links'}->{'dcn-link'});
if ($status != 0) {
        die($res);
}

my $dcn_links = $res;

my %current_endpoints = ();
my @current_links = ();

($status, $res) = parse_endpoints($conf{endpoints}->{endpoint});
if ($status != 0) {
    die($res);
}

%current_endpoints = %{ $res };

($status, $res) = retrieve_dcn_links({ dcn_links => $dcn_links });
if ($status != 0) {
        die($res);
}

foreach my $link (@{ $res->{added_links} }) {
        push @current_links, $link;
}

$logger->debug("Final Links: ".Dumper(\@current_links));

($status, $res) = measure_links({ links => \@current_links });
if ($status != 0) {
        die($res);
}

($status, $res) = color_links({ colors => $colors, links => \@current_links });
if ($status != 0) {
        die($res);
}

$logger->debug("Final Endpoints: ".Dumper(\%current_endpoints));
$logger->debug("Final Links: ".Dumper(\@current_links));

my %results = ();
$results{background} = $background;
$results{endpoints} = \%current_endpoints;
$results{links} = \@current_links;
$results{icons} = $icons;

print encode_json(\%results);

exit 0;

sub color_links {
    my ( @args ) = @_;
    my $parameters = validateParams( @args, { links => 1, colors => 1 } );

    foreach my $link (@{ $parameters->{links} }) {
        next unless ($link->{measurement_results} and $link->{measurement_results}->{type} eq "utilization");

        my $measurement_results = $link->{measurement_results};

        my ($current_srcdst_color, $current_dstsrc_color);

        foreach my $color (@{ $parameters->{colors} }) {
            if ($color->{minimum} and $color->{maximum}) {
                if ($measurement_results->{source_destination}) {
                    if ($color->{minimum} <= $measurement_results->{source_destination}->{value} and
                            $color->{maximum} > $measurement_results->{source_destination}->{value}) {

                            $current_srcdst_color = $color;

                    }
                }

                if ($measurement_results->{destination_source}) {
                    if ($color->{minimum} <= $measurement_results->{destination_source}->{value} and
                            $color->{maximum} > $measurement_results->{destination_source}->{value}) {

                            $current_dstsrc_color = $color;

                    }
                }
            }
            elsif ($color->{minimum}) {
                if ($measurement_results->{source_destination}) {
                    if ($color->{minimum} <= $measurement_results->{source_destination}->{value}) {
                        $current_srcdst_color = $color;
                    }
                }
                if ($measurement_results->{destination_source}) {
                    if ($color->{minimum} <= $measurement_results->{destination_source}->{value}) {
                        $current_dstsrc_color = $color;
                    }
                }
            }
            elsif ($color->{maximum}) {
                if ($measurement_results->{source_destination}) {
                    if ($color->{maximum} >= $measurement_results->{source_destination}->{value}) {
                        $current_srcdst_color = $color;
                    }
                }
                if ($measurement_results->{destination_source}) {
                    if ($color->{maximum} >= $measurement_results->{destination_source}->{value}) {
                        $current_dstsrc_color = $color;
                    }
                }
            }
            elsif ($color->{type} eq "default") {
                $current_srcdst_color = $color unless ($current_srcdst_color);  
                $current_dstsrc_color = $color unless ($current_dstsrc_color);  
            }
        }

        my %suggested_colors = ();

        $suggested_colors{'destination-source'} = $current_dstsrc_color->{color} if ($current_dstsrc_color);
        $suggested_colors{'source-destination'} = $current_srcdst_color->{color} if ($current_srcdst_color);

        $link->{'suggested-colors'} = \%suggested_colors;
    }

    return (0, "");
}

sub measure_links {
    my ( @args ) = @_;
    my $parameters = validateParams( @args, { links => 1 } );

    foreach my $link (@{ $parameters->{links} }) {
        next unless ($link->{measurement_parameters});

        my ($sourcedest_bps, $destsource_bps);

        foreach my $measurement_parameters (@{ $link->{measurement_parameters} }) {
            next unless ($measurement_parameters->{type} eq "SNMP");

            my $ma        = $measurement_parameters->{MA};
            my $hostName  = $measurement_parameters->{hostname};
            my $ifName    = $measurement_parameters->{ifname};
            my $ifIndex   = $measurement_parameters->{ifindex};
            my $direction = $measurement_parameters->{direction};

            my $in_Bps      = callSNMP_MA( ma => $ma, host => $hostName, ifName => $ifName, direction => "in" );
            my $out_Bps     = callSNMP_MA( ma => $ma, host => $hostName, ifName => $ifName, direction => "out" );

            if ($direction eq "reverse") {
                # out = dest -> source
                $sourcedest_bps = ($in_Bps * 8) if (defined $in_Bps);
                $destsource_bps = ($out_Bps  * 8) if (defined $out_Bps);
            }
            else {
                # out = source -> dest
                $sourcedest_bps = ($out_Bps * 8) if (defined $out_Bps);
                $destsource_bps = ($in_Bps * 8) if (defined $in_Bps);
            }

            last if (defined $sourcedest_bps and defined $destsource_bps);
        }

        $link->{measurement_results} = { type => "utilization", source_destination => { value => $sourcedest_bps, unit => "bps" }, destination_source => { value => $destsource_bps, unit => "bps" } };
    }

    return (0, "");
}

=head2 callSNMP_MA( { ma, host, ifName, direction } )

...

=cut

sub callSNMP_MA {
    my ( @args ) = @_;
    my $parameters = validateParams( @args, { ma => 1, host => 1, ifName => 1, direction => 1 } );
    
    my %datum = ();
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    # Standard SNMP MA/RRD MA subject.  Only search on host/direction

    my $subject = "";
    $subject .= "    <nmwg:subject id=\"s-in-16\">\n";
    $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
    $subject .= "        <nmwgt:hostName>" . $parameters->{host} . "</nmwgt:hostName>\n";
    $subject .= "        <nmwgt:ifName>" . $parameters->{ifName} . "</nmwgt:ifName>\n" if ($parameters->{ifName});
    $subject .= "        <nmwgt:ifIndex>" . $parameters->{ifIndex} . "</nmwgt:ifIndex>\n" if ($parameters->{ifIndex});
    $subject .= "        <nmwgt:direction>" . $parameters->{direction} . "</nmwgt:direction>\n";
    $subject .= "      </nmwgt:interface>\n";
    $subject .= "    </nmwg:subject>\n";

    # Standard eventType, we could add more
    my @eventTypes = ("http://ggf.org/ns/nmwg/characteristic/utilization/2.0");

    # Not worrying about 'supportedEventType' parameters (will break RRD MA)

    my $ma_client   = new perfSONAR_PS::Client::MA(  { instance => $parameters->{ma} } );

    # Call up the MA, we just want a little bit of data (1 minute is more than
    #    enough).  Note I am requesting a VERY low resolution, this should give
    #    us the smallest in the RRD file.
    my $ma_result = $ma_client->setupDataRequest(
        {
            consolidationFunction => "AVERAGE",
            resolution            => 1,
            start                 => ( $sec - 300 ),
            end                   => $sec,
            subject               => $subject,
            eventTypes            => \@eventTypes
        }
    );

    my $parser = XML::LibXML->new();

    # There should be only one data, but iterate anyway.
    foreach my $d ( @{ $ma_result->{"data"} } ) {
        my $data = $parser->parse_string($d);

        # Extract the datum elements.
        foreach my $dt ( $data->getDocumentElement->getChildrenByTagNameNS( "http://ggf.org/ns/nmwg/base/2.0/", "datum" ) ) {

            # Make sure the time and data are legit.
            if ( $dt->getAttribute("timeValue") =~ m/^\d{10}$/ ) {
                if ( $dt->getAttribute("value") and $dt->getAttribute("value") ne "nan" ) {
                    if ( $dt->getAttribute("valueUnits") and $dt->getAttribute("valueUnits") eq "Bps" ) {
                        $datum{ $dt->getAttribute("timeValue") } = $dt->getAttribute("value") * 8;
                    }
                    else {
                        $datum{ $dt->getAttribute("timeValue") } = $dt->getAttribute("value");
                    }
                }
                else {

                    # these are usually 'NaN' values
                    $datum{ $dt->getAttribute("timeValue") } = $dt->getAttribute("value");
                }
            }
        }
    }

    my $maxValue;
    foreach my $value ( sort keys %datum ) {
        next if lc( $datum{$value} ) eq "nan";

        $maxValue = $datum{$value} if (not $maxValue or $datum{$value} > $maxValue);
    }

    return $maxValue;
}

sub retrieve_dcn_links {
    my ( @args ) = @_;
    my $parameters = validateParams( @args, { dcn_links => 1 } );

    my $dcn_links = $parameters->{dcn_links};

    $logger->debug("DCN_LINKS: ".Dumper($dcn_links));
    if (ref($conf{idc}) ne "ARRAY") {
        $conf{idc} = [ $conf{idc} ];
    }

    my @added_endpoints = ();
    my @added_links = ();

    foreach my $idc (@{ $conf{idc} }) {
        my $reservations_client = perfSONAR_PS::Client::OSCARS->new();
        $status = $reservations_client->init({ idc_url => $idc, oscars_client => $conf{oscars_client}, axis2_home => $conf{axis2_home}, java_directory => $conf{java_directory} });
        if ($status != 0) {
            $logger->debug("Couldn't initialize oscars client");
            next;
        }

        eval {
            ($status, $res) = $reservations_client->listReservations({ status => "ACTIVE" });
        };
        if ($@) {
            $logger->debug("Problem querying for reservations: ".$@);
            next;
        }
        unless ($status == 0) {
            $logger->debug("Problem querying for reservations: ".$res);
            next;
        }

        # Each reservation starts a new 'path' through the idc (wrt to the 'add
        # edge' functionality).
        foreach my $resv (@{ $res->resDetails }) {
            $logger->debug("Found reservation");
            next unless ($resv->pathInfo);

            $logger->debug("Reservation has a path info");

            my $prev_edge_point;

            foreach my $hop (@{ $resv->pathInfo->path->hop }) {
                $logger->debug("Found hop in path info");

                next unless $hop->link;

                my $link_id = $hop->link->_id->__value;

                $logger->debug("Hop has link: $link_id");

                my $link_info = $dcn_links->{$link_id};

                next unless ($link_info);

                $logger->debug("Hop has link info");

                next unless ($hop->link->SwitchingCapabilityDescriptors->encodingType eq "ethernet");

                $logger->debug("Hop is ethernet");

                my $vlan = $hop->link->SwitchingCapabilityDescriptors->switchingCapabilitySpecificInfo->vlanRangeAvailability->__value;

                my ($MA, $direction, $hostName, $ifName, $ifIndex);

                if ($link_info->{measurement_parameters}) {
                    $logger->debug("Found link info: measurement");

                    $MA        = $link_info->{measurement_parameters}->{MA};
                    $direction = $link_info->{measurement_parameters}->{direction};
                    $hostName  = $link_info->{measurement_parameters}->{hostname};
                    $ifName    = $link_info->{measurement_parameters}->{ifname};
                    $ifIndex   = $link_info->{measurement_parameters}->{ifindex};

                    if ($link_info->{measurement_parameters}->{vlanMapping}) {
                        my $vlanMapping = $link_info->{measurement_parameters}->{vlanMapping};

                        my $new_ifName = $vlanMapping;
                        $new_ifName =~ s/\%p/$ifName/ if ($ifName);
                        $new_ifName =~ s/\%v/$vlan/ if ($vlan);

                        $ifName = $new_ifName;
                    }
                }

                $logger->debug("Link Info: ".Dumper($link_info));

                foreach my $action (@{ $link_info->{actions} }) {
                    # only support 'add' for now. Could support removal or some
                    # such later I guess.
                    $logger->debug("Found action");
                    next unless ($action->{type} eq "add");
                    $logger->debug("Action is add");

                    if ($action->{'subject'}->{'link'}) {
                        $logger->debug("Add type is link");

                        my $source = $action->{'subject'}->{'link'}->{'source'};
                        my $destination = $action->{'subject'}->{'link'}->{'destination'};

                        # The semantics for the edge points says that we link
                        # up the previous edge point to the 'source endpoint'
                        # of the link we're connecting.
                        if ($prev_edge_point and $source ne $prev_edge_point->{name} and $destination ne $prev_edge_point->{name}) {
                            my @measurements = ();
                            if ($prev_edge_point->{'hostName'} and $prev_edge_point->{'direction'} and ($prev_edge_point->{'ifName'} or $prev_edge_point->{'ifIndex'})) {
                                # Previous is the source of the drawn links, so we can use it's direction directly because out == source -> dest.
                                my %measurement_point = (
                                        type => "SNMP",
                                        MA => $prev_edge_point->{'MA'},
                                        hostname => $prev_edge_point->{'hostName'},
                                        ifname => $prev_edge_point->{'ifName'},
                                        ifindex => $prev_edge_point->{'ifIndex'},
                                        direction => $prev_edge_point->{'direction'},
                                        );

                                push @measurements, \%measurement_point;
                            }

                            my %new_link = (
                                    source => $prev_edge_point->{'name'},
                                    destination => $source,
                                    type => "bidirectional-pair",
                                    measurement_parameters => \@measurements,
                                    );

                            $logger->debug("Adding link(2): ".Dumper(\%new_link));
                            push @added_links, \%new_link;
                        }

                        my @measurements = ();
                        if ($hostName and $direction and ($ifName or $ifIndex)) {
                            # Previous is the source of the drawn links, so we can use it's direction directly because out == source -> dest.
                            my %measurement_point = (
                                    type => "SNMP",
                                    MA => $MA,
                                    hostname => $hostName,
                                    ifname => $ifName,
                                    ifindex => $ifIndex,
                                    direction => $direction,
                                    );

                            push @measurements, \%measurement_point;
                        }

                        my %new_link = (
                                source => $source,
                                destination => $destination,
                                measurement_parameters => \@measurements,
                                type => "bidirectional-pair",
                                );

                        $logger->debug("Adding link(3): ".Dumper(\%new_link));
                        push @added_links, \%new_link;

                        # The destination gets setup as the new 'edge-point'

                        my %new_edge_point = ();
                        $new_edge_point{'name'} = $destination;
                        
                        $prev_edge_point = \%new_edge_point;
                    }
                    elsif ($action->{'subject'}->{'edge-point'}) {
                        $logger->debug("Add type is edge-point");

                        my %new_edge_point = ();
                        $new_edge_point{'name'} = $action->{'subject'}->{'edge-point'};
                        $new_edge_point{'MA'} = $MA;
                        $new_edge_point{'hostName'} = $hostName;
                        $new_edge_point{'ifName'} = $ifName;
                        $new_edge_point{'ifIndex'} = $ifIndex;
                        $new_edge_point{'direction'} = $direction;

                        # We want to not add a link if the new edge point's
                        # endpoint is the same as the old one, but the new edge
                        # point needs to be set so that the measurement info
                        # gets carried over.
                        if ($prev_edge_point and $prev_edge_point->{name} ne $action->{'subject'}->{'edge-point'}) {
                            my @measurements = ();
                            if ($prev_edge_point->{'hostName'} and $prev_edge_point->{'direction'} and ($prev_edge_point->{'ifName'} or $prev_edge_point->{'ifIndex'})) {
                                # Previous is the source of the drawn links, so we can use it's direction directly because out == source -> dest.
                                my %measurement_point = (
                                        type => "SNMP",
                                        MA => $prev_edge_point->{'MA'},
                                        hostname => $prev_edge_point->{'hostName'},
                                        ifname => $prev_edge_point->{'ifname'},
                                        ifindex => $prev_edge_point->{'ifindex'},
                                        direction => $prev_edge_point->{'direction'},
                                        );

                                push @measurements, \%measurement_point;
                            }

                            if ($new_edge_point{'hostName'} and $new_edge_point{'direction'} and ($new_edge_point{'ifName'} or $new_edge_point{'ifIndex'})) {
                                # The new node is the destination of the drawn links so we have to reverse its direction because out == dest -> source.
                                my %measurement_point = (
                                        type => "SNMP",
                                        MA => $new_edge_point{'MA'},
                                        hostname => $new_edge_point{'hostName'},
                                        ifname => $new_edge_point{'ifname'},
                                        ifindex => $new_edge_point{'ifindex'},
                                        direction => ($new_edge_point{'direction'}eq"reverse")?"forward":"reverse",
                                   );

                                push @measurements, \%measurement_point;
                            }

                            my %new_link = (
                                    source => $prev_edge_point->{'name'},
                                    destination => $new_edge_point{'name'},
                                    measurement_parameters => \@measurements,
                                    type => "bidirectional-pair",
                                    );

                            $logger->debug("Adding link(1): ".Dumper(\%new_link));
                            push @added_links, \%new_link;
                        }

                        $prev_edge_point = \%new_edge_point;
                    }
                }
            }
        }
    }

    return (0, { added_links => \@added_links, added_endpoints => \@added_endpoints });
}

sub parse_icons {
    my ($icons) = @_;

    if (ref($icons) ne "ARRAY") {
        $logger->debug("Ref: ".ref($icons).": ".Dumper($icons));
        $icons = [ $icons ];
    }

    my @icons = ();

    foreach my $icon (@$icons) {
        my %icon_info = ();

        $icon_info{image} = $icon->{image};
        $icon_info{height} = $icon->{height};
        $icon_info{width} = $icon->{width};

        push @icons, \%icon_info;
    }

    return (0, \@icons);
}

sub parse_background {
    my ($background) = @_;

    my %background_info = ();

    $background_info{image} = $background->{image};
    $background_info{height} = $background->{height};
    $background_info{width} = $background->{width};
    $background_info{color} = $background->{color};

    unless ($background_info{color} or $background_info{image}) {
        $background_info{color} = "rgb(255, 255, 255)"; # default color is white
    }

    unless ($background_info{height} or $background_info{image}) {
        $background_info{height} = "900";
    }

    unless ($background_info{width} or $background_info{image}) {
        $background_info{width} = "1440";
    }

    return (0, \%background_info);
}

sub parse_endpoints {
    my ($endpoints) = @_;

    if (ref($endpoints) ne "ARRAY") {
        $logger->debug("Ref: ".ref($endpoints).": ".Dumper($endpoints));
        $endpoints = [ $endpoints ];
    }

    my %endpoints_by_id = ();

    foreach my $ep (@$endpoints) {
        $logger->debug("Endpoint: ".Dumper($ep));

        unless ($ep->{id}) {
            return (-1, "No endpoint id(s) specified");
        }

        ($status, $res) = parse_endpoint_ids($ep->{id});
        return ($status, $res) if ($status != 0);

        my $ids = $res;

        my %endpoint = (
                ids => $ids,
                x => $ep->{x},
                y => $ep->{y},
                height => $ep->{height},
                width => $ep->{width},
                icon => $ep->{icon},
        );

        foreach my $id (@$ids) {
                if ($endpoints_by_id{$id}) {
                        # probably should either merge or just allow multiple.
                        return (-1, $id." appears in multiple endpoints");
                }

                $endpoints_by_id{$id} = \%endpoint;
        }
    }

    return (0, \%endpoints_by_id);
}

sub parse_endpoint_ids {
    my ($ids) = @_;

    if (ref($ids) ne "ARRAY") {
        $ids = [ $ids ];
    }

    # probably should validate in someway, but as long as they're URNs, we're happy.
    return (0, $ids);
}

sub parse_dcn_links {
    my ($dcnlinks) = @_;

    if (ref($dcnlinks) ne "ARRAY") {
        $dcnlinks = [ $dcnlinks ];
    }

    my %links_by_id = ();

    foreach my $link (@$dcnlinks) {
        unless ($link->{id}) {
            return (-1, "No link ID(s) specified");
        }

        ($status, $res) = parse_dcn_link_ids($link->{id});
        return ($status, $res) if ($status != 0);

        my $ids = $res;

        unless ($link->{measurement}) {
            return (-1, "No measurement parameters specified");
        }

        ($status, $res) = parse_dcn_link_measurement($link->{measurement});
        return ($status, $res) if ($status != 0);

        my $measurement = $res;

        unless ($link->{action}) {
            return (-1, "No action parameters specified");
        }

        ($status, $res) = parse_dcn_link_actions($link->{action});
        return ($status, $res) if ($status != 0);

        my $actions = $res;

        my %dcn_link_info = (
                ids => $ids,
                measurement_parameters => $measurement,
                actions => $actions,
        );

        foreach my $id (@$ids) {
                if ($links_by_id{$id}) {
                        # probably should either merge or just allow multiple.
                        return (-1, $id." appears in multiple dcn-link entities");
                }

                $links_by_id{$id} = \%dcn_link_info;
        }
    }

    return (0, \%links_by_id);
}

sub parse_dcn_link_ids {
    my ($ids) = @_;

    if (ref($ids) ne "ARRAY") {
        $ids = [ $ids ];
    }

    # probably should validate in someway, but as long as they're URNs, we're happy.
    return (0, $ids);
}

sub parse_dcn_link_measurement {
    my ($measurement) = @_;

    if (ref($measurement) eq "ARRAY") {
        return (-1, "Multiple measurement blocks associated with link");
    }

    if ($measurement->{type} and $measurement->{type} ne "SNMP") {
        return (-1, "Only SNMP measurement types are accepted");
    }

    unless ($measurement->{MA}) {
        return (-1, "No measurement archive specified");
    }

    if ($measurement->{direction} and $measurement->{direction} ne "forward" and $measurement->{direction} ne "reverse") {
        return (-1, "Direction must be either 'forward' or 'reverse'");
    }

    unless ($measurement->{snmp} and ref($measurement->{snmp}) eq "HASH") {
        return (-1, "No SNMP parameters specified");
    }

    my $hostname = $measurement->{snmp}->{hostname};
    $hostname = $measurement->{snmp}->{hostName} unless ($hostname);
    return (-1, "No SNMP hostname parameter specified") unless ($hostname);

    my $ifname = $measurement->{snmp}->{ifname};
    $ifname = $measurement->{snmp}->{ifName} unless ($ifname);

    my $ifindex = $measurement->{snmp}->{ifindex};
    $ifindex = $measurement->{snmp}->{ifIndex} unless ($ifindex);

    return (-1, "No SNMP ifName or ifIndex parameter specified") unless ($ifname or $ifindex);

    my $vlanMapping = $measurement->{snmp}->{vlanMapping};

    my %measurement_info = ();
    $measurement_info{type} = "SNMP";
    $measurement_info{direction} = $measurement->{direction}?$measurement->{direction}:"forward";
    $measurement_info{MA} = $measurement->{MA};
    $measurement_info{hostname} = $hostname;
    $measurement_info{ifindex} = $ifindex;
    $measurement_info{ifname} = $ifname;
    $measurement_info{vlanMapping} = $vlanMapping;

    return (0, \%measurement_info);
}

sub parse_dcn_link_actions {
    my ($actions) = @_;

    if (ref($actions) ne "ARRAY") {
        $actions = [ $actions ];
    }

    my @new_actions = ();
    foreach my $action (@$actions) {
        my ($status, $res) = parse_dcn_link_action($action);
        return ($status, $res) if ($status != 0);

        push @new_actions, $res;
    }

    return (0, \@new_actions);
}

sub parse_dcn_link_action {
    my ($action) = @_;

    return (0, $action);
}

sub parse_colors {
    my ($values) = @_;

    if (ref($values) ne "ARRAY") {
        $values = [ $values ];
    }

    my @color_ranges = ();

    foreach my $value (@$values) {
        my %range_descriptor = ();

        if ($value->{range}) {
            my ($status, $res) = parse_range($value->{range});
            if ($status != 0) {
                return(-1, "Error parsing ".$value->{range}.": ".$res);
            }
            $range_descriptor{type} = "range";
            $range_descriptor{minimum} = $res->{minimum};
            $range_descriptor{maximum} = $res->{maximum};
        }
        elsif ($value->{point}) {
            my ($status, $res) = parse_number($value->{point});
            if ($status != 0) {
                return(-1, "Error parsing ".$value->{point}.": ".$res);
            }
            $range_descriptor{type} = "point";
            $range_descriptor{point} = $res;
        }
        elsif ($value->{default}) {
            $range_descriptor{type} = "default";
        }

        unless ($value->{color}) {
            return(-1, "No color specified");
        }

        $range_descriptor{color} = $value->{color};

        push @color_ranges, \%range_descriptor;
    }

    return (0, \@color_ranges);
}

sub parse_range {
    my ($range) = @_;

    unless ($range =~ /-/) {
        return (-1, "No range specified");
    }

    my ($minimum, $maximum) = split(/-/, $range);

    if ($minimum) {
        my ($status, $res) = parse_number($minimum);
        if ($status != 0) {
             return ($status, $res);
        }

        $minimum = $res;
    }

    if ($maximum) {
        my ($status, $res) = parse_number($maximum);
        if ($status != 0) {
             return ($status, $res);
        }

        $maximum = $res;
    }

    # swap min/max if they were entered backwards
    if ($minimum and $maximum and $maximum < $minimum) {
        my $tmp = $minimum;
        $minimum = $maximum;
        $maximum = $tmp;
    }

    return (0, { minimum => $minimum, maximum => $maximum });
}

sub parse_number {
    my ($number) = @_;

    if ($number =~ /^\s*(\d+)([GgMmKk]?)\s*$/) {
        my $new_number = $1;
        if ($2) {
                if ($2 eq "G" or $2 eq "G") {
                    $new_number *= 1000*1000*1000;
                }
                elsif ($2 eq "M" or $2 eq "M") {
                    $new_number *= 1000*1000;
                }
                elsif ($2 eq "K" or $2 eq "K") {
                    $new_number *= 1000;
                }
        }

        return (0, $new_number);
    }
    else {
        return (-1, "Invalid number: $number");
    }
}

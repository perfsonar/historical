package perfSONAR_PS::SCWeatherMap::DCNLinkUtilization;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Utilization';

use fields 'OSCARS_CLIENT', 'IDCS', 'AXIS2_HOME', 'JAVA_DIRECTORY', 'DCN_LINKS';

use Data::Dumper;

use perfSONAR_PS::Client::OSCARS;
use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{'dcn-links'} and $conf->{'dcn-links'}->{'dcn-link'}) {
        $self->{LOGGER}->debug("No dcn links defined");
        return (0, "");
    }

    my ($status, $res) = $self->parse_dcn_links($conf->{'dcn-links'}->{'dcn-link'});
    if ($status != 0) {
        return ($status, $res);
    }

    $self->{DCN_LINKS} = $res;

    unless ($conf->{oscars_client}) {
        return (-1, "No oscars client directory specified");
    }

    $self->{OSCARS_CLIENT} = $conf->{oscars_client};

    unless ($conf->{axis2_home}) {
        return (-1, "No Axis directory specified");
    }

    $self->{AXIS2_HOME} = $conf->{axis2_home};

    $self->{JAVA_DIRECTORY} = $conf->{java_directory};

    unless ($conf->{idc}) {
        return (-1, "No idcs specified");
    }

    $self->{IDCS} = ();

    if (ref($conf->{idc}) ne "ARRAY") {
        $conf->{idc} = [ $conf->{idc} ];
    }

    foreach my $idc (@{ $conf->{idc} }) {
        push @{ $self->{IDCS} }, $idc;
    }

    return (0, "");
}

sub run {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            current_endpoints  => 1,
            current_links      => 1,
            current_icons      => 1,
            current_background => 1,
        }
    );

    my ($status, $res);

    my $dcn_links = $self->{DCN_LINKS};

    foreach my $idc (@{ $self->{IDCS} }) {
        my $reservations_client = perfSONAR_PS::Client::OSCARS->new();
        $status = $reservations_client->init({ idc_url => $idc, oscars_client => $self->{OSCARS_CLIENT}, axis2_home => $self->{AXIS2_HOME}, java_directory => $self->{JAVA_DIRECTORY} });
        if ($status != 0) {
            $self->{LOGGER}->debug("Couldn't initialize oscars client");
            next;
        }

        eval {
            ($status, $res) = $reservations_client->listReservations({ status => "ACTIVE" });
        };
        if ($@) {
            $self->{LOGGER}->debug("Problem querying for reservations: ".$@);
            next;
        }
        unless ($status == 0) {
            $self->{LOGGER}->debug("Problem querying for reservations: ".$res);
            next;
        }

        # Each reservation starts a new 'path' through the idc (wrt to the 'add
        # edge' functionality).
        foreach my $resv (@{ $res->resDetails }) {
            $self->{LOGGER}->debug("Found reservation");
            next unless ($resv->pathInfo);

            $self->{LOGGER}->debug("Reservation has a path info");

            my $prev_edge_point;

            foreach my $hop (@{ $resv->pathInfo->path->hop }) {
                $self->{LOGGER}->debug("Found hop in path info");

                next unless $hop->link;

                my $link_id = $hop->link->_id->__value;

                $self->{LOGGER}->debug("Hop has link: $link_id");

                next unless ($hop->link->SwitchingCapabilityDescriptors->encodingType eq "ethernet");

                $self->{LOGGER}->debug("Hop is ethernet");

                my $link_match_info_arr = $self->{DCN_LINKS}->{$link_id};

                next unless ($link_match_info_arr);

                foreach my $link_match_info (@$link_match_info_arr) {
                    $self->{LOGGER}->debug("Hop has link match info: ".Dumper($link_match_info));

                    my $vlan = $hop->link->SwitchingCapabilityDescriptors->switchingCapabilitySpecificInfo->vlanRangeAvailability->__value;

                    # XXX validate whether or not the vlan matches
                    if ($link_match_info->{vlans}) {
                        my $match;

                        foreach my $vlan_range (@{ $link_match_info->{vlans} }) {
                                next if ($vlan_range->{min} and $vlan < $vlan_range->{min});
                                next if ($vlan_range->{max} and $vlan > $vlan_range->{max});

                                $self->{LOGGER}->debug("VLAN matches");
                                $match = 1;
                        }

                        unless ($match) {
                            $self->{LOGGER}->debug("VLAN doesn't match");
                            next;
                        }
                    }

                    my $link_info = $link_match_info->{link_info};

                    my ($MA, $direction, $hostName, $ifName, $ifIndex);

                    if ($link_info->{measurement_parameters}) {
                        $self->{LOGGER}->debug("Found link info: measurement");

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

                    $self->{LOGGER}->debug("Link Info: ".Dumper($link_info));

                    foreach my $action (@{ $link_info->{actions} }) {
                        # only support 'add' for now. Could support removal or
                        # some such later I guess.
                        $self->{LOGGER}->debug("Found action");
                        next unless ($action->{type} eq "add");
                        $self->{LOGGER}->debug("Action is add");

                        if ($action->{'subject'}->{'link'}) {
                            $self->{LOGGER}->debug("Add type is link");

                            my $source = $action->{'subject'}->{'link'}->{'source'};
                            my $destination = $action->{'subject'}->{'link'}->{'destination'};

                            # The semantics for the edge points says that we
                            # link up the previous edge point to the 'source
                            # endpoint' of the link we're connecting.
                            if ($prev_edge_point and $source ne $prev_edge_point->{name} and $destination ne $prev_edge_point->{name}) {
                                my @measurements = ();
                                if ($prev_edge_point->{'hostName'} and $prev_edge_point->{'direction'} and ($prev_edge_point->{'ifName'} or $prev_edge_point->{'ifIndex'})) {
                                    # Previous is the source of the drawn
                                    # links, so we can use it's direction
                                    # directly because out == source -> dest.
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

                                $self->{LOGGER}->debug("Adding link(2): ".Dumper(\%new_link));
                                push @{ $args->{current_links} }, \%new_link;
                            }

                            my @measurements = ();
                            if ($hostName and $direction and ($ifName or $ifIndex)) {
                                # Previous is the source of the drawn links, so
                                # we can use it's direction directly because
                                # out == source -> dest.
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

                            $self->{LOGGER}->debug("Adding link(3): ".Dumper(\%new_link));
                            push @{ $args->{current_links} }, \%new_link;

                            # The destination gets setup as the new
                            # 'edge-point'

                            my %new_edge_point = ();
                            $new_edge_point{'name'} = $destination;

                            $prev_edge_point = \%new_edge_point;
                        }
                        elsif ($action->{'subject'}->{'edge-point'}) {
                            $self->{LOGGER}->debug("Add type is edge-point");

                            my %new_edge_point = ();
                            $new_edge_point{'name'} = $action->{'subject'}->{'edge-point'};
                            $new_edge_point{'MA'} = $MA;
                            $new_edge_point{'hostName'} = $hostName;
                            $new_edge_point{'ifName'} = $ifName;
                            $new_edge_point{'ifIndex'} = $ifIndex;
                            $new_edge_point{'direction'} = $direction;

                            # We want to not add a link if the new edge point's
                            # endpoint is the same as the old one, but the new
                            # edge point needs to be set so that the
                            # measurement info gets carried over.
                            if ($prev_edge_point and $prev_edge_point->{name} ne $action->{'subject'}->{'edge-point'}) {
                                my @measurements = ();
                                if ($prev_edge_point->{'hostName'} and $prev_edge_point->{'direction'} and ($prev_edge_point->{'ifName'} or $prev_edge_point->{'ifIndex'})) {
                                    # Previous is the source of the drawn
                                    # links, so we can use it's direction
                                    # directly because out == source -> dest.
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
                                    # The new node is the destination of the
                                    # drawn links so we have to reverse its
                                    # direction because out == dest -> source.
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

                                $self->{LOGGER}->debug("Adding link(1): ".Dumper(\%new_link));
                                push @{ $args->{current_links} }, \%new_link;
                            }

                            $prev_edge_point = \%new_edge_point;
                        }
                    }
                }
            }
        }
    }

    return (0, "");
}

sub parse_dcn_links {
    my ($self, $dcnlinks) = @_;

    if (ref($dcnlinks) ne "ARRAY") {
        $dcnlinks = [ $dcnlinks ];
    }

    my %links_by_id = ();

    foreach my $link (@$dcnlinks) {
        unless ($link->{'dcn-edgepoint'}) {
            return (-1, "No link endpoint(s) specified");
        }

	my ($status, $res);

        ($status, $res) = $self->parse_dcn_link_edgepoints($link->{'dcn-edgepoint'});
        return ($status, $res) if ($status != 0);

        my $dcnlink_endpoints = $res;

        unless ($link->{measurement}) {
            return (-1, "No measurement parameters specified");
        }

        ($status, $res) = $self->parse_dcn_link_measurement($link->{measurement});
        return ($status, $res) if ($status != 0);

        my $measurement = $res;

        unless ($link->{action}) {
            return (-1, "No action parameters specified");
        }

        ($status, $res) = $self->parse_dcn_link_actions($link->{action});
        return ($status, $res) if ($status != 0);

        my $actions = $res;

        my %dcn_link_info = (
                dcn_endpoints => $dcnlink_endpoints,
                measurement_parameters => $measurement,
                actions => $actions,
        );

        foreach my $link_id (keys %$dcnlink_endpoints) {
            foreach my $dcnlink_endpoint (@{ $dcnlink_endpoints->{$link_id} }) {
                unless ($links_by_id{$dcnlink_endpoint->{link_id}}) {
                    $links_by_id{$dcnlink_endpoint->{link_id}} = ();
                }

                $dcnlink_endpoint->{link_info} = \%dcn_link_info;

                push @{ $links_by_id{$dcnlink_endpoint->{link_id}} }, $dcnlink_endpoint;
            }
        }
    }

    return (0, \%links_by_id);
}

sub parse_dcn_link_edgepoints {
    my ($self, $dcn_endpoints) = @_;

    if (ref($dcn_endpoints) ne "ARRAY") {
        $dcn_endpoints = [ $dcn_endpoints ];
    }

    my %endpoints_by_linkid = ();

    foreach my $dcn_endpoint (@$dcn_endpoints) {
        $self->{LOGGER}->debug("DCN Endpoint: ".Dumper($dcn_endpoint));

        my %endpoint = ();
        unless ($dcn_endpoint->{link_id}) {
                return (-1, "Endpoint does not have link id");
        }

        $endpoint{link_id} = $dcn_endpoint->{link_id};

        if ($dcn_endpoint->{vlans}) {
            $self->{LOGGER}->debug("Found vlans: ".Dumper($dcn_endpoint->{vlans}));
            my ($status, $res) = $self->parse_dcn_link_vlans($dcn_endpoint->{vlans});
            return ($status, $res) if ($status != 0);

            $endpoint{vlans} = $res;
        }

        unless ($endpoints_by_linkid{$endpoint{link_id}}) {
            $endpoints_by_linkid{$endpoint{link_id}} = ();
        }

        push @{ $endpoints_by_linkid{$endpoint{link_id}} }, \%endpoint;

        $self->{LOGGER}->debug("Endpoint: ".Dumper(\%endpoint));
    }

    return (0, \%endpoints_by_linkid);
}

sub parse_dcn_link_vlans {
    my ($self, $vlans) = @_;
    my @vlans = split(",", $vlans);

    my @ret_vlans = ();
    foreach my $vlan (@vlans) {
        my %vlan_range = ();
        if ($vlan =~ /-/) {
            my ($min, $max) = split('-', $vlan);
            $vlan_range{min} = $min;
            $vlan_range{max} = $max;
        } else {
            $vlan_range{min} = $vlan;
            $vlan_range{max} = $vlan;
        }

        push @ret_vlans, \%vlan_range;
    }

    return (0, \@ret_vlans);
}

sub parse_dcn_link_measurement {
    my ($self, $measurement) = @_;

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

    my $hostname = $measurement->{hostname};
    $hostname = $measurement->{hostName} unless ($hostname);
    return (-1, "No SNMP hostname parameter specified") unless ($hostname);

    my $ifname = $measurement->{ifname};
    $ifname = $measurement->{ifName} unless ($ifname);

    my $ifindex = $measurement->{ifindex};
    $ifindex = $measurement->{ifIndex} unless ($ifindex);

    return (-1, "No SNMP ifName or ifIndex parameter specified") unless ($ifname or $ifindex);

    my $vlanMapping = $measurement->{vlanMapping};

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
    my ($self, $actions) = @_;

    if (ref($actions) ne "ARRAY") {
        $actions = [ $actions ];
    }

    my @new_actions = ();
    foreach my $action (@$actions) {
        my ($status, $res) = $self->parse_dcn_link_action($action);
        return ($status, $res) if ($status != 0);

        push @new_actions, $res;
    }

    return (0, \@new_actions);
}

sub parse_dcn_link_action {
    my ($self, $action) = @_;

    return (0, $action);
}

1;

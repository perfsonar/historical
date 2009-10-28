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

my %configuration = Config::General->new($file)->getall;

my ($status, $res);

my $background_filter = perfSONAR_PS::WeatherMap::Background->new();
($status, $res) = $background_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $icons_filter = perfSONAR_PS::WeatherMap::Icons->new();
($status, $res) = $icons_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $endpoints_filter = perfSONAR_PS::WeatherMap::Endpoints->new();
($status, $res) = $endpoints_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $static_links_filter = perfSONAR_PS::WeatherMap::Links::Static->new();
($status, $res) = $static_links_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $dcn_links_filter = perfSONAR_PS::WeatherMap::Links::DCN->new();
($status, $res) = $dcn_links_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $utilization_filter = perfSONAR_PS::WeatherMap::Measurement::Utilization->new();
($status, $res) = $utilization_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $color_filter = perfSONAR_PS::WeatherMap::Color::Utilization->new();
($status, $res) = $color_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $stacked_filter = perfSONAR_PS::WeatherMap::Layout::Stacked->new();
($status, $res) = $stacked_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my %endpoints = ();
my @links = ();
my %background = ();
my @icons = ();

($status, $res) = $background_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $icons_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $endpoints_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $static_links_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $dcn_links_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $utilization_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $color_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $stacked_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

my %results = ();
$results{background} = \%background;
$results{endpoints} = \%endpoints;
$results{links} = \@links;
$results{icons} = \@icons;

print encode_json(\%results);

exit 0;

package perfSONAR_PS::WeatherMap::Base;

use strict;
use warnings;

use Log::Log4perl qw(get_logger);

use fields 'LOGGER';

use perfSONAR_PS::Utils::ParameterValidation;

=head2 new()

This call instantiates new objects. The object's "init" function must be called
before any interaction can occur.

=cut

sub new {
    my $class = shift;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

=head2 init($self, $conf)

This function initializes the object according to the configuration options set

=cut

sub init {
    my ( $self, $conf ) = @_;

    return (0, "");
}

=head2 run
    Runs the specified filter on the given endpoints, links, icons and background info
=cut
sub run {
    my ( $self ) = @_;
    my $args = validateParams(
        @_,
        {
            current_endpoints  => 1,
            current_links      => 1,
            current_icons      => 1,
            current_background => 1,
        }
    );

    die("Needs to be overridden");
}

package perfSONAR_PS::WeatherMap::Background;

use strict;
use warnings;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'IMAGE', 'HEIGHT', 'WIDTH', 'COLOR';

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    if ($conf->{background}) {
        my ($status, $res) = $self->parse_background({ background => $conf->{background} });
        if ($status != 0) {
            return ($status, $res);
        }

        $self->{IMAGE} = $res->{image};
        $self->{HEIGHT} = $res->{height};
        $self->{WIDTH} = $res->{width};
        $self->{COLOR} = $res->{color};
    } else {
        $self->{LOGGER}->debug("Using default background: 1024x768/white");

        $self->{IMAGE} = undef;
        $self->{HEIGHT} = "1024";
        $self->{WIDTH} = "768";
        $self->{COLOR} = "rgb(255,255,255)";
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

    $args->{current_background}->{image} = $self->{IMAGE} if ($self->{IMAGE});
    $args->{current_background}->{height} = $self->{HEIGHT} if ($self->{HEIGHT});
    $args->{current_background}->{width} = $self->{WIDTH} if ($self->{WIDTH});
    $args->{current_background}->{color} = $self->{COLOR} if ($self->{COLOR});

    return (0, "");
}

sub parse_background {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            background => 1,
        }
        );

    my $background = $args->{background};

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

package perfSONAR_PS::WeatherMap::Icons;

use strict;
use warnings;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'ICONS';

use Clone::Fast qw( clone );
use Data::Dumper;

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    if ($conf->{icons} and $conf->{icons}->{icon}) {
        my ($status, $res) = $self->parse_icons({ icons => $conf->{icons}->{icon} });
        if ($status != 0) {
            return ($status, $res);
        }

        $self->{ICONS} = $res;
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

    return (0, "") unless ($self->{ICONS});

    # add a copy of each endpoint since a later module can modify endpoints in
    # arbitrary ways.
    my $icons = clone($self->{ICONS});

    foreach my $icon (@$icons) {
        push @{ $args->{current_icons} }, $icon;
    }

    return (0, "");
}

sub parse_icons {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            icons => 1,
        }
        );

    my $icons = $args->{icons};

    if (ref($icons) ne "ARRAY") {
        $icons = [ $icons ];
    }

    my @icons = ();

    foreach my $icon (@$icons) {
        my %icon_info = ();

        $self->{LOGGER}->debug("Icon: ".Dumper($icon));
        unless ($icon->{x} and $icon->{y} and $icon->{image}) {
            return (-1, "Icons must have x coordinate, y coordinate and an image location");
        }

        $icon_info{x} = $icon->{y};
        $icon_info{y} = $icon->{x};
        $icon_info{image} = $icon->{image};
        $icon_info{height} = $icon->{height};
        $icon_info{width} = $icon->{width};

        push @icons, \%icon_info;
    }

    return (0, \@icons);
}

package perfSONAR_PS::WeatherMap::Endpoints;

use strict;
use warnings;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'ENDPOINTS';

use Clone::Fast qw( clone );
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

sub init {
    my ( $self, $conf ) = @_;

    if ($conf->{endpoints} and $conf->{endpoints}->{endpoint}) {
        my ($status, $res) = $self->parse_endpoints({ endpoints => $conf->{endpoints}->{endpoint} });
        if ($status != 0) {
            return ($status, $res);
        }

        $self->{ENDPOINTS} = $res;
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

    return (0, "") unless ($self->{ENDPOINTS});

    # add a copy of each endpoint since a later module can modify endpoints in
    # arbitrary ways.
    my $endpoints = clone($self->{ENDPOINTS});

    foreach my $ep_id (keys %{ $endpoints }) {
        $args->{current_endpoints}->{$ep_id} = $endpoints->{$ep_id};
    }

    return (0, "");
}

sub parse_endpoints {
    my ( $self, @args ) = @_;
    my $args = validateParams(
        @args,
        {
            endpoints => 1,
        }
        );

    my $endpoints = $args->{endpoints};

    if (ref($endpoints) ne "ARRAY") {
        $endpoints = [ $endpoints ];
    }

    my %endpoints_by_id = ();

    foreach my $ep (@$endpoints) {
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
                icon => $ep->{icon},
                height => $ep->{height},
                width => $ep->{width},
                type  => $ep->{type},
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

package perfSONAR_PS::WeatherMap::Links::DCN;

use base 'perfSONAR_PS::WeatherMap::Base';

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

package perfSONAR_PS::WeatherMap::Measurement::Utilization;

use base 'perfSONAR_PS::WeatherMap::Base';

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

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

    foreach my $link (@{ $args->{current_links} }) {
        next unless ($link->{measurement_parameters});

        my ($sourcedest_bps, $destsource_bps);

        foreach my $measurement_parameters (@{ $link->{measurement_parameters} }) {
            next unless ($measurement_parameters->{type} eq "SNMP");

            my $ma        = $measurement_parameters->{MA};
            my $hostName  = $measurement_parameters->{hostname};
            my $ifName    = $measurement_parameters->{ifname};
            my $ifIndex   = $measurement_parameters->{ifindex};
            my $direction = $measurement_parameters->{direction};

            my $in_Bps      = $self->callSNMP_MA( ma => $ma, host => $hostName, ifName => $ifName, direction => "in" );
            my $out_Bps     = $self->callSNMP_MA( ma => $ma, host => $hostName, ifName => $ifName, direction => "out" );

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
    my ( $self, @args ) = @_;
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

package perfSONAR_PS::WeatherMap::Color::Utilization;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'COLORS';

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{'colors'} and $conf->{'colors'}->{'value'}) { 
        return (0, "");
    }

    my ($status, $res) = parse_colors($conf->{'colors'}->{'value'});
    if ($status != 0) {
        return ($status, $res);
    }

    $self->{COLORS} = $res;

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

    foreach my $link (@{ $args->{current_links} }) {
        next unless ($link->{measurement_results} and $link->{measurement_results}->{type} eq "utilization");

        my $measurement_results = $link->{measurement_results};

        my ($current_srcdst_color, $current_dstsrc_color);

        foreach my $color (@{ $self->{COLORS} }) {

            if ($color->{type} eq "default") {
                $current_srcdst_color = $color unless ($current_srcdst_color);  
                $current_dstsrc_color = $color unless ($current_dstsrc_color);  
            }

            if ($measurement_results->{source_destination} and defined $measurement_results->{source_destination}->{value}) {
                if ($color->{minimum} and $color->{maximum}) {
                    if ($color->{minimum} <= $measurement_results->{source_destination}->{value} and
                            $color->{maximum} > $measurement_results->{source_destination}->{value}) {

                        $current_srcdst_color = $color;

                    }
                }
                elsif ($color->{minimum}) {
                    if ($color->{minimum} <= $measurement_results->{source_destination}->{value}) {
                        $current_srcdst_color = $color;
                    }
                }
                elsif ($color->{maximum}) {
                    if ($color->{maximum} >= $measurement_results->{source_destination}->{value}) {
                        $current_srcdst_color = $color;
                    }
                }
            }

            if ($measurement_results->{destination_source} and defined $measurement_results->{destination_source}->{value}) {
                if ($color->{minimum} and $color->{maximum}) {
                    if ($color->{minimum} <= $measurement_results->{destination_source}->{value} and
                            $color->{maximum} > $measurement_results->{destination_source}->{value}) {

                        $current_dstsrc_color = $color;

                    }
                }
                elsif ($color->{minimum}) {
                    if ($color->{minimum} <= $measurement_results->{destination_source}->{value}) {
                        $current_dstsrc_color = $color;
                    }
                }
                elsif ($color->{maximum}) {
                    if ($color->{maximum} >= $measurement_results->{destination_source}->{value}) {
                            $current_dstsrc_color = $color;
                    }
                }
            }
        }

        my %suggested_colors = ();

        $suggested_colors{'destination-source'} = $current_dstsrc_color->{color} if ($current_dstsrc_color);
        $suggested_colors{'source-destination'} = $current_srcdst_color->{color} if ($current_srcdst_color);

        $link->{'suggested-colors'} = \%suggested_colors;
    }

    return (0, "");
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


package perfSONAR_PS::WeatherMap::Links::Static;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'LINKS';

use Clone::Fast qw( clone );
use Data::Dumper;

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{'static-links'} and $conf->{'static-links'}->{'link'}) {
        $self->{LOGGER}->debug("No dcn links defined");
        return (0, "");
    }

    my ($status, $res) = $self->parse_static_links($conf->{'static-links'}->{'link'});
    if ($status != 0) {
        return ($status, $res);
    }

    $self->{LINKS} = $res;

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

    my $links = clone($self->{LINKS});

    foreach my $link (@$links) {
        push @{ $args->{current_links} }, $link;
    }

    return (0, "");
}

sub parse_static_links {
    my ($self, $staticlinks) = @_;

    if (ref($staticlinks) ne "ARRAY") {
        $staticlinks = [ $staticlinks ];
    }

    my @links = ();

    foreach my $link (@$staticlinks) {
        my %new_link = ();

        unless ($link->{source}) {
                return (-1, "Link does not have a source");
        }

        unless ($link->{destination}) {
                return (-1, "Link does not have a destination");
        }

        unless ($link->{type}) {
                return (-1, "Link does not have a type");
        }

        $new_link{source} = $link->{source};
        $new_link{destination} = $link->{destination};
        $new_link{type} = $link->{type};

        if ($link->{measurement}) {
            my ($status, $res) = $self->parse_link_measurement_parameters($link->{measurement});
            if ($status != 0) {
                return ($status, $res);
            }

            $new_link{measurement_parameters} = $res;
        }

        push @links, \%new_link;
    }

    return (0, \@links);
}

sub parse_link_measurement_parameters {
    my ($self, $measurements) = @_;

    if (ref($measurements) ne "ARRAY") {
        $measurements = [ $measurements ];
    }

    my @measurement_parameters_list = ();

    foreach my $params (@$measurements) {
        $self->{LOGGER}->debug("PARAMS: ".Dumper($params));

        unless ($params->{type}) {
                return (-1, "Measurement set does not have a type");
        }

        push @measurement_parameters_list, $params;
    }

    return (0, \@measurement_parameters_list);
}

package perfSONAR_PS::WeatherMap::Layout::Stacked;

use base 'perfSONAR_PS::WeatherMap::Base';

use fields 'ENABLED', 'ENDPOINT_HEIGHT', 'ENDPOINT_WIDTH', 'ROW_WIDTH';

use Clone::Fast qw( clone );
use Data::Dumper;

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{layout} and $conf->{layout}->{type} and $conf->{layout}->{type} eq "stacked") {
        $self->{ENABLED} = 0;
        return (0, "");
    }

    $self->{ENDPOINT_HEIGHT} = 30;
    $self->{ENDPOINT_HEIGHT} = $conf->{layout}->{endpoint_height} if ($conf->{layout}->{endpoint_height});

    $self->{ENDPOINT_WIDTH} = 30;
    $self->{ENDPOINT_WIDTH} = $conf->{layout}->{endpoint_width} if ($conf->{layout}->{endpoint_width});

    $self->{ROW_WIDTH} = 700;
    $self->{ROW_WIDTH} = $conf->{layout}->{row_width} if ($conf->{layout}->{row_width});

    $self->{ENABLED} = 1;

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

    return (0, "") unless ($self->{ENABLED});

    my %new_endpoints = ();

    my $link_num = 0;

    foreach my $link (@{ $args->{current_links} }) {
        my $curr_src_endpoint = $args->{current_endpoints}->{$link->{"source"}};
        my $curr_dst_endpoint = $args->{current_endpoints}->{$link->{"destination"}};

        # Skip any missing endpoints
        next unless ($curr_src_endpoint and $curr_dst_endpoint);

        my $new_src_id = $link->{"source"}."-".$link_num;
        my $new_dst_id = $link->{"destination"}."-".$link_num;

        my %new_src_endpoint = ();
        $new_src_endpoint{ids} = [ $new_src_id ];
        $new_src_endpoint{type} = $curr_src_endpoint->{type};
        $new_src_endpoint{icon} = $curr_src_endpoint->{icon};
        $new_src_endpoint{type} = $curr_src_endpoint->{type};
        $new_src_endpoint{outerRadius} = $curr_src_endpoint->{outerRadius};
        $new_src_endpoint{innerRadius} = $curr_src_endpoint->{innerRadius};

        $new_src_endpoint{height} = $self->{ENDPOINT_HEIGHT};
        $new_src_endpoint{width}  = $self->{ENDPOINT_WIDTH};
        $new_src_endpoint{x}      = 2*$self->{ENDPOINT_WIDTH};
        $new_src_endpoint{y}      = $self->{ENDPOINT_HEIGHT}*($link_num + 1);

        my %new_dst_endpoint = ();
        $new_dst_endpoint{ids} = [ $new_dst_id ];
        $new_dst_endpoint{type} = $curr_dst_endpoint->{type};
        $new_dst_endpoint{icon} = $curr_dst_endpoint->{icon};
        $new_dst_endpoint{type} = $curr_dst_endpoint->{type};
        $new_dst_endpoint{outerRadius} = $curr_dst_endpoint->{outerRadius};
        $new_dst_endpoint{innerRadius} = $curr_dst_endpoint->{innerRadius};

        $new_dst_endpoint{height} = $self->{ENDPOINT_HEIGHT};
        $new_dst_endpoint{width}  = $self->{ENDPOINT_WIDTH};
        $new_dst_endpoint{x}      = $self->{ROW_WIDTH} - 2*$self->{ENDPOINT_WIDTH};
        $new_dst_endpoint{y}      = $self->{ENDPOINT_HEIGHT}*($link_num + 1);

        $new_endpoints{$new_src_id} = \%new_src_endpoint;
        $new_endpoints{$new_dst_id} = \%new_dst_endpoint;

        # update the links to point to the new endpoints
        $link->{"source"} = $new_src_id;
        $link->{"destination"} = $new_dst_id;

        $link_num++;
    }

    # delete all the current endpoints and replace them with the modified endpoints
    foreach my $key (keys %{ $args->{current_endpoints} }) {
        delete($args->{current_endpoints}->{$key});
    }

    foreach my $key (keys %new_endpoints) {
        $args->{current_endpoints}->{$key} = $new_endpoints{$key};
    }

    $args->{background}->{height} = $self->{ENDPOINT_HEIGHT}*($link_num + 1);
    $args->{background}->{width} = $self->{ROW_WIDTH};

    return (0, "");
}

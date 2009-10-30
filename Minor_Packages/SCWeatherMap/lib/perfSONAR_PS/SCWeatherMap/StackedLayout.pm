package perfSONAR_PS::SCWeatherMap::StackedLayout;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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

1;

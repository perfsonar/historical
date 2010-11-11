package perfSONAR_PS::SCWeatherMap::Icons;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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

1;

package perfSONAR_PS::SCWeatherMap::Background;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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

1;

package perfSONAR_PS::SCWeatherMap::StaticLinks;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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
        $new_link{arrow_scale} = $link->{arrow_scale};

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

1;

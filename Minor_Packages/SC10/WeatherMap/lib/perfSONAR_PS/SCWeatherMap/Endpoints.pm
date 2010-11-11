package perfSONAR_PS::SCWeatherMap::Endpoints;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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

        my ($status, $res) = parse_endpoint_ids($ep->{id});
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

1;

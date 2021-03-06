package perfSONAR_PS::SCWeatherMap::UtilizationColors;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

use fields 'COLORS';

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{'colors'}) { 
        return (0, "");
    }

    my ($status, $res) = parse_colors($conf->{'colors'});
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
        next unless ($link->{measurement_results});

	my ($current_srcdst_color, $current_dstsrc_color);

	foreach my $measurement_result (@{ $link->{measurement_results} }) {
		next unless ($measurement_result->{type} eq "utilization");

		my $measurement_result = $link->{measurement_result};

		foreach my $color (@{ $self->{COLORS} }) {

			if ($color->{type} eq "default") {
				$current_srcdst_color = $color unless ($current_srcdst_color);  
				$current_dstsrc_color = $color unless ($current_dstsrc_color);  
			}

			if ($measurement_result->{source_destination} and defined $measurement_result->{source_destination}->{value}) {
				if ($color->{minimum} and $color->{maximum}) {
					if ($color->{minimum} <= $measurement_result->{source_destination}->{value} and
							$color->{maximum} > $measurement_result->{source_destination}->{value}) {

						$current_srcdst_color = $color;

					}
				}
				elsif ($color->{minimum}) {
					if ($color->{minimum} <= $measurement_result->{source_destination}->{value}) {
						$current_srcdst_color = $color;
					}
				}
				elsif ($color->{maximum}) {
					if ($color->{maximum} >= $measurement_result->{source_destination}->{value}) {
						$current_srcdst_color = $color;
					}
				}
			}

			if ($measurement_result->{destination_source} and defined $measurement_result->{destination_source}->{value}) {
				if ($color->{minimum} and $color->{maximum}) {
					if ($color->{minimum} <= $measurement_result->{destination_source}->{value} and
							$color->{maximum} > $measurement_result->{destination_source}->{value}) {

						$current_dstsrc_color = $color;

					}
				}
				elsif ($color->{minimum}) {
					if ($color->{minimum} <= $measurement_result->{destination_source}->{value}) {
						$current_dstsrc_color = $color;
					}
				}
				elsif ($color->{maximum}) {
					if ($color->{maximum} >= $measurement_result->{destination_source}->{value}) {
						$current_dstsrc_color = $color;
					}
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
    my ($colors) = @_;

    if (ref($colors) ne "ARRAY") {
        $colors = [ $colors ];
    }

    foreach my $color_type (@$colors) {
        next unless ($color_type->{type} eq "utilization");

	unless ($color->{value}) {
		return (-1, "No color values for utilization colors");
	}

        my @color_ranges = ();

	if (ref($color_type->{value}) ne "ARRAY") {
		$color_type->{value} = [ $color_type->{value} ];
	}

        foreach my $value (@{ $color_type->{value} }) {
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
                        return(-1, "No color specified in utilization colors");
                }

                $range_descriptor{color} = $value->{color};

                push @color_ranges, \%range_descriptor;
        }

        return (0, \@color_ranges);
    }

    return (-1, "No utilization colors");
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

1;

package perfSONAR_PS::SCWeatherMap::Utilization;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

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

        $link->{measurement_results} = [ { type => "utilization", source_destination => { value => $sourcedest_bps, unit => "bps" }, destination_source => { value => $destsource_bps, unit => "bps" } } ];
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

1;

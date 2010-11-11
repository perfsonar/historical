package perfSONAR_PS::SCWeatherMap::perfSONARBUOYOwamp;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

use fields 'DBI_STRING', 'DB_USERNAME', 'DB_PASSWORD', 'DURATION', 'ENABLED'; 

use strict;
use warnings;

use DBI;
use owdb;
use OWP::Utils;

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{perfsonarbuoy_owamp}) {
        $self->{ENABLED} = 0;

        return (0, "");
    }

    unless ($conf->{perfsonarbuoy_owamp}->{db_type}) {
        return (-1, "No database type specified for perfSONARBUOY/owamp");
    }

    unless ($conf->{perfsonarbuoy_owamp}->{db_name}) {
        return (-1, "No database name specified for perfSONARBUOY/owamp");
    }

    my $dbistring = "DBI:".$conf->{perfsonarbuoy_owamp}->{db_type}.":".$conf->{perfsonarbuoy_owamp}->{db_name};

    if ($conf->{perfsonarbuoy_owamp}->{db_host}) {
        $dbistring .= ":".$conf->{perfsonarbuoy_owamp}->{db_host};
    } else {
        $dbistring .= ":localhost";
    }

    if ($conf->{perfsonarbuoy_owamp}->{db_port}) {
        $dbistring .= ":".$conf->{perfsonarbuoy_owamp}->{db_port};
    }

    $self->{DBI_STRING} = $dbistring;

    $self->{DB_USERNAME} = $conf->{perfsonarbuoy_owamp}->{db_username};
    $self->{DB_PASSWORD} = $conf->{perfsonarbuoy_owamp}->{db_password};

    $self->{DURATION} = $conf->{perfsonarbuoy_owamp}->{duration};
    unless ($self->{DURATION}) {
        $self->{LOGGER}->debug("No time specified, using 5 minutes");
        $self->{DURATION} = 800;
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

    my $end = time;
    my $start = $end - $self->{DURATION};

    foreach my $link (@{ $args->{current_links} }) {
        next unless ($link->{measurement_parameters});

        my %final_srcdst_stats = ();
        my %final_dstsrc_stats = ();

        foreach my $measurement_parameters (@{ $link->{measurement_parameters} }) {
            next unless ($measurement_parameters->{type} eq "perfSONARBUOY/owamp");

            my $source_name = $measurement_parameters->{source_node};
            my $destination_name = $measurement_parameters->{destination_node};
            my $direction = $measurement_parameters->{direction};
            $direction = "forward" unless ($direction);

            my $dbh = DBI->connect( $self->{DBI_STRING}, $self->{DB_USERNAME}, $self->{DB_PASSWORD}, { RaiseError => 0, PrintError => 1 });
            unless ($dbh) {
                $self->{LOGGER}->error("Couldn't connect to database");
                next;
            }

            my ($status, $res);

            my ($srcdst_stats, $dstsrc_stats);

            ($status, $res) = $self->calculate_link_stats({ dbh => $dbh, source => $source_name, destination => $destination_name, start => $start, end => $end });
            $srcdst_stats = $res;
            ($status, $res) = $self->calculate_link_stats({ dbh => $dbh, source => $destination_name, destination => $source_name, start => $start, end => $end });
            $dstsrc_stats = $res;

            # swap if the directions are reversed
            if ($direction eq "reverse") {
                my $tmp = $srcdst_stats;
                $srcdst_stats = $dstsrc_stats;
                $dstsrc_stats = $tmp;
            }

            $final_srcdst_stats{jitter} = $srcdst_stats->{jitter} if (defined $srcdst_stats->{jitter} and (not $final_srcdst_stats{jitter} or $final_srcdst_stats{jitter} < $srcdst_stats->{jitter}));
            $final_srcdst_stats{min_delay} = $srcdst_stats->{min_delay} if (defined $srcdst_stats->{min_delay} and (not $final_srcdst_stats{min_delay} or $final_srcdst_stats{min_delay} > $srcdst_stats->{min_delay}));
            $final_srcdst_stats{max_delay} = $srcdst_stats->{max_delay} if (defined $srcdst_stats->{max_delay} and (not $final_srcdst_stats{max_delay} or $final_srcdst_stats{max_delay} < $srcdst_stats->{max_delay}));
            $final_srcdst_stats{loss} = $srcdst_stats->{loss} if (defined $srcdst_stats->{loss} and (not $final_srcdst_stats{loss} or $final_srcdst_stats{loss} < $srcdst_stats->{loss}));

            $final_dstsrc_stats{jitter} = $dstsrc_stats->{jitter} if (defined $dstsrc_stats->{jitter} and (not $final_dstsrc_stats{jitter} or $final_dstsrc_stats{jitter} < $dstsrc_stats->{jitter}));
            $final_dstsrc_stats{min_delay} = $dstsrc_stats->{min_delay} if (defined $dstsrc_stats->{min_delay} and (not $final_dstsrc_stats{min_delay} or $final_dstsrc_stats{min_delay} > $dstsrc_stats->{min_delay}));
            $final_dstsrc_stats{max_delay} = $dstsrc_stats->{max_delay} if (defined $dstsrc_stats->{max_delay} and (not $final_dstsrc_stats{max_delay} or $final_dstsrc_stats{max_delay} < $dstsrc_stats->{max_delay}));
            $final_dstsrc_stats{loss} = $dstsrc_stats->{loss} if (defined $dstsrc_stats->{loss} and (not $final_dstsrc_stats{loss} or $final_dstsrc_stats{loss} < $dstsrc_stats->{loss}));
        }

        $link->{measurement_results} = [
		{
                type => "jitter",
                source_destination => { value => $final_srcdst_stats{jitter}, unit => "milliseconds" },
                destination_source => { value => $final_dstsrc_stats{jitter}, unit => "milliseconds" }
                },
        	{
                type => "loss",
                source_destination => { value => $final_srcdst_stats{loss}, unit => "percent" },
                destination_source => { value => $final_dstsrc_stats{loss}, unit => "percent" }
                },
		{
                type => "min_delay",
                source_destination => { value => $final_srcdst_stats{min_delay}, unit => "milliseconds" },
                destination_source => { value => $final_dstsrc_stats{min_delay}, unit => "milliseconds" }
                },
		{
                type => "max_delay",
                source_destination => { value => $final_srcdst_stats{max_delay}, unit => "milliseconds" },
                destination_source => { value => $final_dstsrc_stats{max_delay}, unit => "milliseconds" }
                }
	];

    }

    return (0, "");
}

=head2 calculate_link_stats({ dbh, source, destination, start, end })

...

=cut

sub calculate_link_stats{
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, { dbh => 1, source => 1, destination => 1, start => 1, end => 1 } );
  
    my $dbh =  $args->{dbh};
    my $source =  $args->{source};
    my $destination =  $args->{destination};
    my $start =  $args->{start};
    my $end =  $args->{end};
 
    my $max_jitter;
    my $alpha_min = "0.0";
    my $alpha_max = "0.95";

    my %owpvals = ();

    my $owdb = owdb_prep(
		DBH         => $dbh,
		SEND_NAME   => $source,
		RECV_NAME   => $destination,
		FIRST       => owptstampi( time2owptime($start) ),
		LAST        => owptstampi( time2owptime($end) ),
		ALPHAS      => [ $alpha_min, $alpha_max ],
		OWHASH      => \%owpvals,
		);

    unless ($owdb) {
	    my $msg = "Unable to init owp data request";
	    $self->{LOGGER}->error($msg);
	    return (-1, $msg);
    }

    my ($loss, $max_delay, $min_delay, $jitter);

    $self->{LOGGER}->debug("Checking $source -> $destination");
    while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
	use Data::Dumper;
	    $self->{LOGGER}->debug("Got bucket for $source -> $destination: ".Dumper(\%owpvals));

            my $loss_percentage = $owpvals{'LOST'} / $owpvals{'SENT'} * 100;

            my $max = $owpvals{'MAX'};
            my $min = $owpvals{'MIN'};

            $loss = $loss_percentage if (not $loss or $loss_percentage > $loss);
            $max_delay = $max if (not $max_delay or $max > $max_delay);
            $min_delay = $min if (not $min_delay or $min < $min_delay);

            my $tmp_max = $owpvals{ALPHAS}->{$alpha_max};
            my $tmp_min = $owpvals{ALPHAS}->{$alpha_min};

            $tmp_max = $max_delay unless ($max);
            $tmp_min = $min_delay unless ($min);

            my $jitter_value = $tmp_max - $tmp_min;

            $jitter_value *= 1000;
            $max *= 1000;
            $min *= 1000;

            $jitter = $jitter_value if (not $jitter or $jitter_value > $jitter);

            $self->{LOGGER}->debug("Min: $min, Max: $max, Alpha Max: $owpvals{ALPHAS}->{$alpha_max}, Alpha Min: $owpvals{ALPHAS}->{$alpha_min}, Jitter: $jitter");
    }

    return (0, { loss => $loss, max_delay => $max_delay, min_delay => $min_delay, jitter => $jitter });
}

1;

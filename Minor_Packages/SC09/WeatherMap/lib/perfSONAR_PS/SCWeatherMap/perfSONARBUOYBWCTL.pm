package perfSONAR_PS::SCWeatherMap::perfSONARBUOYBWCTL;

use strict;
use warnings;

use base 'perfSONAR_PS::SCWeatherMap::Base';

use fields 'DBI_STRING', 'DB_USERNAME', 'DB_PASSWORD', 'DURATION', 'ENABLED'; 

use strict;
use warnings;

use DBI;
use bwdb;
use OWP::Utils;

use perfSONAR_PS::Utils::ParameterValidation;

sub init {
    my ( $self, $conf ) = @_;

    unless ($conf->{perfsonarbuoy_bwctl}) {
        $self->{ENABLED} = 0;

        return (0, "");
    }

    unless ($conf->{perfsonarbuoy_bwctl}->{db_type}) {
        return (-1, "No database type specified for perfSONARBUOY/bwctl");
    }

    unless ($conf->{perfsonarbuoy_bwctl}->{db_name}) {
        return (-1, "No database name specified for perfSONARBUOY/bwctl");
    }

    my $dbistring = "DBI:".$conf->{perfsonarbuoy_bwctl}->{db_type}.":".$conf->{perfsonarbuoy_bwctl}->{db_name};

    if ($conf->{perfsonarbuoy_bwctl}->{db_host}) {
        $dbistring .= ":".$conf->{perfsonarbuoy_bwctl}->{db_host};
    } else {
        $dbistring .= ":localhost";
    }

    if ($conf->{perfsonarbuoy_bwctl}->{db_port}) {
        $dbistring .= ":".$conf->{perfsonarbuoy_bwctl}->{db_port};
    }

    $self->{DBI_STRING} = $dbistring;

    $self->{DB_USERNAME} = $conf->{perfsonarbuoy_bwctl}->{db_username};
    $self->{DB_PASSWORD} = $conf->{perfsonarbuoy_bwctl}->{db_password};

    $self->{DURATION} = $conf->{perfsonarbuoy_bwctl}->{duration};
    unless ($self->{DURATION}) {
        $self->{LOGGER}->debug("No time specified, using 1 day");
        $self->{DURATION} = 86400;
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
            next unless ($measurement_parameters->{type} eq "perfSONARBUOY/bwctl");

            my $source_name = $measurement_parameters->{source_node};
            my $source_address = $measurement_parameters->{source_address};
            my $destination_name = $measurement_parameters->{destination_node};
            my $destination_address = $measurement_parameters->{destination_address};

            my $direction = $measurement_parameters->{direction};
            $direction = "forward" unless ($direction);

            my $dbh = DBI->connect( $self->{DBI_STRING}, $self->{DB_USERNAME}, $self->{DB_PASSWORD}, { RaiseError => 0, PrintError => 1 });
            unless ($dbh) {
                $self->{LOGGER}->error("Couldn't connect to database");
                next;
            }

            my ($status, $res);

            my ($srcdst_stats, $dstsrc_stats);

            ($status, $res) = $self->calculate_link_stats({
			    dbh => $dbh,
			    source => $source_name,
			    source_address => $source_address,
			    destination => $destination_name,
			    destination_address => $destination_address,
			    start => $start,
			    end => $end });

            $srcdst_stats = $res;

            ($status, $res) = $self->calculate_link_stats({
			    dbh => $dbh,
			    source => $destination_name,
			    source_address => $destination_address,
			    destination => $source_name,
			    destination_address => $source_address,
			    start => $start,
			    end => $end });
            $dstsrc_stats = $res;

            # swap if the directions are reversed
            if ($direction eq "reverse") {
                my $tmp = $srcdst_stats;
                $srcdst_stats = $dstsrc_stats;
                $dstsrc_stats = $tmp;
            }

            $final_srcdst_stats{average_throughput} = $srcdst_stats->{average_throughput} if (defined $srcdst_stats->{average_throughput} and (not $final_srcdst_stats{average_throughput} or $final_srcdst_stats{average_throughput} > $srcdst_stats->{average_throughput}));
            $final_srcdst_stats{min_throughput} = $srcdst_stats->{min_throughput} if (defined $srcdst_stats->{min_throughput} and (not $final_srcdst_stats{min_throughput} or $final_srcdst_stats{min_throughput} > $srcdst_stats->{min_throughput}));
            $final_srcdst_stats{max_throughput} = $srcdst_stats->{max_throughput} if (defined $srcdst_stats->{max_throughput} and (not $final_srcdst_stats{max_throughput} or $final_srcdst_stats{max_throughput} < $srcdst_stats->{max_throughput}));
            $final_srcdst_stats{median_throughput} = $srcdst_stats->{median_throughput} if (defined $srcdst_stats->{median_throughput} and (not $final_srcdst_stats{median_throughput} or $final_srcdst_stats{median_throughput} > $srcdst_stats->{median_throughput}));
            $final_srcdst_stats{last_throughput} = $srcdst_stats->{last_throughput} if (defined $srcdst_stats->{last_throughput});

            $final_dstsrc_stats{average_throughput} = $dstsrc_stats->{average_throughput} if (defined $dstsrc_stats->{average_throughput} and (not $final_dstsrc_stats{average_throughput} or $final_dstsrc_stats{average_throughput} > $dstsrc_stats->{average_throughput}));
            $final_dstsrc_stats{min_throughput} = $dstsrc_stats->{min_throughput} if (defined $dstsrc_stats->{min_throughput} and (not $final_dstsrc_stats{min_throughput} or $final_dstsrc_stats{min_throughput} > $dstsrc_stats->{min_throughput}));
            $final_dstsrc_stats{max_throughput} = $dstsrc_stats->{max_throughput} if (defined $dstsrc_stats->{max_throughput} and (not $final_dstsrc_stats{max_throughput} or $final_dstsrc_stats{max_throughput} < $dstsrc_stats->{max_throughput}));
            $final_dstsrc_stats{median_throughput} = $dstsrc_stats->{median_throughput} if (defined $dstsrc_stats->{median_throughput} and (not $final_dstsrc_stats{median_throughput} or $final_dstsrc_stats{median_throughput} > $dstsrc_stats->{median_throughput}));
            $final_dstsrc_stats{last_throughput} = $dstsrc_stats->{last_throughput} if (defined $dstsrc_stats->{last_throughput});
        }

        $link->{measurement_results} = [
		{
                type => "average_throughput",
                source_destination => { value => $final_srcdst_stats{average_throughput}, unit => "bps" },
                destination_source => { value => $final_dstsrc_stats{average_throughput}, unit => "bps" }
                },
        	{
                type => "median_throughput",
                source_destination => { value => $final_srcdst_stats{median_throughput}, unit => "bps" },
                destination_source => { value => $final_dstsrc_stats{median_throughput}, unit => "bps" }
                },
		{
                type => "min_throughput",
                source_destination => { value => $final_srcdst_stats{min_throughput}, unit => "bps" },
                destination_source => { value => $final_dstsrc_stats{min_throughput}, unit => "bps" }
                },
		{
                type => "max_throughput",
                source_destination => { value => $final_srcdst_stats{max_throughput}, unit => "bps" },
                destination_source => { value => $final_dstsrc_stats{max_throughput}, unit => "bps" }
                },
		{
                type => "last_throughput",
                source_destination => { value => $final_srcdst_stats{last_throughput}, unit => "bps" },
                destination_source => { value => $final_dstsrc_stats{last_throughput}, unit => "bps" }
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
    my $args = validateParams( @args, { dbh => 1, source => 1, source_address => 0, destination => 1, destination_address => 0, start => 1, end => 1 } );
  
    my $dbh =  $args->{dbh};
    my $source =  $args->{source};
    my $source_address =  $args->{source_address};
    my $destination =  $args->{destination};
    my $destination_address =  $args->{destination_address};
    my $start =  $args->{start};
    my $end =  $args->{end};
 
    my %bwvals = ();

    $self->{LOGGER}->debug("Looking up stats for $source -> $destination");

    my $bwdb = bwdb_prep(
		DBH         => $dbh,
		SEND_NAME   => $source,
		SEND_ADDR   => $source_address,
		RECV_NAME   => $destination,
		RECV_ADDR   => $destination_address,
		FIRST       => owptstampi( time2owptime($start) ),
		LAST        => owptstampi( time2owptime($end) ),
		BWHASH      => \%bwvals,
		);

    unless ($bwdb) {
	    my $msg = "Unable to init owp data request";
	    $self->{LOGGER}->error($msg);
	    return (-1, $msg);
    }

    my ($max_throughput, $min_throughput, $num_throughputs, $sum_throughputs, $last_throughput);

    my @throughputs = ();

    while ( bwdb_fetch( BWDBH => $bwdb ) ) {
	    $self->{LOGGER}->debug("Got bucket for $source -> $destination");

	    my $test_time = owptime2exacttime( $bwvals{'TIME'} );
	    my $test_throughput = eval( $bwvals{'THROUGHPUT'} );

	    push @throughputs, $test_throughput;
            $num_throughputs++;
	    $sum_throughputs += $test_throughput;

 	    $max_throughput = $test_throughput if (not $max_throughput or $max_throughput < $test_throughput);
 	    $min_throughput = $test_throughput if (not $min_throughput or $min_throughput > $test_throughput);

	    # they come out in order
            $last_throughput = $test_throughput;
    }

    my $avg_throughput = undef;
    $avg_throughput = $sum_throughputs / $num_throughputs if ($num_throughputs);

    @throughputs = sort @throughputs;

    my $med_throughput = $throughputs[int($#throughputs/2)];

    $self->{LOGGER}->debug("Max for $source -> $destination: $max_throughput");

    return (0, { max_throughput => $max_throughput, min_throughput => $min_throughput, average_throughput => $avg_throughput, median_throughput => $med_throughput, last_throughput => $last_throughput });
}

1;

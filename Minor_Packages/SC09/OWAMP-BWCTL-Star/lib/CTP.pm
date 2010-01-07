package CTP;

use strict;
use warnings;

use owdb;
use OWP::Utils;
use Data::Dumper;

our $VERSION = 3.1;

=head1 NAME

OWP::CTP

=head1 DESCRIPTION

XXX

=cut

use Params::Validate qw(:all);

use base 'Exporter';
our @EXPORT_OK = qw( retrieve_mesh_summary );

sub retrieve_tests_summary {
        my $parameters = validate( @_,
                        {
                        db_handle      => 1,
                        tests          => 1,
                        start_time     => 1,
                        end_time       => 1,
                        resolution     => 1,
                        bucket_width   => 1,
                        flag_point     => 0,
                        loss_threshold => 0,
                        }
                        );

        my @tests;
        if (ref($parameters->{tests}) ne "ARRAY") {
                @tests = ();
                push @tests, $parameters->{tests};
        } else {
                @tests = @{ $parameters->{tests} };
        }

        my $dbh = $parameters->{db_handle};
        my $resolution = $parameters->{resolution};
        my $bucket_width = $parameters->{bucket_width};
        my $flag_point   = $parameters->{flag_point};
        my $loss_threshold =  $parameters->{loss_threshold};

        my $start_time_int = time2owptime( $parameters->{start_time} );
        my $end_time_int   = time2owptime( $parameters->{end_time} );


        my %all_results = ();
        my %individual_results = ();

        foreach my $test_name ( @tests ) {
                my %owpvals      = ();
                my @alphas = [0.5,0.95];

                my $owdb = owdb_prep(
                                DBH         => $dbh,
                                RES         => $resolution,
                                TNAME       => $test_name,
                                FIRST       => owptstampi( $start_time_int ),
                                LAST        => owptstampi( $end_time_int ),
                                OWHASH      => \%owpvals,
                                BUCKETWIDTH => $bucket_width,
                                ALPHAS      => @alphas,
                                );

                unless ($owdb) {
                        return (-1, "Unable to init owp data request for test $test_name, resolution $resolution");
                }

                my %test_results  = ();
                $test_results{SENT} = 0;
                $test_results{LOST} = 0;
                $test_results{ERR} = 0;
                $test_results{DUPS} = 0;
                $test_results{FLAGGED} = 0;
                $test_results{JITTER} = 0;
                $test_results{HISTOGRAM} = ();

                while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
                        my %yvals = ();

                        $test_results{LOST} += $owpvals{LOST};

                        if ($owpvals{MAX}) {
                            $test_results{MAX} = $owpvals{MAX} if (not $test_results{MAX} or $test_results{MAX} < $owpvals{MAX});
                        }
                        if ($owpvals{MIN}) {
                            $test_results{MIN} = $owpvals{MIN} if (not $test_results{MIN} or $test_results{MIN} > $owpvals{MIN});
                        }

                        if ($owpvals{MAX} and $owpvals{MIN}) {
                                $test_results{JITTER} = $owpvals{MAX} - $owpvals{MIN} if (not $test_results{JITTER} or $test_results{JITTER} < ($owpvals{MAX} - $owpvals{MIN}));
                        }

                        foreach my $key ( keys %{ $owpvals{HISTOGRAM} } ) {
                                my $hist_value = $owpvals{HISTOGRAM}->{$key};

                                unless ($test_results{JITTER}) {
                                        $test_results{JITTER} = $key * $bucket_width if (not $test_results{JITTER} or $test_results{JITTER} < ($key * $bucket_width));
                                }

                                $test_results{SENT} += $hist_value;

                                if ( $loss_threshold and $key * $bucket_width > $loss_threshold ) {
                                        $test_results{LOST} += $hist_value;
                                        next;
                                }

                                if ( $flag_point and $key * $bucket_width > $flag_point ) {
                                        $test_results{FLAGGED} += $hist_value;
                                }

                                $test_results{HISTOGRAM}->{$key} = $hist_value;
                        }
                }

                $all_results{LOST} += $test_results{LOST};
                $all_results{SENT} += $test_results{SENT};
                $all_results{ERR} += $test_results{ERR};
                $all_results{DUPS} += $test_results{DUPS};
                $all_results{FLAGGED} += $test_results{FLAGGED};
                $all_results{JITTER} = $test_results{JITTER} if (not $all_results{JITTER} or $all_results{JITTER} < $test_results{JITTER});

                if ($test_results{MAX}) {
                        $all_results{MAX} = $test_results{MAX} if (not $all_results{MAX} or $all_results{MAX} < $test_results{MAX});
                }

                if ($test_results{MIN}) {
                        $all_results{MIN} = $test_results{MIN} if (not $all_results{MIN} or $all_results{MIN} > $test_results{MIN});
                }

                foreach my $key ( keys %{ $test_results{HISTOGRAM} } ) {
                        my $time = $key * $bucket_width;

                        unless ($all_results{HISTOGRAM}->{$key}) {
                                $all_results{HISTOGRAM}->{$key} = 0;
                        }

                        $all_results{HISTOGRAM}->{$key} += $test_results{HISTOGRAM}->{$key};
                }

                $individual_results{$test_name} = \%test_results;
        }

        return (0, \%all_results, \%individual_results);
}

=head2 retrieve_mesh_summary

A function to return a summary for each test in a mesh, along with a summary
combining all the tests. The function takes the following parameters as a hash.

    db_handle       => the database handle
    mesh            => the mesh name
    bucket_width    => the mesh's bucket width
    resolution      => the desired resolution
    flag_point      => optional, the flag point in seconds
    loss_threshold  => optional, the loss threshold in seconds
    start_time      => a unix timestamp of the start
    end_time        => a unix timestamp of the end
    ignore_loopback => optional, set to 1 to ignore loopback tests
    paths_to_ignore => optional, a pointer to an array of hash elements containing 'receiver' and 'sender' keys whose values are the node names

=cut
sub retrieve_mesh_summary {
        my $parameters = validate( @_,
                        {
                        db_handle       => 1,		# the database handle
                        mesh            => 1,		# the mesh name
                        bucket_width    => 1,		# the mesh's bucket width
                        resolution      => 1,		# the desired resolution
                        flag_point      => 0,		# the flag point in seconds
                        loss_threshold  => 0,		# the loss threshold in seconds
                        start_time      => 1,		# a unix timestamp of the start
                        end_time        => 1,		# a unix timestamp of the end
                        ignore_loopback => 0,		# set to 1 to ignore loopback tests
                        paths_to_ignore => 0,		# an optional pointer to an array of hash elements containing 'receiver' and 'sender' keys whose values are the node names
                        }
                        );

        my $dbh = $parameters->{db_handle};

        my $mesh = $parameters->{mesh};

        my $bucket_width = $parameters->{bucket_width};
        my $resolution = $parameters->{resolution};

        my $flag_point   = $parameters->{flag_point};
        my $loss_threshold =  $parameters->{loss_threshold};

        my $start_time_int = time2owptime( $parameters->{start_time} );
        my $end_time_int   = time2owptime( $parameters->{end_time} );

	my $ignore_loopback = $parameters->{ignore_loopback};
	$ignore_loopback = 0 unless (defined $ignore_loopback);

	my %tests_to_ignore = ();
	if ($parameters->{paths_to_ignore}) {
		foreach my $path (@{ $parameters->{paths_to_ignore} }) {
			my $tname = $mesh."_".$path->{receiver}."_".$path->{sender};
			$tests_to_ignore{$tname} = 1;
		}
	}

	my ($sql, $sth);

	# get receivers
	my @receivers;
	$sql = "SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.recv_id";
	$sth = $dbh->prepare( $sql ) or return (-1, "Prep:Select receivers");
	$sth->execute() or return (-1, "Select receivers");
	while ( my @row = $sth->fetchrow_array ) {
	    push @receivers, @row;
	}
	@receivers = sort @receivers;

	# get senders
	my @senders;
	$sql = "SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.send_id";
	$sth = $dbh->prepare( $sql ) or return (-1, "Prep:Select senders");
	$sth->execute() or return (-1, "Select senders");
	while ( my @row = $sth->fetchrow_array ) {
	    push @senders, @row;
	}
	@senders = sort @senders;

	# get tests
	my %tests;
	$sql = "SELECT test_name from tests";
	$sth = $dbh->prepare( $sql ) || die "Prep:Select tests";
	$sth->execute() || die "Select tests";
	while ( my @row = $sth->fetchrow_array ) {
		my $tname = $row[0];
		$tests{$tname} = 1;
	}

	my @tests = ();
	foreach my $sender ( @senders ) {
		foreach my $receiver ( @receivers ) {
			my $tname = $mesh."_".$receiver."_".$sender;
			next if ($ignore_loopback and ($sender eq $receiver));
			next if ($tests_to_ignore{$tname});

			push @tests, $tname;
		}
	}

        my %all_results = ();
        my %individual_results = ();

        foreach my $test_name ( @tests ) {
                my %owpvals      = ();
                my @alphas = [0.5,0.95];

                my $owdb = owdb_prep(
                                DBH         => $dbh,
                                RES         => $resolution,
                                TNAME       => $test_name,
                                FIRST       => owptstampi( $start_time_int ),
                                LAST        => owptstampi( $end_time_int ),
                                OWHASH      => \%owpvals,
                                BUCKETWIDTH => $bucket_width,
                                ALPHAS      => @alphas,
                                );

                unless ($owdb) {
                        return (-1, "Unable to init owp data request for test $test_name, resolution $resolution");
                }


                my %test_results  = ();
		if ($test_name =~ /([^_]*)_([^_]*)_([^_]*)/) {
			$test_results{MESH} = $1;
			$test_results{SENDER} = $2;
			$test_results{RECEIVER} = $3;
		}

                $test_results{SENT} = 0;
                $test_results{LOST} = 0;
                $test_results{ERR} = 0;
                $test_results{DUPS} = 0;
                $test_results{FLAGGED} = 0;
                $test_results{JITTER} = 0;
                $test_results{HISTOGRAM} = ();

                while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
                        my %yvals = ();

                        $test_results{LOST} += $owpvals{LOST};

                        if ($owpvals{MAX}) {
                            $test_results{MAX} = $owpvals{MAX} if (not $test_results{MAX} or $test_results{MAX} < $owpvals{MAX});
                        }
                        if ($owpvals{MIN}) {
                            $test_results{MIN} = $owpvals{MIN} if (not $test_results{MIN} or $test_results{MIN} > $owpvals{MIN});
                        }

                        if ($owpvals{MAX} and $owpvals{MIN}) {
                                $test_results{JITTER} = $owpvals{MAX} - $owpvals{MIN} if (not $test_results{JITTER} or $test_results{JITTER} < ($owpvals{MAX} - $owpvals{MIN}));
                        }

                        foreach my $key ( keys %{ $owpvals{HISTOGRAM} } ) {
                                my $hist_value = $owpvals{HISTOGRAM}->{$key};

                                unless ($test_results{JITTER}) {
                                        $test_results{JITTER} = $key * $bucket_width if (not $test_results{JITTER} or $test_results{JITTER} < ($key * $bucket_width));
                                }

                                $test_results{SENT} += $hist_value;

                                if ( $loss_threshold and $key * $bucket_width > $loss_threshold ) {
                                        $test_results{LOST} += $hist_value;
                                        next;
                                }

                                if ( $flag_point and $key * $bucket_width > $flag_point ) {
                                        $test_results{FLAGGED} += $hist_value;
                                }

                                $test_results{HISTOGRAM}->{$key} = $hist_value;
                        }
                }

                $all_results{LOST} += $test_results{LOST};
                $all_results{SENT} += $test_results{SENT};
                $all_results{ERR} += $test_results{ERR};
                $all_results{DUPS} += $test_results{DUPS};
                $all_results{FLAGGED} += $test_results{FLAGGED};
                $all_results{JITTER} = $test_results{JITTER} if (not $all_results{JITTER} or $all_results{JITTER} < $test_results{JITTER});

                if ($test_results{MAX}) {
                        $all_results{MAX} = $test_results{MAX} if (not $all_results{MAX} or $all_results{MAX} < $test_results{MAX});
                }

                if ($test_results{MIN}) {
                        $all_results{MIN} = $test_results{MIN} if (not $all_results{MIN} or $all_results{MIN} > $test_results{MIN});
                }

                foreach my $key ( keys %{ $test_results{HISTOGRAM} } ) {
                        my $time = $key * $bucket_width;

                        unless ($all_results{HISTOGRAM}->{$key}) {
                                $all_results{HISTOGRAM}->{$key} = 0;
                        }

                        $all_results{HISTOGRAM}->{$key} += $test_results{HISTOGRAM}->{$key};
                }

                $individual_results{$test_name} = \%test_results;
        }

        return (0, \%all_results, \%individual_results);
}

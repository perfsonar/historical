#
#      $Id: owdb.pm 2751 2009-04-13 13:32:53Z aaron $
#
#########################################################################
#									#
#			   Copyright (C)  2003				#
#	     			Internet2				#
#			   All Rights Reserved				#
#									#
#########################################################################
#
#	File:		owdb.pm
#
#	Author:		Jeff Boote
#			Internet2
#
#	Date:		Tue Aug  5 12:40:08 UTC 2003
#
#	Description:	
#
#	Usage:
#
#	Environment:
#
#	Files:
#
#	Options:
package owdb;
require 5.005;
require Exporter;
use strict;
use FindBin;
use POSIX;
use Fcntl qw(:flock);
use FileHandle;
use Data::Dumper;
use OWP;
use OWP::Utils;
use OWP::Helper;
use vars qw(@ISA @EXPORT $VERSION);
#use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
use File::Basename;
use Params::Validate qw(:all);
use Digest::MD5;

@ISA = qw(Exporter);
@EXPORT = qw(owdb_prep owdb_fetch owdb_retrieve_mesh_summary owdb_lookup_nodes);

$OWP::REVISION = '$Id: owdb.pm 2751 2009-04-13 13:32:53Z aaron $';
$VERSION = '1.0';

#
# owdb_prep: this routine is used to initialize the database connection
# for fetching owamp data.
# Pass in a ref to a hash, and it will be filled with values for:
#	START
#	END
#	SENT
#	LOST
#	DUPS
#	MIN
#	MAX
#	ERR
#	ALPHA_%08.6f (with the %08.6f replaced ala sprintf for every alpha
#			value passed in using the 'ALPHAS' arg.)
#	ALPHAS (A sub hash with the keys set from the original alphas passed
#		in and the values set to the delay of that "alpha".)
sub owdb_prep{
	my %args = validate(@_, {
					DBH => 1,
					RECV_NAME => 1,
					SEND_NAME => 1,
					FIRST => 1,
					LAST => 1,
					OWHASH => 1,
					TESTID => 0,
					ONLY_VALIDATED => 0,
					ALPHAS => 0,
				}
			);

	my(%owdbh);

	# save ref to callers hash - values are returned in this hash.
	$owdbh{'OWHASH'} = $args{'OWHASH'};

	my ($status, $res);

	($status, $res) = calculate_table_prefixes({ dbh => $args{'DBH'}, test_id => $args{TESTID}, recv_name => $args{RECV_NAME}, send_name => $args{SEND_NAME}, first => $args{FIRST}, last => $args{LAST} });
	if ($status != 0) {
		die("Problem calculating table prefixes: ".$res);
	}

	$owdbh{'PREFIXES'} = $res;

	my @alphas;
	for (ref $args{'ALPHAS'}){
		/^$/	and push @alphas, $args{'ALPHAS'},
				next;
		/ARRAY/	and @alphas = @{$args{'ALPHAS'}},
				next;
	}

	@{$owdbh{'ALPHAVALS'}} = sort @alphas if(@alphas);

	$owdbh{'TABLE_DONE'} = 1;
	$owdbh{'OSTART'} = 0;
	$owdbh{'OEND'} = 0;
	$owdbh{'RECV_NAME'} = $args{'RECV_NAME'};
	$owdbh{'SEND_NAME'} = $args{'SEND_NAME'};
	$owdbh{'TESTID'} = $args{'TESTID'};
	$owdbh{'ONLY_VALIDATED'} = $args{'ONLY_VALIDATED'};
	$owdbh{'DBH'} = $args{'DBH'};
	$owdbh{'FIRST'} = $args{'FIRST'};
	$owdbh{'LAST'} = $args{'LAST'};
	$owdbh{'ALPHAVALS'} = $args{'ALPHAS'}?$args{'ALPHAS'}:[];

	return \%owdbh;
}

sub calculate_table_prefixes {
# XXX: should calculate table prefixes to ignore unnecessary tables.
	my $args = validate(@_, {
				dbh     => 1,
				test_id => 0,
				recv_name => 0,
				send_name => 0,
				first   => 1,
				last    => 1,
			});

	my $first = $args->{first};
	my $last = $args->{last};

	my $diff = 12*60*60;

	my ($status, $res) = get_valid_prefixes({ dbh => $args->{dbh} });

	if ($status != 0) {
		return ($status, $res);
	}

	my $valid_prefixes = $res;

	my $start = owptime2time(owpi2owp($first));
	my $end = owptime2time(owpi2owp($last));

	my $prefix = generate_prefix($start);
	my $end_prefix = generate_prefix($end);

	my @prefixes = ();

	while($prefix ne $end_prefix) {
		# unshift makes sure that "pop" is ordered correctly
		unshift @prefixes, $prefix if ($valid_prefixes->{$prefix});

		$start += $diff;

		$prefix = generate_prefix($start);
	}
	if ($valid_prefixes->{$end_prefix}) {
		push @prefixes, $end_prefix 
	}	

	return (0, \@prefixes);
}

sub get_valid_prefixes {
	my $args = validate(@_, {
			dbh     => 1,
			}
			);
	
	my $dbh = $args->{dbh};

	my $sql = "SELECT year, month, day FROM DATES";
	my $sth = $dbh->prepare($sql);
	unless ($sth) {
		return (-1, "Prep:Select DATES");
	}

	my $status = $sth->execute();
	unless ($sth) {
		return (-1, "Select owdb data $DBI::errstr");
	}

	my %prefixes = ();

	while (my $row = $sth->fetchrow_arrayref) {
		my ($year,$month,$day) = @$row;
		my $prefix = sprintf('%d%02d%02d', $year, $month, $day);
		$prefixes{$prefix} = 1;
	}
	$sth->finish;

	return (0, \%prefixes);
}

sub generate_prefix {
	my ($time) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);

	$year += 1900;
	$mon ++;

	my $prefix = sprintf('%d%02d%02d', $year, $mon, $mday);

	return $prefix;
}

sub owdb_lookup_node {
	my $args = validate(@_, {
			dbh          => 1,
			table_prefix => 1,
			node_name    => 1,
			}
			);

	my $dbh          = $args->{dbh};
	my $table_prefix = $args->{table_prefix};
	my $node_name    = $args->{node_name};

	my $sql = "select node_id from ".$table_prefix."_NODES where node_name=?";
	my $sth = $dbh->prepare($sql);
	unless ($sth) {
		return (-1, "Prep:Select NODES");
	}

	my $status = $sth->execute($node_name);
	unless ($sth) {
		return (-1, "Select owdb data $DBI::errstr");
	}

	my $node_id;
	while (my $row = $sth->fetchrow_arrayref) {
		$node_id = $row->[0];
	}
	$sth->finish;

	return (0, $node_id);
}

sub owdb_lookup_nodes {
	my $args = validate(@_, {
			dbh          => 1,
			first        => 1,
			last         => 1,
			}
			);

	my $dbh = $args->{dbh};
	my $first = $args->{first};
	my $last = $args->{last};

	my ($status, $res);

	($status, $res) = calculate_table_prefixes({ dbh => $dbh, first => $first, last => $last });
	if ($status != 0) {
		return (-1, "Problem calculating table prefixes: ".$res);
	}

	my $prefixes = $res;

	my %nodes = ();
	foreach my $prefix (@{ $prefixes }) {
  		#| node_id | node_name | longname | host | addr | first | last |

		my $sql = "select node_name, longname, host, addr from ".$prefix."_NODES";

		my $sth = $dbh->prepare($sql);
		unless ($sth) {
			return (-1, "Prep:Select NODES");
		}

		my $status = $sth->execute();
		unless ($sth) {
			return (-1, "Select owdb data $DBI::errstr");
		}

		my $node_id;
		while (my $row = $sth->fetchrow_arrayref) {
			my ($node_name, $longname, $host, $addr) = @$row;
			$nodes{$node_name} = {
				name => $node_name,
				longname => $longname,
				host => $host,
				addr => $addr,
			};
		}
		$sth->finish;
	}

	return (0, \%nodes);
}

sub owdb_fetch{
	my(%args) = @_;
	my(@argnames) = qw(OWDBH);
	%args = owpverify_args(\@argnames,\@argnames,%args);
	scalar %args || die "Invalid args passed to owdb_fetch";

	my $owdbh = $args{'OWDBH'};

	my $test_id = $owdbh->{'TESTID'};
	my $recv_name = $owdbh->{'RECV_NAME'};
	my $send_name = $owdbh->{'SEND_NAME'};
	my $first_time = $owdbh->{'FIRST'};
	my $last_time = $owdbh->{'LAST'};

RETRY:
	if ($owdbh->{'TABLE_DONE'}) {
		my @prefixes = @{ $owdbh->{'PREFIXES'} };
		my $next_prefix = pop @prefixes;

		$owdbh->{'PREFIXES'} = \@prefixes;

		# if there are no more tables to try, return 0
		return 0 unless ($next_prefix);

		my ($status, $res);

		($status, $res) = owdb_lookup_node({ dbh => $owdbh->{'DBH'}, node_name => $recv_name, table_prefix => $next_prefix });
		if ($status != 0) {
			goto RETRY;
		}

		my $recv_id = $res;

		($status, $res) = owdb_lookup_node({ dbh => $owdbh->{'DBH'}, node_name => $send_name, table_prefix => $next_prefix });
		if ($status != 0) {
			goto RETRY;
		}

		my $send_id = $res;

		my $where_clause = "WHERE a.recv_id=? AND a.send_id=? AND a.ei>? AND a.si<?";
		$where_clause .= " AND a.valid!=0" if ($owdbh->{'ONLY_VALIDATED'});
		$where_clause .= " AND a.tspec_id=?" if ($test_id);

		my $sql = "SELECT a.tspec_id,a.recv_id,a.send_id,a.si,a.stimestamp,a.etimestamp,a.sent,a.lost,a.dups, a.min,a.max,a.maxerr,b.i,b.n,b.basei,b.bucket_width
		FROM ".$next_prefix."_DATA AS a
		JOIN ".$next_prefix."_DELAY AS b
		ON a.si = b.si
		$where_clause
		ORDER BY a.si,b.i";

		$owdbh->{'STH'} = $owdbh->{'DBH'}->prepare($sql) || die "Prep:Select owdb data";
		if ($test_id) {
			$owdbh->{'STH'}->execute($recv_id, $send_id, $first_time, $last_time, $test_id) || die "Select owdb data $DBI::errstr";
		} else {
			$owdbh->{'STH'}->execute($recv_id, $send_id, $first_time, $last_time) || die "Select owdb data $DBI::errstr";
		}

		my @vrefs = \(
			$owdbh->{'TEST_ID'},
			$owdbh->{'RECV_ID'},
			$owdbh->{'SEND_ID'},
			$owdbh->{'FIRST'},
			$owdbh->{'START'},
			$owdbh->{'END'},
			$owdbh->{'SENT'},
			$owdbh->{'LOST'},
			$owdbh->{'DUPS'},
			$owdbh->{'MIN'},
			$owdbh->{'MAX'},
			$owdbh->{'MAXERR'},
			$owdbh->{'Bi'},
			$owdbh->{'Bn'},
			$owdbh->{'Bbasei'},
			$owdbh->{'Bwidth'},
			);

		$owdbh->{'STH'}->bind_columns(@vrefs);
	}

	$owdbh->{'TABLE_DONE'} = 0;

	my $owhash = $owdbh->{'OWHASH'};
	my $nrecs = 0;
	my $session_done = 0;

	# increment nrecs to account for last record
	# from "previous" session.
	$nrecs++ if($owdbh->{'OSTART'});

	while(not $session_done){
		unless ($owdbh->{'STH'}->fetch){
			#print "In owdb_fetch($recv_name, $send_name, $first_time, $last_time): fetch empty\n";
			$owdbh->{'START'} = 0;
			$owdbh->{'TABLE_DONE'} = 1;
			$session_done = 1;

			# skip to the next table if we don't have any records
			goto RETRY unless ($owdbh->{'OSTART'});
		}

		#print "In owdb_fetch($recv_name, $send_name, $first_time, $last_time): fetch not empty\n";

		if($owdbh->{'START'} ne $owdbh->{'OSTART'}){
			# new owamp session - output current values
			if($owdbh->{'OSTART'}){
				$owhash->{'TEST_ID'} = $owdbh->{'OTEST_ID'};
				$owhash->{'RECV_ID'} = $owdbh->{'ORECV_ID'};
				$owhash->{'SEND_ID'} = $owdbh->{'OSEND_ID'};
				$owhash->{'START'} = $owdbh->{'OSTART'};
				$owhash->{'END'} = $owdbh->{'OEND'};
				$owhash->{'SENT'} = $owdbh->{'OSENT'};
				$owhash->{'LOST'} = $owdbh->{'OLOST'};
				$owhash->{'DUPS'} = $owdbh->{'ODUPS'};
				$owhash->{'ERR'} = $owdbh->{'OERR'};
				$owhash->{'MIN'} = $owdbh->{'OMIN'};
				$owhash->{'MAX'} = $owdbh->{'OMAX'};
				$owhash->{'BASEI'} = $owdbh->{'OBASEI'};
				$owhash->{'BUCKETWIDTH'} = $owdbh->{'OBUCKETWIDTH'};
				$owhash->{'HISTOGRAM'} = $owdbh->{'HISTOGRAM'};
				my $avref = $owdbh->{'ALPHAVALS'};
				my $adref = $owdbh->{'ALPHADELAYS'};
				my $num_alphas = @{$avref};
				my $i;
				delete $owhash->{'ALPHAS'};
				for($i=0;$i< $num_alphas;$i++){
					my $nstr = sprintf("%08.6f", ${$avref}[$i]);
					$owhash->{"ALPHA_$nstr"} = ${$adref}[$i];
					${$owhash->{'ALPHAS'}}{${$avref}[$i]} = ${$adref}[$i];
				}

				$session_done = 1;
			}

			# reset buckets
			$owdbh->{'ALPHADELAYS'} = [];
			$owdbh->{'ALPHAINDEX'} = 0;
			$owdbh->{'ALPHASUM'} = 0;
			delete $owdbh->{'HISTOGRAM'};
		}

		$nrecs++;

		# This doesn't need to get run repeatedly.
		$owdbh->{'OTEST_ID'} = $owdbh->{'TEST_ID'};
		$owdbh->{'ORECV_ID'} = $owdbh->{'RECV_ID'};
		$owdbh->{'OSEND_ID'} = $owdbh->{'SEND_ID'};
		$owdbh->{'OSTART'} = new Math::BigInt($owdbh->{'START'});
		$owdbh->{'OEND'} = new Math::BigInt($owdbh->{'END'});
		$owdbh->{'OSENT'} = $owdbh->{'SENT'};
		$owdbh->{'OLOST'} = $owdbh->{'LOST'};
		$owdbh->{'ODUPS'} = $owdbh->{'DUPS'};
		$owdbh->{'OERR'} = $owdbh->{'ERR'};
		$owdbh->{'OMIN'} = $owdbh->{'MIN'};
		$owdbh->{'OMAX'} = $owdbh->{'MAX'};
		$owdbh->{'OBASEI'} = $owdbh->{'Bbasei'};
		$owdbh->{'OBUCKETWIDTH'} = $owdbh->{'Bwidth'};

		my $sum = ($owdbh->{'ALPHASUM'} += $owdbh->{'Bn'});
		my $index = $owdbh->{'ALPHAINDEX'};
		my $avref = $owdbh->{'ALPHAVALS'};
		my $adref = $owdbh->{'ALPHADELAYS'};
		my $sent = $owdbh->{'OSENT'};
		my $num_alphas = @{$avref};
		my $href = $owdbh->{'HISTOGRAM'};
		$owdbh->{'HISTOGRAM'}{$owdbh->{'Bi'}} = $owdbh->{'Bn'};
		while(($index < $num_alphas) && ($sum >= ${$avref}[$index]*$sent)) {
			${$adref}[$index] = $owdbh->{'Bi'} * $owdbh->{'Bwidth'};
			$index++
		}
		$owdbh->{'ALPHAINDEX'} = $index;
	}

	return $nrecs;
}

=head2 owdb_retrieve_mesh_summary

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
    senders          => optional, a pointer to an array to specify only tests where these nodes are the sender.
    receivers        => optional, a pointer to an array to specify only tests where these nodes are the receiver.
    senders_to_ignore => optional, a pointer to an array to specify only tests where these nodes are NOT the sender.
    receivers_to_ignore => optional, a pointer to an array to specify only tests where these nodes are NOT the receiver.

The return value will be an array with (-1, $error_msg) in the case of an
error, and (0, \%mesh_summary, \%test_summaries). The test summaries is a hash
keyed on the test name with a value of a hash containing the mesh name, the
sender and receiver, the number of packets sent, lost, errored, duplicated,
flagged, the maximum delay seen, the minimum delay seen, the maximum jitter
seen and a histogram of the packet delays. The mesh summary contains the
packets sent, the packets lost, packets errored, packets duplicated, packets
flagged, the maximum jitter seen, the maximum delay seen and the minimum delay
seen.

=cut
sub owdb_retrieve_mesh_summary {
        my $parameters = validate( @_,
                        {
                        db_handle       => 1,		# the database handle
                        mesh            => 1,		# the mesh name
                        bucket_width    => 1,		# the mesh's bucket width
                        resolution      => 1,		# the desired resolution
                        flag_points      => 0,		# the flag point in seconds
                        loss_threshold  => 0,		# the loss threshold in seconds
                        start_time      => 1,		# a unix timestamp of the start
                        end_time        => 1,		# a unix timestamp of the end
                        ignore_loopback => 0,		# set to 1 to ignore loopback tests
                        paths_to_ignore => 0,		# an optional pointer to an array of hash elements containing 'receiver' and 'sender' keys whose values are the node names. If either is undefined, it will ignore all tests.
                        senders          => 0,		# an optional array to specify only tests where these nodes are the sender.
                        receivers        => 0,		# an optional array to specify only tests where these nodes are the receiver.
                        senders_to_ignore => 0,		# an optional array to specify only tests where these nodes are NOT the sender.
                        receivers_to_ignore => 0,	# an optional array to specify only tests where these nodes are NOT the receiver.
                        rolling_loss_packets => 0,	# an optional value to tell the function to calculate a rolling loss rate, based on the largest loss rate that is seen every "value" packets.
                        }
                        );

        my $dbh = $parameters->{db_handle};

        my $mesh = $parameters->{mesh};

        my $bucket_width = $parameters->{bucket_width};
        my $resolution = $parameters->{resolution};

        my $flag_points   = $parameters->{flag_points};
	my @flag_points = ();
	if ($flag_points) {
		if (ref($flag_points) eq "ARRAY") {
			@flag_points = @$flag_points;
		} else {
			push @flag_points, $flag_points;
		}
	}

	my $rolling_loss_packets = $parameters->{rolling_loss_packets};

        my $loss_threshold =  $parameters->{loss_threshold};

        my $start_time_int = time2owptime( $parameters->{start_time} );
        my $end_time_int   = time2owptime( $parameters->{end_time} );

	my $ignore_loopback = $parameters->{ignore_loopback};
	$ignore_loopback = 0 unless (defined $ignore_loopback);

	my %tests_to_ignore = ();
	my %receiver_nodes_to_ignore = ();
	my %sender_nodes_to_ignore = ();
	if ($parameters->{paths_to_ignore}) {
		foreach my $path (@{ $parameters->{paths_to_ignore} }) {
			if ($path->{receiver} and $path->{sender}) {
				my $tname = $mesh."_".$path->{receiver}."_".$path->{sender};
				$tests_to_ignore{$tname} = 1;
			} elsif ($path->{receiver}) {
				$receiver_nodes_to_ignore{$path->{receiver}} = 1;
			} elsif ($path->{sender}) {
				$sender_nodes_to_ignore{$path->{sender}} = 1;
			}
		}
	}

	my %receiver_nodes_to_display = ();
	my %sender_nodes_to_display = ();

	if ($parameters->{senders}) {
		foreach my $sender (@{ $parameters->{senders} }) {
			$sender_nodes_to_display{$sender} = 1;
		}
	}

	if ($parameters->{senders_to_ignore}) {
		foreach my $sender (@{ $parameters->{senders_to_ignore} }) {
			$sender_nodes_to_ignore{$sender} = 1;
		}
	}

	if ($parameters->{receivers}) {
		foreach my $receiver (@{ $parameters->{receivers} }) {
			$receiver_nodes_to_display{$receiver} = 1;
		}
	}

	if ($parameters->{receivers_to_ignore}) {
		foreach my $receiver (@{ $parameters->{receivers_to_ignore} }) {
			$receiver_nodes_to_ignore{$receiver} = 1;
		}
	}


	my ($sql, $sth);

	# get receivers
	my @receivers;
	$sql = "SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.recv_id";
	$sth = $dbh->prepare( $sql ) or return (-1, "Prep:Select receivers");
	$sth->execute() or return (-1, "Select receivers");
	while ( my @row = $sth->fetchrow_array ) {
	    next if ($receiver_nodes_to_ignore{$row[0]});
	    next unless (scalar(keys %receiver_nodes_to_display) == 0 or $receiver_nodes_to_display{$row[0]});
	    push @receivers, @row;
	}
	@receivers = sort @receivers;

	# get senders
	my @senders;
	$sql = "SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.send_id";
	$sth = $dbh->prepare( $sql ) or return (-1, "Prep:Select senders");
	$sth->execute() or return (-1, "Select senders");
	while ( my @row = $sth->fetchrow_array ) {
	    next if ($sender_nodes_to_ignore{$row[0]});
	    next unless (scalar(keys %sender_nodes_to_display) == 0 or $sender_nodes_to_display{$row[0]});
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

	my %senders = ();
	my %receivers = ();

	$all_results{SENT} = 0;
	$all_results{LOST} = 0;
	$all_results{ERR} = 0;
	$all_results{DUPS} = 0;
	$all_results{FLAGGED} = ();
	foreach my $flag_point (@flag_points) {
		$all_results{FLAGGED}->{$flag_point} = 0;
	}
	$all_results{JITTER} = 0;
	$all_results{HISTOGRAM} = ();
	$all_results{HIGHEST_LOSSRATE} = 0;
	$all_results{START} = undef;
	$all_results{END} = undef;

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
			$test_results{RECEIVER} = $2;
			$test_results{SENDER} = $3;
			$senders{$3} = 1;
			$receivers{$2} = 1;
		}

                $test_results{SENT} = 0;
                $test_results{LOST} = 0;
                $test_results{ERR} = 0;
                $test_results{DUPS} = 0;
		foreach my $flag_point (@flag_points) {
			$test_results{FLAGGED}->{$flag_point} = 0;
		}
                $test_results{JITTER} = 0;
                $test_results{HISTOGRAM} = ();
                $test_results{HIGHEST_LOSSRATE} = 0;
                $test_results{ROLLING_LOSSRATE} = 0;
                $test_results{START} = undef;
                $test_results{END} = undef;

		my $num_rolling_sent_packets = 0;
		my $num_rolling_lost_packets = 0;
		my @previous_sent = ();
		my @previous_lost = ();

                while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
                        my %yvals = ();

			my $curr_start = owptime2exacttime( $owpvals{'START'} );
			my $curr_end = owptime2exacttime( $owpvals{'END'} );

                        $test_results{LOST} += $owpvals{LOST};
			$test_results{START} = $curr_start if (not $test_results{START} or $curr_start < $test_results{START});
			$test_results{END} = $curr_end if (not $test_results{END} or $curr_end > $test_results{END});

                        my $loss_rate = 0;

			if ($owpvals{LOST} and $owpvals{SENT}) {
				$loss_rate = $owpvals{LOST}/$owpvals{SENT};
			}

			$test_results{HIGHEST_LOSSRATE} = $loss_rate if (not $test_results{HIGHEST_LOSSRATE} or $test_results{HIGHEST_LOSSRATE} < $loss_rate);

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

				foreach my $flag_point (@flag_points) {
	                                if ( $flag_point and $key * $bucket_width > $flag_point ) {
	                                        $test_results{FLAGGED}->{$flag_point} += $hist_value;
	                                }
				}

                                $test_results{HISTOGRAM}->{$key * $bucket_width} = $hist_value;
                        }

			if ($rolling_loss_packets and $test_results{SENT}) {
				$num_rolling_sent_packets += $owpvals{SENT};
				$num_rolling_lost_packets += $owpvals{LOST};
				push @previous_sent, $owpvals{SENT};
				push @previous_lost, $owpvals{LOST};

#				print "Adding $owpvals{LOST}/$owpvals{SENT} to the queue: $num_rolling_lost_packets/$num_rolling_sent_packets\n";

				if ($num_rolling_sent_packets >= $rolling_loss_packets) {
					# we've hit our threshold, check
					my $rolling_loss = ($num_rolling_lost_packets/$num_rolling_sent_packets);
					$test_results{ROLLING_LOSSRATE} = $rolling_loss if (not $test_results{ROLLING_LOSSRATE} or $test_results{ROLLING_LOSSRATE} < $rolling_loss);
					my $a = shift @previous_sent;
					$num_rolling_sent_packets -= $a;
					my $b = shift @previous_lost;
					$num_rolling_lost_packets -= $b;
#					print "Removing $b/$a from the queue\n";
				}
			}
                }

                $all_results{LOST} += $test_results{LOST};
                $all_results{SENT} += $test_results{SENT};
                $all_results{ERR} += $test_results{ERR};
                $all_results{DUPS} += $test_results{DUPS};

		foreach my $flag_point (@flag_points) {
			$all_results{FLAGGED}->{$flag_point} = 0 unless ($all_results{FLAGGED}->{$flag_point});
			$all_results{FLAGGED}->{$flag_point} += $test_results{FLAGGED}->{$flag_point} if ($test_results{FLAGGED}->{$flag_point});
		}

                $all_results{JITTER} = $test_results{JITTER} if (not $all_results{JITTER} or $all_results{JITTER} < $test_results{JITTER});
		$all_results{HIGHEST_LOSSRATE} = $test_results{HIGHEST_LOSSRATE} if (not $all_results{HIGHEST_LOSSRATE} or $all_results{HIGHEST_LOSSRATE} < $test_results{HIGHEST_LOSSRATE});
		$all_results{ROLLING_LOSSRATE} = $test_results{ROLLING_LOSSRATE} if (not $all_results{ROLLING_LOSSRATE} or $all_results{ROLLING_LOSSRATE} < $test_results{ROLLING_LOSSRATE});
		if ($test_results{START}) {
			$all_results{START} = $test_results{START} if (not $all_results{START} or $all_results{START} > $test_results{START});
		}
		if ($test_results{END}) {
			$all_results{END} = $test_results{END} if (not $all_results{END} or $all_results{END} < $test_results{END});
		}

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

	my @mesh_senders = sort keys %senders;
	my @mesh_receivers = sort keys %receivers;

	$all_results{MESH} = $mesh;
	$all_results{SENDERS} = \@mesh_senders;
	$all_results{RECEIVERS} = \@mesh_receivers;


        return (0, \%all_results, \%individual_results);
}

sub create_bwctl_testspec_digest {
        my $args = validate( @_,
                        {
                        description      => 0,
                        test_duration    => 0,
                        buffer_len       => 0,
                        window_size      => 0,
                        tos              => 0,
                        parallel_streams => 0,
                        tcp              => 0,
                        udp              => 0,
                        udp_bandwidth    => 0,
			}
			);
 
    my $md5 = Digest::MD5->new;
    my $key;

    # compute an MD5 hash for this testspec
    foreach $key ( qw(description test_duration buffer_len window_size tos parallel_streams tcp udp udp_bandwidth) ) {
        if ( exists $args->{$key} ) {
            $md5->add( $key );
            $md5->add( $args->{$key} );
        }
    }

    my $hexdigest = $md5->hexdigest;
    my $digest = hex( substr( $hexdigest, -8, 8 ) );

    return $digest;
}

sub create_owamp_testspec_digest {
        my $args = validate( @_,
                        {
			session_packet_count => 0,
			sample_packet_count => 0,
			interval => 0,
			dscp => 0,
			loss_timeout => 0,
			packet_padding => 0,
			bucket_width => 0,
			}
			);
 
    my $md5 = Digest::MD5->new;
    my $key;

    # compute an MD5 hash for this testspec
    foreach $key ( qw(session_packet_count sample_packet_count interval dscp loss_timeout packet_padding bucket_width) ) {
        if ( exists $args->{$key} ) {
            $md5->add( $key );
            $md5->add( $args->{$key} );
        }
    }

    my $hexdigest = $md5->hexdigest;
    my $digest = hex( substr( $hexdigest, -8, 8 ) );

    return $digest;
}

1;


#
#      $Id: bwdb.pm 2751 2009-04-13 13:32:53Z aaron $
#
#########################################################################
#									#
#			   Copyright (C)  2003				#
#	     			Internet2				#
#			   All Rights Reserved				#
#									#
#########################################################################
#
#	File:		bwdb.pm
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
package bwdb;
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
@EXPORT = qw(bwdb_prep bwdb_fetch bwdb_lookup_nodes);

$OWP::REVISION = '$Id: bwdb.pm 2751 2009-04-13 13:32:53Z aaron $';
$VERSION = '1.0';

#
# bwdb_prep: this routine is used to initialize the database connection
# for fetching bwctl data.
#
sub bwdb_prep{
	my %args = validate(@_, {
					DBH => 1,
					RECV_NAME => 1,
					SEND_NAME => 1,
					RECV_ADDR => 1,
					SEND_ADDR => 1,
					FIRST => 1,
					LAST => 1,
					BWHASH => 1,
					TESTID => 0,
				}
			);

	my(%bwdbh);

	# save ref to callers hash - values are returned in this hash.
	$bwdbh{'BWHASH'} = $args{'BWHASH'};

	my ($status, $res);

	($status, $res) = calculate_table_prefixes({ dbh => $args{'DBH'}, test_id => $args{TESTID}, recv_name => $args{RECV_NAME}, send_name => $args{SEND_NAME}, first => $args{FIRST}, last => $args{LAST} });
	if ($status != 0) {
		die("Problem calculating table prefixes: ".$res);
	}

	$bwdbh{'PREFIXES'} = $res;

	$bwdbh{'TABLE_DONE'} = 1;

	$bwdbh{'RECV_NAME'} = $args{'RECV_NAME'};
	$bwdbh{'SEND_NAME'} = $args{'SEND_NAME'};
	$bwdbh{'RECV_ADDR'} = $args{'RECV_ADDR'};
	$bwdbh{'SEND_ADDR'} = $args{'SEND_ADDR'};
	$bwdbh{'TESTID'} = $args{'TESTID'};
	$bwdbh{'DBH'} = $args{'DBH'};
	$bwdbh{'FIRST'} = $args{'FIRST'};
	$bwdbh{'LAST'} = $args{'LAST'};

	return \%bwdbh;
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

	my $sql = "SELECT year, month FROM DATES";
	my $sth = $dbh->prepare($sql);
	unless ($sth) {
		return (-1, "Prep:Select DATES");
	}

	my $status = $sth->execute();
	unless ($sth) {
		return (-1, "Select bwdb data $DBI::errstr");
	}

	my %prefixes = ();

	while (my $row = $sth->fetchrow_arrayref) {
		my ($year,$month) = @$row;
		my $prefix = sprintf('%d%02d', $year, $month);
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

	my $prefix = sprintf('%d%02d', $year, $mon );

	return $prefix;
}

# +------------+-----------+-----------------------------+-----------------+------------+------------+
# | node_id    | node_name | longname                    | addr            | first      | last       |
# +------------+-----------+-----------------------------+-----------------+------------+------------+
# | 3757411845 | SCINET1G  | SCinet 1G BWCTL Host        | 140.221.250.250 | 1257167823 | 1257273233 | 

sub bwdb_lookup_node {
	my $args = validate(@_, {
			dbh          => 1,
			table_prefix => 1,
			node_name    => 1,
			node_address => 0,
			}
			);

	my $dbh          = $args->{dbh};
	my $table_prefix = $args->{table_prefix};
	my $node_name    = $args->{node_name};
	my $node_address = $args->{node_address};

	my $sql = "select node_id from ".$table_prefix."_NODES where node_name=?";
	$sql .= " and addr=?" if ($node_address);

	print STDERR "Node: $node_name<br>\n";
	print STDERR "Address: $node_address<br>\n";
	print STDERR "SQL: $sql<br>\n";

	my $sth = $dbh->prepare($sql);
	unless ($sth) {
		return (-1, "Prep:Select NODES");
	}

	my $status;
	if ($node_address) {
		$status = $sth->execute($node_name, $node_address);
	} else {
		$status = $sth->execute($node_name);
	}

	unless ($sth) {
		return (-1, "Select bwdb data $DBI::errstr");
	}

	my @node_ids;
	while (my $row = $sth->fetchrow_arrayref) {
		push @node_ids, $row->[0];
	}
	$sth->finish;

	print STDERR "Returning: ".join(',', @node_ids)."<br>";

	return (0, \@node_ids);
}

sub bwdb_lookup_nodes {
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

		# +------------+-----------+-----------------------------+-----------------+------------+------------+
		# | node_id    | node_name | longname                    | addr            | first      | last       |
		# +------------+-----------+-----------------------------+-----------------+------------+------------+
		# | 3757411845 | SCINET1G  | SCinet 1G BWCTL Host        | 140.221.250.250 | 1257167823 | 1257273233 | 

		my $sql = "select node_name, longname, addr from ".$prefix."_NODES";

		my $sth = $dbh->prepare($sql);
		unless ($sth) {
			return (-1, "Prep:Select NODES");
		}

		my $status = $sth->execute();
		unless ($sth) {
			return (-1, "Select bwdb data $DBI::errstr");
		}

		my $node_id;
		while (my $row = $sth->fetchrow_arrayref) {
			my ($node_name, $longname, $addr) = @$row;

			$nodes{$node_name} = [] unless ($nodes{$node_name});

			push @{ $nodes{$node_name} }, {
				name => $node_name,
				longname => $longname,
				addr => $addr,
			};
		}
		$sth->finish;
	}

	return (0, \%nodes);
}

sub bwdb_fetch{
	my(%args) = @_;
	my(@argnames) = qw(BWDBH);
	%args = owpverify_args(\@argnames,\@argnames,%args);
	scalar %args || die "Invalid args passed to bwdb_fetch";

	my $bwdbh = $args{'BWDBH'};

	my $test_id = $bwdbh->{'TESTID'};
	my $recv_name = $bwdbh->{'RECV_NAME'};
	my $recv_addr = $bwdbh->{'RECV_ADDR'};
	my $send_name = $bwdbh->{'SEND_NAME'};
	my $send_addr = $bwdbh->{'SEND_ADDR'};
	my $first_time = $bwdbh->{'FIRST'};
	my $last_time = $bwdbh->{'LAST'};

RETRY:
	if ($bwdbh->{'TABLE_DONE'}) {
		my @prefixes = @{ $bwdbh->{'PREFIXES'} };
		my $next_prefix = pop @prefixes;

		$bwdbh->{'PREFIXES'} = \@prefixes;

		# if there are no more tables to try, return 0
		return 0 unless ($next_prefix);

		my ($status, $res);

		($status, $res) = bwdb_lookup_node({ dbh => $bwdbh->{'DBH'}, node_name => $recv_name, node_address => $recv_addr, table_prefix => $next_prefix });
		if ($status != 0 or scalar(@$res) == 0) {
			print STDERR "Didn't find $recv_name\n";
			goto RETRY;
		}

		my $recv_ids = $res;

		($status, $res) = bwdb_lookup_node({ dbh => $bwdbh->{'DBH'}, node_name => $send_name, node_address => $send_addr, table_prefix => $next_prefix });
		if ($status != 0 or scalar(@$res) == 0) {
			print STDERR "Didn't find $send_name\n";
			goto RETRY;
		}

		my $send_ids = $res;

		#+------------+------------+------------+------------+----------------------+-------------+--------+------+------+
		#| send_id    | recv_id    | tspec_id   | ti         | timestamp            | throughput  | jitter | lost | sent |
		#+------------+------------+------------+------------+----------------------+-------------+--------+------+------+
		#| 1269445248 | 3757411845 | 1298869372 | 3466156623 | 14887029339161285357 | 9.36671e+08 |   NULL | NULL | NULL | 
		#+------------+------------+------------+------------+----------------------+-------------+--------+------+------+

		my $where_clause = 'WHERE ti>=? AND ti<=?';
		if ($recv_ids) {
			$where_clause .= " AND (";
			my $connector = "";
			foreach my $recv_id (@$recv_ids) {
				$where_clause .= $connector."recv_id=?";
				$connector = " OR ";
			}
			$where_clause .= ")";
		}

		if ($send_ids) {
			$where_clause .= " AND (";
			my $connector = "";
			foreach my $send_id (@$send_ids) {
				$where_clause .= $connector." send_id=?";
				$connector = " OR ";
			}
			$where_clause .= ")";
		}
		$where_clause .= " AND tspec_id=?" if ($test_id);

		my $sql = "SELECT tspec_id,recv_id,send_id,ti,throughput,jitter,lost,sent FROM ".$next_prefix."_DATA $where_clause ORDER BY ti";

		$bwdbh->{'STH'} = $bwdbh->{'DBH'}->prepare($sql) || die "Prep:Select bwdb data";

		my @args = ();
		push @args, $first_time;
		push @args, $last_time;
		push @args, @$recv_ids;
		push @args, @$send_ids;
		push @args, $test_id if ($test_id);

		use Data::Dumper;

		print STDERR "send: $send_name\n";
		print STDERR "recv: $recv_name\n";
		print STDERR "SQL: $sql\n";
		print STDERR "Args: ".join('|', @args)."\n";

		$bwdbh->{'STH'}->execute(@args) || die "Select bwdb data $DBI::errstr";

		my @vrefs = \(
			$bwdbh->{'TEST_ID'},
			$bwdbh->{'RECV_ID'},
			$bwdbh->{'SEND_ID'},
			$bwdbh->{'TIME'},
			$bwdbh->{'THROUGHPUT'},
			$bwdbh->{'JITTER'},
			$bwdbh->{'LOST'},
			$bwdbh->{'SENT'},
			);

		$bwdbh->{'STH'}->bind_columns(@vrefs);
	}

	$bwdbh->{'TABLE_DONE'} = 0;

	unless ($bwdbh->{'STH'}->fetch){
		$bwdbh->{'TABLE_DONE'} = 1;

		goto RETRY;
	}

	my $bwhash = $bwdbh->{'BWHASH'};

	$bwhash->{'TEST_ID'} = $bwdbh->{'TEST_ID'};
	$bwhash->{'RECV_ID'} = $bwdbh->{'RECV_ID'};
	$bwhash->{'SEND_ID'} = $bwdbh->{'SEND_ID'};
	$bwhash->{'TIME'} = $bwdbh->{'TIME'};
	$bwhash->{'THROUGHPUT'} = $bwdbh->{'THROUGHPUT'};
	$bwhash->{'JITTER'} = $bwdbh->{'JITTER'};
	$bwhash->{'LOST'} = $bwdbh->{'LOST'};
	$bwhash->{'SENT'} = $bwdbh->{'SENT'};

	return 1;
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


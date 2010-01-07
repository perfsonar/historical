#!/usr/bin/perl -w 

use strict;
use warnings;

=head1 NAME

owamp.cgi - CGI script to extract OWAMP measurements from a pSB database.  Each
entry in the matrix can be clicked to get a graph (provided by owampplot.cgi).  

=head1 DESCRIPTION

Read the OWAMP portion of the pSB database and plot the most recent entries.  

=cut

use CGI;
use CGI::Carp qw(fatalsToBrowser);
use HTML::Template;
use DBI;
use Data::Dumper;

# ###############################
#
# Make sure we get any URL arguments (e.g. we need the mesh name)
#

my $cgi = CGI->new();
print $cgi->header();
my $template = q{};

my $name;
if ( $cgi->param( 'name' ) ) {
    $name = $cgi->param( 'name' );
}
else {

    #    die "Mesh name not provided, aborting.  Set ?name=SOMENAME in the URL."
}

# ###############################
#
# OWP specific libraries and defaults
#

use lib "/opt/perfsonar_ps/perfsonarbuoy_ma/lib";

use OWP;
use OWP::Utils;

my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "/opt/perfsonar_ps/perfsonarbuoy_ma/etc",
        LIBDIR  => "/opt/perfsonar_ps/perfsonarbuoy_ma/lib",
    );
}

my $conf = new OWP::Conf( %amidefaults );

# ###############################
#
# Unroll the owmesh file, get anything we need from there (mesh defns + database info)
#

my $dbhost = $conf->must_get_val( ATTR => 'CentralDBHost' );
my $dbtype = $conf->must_get_val( ATTR => 'CentralDBType' );
my $dbname = $conf->must_get_val( ATTR => 'OWPCentralDBName' );
my $dbuser = $conf->must_get_val( ATTR => 'CGIDBUser' );
my $dbpass = $conf->get_val( ATTR      => 'CGIDBPass' );

my @measurement_sets = $conf->get_val( ATTR => 'MEASUREMENTSETLIST' );
my %temp = map { $_ => 1 } @measurement_sets;
die "Cannot find '" . $name . "' on this server, aborting.\n" unless exists $temp{$name};

my $group  = $conf->get_val( MEASUREMENTSET => $name,  ATTR => 'GROUP' );
my $g_type = $conf->get_val( GROUP          => $group, ATTR => 'GROUPTYPE' );
die "Measurement set '" . $name . "' is not a mesh (stored as a '" . $g_type . "'), aborting.\n" unless $g_type eq "MESH";

my $meas_desc = $conf->get_val( MEASUREMENTSET => $name, ATTR => 'DESCRIPTION' );
my $testspec  = $conf->get_val( MEASUREMENTSET => $name, ATTR => 'TESTSPEC' );
my $addrtype  = $conf->get_val( MEASUREMENTSET => $name, ATTR => 'ADDRTYPE' );

my @nodes      = $conf->get_val( GROUP => $group, ATTR => 'NODES' );
my $group_desc = $conf->get_val( GROUP => $group, ATTR => 'DESCRIPTION' );

my $test_description  = $conf->get_val( TESTSPEC => $testspec, ATTR => 'DESCRIPTION' );
my $test_tool         = $conf->get_val( TESTSPEC => $testspec, ATTR => 'TOOL' );
my $test_interval     = $conf->get_val( TESTSPEC => $testspec, ATTR => 'OWPINTERVAL' );
my $test_lossthresh   = $conf->get_val( TESTSPEC => $testspec, ATTR => 'OWPLOSSTHRESH' );
my $test_sessioncount = $conf->get_val( TESTSPEC => $testspec, ATTR => 'OWPSESSIONCOUNT' );
my $test_samplecount  = $conf->get_val( TESTSPEC => $testspec, ATTR => 'OWPSAMPLECOUNT' );
my $test_bucketwidth  = $conf->get_val( TESTSPEC => $testspec, ATTR => 'OWPBUCKETWIDTH' );

# ###############################
#
# Time information (e.g. we want to check for the most recent of the last 5 test results)
#

my $endTime = time;
my ( $e_sec, $e_min, $e_hour, $e_mday, $e_mon, $e_year ) = gmtime( $endTime );

my $startTime = $endTime - 600;
my ( $s_sec, $s_min, $s_hour, $s_mday, $s_mon, $s_year ) = gmtime( $startTime );

# ###############################
#
# Connect to the database, get the actual data
#

my $dbsource = $dbtype . ":" . $dbname . ":" . $dbhost;
my $dbh      = DBI->connect(
    $dbsource,
    $dbuser, $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
) || croak "Couldn't connect to database";

#
#  Sanity check the DB to be sure we have the proper date(s) stored
#
my $sql = "select * from DATES where year=" . ( $s_year + 1900 ) . " and month=" . ( $s_mon + 1 ) . " and day=" . $s_mday;
my $s_date_ref = $dbh->selectall_arrayref( $sql );

$sql = "select * from DATES where year=" . ( $e_year + 1900 ) . " and month=" . ( $e_mon + 1 ) . " and day=" . $e_mday;
my $e_date_ref = $dbh->selectall_arrayref( $sql );

unless ( exists $e_date_ref->[0] ) {
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][0];
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][1];
}

my $flag       = 1;
my @cursor     = ( $s_date_ref->[0][0], $s_date_ref->[0][1], $s_date_ref->[0][2] );
my @dates_list = ();
while ( $flag == 1 ) {
    push @dates_list, [ $cursor[0], sprintf( "%02d", $cursor[1] ), sprintf( "%02d", $cursor[2] ) ];
    $flag = 0 if $cursor[0] == $e_date_ref->[0][0] and $cursor[1] == $e_date_ref->[0][1] and $cursor[2] == $e_date_ref->[0][2];
    $cursor[2]++;

    if ( $cursor[1] == 4 or $cursor[1] == 6 or $cursor[1] == 9 or $cursor[1] == 11 ) {
        if ( $cursor[2] == 30 ) {
            $cursor[1]++;
            $cursor[2] = 1;
        }
    }
    elsif ( $cursor[1] == 1 or $cursor[1] == 3 or $cursor[1] == 5 or $cursor[1] == 7 or $cursor[1] == 8 or $cursor[1] == 10 or $cursor[1] == 12 ) {
        if ( $cursor[2] == 31 ) {
            $cursor[1]++;
            $cursor[2] = 1;
        }
    }
    elsif ( $cursor[1] == 2 ) {
        if ( 0 == ( $cursor[0] % 4 ) and 0 != ( $cursor[0] % 100 ) or 0 == ( $cursor[0] % 400 ) ) {
            if ( $cursor[2] == 29 ) {
                $cursor[1]++;
                $cursor[2] = 1;
            }
        }
        else {
            if ( $cursor[2] == 28 ) {
                $cursor[1]++;
                $cursor[2] = 1;
            }
        }
    }

    if ( $cursor[1] == 13 ) {
        $cursor[0]++;
        $cursor[1] = 1;
    }
}

my %res = ();
my %node_info;
if ( $#{$s_date_ref} == 0 or $#{$e_date_ref} == 0 ) {

    # do one select statement
    my $t_ref = q{};

    # first do the node info
    foreach my $node ( @nodes ) {
        $node_info{$node}{"LONGNAME"} = $conf->get_val( NODE => $node, ATTR => 'LONGNAME' );
        my $temp = $conf->get_val( NODE => $node, ATTR => 'ADDR', TYPE => $addrtype );
        $temp =~ s/:.*$//;

        $sql = q{};
        foreach my $d ( @dates_list ) {
            $sql .= " union " if $sql;
            $sql .= " select node_id,last from " . $d->[0] . $d->[1] . $d->[2] . "_NODES where node_name='" . $node . "' and addr like '%" . $node_info{$node}{"ADDRESS"} . "%'";
        }

        $t_ref = $dbh->selectall_arrayref( $sql );

        $node_info{$node}{"ID"}   = $t_ref->[0][0] if $t_ref->[0][0];
        $node_info{$node}{"LAST"} = $t_ref->[0][1] if $t_ref->[0][1];
    }

    # get the testspecid

    #    $sql = q{};
    #    foreach my $d ( @dates_list ) {
    #        $sql .= " union " if $sql;
    #        $sql .= " select tspec_id from ".$d->[0].$d->[1]."_TESTSPEC where description='".$name."'";
    #    }
    #    my $t_ref = $dbh->selectall_arrayref($sql);
    #    my $tspec_id = "(";
    #    my $counter = 0;
    #    foreach my $id ( @{ $t_ref } ) {
    #        $tspec_id .= " or " if $counter;
    #        $tspec_id .= "tspec_id ='" . $id->[0] . "'";
    #        $counter++;
    #    }
    #    $tspec_id .= ")";

    my $tspec_id = " ( tspec_id = '2855302762' ) ";

    foreach my $r ( @nodes ) {
        foreach my $s ( @nodes ) {

            $sql = q{};
            foreach my $d ( @dates_list ) {
                $sql .= " union " if $sql;
                $sql
                    .= " select max(etimestamp) from "
                    . $d->[0]
                    . $d->[1]
                    . $d->[2]
                    . "_DATA where "
                    . $tspec_id
                    . " and recv_id='"
                    . $node_info{$r}{"ID"}
                    . "' and send_id='"
                    . $node_info{$s}{"ID"}
                    . "' and etimestamp > "
                    . time2owptime( $startTime )
                    . " and etimestamp < "
                    . time2owptime( $endTime );
            }

            my $d_ref1 = $dbh->selectall_arrayref( $sql );

            $sql = q{};
            my $c1 = 0;
            foreach my $d ( @dates_list ) {
                $sql .= " union " if $sql;
                $sql .= " select * from " . $d->[0] . $d->[1] . $d->[2] . "_DATA where " . $tspec_id . " and recv_id='" . $node_info{$r}{"ID"} . "' and send_id='" . $node_info{$s}{"ID"} . "' and etimestamp=" . $d_ref1->[$c1][0] if $d_ref1->[$c1][0];
                $c1++;
            }

            my $d_ref = $dbh->selectall_arrayref( $sql );

            $res{$r}{$s}{"TIME"}   = $d_ref->[0][6]  if defined $d_ref->[0][6];
            $res{$r}{$s}{"MIN"}    = $d_ref->[0][9]  if defined $d_ref->[0][9];
            $res{$r}{$s}{"MAX"}    = $d_ref->[0][10] if defined $d_ref->[0][10];
            $res{$r}{$s}{"SENT"}   = $d_ref->[0][13] if defined $d_ref->[0][13];
            $res{$r}{$s}{"LOST"}   = $d_ref->[0][14] if defined $d_ref->[0][14];
            $res{$r}{$s}{"DUPS"}   = $d_ref->[0][15] if defined $d_ref->[0][15];
            $res{$r}{$s}{"MAXERR"} = $d_ref->[0][16] if defined $d_ref->[0][16];
        }
    }
}
else {

    # error - load junk into the template?
}

# ###############################
#
# Load the template, then display
#

my $meshName = $meas_desc;
my $sites    = $#nodes + 1;
my $type     = $test_tool;

my @header = ();
foreach my $site ( @nodes ) {
    push @header, { VAL => $node_info{$site}{"LONGNAME"} };
}

my @rec = ();
foreach my $r ( @nodes ) {
    my @send = ();
    foreach my $s ( @nodes ) {
        if ( exists $res{$r}{$s}{"TIME"} and $res{$r}{$s}{"TIME"} ) {
            my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime( owptime2time( $res{$r}{$s}{"TIME"} ) );
            my $timestring = ( $year + 1900 ) . "-" . sprintf( "%02d", ( $mon + 1 ) ) . "-" . sprintf( "%02d", $mday ) . " " . sprintf( "%02d", $hour ) . ":" . sprintf( "%02d", $min ) . ":" . sprintf( "%02d", $sec ) . "UTC";

            my $delay = $res{$r}{$s}{"MAX"} * 1000 if exists $res{$r}{$s}{"MAX"};
            my $jitter = ( $res{$r}{$s}{"MAX"} - $res{$r}{$s}{"MIN"} ) * 1000  if $res{$r}{$s}{"MAX"}         and $res{$r}{$s}{"MIN"};
            my $loss   = ( $res{$r}{$s}{"LOST"} / $res{$r}{$s}{"SENT"} ) * 100 if exists $res{$r}{$s}{"SENT"} and exists $res{$r}{$s}{"LOST"};

            my $colorchoice = "white";
            if ( $loss > 0 ) {
                $colorchoice = "red";
            }
            else {
                $colorchoice = "white";
            }

            my $value;
            if ( $loss == 100 ) {
                $value = "* / * / " . $loss;
            }
            else {
                if ( $loss == 0 ) {
                    $value = sprintf( "%.3f", $delay ) . " / " . sprintf( "%.3f", $jitter ) . " / " . $loss;
                }
                else {
                    $value = sprintf( "%.3f", $delay ) . " / " . sprintf( "%.3f", $jitter ) . " / " . sprintf( "%.2f", $loss );
                }
            }
            push @send, { VALUE => $value, TIME => $timestring, ALIVE => 1, R => $r, S =>, $s, COLOR => 1, COLORCHOICE => $colorchoice };
        }
        else {
            push @send, { VALUE => -1, TIME => -1, ALIVE => 0, COLOR => 0 };
        }

    }
    push @rec, { HEADER => $node_info{$r}{"LONGNAME"}, SEND => \@send };
}

$template = HTML::Template->new( filename => "etc/owamp.tmpl" );
$template->param(
    NAME   => $meshName,
    COLS   => $sites + 2,
    TYPE   => $type,
    HEADER => \@header,
    RECV   => \@rec
);

print $template->output;

__END__

=head1 SEE ALSO

L<CGI>, L<CGI::Carp>, L<HTML::Template>, L<DBI>, L<Data::Dumper>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut


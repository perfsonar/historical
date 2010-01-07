#!/usr/bin/perl -w
#
#      $Id: owamp_grid.cgi 707 2007-08-02 17:52:24Z boote $
#
#########################################################################
#                                    #
#               Copyright (C)  2006                #
#                     Internet2                #
#               All Rights Reserved                #
#                                    #
#########################################################################
#
#    File:        owamp_grid.cgi
#
#    Author:        Jeff Boote
#            Internet2
#
#    Date:        Tue Jul 11 11:18:15 MDT 2006
use strict;
use FindBin;

# BEGIN FIXMORE HACK - DO NOT EDIT
# %amidefaults is initialized by fixmore MakeMaker hack
my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "$FindBin::Bin/../etc",
        LIBDIR  => "$FindBin::Bin/../lib",
    );
}

# END FIXMORE HACK - DO NOT EDIT

# use amidefaults to find other modules $env('PERL5LIB') still works...
use lib $amidefaults{'LIBDIR'};
use Getopt::Std;
use Carp qw(cluck);
use File::Basename;
use DBI;
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use Template;
use OWP;
use OWP::Utils;
use owdb;
use Data::Dumper;

# Fetch configuration options.
my $conf = new OWP::Conf( %amidefaults );

my $debug = $conf->get_val( ATTR => 'DEBUG' );

my $cgi = new CGI;

#
# URL decomposition
#
my ( $base, $dir, $suffix ) = fileparse( $cgi->script_name, ".cgi" );
$dir =~ s#(.*)/$#$1#;
my $navfile = $dir . "/nav.html";
my $selfdir = "http://" . $cgi->virtual_host() . $dir . "/";
my $selfurl = $selfdir . $base . ".cgi";

my $default_duration = 15; 	# minutes

my $start_time     = $cgi->param( 'start_time' );
my $end_time       = $cgi->param( 'end_time' );
my $duration       = $cgi->param( 'duration' );
my $loss_threshold = $cgi->param( 'loss_threshold' );
my $senders        = $cgi->param( 'senders' );
my $receivers      = $cgi->param( 'receivers' );

$duration = $default_duration unless ($duration);

my $start_time_set = 0;
$start_time_set = 1 if ($start_time);

my $end_time_set = 0;
$end_time_set = 1 if ($end_time);

my $is_now = 0;
$is_now = 1 unless ($start_time_set or $end_time_set);

$end_time = time unless ($end_time);
$start_time = $end_time - $duration*60 unless ($start_time);

$duration = $end_time - $start_time;

#
# Read database options
#
my $ttype    = 'OWP';
my $dbuser   = $conf->must_get_val( ATTR => 'CGIDBUser', TYPE => $ttype );
my $dbpass   = $conf->get_val( ATTR => 'CGIDBPass', TYPE => $ttype );
my $dbsource = $conf->must_get_val( ATTR => 'CentralDBType', TYPE => $ttype ) . ":" . $conf->must_get_val( ATTR => 'CentralDBName', TYPE => $ttype );
my $dbhost   = $conf->get_val( ATTR => 'CentralDBHost', TYPE => $ttype ) || "localhost";
my $dbport   = $conf->get_val( ATTR => 'CentralDBPort', TYPE => $ttype );
if ( defined( $dbport ) ) {
    $dbhost .= ":" . $dbport;
}
$dbsource .= ":" . $dbhost;

#
# Connect to database
#
my $dbh = DBI->connect(
    $dbsource,
    $dbuser, $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
    )
    || die "Couldn't connect to database";

my $sql;
my $sth;
my @row;
my $rc;

# get resolutions
my @reslist;
$sql = "SELECT res from resolutions order by res";
$sth = $dbh->prepare( $sql ) || die "Prep: Select resolutions";
$sth->execute() || die "Select resolutions";
while ( @row = $sth->fetchrow_array ) {
    push @reslist, @row;
}

# get meshes
my %meshes;
$sql = "SELECT mesh_name,addr_type from meshes";
$sth = $dbh->prepare( $sql ) || die "Prep:Select meshes";
$sth->execute() || die "Select meshes";
while ( @row = $sth->fetchrow_array ) {
    $meshes{ $row[0] } = $row[1];
}
my @meshes = sort keys %meshes;

# TODO: Add a sort parameter to the meshes in the conf file. (Each
# mesh can have an 'Order' parameter and then the sort could key
# on that. (make it a cookie-parm..?)

# Fetch all the data

my %results = ();
my %mesh_results = ();

foreach my $mesh (@meshes) {
	my $bucket_width = $conf->must_get_val(MESH=>$mesh,ATTR=>'OWPBUCKETWIDTH');
	my $resolution = $reslist[-1];

	my ($status, $res1, $res2) = owdb_retrieve_mesh_summary({ db_handle => $dbh, mesh => $mesh, start_time => $start_time, end_time => $end_time, resolution => $reslist[0], bucket_width => $bucket_width, flag_points => 0.01, rolling_loss_packets => 2000, loss_threshold => $loss_threshold, senders_to_ignore => [ "CHIC", "AATRAVERSE", "MITC", "HOTELCAKEBOX" ], receivers_to_ignore => [ "CHIC", "AATRAVERSE", "MITC", "HOTELCAKEBOX" ] });
	if ($status == 0) {
		$mesh_results{$mesh} = $res1;

		foreach my $test_name (keys %{ $res2 }) {
			$results{$test_name} = $res2->{$test_name};
		}
	}
}

my (%receivers, %senders, %nodenames);

foreach my $tname (keys %results) {
	$receivers{$results{$tname}->{RECEIVER}} = 1;
	$senders{$results{$tname}->{SENDER}} = 1;
	unless ($nodenames{$results{$tname}->{RECEIVER}}) {
		$nodenames{$results{$tname}->{RECEIVER}} = $conf->get_val( NODE => $results{$tname}->{RECEIVER}, ATTR => 'LONGNAME' );
	}
	unless ($nodenames{$results{$tname}->{SENDER}}) {
		$nodenames{$results{$tname}->{SENDER}} = $conf->get_val( NODE => $results{$tname}->{SENDER}, ATTR => 'LONGNAME' );
	}
}

my @receivers;
if ($receivers) {
	@receivers = split(",", $receivers);
} else {
	@receivers = sort { $nodenames{$a} cmp $nodenames{$b} }keys %receivers;
}

my @senders;
if ($senders) {
	@senders= split(",", $senders);
} else {
	@senders = sort { $nodenames{$a} cmp $nodenames{$b} }keys %senders;
}


# Now display the results
my @headers;
push(
    @headers,
    -type    => 'text/html',
    -expires => '+1min'
);

my $time_select_url = "${selfdir}time_select.cgi";
my $delim = "?";
if ($start_time and not $is_now) {
	$time_select_url .= $delim."start_time=$start_time";
	$delim = "&";
}
if ($end_time and not $is_now) {
	$time_select_url .= $delim."end_time=$end_time";
	$delim = "&";
}

my $time_string = "";
$time_string .= "&start_time=$start_time" if ($start_time_set);
$time_string .= "&end_time=$end_time" if ($end_time_set);

my @mesh_status = ();

foreach my $mesh (@meshes) {
	my %mesh_desc = ();

	my $jitter = $mesh_results{$mesh}->{JITTER}?sprintf "%.3f", $mesh_results{$mesh}->{JITTER} * 1000:'*';
	my $delay = $mesh_results{$mesh}->{MAX}?sprintf "%.3f", $mesh_results{$mesh}->{MAX} * 1000:'*';
	my $loss = ($mesh_results{$mesh}->{ROLLING_LOSSRATE} * 100) if ($mesh_results{$mesh}->{SENT});

	if (defined $loss) {
		if ($loss) {
			$loss = sprintf "%.3f", $loss;
		} else {
			$loss = "0";
		}
	}

	$mesh_desc{loss} = $loss;
	$mesh_desc{latency} = $delay;
	$mesh_desc{jitter} = $jitter;

	push @mesh_status, \%mesh_desc;
}

my @receivers_disp = ();

foreach my $recv ( @receivers ) {
	my %receiver = ();
	$receiver{name} = $nodenames{$recv};
	$receiver{url} = "${selfdir}owamp_path_jitter.cgi?node=$recv".$time_string;
	push @receivers_disp, \%receiver;
}

# Now for the data rows
my @senders_disp = ();
SEND:
foreach my $send ( @senders ) {

    my $mesh;
    foreach $mesh ( @meshes ) {
        my $do_mesh;

        foreach my $recv ( @receivers ) {
            my $tname = "${mesh}_${recv}_${send}";
            next if !exists( $results{$tname} );
            $do_mesh = 1;
            last;
        }

        next MESH if ( !$do_mesh );


        #        $line .= $cgi->th({-align => 'center'},
        #            $conf->get_val(NODE=>$send,
        #                ATTR=>'ADDRDESC',
        #                TYPE=>$meshes{$mesh}) || '') . "\n";

	my %nodes = ();

        foreach my $recv ( @receivers ) {
	    my %receiver = ();

            my $tname = "${mesh}_${recv}_${send}";
            if ( !exists( $results{$tname} ) ) {
		$receiver{latency} = "";
		$receiver{jitter} = "";
		$receiver{loss} = "";
		$receiver{latency_color} = "#DDDDDD";
		$receiver{jitter_color} = "#DDDDDD";
		$receiver{loss_color} = "#DDDDDD";
            }
            else {
		my $jitter = $results{$tname}->{JITTER}?sprintf "%.3f", $results{$tname}->{JITTER} * 1000:'*';
		my $delay = $results{$tname}->{MAX}?sprintf "%.3f", $results{$tname}->{MAX} * 1000:'*';
		my $loss = 100 * $results{$tname}->{ROLLING_LOSSRATE} if (defined $results{$tname}->{ROLLING_LOSSRATE});

		if (defined $loss) {
			if ($loss) {
				$loss = sprintf "%.3f", $loss;
			} else {
				$loss = "0";
			}
		}
		$loss = '*' if (not defined $loss);

		$receiver{loss} = $loss;
		$receiver{latency} = $delay;
		$receiver{jitter} = $jitter;
		$receiver{url} = "${selfdir}plot_path.cgi?mesh=$mesh&destination=$recv&source=$send".$time_string;
            }

	    $nodes{$nodenames{$recv}} = \%receiver;
        }

	my %sender = ();

	$sender{url} = "${selfdir}owamp_path_jitter.cgi?mesh=$mesh&node=$send".$time_string;
	$sender{name} = $nodenames{$send};
	$sender{mesh} = $mesh;
	$sender{nodes} = \%nodes;

	push @senders_disp, \%sender,
    }
}

my $seperator = "?";
my $base_url = $cgi->script_name;
if ($senders) {
$base_url .= $seperator."senders=$senders";
$seperator = "&";
}
if ($receivers) {
$base_url .= $seperator."receivers=$receivers";
$seperator = "&";
}
if ($loss_threshold) {
$base_url .= $seperator."loss_threshold=$loss_threshold";
$seperator = "&";
}
my $prev_url = $base_url.$seperator."start_time=".($start_time-$duration)."&end_time=".$start_time;
my $next_url = $base_url.$seperator."end_time=".($end_time+$duration)."&start_time=".$end_time;


push( @headers, '-Refresh' => 60 );

print $cgi->header( @headers );

my $tt = Template->new(include_path => '.');
my %vars = (
		start_time => scalar(localtime($start_time)),
		end_time => scalar(localtime($end_time)),
		meshes  => \@mesh_status,
		senders  => \@senders_disp,
		receivers => \@receivers_disp,
		next_url => $next_url, 
		prev_url => $prev_url, 
		);

$tt->process("owamp_grid_jitter.tmpl", \%vars) or die $tt->error(), "\n";

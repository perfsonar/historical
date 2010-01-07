#!/usr/bin/perl -w 
use strict;
use warnings;

use strict;
use FindBin;
use File::Temp qw/tempfile/;
use Template;

# BEGIN FIXMORE HACK - DO NOT EDIT
# %amidefaults is initialized by fixmore MakeMaker hack
my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "$FindBin::Bin/../etc",
        LIBDIR  => "$FindBin::Bin/../lib",
    );
}

use lib $amidefaults{'LIBDIR'};
my $conf = new OWP::Conf( %amidefaults );

use OWP;
use OWP::Utils;
use owdb;

use CGI;
use CGI::Carp qw(fatalsToBrowser);
use HTML::Template;
use DBI;
use Data::Dumper;

my $cgi = CGI->new();

my $sender            = $cgi->param('sender');
my $receiver          = $cgi->param('receiver');
my $receiver_address  = $cgi->param('receiver_address');
my $sender_address    = $cgi->param('sender_addr');
my $tests          = $cgi->param( 'tests' );
my $start_time     = $cgi->param( 'start_time' );
my $end_time       = $cgi->param( 'end_time' );
my $duration       = $cgi->param( 'duration' );
my $image_width    = $cgi->param( 'width' );
my $image_height   = $cgi->param( 'height' );
my $flag_point     = $cgi->param( 'flag_point' );
my $loss_threshold = $cgi->param( 'loss_threshold' );
my $jitter_max     = $cgi->param( 'alpha_max' );
my $jitter_min     = $cgi->param( 'alpha_min' );
my $specific_ymax  = $cgi->param( 'y_max' );
my $specific_ymin  = $cgi->param( 'y_min' );
my $show_legend    = $cgi->param( 'show_legend' );
my $plot_min       = $cgi->param( 'plot_min' );

my $default_duration     = 120;      # in minutes
my $default_image_width  = 1200;    # in pixels
my $default_image_height = 600;     # in pixels
my $default_font_size    = 600;     # in pixels
my $default_flag_point   = 0.01;    # in milliseconds
my $default_plot_points  = 100;     # Will plot no less than this number of plot points.
my $default_ymin         = 0;       # Set by default but probably should be undef by default
my $default_ymax         = 30;    # Set by default but probably should be undef by default
my $default_show_legend  = "yes";

unless ( $sender and $receiver ) {
    die "Must have a sender($sender) and receiver($receiver)";
}

$show_legend = $default_show_legend unless ( $show_legend );

$duration = $default_duration unless ( $duration );

$flag_point = $default_flag_point unless ( $flag_point );

$end_time = time unless ($end_time);
$start_time = $end_time - $duration * 60 unless ($start_time);

unless ( $image_height ) {
    $image_height = $default_image_height;
}

unless ( $image_width ) {
    $image_width = $default_image_width;
}

$specific_ymin = $default_ymin unless ( $specific_ymin );
$specific_ymax = $default_ymax unless ( $specific_ymax );

my @test_names = ( undef );
if ($tests) {
	@test_names = split( ",", $tests );
}

my $start_time_int = time2owptime( $start_time );
my $end_time_int   = time2owptime( $end_time );

my $ploticus  = $conf->must_get_val( ATTR => 'Ploticus' );
my $cgitmpdir = $conf->must_get_val( ATTR => 'CGITmpDir' );

my $ttype    = 'OWP';
my $dbuser   = $conf->must_get_val( ATTR => 'CGIDBUser', TYPE => $ttype );
my $dbpass   = $conf->get_val( ATTR => 'CGIDBPass', TYPE => $ttype );
my $dbsource = $conf->must_get_val( ATTR => 'CentralDBType', TYPE => $ttype ) . ":" . $conf->must_get_val( ATTR => 'CentralDBName', TYPE => $ttype );
my $dbhost   = $conf->get_val( ATTR => 'CentralDBHost', TYPE => $ttype ) || "localhost";
my $dbport = $conf->get_val( ATTR => 'CentralDBPort', TYPE => $ttype );

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

my $nrecs = 0;
my $oend  = 0;
my $tdate;
my $ymin;
my $ymax;
my $xmin;
my $xmax;
my $num_flagged = 0;
my $total       = 0;
my $lost        = 0;

my %buckets = ();
my %times   = ();

my %packet_buckets = (
    1 => { point_type => 1, color => 8,   max => 1,   description => "1 packet" },  # blue
    2 => { point_type => 3, color => 2,  min => 2,   max         => 9, description => "< 10 packets" }, # green
    3 => { point_type => 6, color => 4, min => 10,  max         => 99, description => "< 100 packets" }, # purple
    4 => { point_type => 8, color => 1, min => 100, description => ">= 100 packets" }, # orange
);

my %cutoffs = (
	1 => { value => 0.01, description => "Warning Level" },
	2 => { value => 0.02, description => "Error Level" },
);

my $plot_points = $default_plot_points;

my %cutoff_bucket = ();
my %lost_bucket = ();

#open(BAD, ">/tmp/bad.$$");
#print BAD "Loss Threshold: $loss_threshold\n";
foreach my $test_name ( @test_names ) {
    my %bad = ();

    my %owpvals      = ();

    my $range  = $end_time - $start_time;

    my @alphas = ( 0.99 ); # XXX need to have at least 1 to avoid a crash
    push @alphas, $jitter_min if ($jitter_min);
    push @alphas, $jitter_max if ($jitter_max);

    my $owdb = owdb_prep(
        DBH         => $dbh,
        TESTID      => $test_name,
        RECV_NAME   => $receiver,
	RECV_ADDR   => $receiver_address,
        SEND_NAME   => $sender,
        SEND_ADDR   => $sender_address,
        FIRST       => owptstampi( $start_time_int ),
        LAST        => owptstampi( $end_time_int ),
        ALPHAS      => \@alphas,
        OWHASH      => \%owpvals,
        )
        or die "Unable to init owp data request";

    open(OUTPUT, ">", "/tmp/output");

    while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
	my $period_start = owptime2exacttime( $owpvals{'START'} );
	my $bucket_width = $owpvals{'BUCKETWIDTH'};

        next if ($start_time > $period_start );
        next if ($end_time < $period_start );

        my $curr_jitter_min;
        my $curr_jitter_max;
       
	#print OUTPUT Dumper(\%owpvals); 
        if ($jitter_min and defined $owpvals{ALPHAS}->{$jitter_min}) {
		$curr_jitter_min = $owpvals{ALPHAS}->{$jitter_min};
        }       
        
        if ($jitter_max and defined $owpvals{ALPHAS}->{$jitter_max}) {
		$curr_jitter_max = $owpvals{ALPHAS}->{$jitter_max};
        }

        my %yvals = ();

	my $num_lost = 0;
	my $num_cutoff = 0;

        $num_lost += $owpvals{'LOST'};
	if ($owpvals{'LOST'}) {
		$bad{$owpvals{'START'}}->{lost} = $owpvals{'LOST'};
	}

	my $saw_flagged;

	#print OUTPUT "Period Duration: ".(owptime2exacttime( $owpvals{'END'} ) - owptime2exacttime( $owpvals{'START'} )).": ".$bucket_width.": ".localtime(owptime2exacttime($owpvals{'START'}))."\n";
	#print OUTPUT "Start Time/End Time: ".localtime($start_time)."/".localtime($end_time)."\n";

	#print OUTPUT "Jitter Min: $curr_jitter_min\n";
	#print OUTPUT "Jitter Max: $curr_jitter_max\n";

        foreach my $key ( keys %{ $owpvals{'HISTOGRAM'} } ) {
            my $pkt_count = $owpvals{'HISTOGRAM'}->{$key};
            my $jitter = $key * $bucket_width;

            next if (defined $curr_jitter_min and $jitter < $curr_jitter_min);
            next if (defined $curr_jitter_max and $jitter > $curr_jitter_max);

            my $value;
            foreach my $bucket ( keys %packet_buckets ) {
                my $min = $packet_buckets{$bucket}->{min};
                my $max = $packet_buckets{$bucket}->{max};

                next unless ( $max or $min );

                # Skip if too small
                next if ( $min and $pkt_count < $min );
                next if ( $max and $pkt_count > $max );

                $value = $bucket;
                last;
            }

            next unless ($value);

            if ( $loss_threshold and $jitter > $loss_threshold ) {
                $num_lost += $pkt_count;
		#print BAD "Lost: $pkt_count\n";
		next;
            }

            if ( $jitter > $flag_point ) {
		$bad{$owpvals{'START'}}->{flagged} = 0 unless ($bad{$owpvals{'START'}}->{flagged});
		$bad{$owpvals{'START'}}->{spots} = () unless ($bad{$owpvals{'START'}}->{spots});
		$bad{$owpvals{'START'}}->{flagged} += $pkt_count;
		push @{ $bad{$owpvals{'START'}}->{spots} }, { value => $jitter, count => $pkt_count };

                $num_flagged += $pkt_count;
		$saw_flagged = 1;
            }

            $total += $pkt_count;

            $xmin = $period_start if ( not $xmin or $period_start < $xmin );
            $xmax = $period_start if ( not $xmax or $period_start > $xmax );

            if ($specific_ymax and ($jitter > $specific_ymax)) {
		$num_cutoff += $pkt_count;
		next;
            }

            if ($plot_min) {
                $jitter += $owpvals{'MIN'};
            }

	    $jitter *= 1000;

            $ymin = $jitter                                if ( not $ymin or $jitter < $ymin );
            $ymax = $jitter                                if ( not $ymax or $jitter > $ymax );

            $buckets{$value} = () unless ( defined $buckets{$value} );
            $buckets{$value}->{ $period_start } = () unless $buckets{$value}->{ $period_start };
            push @{ $buckets{$value}->{ $period_start } }, $jitter;
        }

	if ($owpvals{'LOST'} or $saw_flagged) {
		$bad{$owpvals{'START'}}->{sent} = $owpvals{'SENT'};
	}

	if ($num_lost) {
		$lost_bucket{ $period_start } = 0 unless $lost_bucket{ $period_start };
		$lost_bucket{ $period_start } += $num_lost;
	}

	if ($num_cutoff) {
		$cutoff_bucket{ $period_start } = 0 unless $cutoff_bucket{ $period_start };
		$cutoff_bucket{ $period_start } += $num_cutoff;
	}

	$lost += $num_lost;
    }

#open(BAD, ">/tmp/bad.$test_name");
#foreach my $time ( sort { $a <=> $b } keys %bad) {
#	print BAD scalar(gmtime(owptime2exacttime( $time )));
#	print BAD ",".$bad{$time}->{sent};
#	print BAD ",".$bad{$time}->{lost};
#	print BAD ",".$bad{$time}->{flagged};
#	foreach my $pair (@{ $bad{$time}->{spots} }) {
#		print BAD ",".$pair->{value}.",".$pair->{count};
#	}
#	print BAD "\n";
#}
#close(BAD);

}
#close(BAD);

close(OUTPUT);

my $data  = "plot ";
my $comma = "";

my %files = ();

foreach my $bucket ( sort { $a <=> $b } keys %buckets ) {
    my ( $filehandle, $filename ) = tempfile( DIR => $cgitmpdir );
    $files{$bucket}             = ();
    $files{$bucket}->{fh}       = $filehandle;
    $files{$bucket}->{filename} = $filename;

    $data .= $comma;
    $data .= "'$filename' using 1:2 lt " . $packet_buckets{$bucket}->{color} . " pt ".$packet_buckets{$bucket}->{point_type}." title '" . $packet_buckets{$bucket}->{description} . "'";
    $comma = ", ";
}

foreach my $bucket ( sort { $a <=> $b } keys %buckets ) {
    foreach my $time ( sort { $a <=> $b } keys %{ $buckets{$bucket} } ) {
        foreach my $val ( @{ $buckets{$bucket}->{$time} } ) {
            print { $files{$bucket}->{fh} } ts2output($time) . " " .$val. "\n";
        }
    }
}

if (scalar(keys %cutoff_bucket)) { # handle adding in cut off data

	my ( $filehandle, $filename ) = tempfile( DIR => $cgitmpdir );

	$data .= $comma;
	$data .= "'$filename' using 1:2 lt 1 pt 4 title 'Cutoff Packets'";
	$comma = ", ";

	foreach my $time ( sort { $a <=> $b } keys %cutoff_bucket ) {
		print { $filehandle } ts2output($time) . " " . $specific_ymax . "\n";
	}
}

if (scalar(keys %lost_bucket)) { # handle adding in cut off data

	my ( $filehandle, $filename ) = tempfile( DIR => $cgitmpdir );

	$data .= $comma;
	$data .= "'$filename' using 1:2 lt 10 pt 8 title 'Lost Packets'";
	$comma = ", ";

	foreach my $time ( sort { $a <=> $b } keys %lost_bucket ) {
		print { $filehandle } ts2output($time) . " " . $specific_ymax . "\n";
	}
}

$ymax = $specific_ymax if (defined $specific_ymax);
$ymin = $specific_ymin if (defined $specific_ymin);

$data .= $comma;
$data .= "$flag_point lt -1 title ' Flag Point: $flag_point'";

my $x_min_out = ts2output($start_time);
my $x_max_out = ts2output($end_time);

if ($ymin == $ymax) {
	$ymax = $ymin + 1;
}

my %vars = ();
$vars{width}             = $image_width;
$vars{height}            = $image_height;
$vars{xmin}              = $x_min_out;
$vars{xmax}              = $x_max_out;
$vars{ymin}              = $ymin;
$vars{ymax}              = $ymax;
$vars{flagged_packets}   = $num_flagged;
$vars{lost_packets}      = $lost;
$vars{total_packets}     = $total;
$vars{show_legend}       = $show_legend;

my $gnuplot_script;

my $tt = Template->new( INCLUDE_PATH => '.' ) or die( "Couldn't initialize template toolkit" );
$tt->process( "plot_histogram.gnuplot.tmpl", \%vars, \$gnuplot_script ) or die $tt->error();

$gnuplot_script .= $data;

print $cgi->header( '-Content-type' => 'image/png' );

open( GNUPLOT, "| gnuplot" );
print GNUPLOT $gnuplot_script;
pipe( STDOUT, GNUPLOT );
close GNUPLOT;

foreach my $bucket ( sort { $a <=> $b } keys %buckets ) {
    close( $files{$bucket}->{fh} );
    unlink( $files{$bucket}->{filename} );
}

exit 0;

sub ts2output {
        my ($ts) = @_;

        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
        $year += 1900;
        $mon++;

        return sprintf "%4d-%02d-%02dT%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec;
}

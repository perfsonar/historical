#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

use Config::General;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use JSON::XS;
use File::Temp qw/ tempfile /;
use File::Copy;

use perfSONAR_PS::SCWeatherMap::Background;
use perfSONAR_PS::SCWeatherMap::Icons;
use perfSONAR_PS::SCWeatherMap::Endpoints;
use perfSONAR_PS::SCWeatherMap::SC09;
use perfSONAR_PS::SCWeatherMap::UtilizationColors;

my $output_level = $DEBUG;

my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
        file   => "/tmp/wmap.output",
        );


Log::Log4perl->easy_init( \%logger_opts );
my $logger = get_logger( "perfSONAR_PS::SCWeatherMap" );

my $file = shift;

$file = $confdir."/sc09_dcn_configuration.conf" unless ($file);

my %configuration = Config::General->new($file)->getall;

my ($status, $res);

my $background_filter = perfSONAR_PS::SCWeatherMap::Background->new();
($status, $res) = $background_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $icons_filter = perfSONAR_PS::SCWeatherMap::Icons->new();
($status, $res) = $icons_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $endpoints_filter = perfSONAR_PS::SCWeatherMap::Endpoints->new();
($status, $res) = $endpoints_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $sc09_filter = perfSONAR_PS::SCWeatherMap::SC09->new();
($status, $res) = $sc09_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $color_filter = perfSONAR_PS::SCWeatherMap::UtilizationColors->new();
($status, $res) = $color_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

if ($configuration{daemon}) {
	$configuration{sleep_time} = 20 unless ($configuration{sleep_time});
}

do {
	my %endpoints = ();
	my @links = ();
	my %background = ();
	my @icons = ();

	($status, $res) = $background_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
	if ($status != 0) {
		die($res);
	}

	($status, $res) = $icons_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
	if ($status != 0) {
		die($res);
	}

	($status, $res) = $endpoints_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
	if ($status != 0) {
		die($res);
	}

	($status, $res) = $sc09_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
	if ($status != 0) {
		die($res);
	}

	($status, $res) = $color_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
	if ($status != 0) {
		die($res);
	}
	my %results = ();
	$results{background} = \%background;
	$results{endpoints} = \%endpoints;
	$results{links} = \@links;
	$results{icons} = \@icons;

	print Dumper(\@links);

	if ($configuration{output_file}) {
		print "Getting temp file\n";
		my ($fh, $filename) = tempfile( DIR => "/tmp" );
		print "Writing file\n";
		print $fh encode_json(\%results);
		close($fh);

		print "Renaming file: ".$configuration{output_file}."\n";
		move($filename, $configuration{output_file});
	} else {
		print encode_json(\%results);
	}

	if ($configuration{sleep_time}) {
		sleep($configuration{sleep_time});
	}
} while($configuration{daemon});

exit 0;

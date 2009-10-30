#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

use lib "/home/aaron/owamp/lib";

use Config::General;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use JSON::XS;

use perfSONAR_PS::SCWeatherMap::Background;
use perfSONAR_PS::SCWeatherMap::Icons;
use perfSONAR_PS::SCWeatherMap::Endpoints;
use perfSONAR_PS::SCWeatherMap::StaticLinks;
use perfSONAR_PS::SCWeatherMap::perfSONARBUOY;
use perfSONAR_PS::SCWeatherMap::JitterColors;
use perfSONAR_PS::SCWeatherMap::StackedLayout;

my $output_level = $DEBUG;

my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
        file   => "/tmp/wmap.output",
        );


Log::Log4perl->easy_init( \%logger_opts );
my $logger = get_logger( "perfSONAR_PS::SCWeatherMap" );

my $file = shift;

$file = $confdir."/owamp_configuration.conf" unless ($file);

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

my $static_links_filter = perfSONAR_PS::SCWeatherMap::StaticLinks->new();
($status, $res) = $static_links_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $perfsonarbuoy_filter = perfSONAR_PS::SCWeatherMap::perfSONARBUOY->new();
($status, $res) = $perfsonarbuoy_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $color_filter = perfSONAR_PS::SCWeatherMap::JitterColors->new();
($status, $res) = $color_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

my $stacked_filter = perfSONAR_PS::SCWeatherMap::StackedLayout->new();
($status, $res) = $stacked_filter->init(\%configuration);
if ($status != 0) {
        die($res);
}

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

($status, $res) = $static_links_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $perfsonarbuoy_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

($status, $res) = $color_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
if ($status != 0) {
        die($res);
}

#($status, $res) = $stacked_filter->run({ current_endpoints => \%endpoints, current_links => \@links, current_background => \%background, current_icons => \@icons });
#if ($status != 0) {
#        die($res);
#}

$logger->debug("Links: ".Dumper(\@links));

my %results = ();
$results{background} = \%background;
$results{endpoints} = \%endpoints;
$results{links} = \@links;
$results{icons} = \@icons;

print encode_json(\%results);

exit 0;

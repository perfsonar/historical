#!/usr/bin/perl

# Include current script directory in the module path (needed on Microsoft IIS).
# This allows this script to work by copying ChartDirector to the same directory
# as the script (as an alternative to installation in Perl module directory)
use File::Basename;
use lib dirname($0);

use perlchartdir;

# Get HTTP query parameters
use CGI;
my $query = new CGI;

# The data for the pie chart
my $data = [25, 18, 15, 12, 8, 30, 35];

# The labels for the pie chart
my $labels = ["Labor", "Licenses", "Taxes", "Legal", "Insurance", "Facilities",
    "Production"];

# Colors of the sectors if custom coloring is used
my $colors = [0xb8bc9c, 0xecf0b9, 0x999966, 0x333366, 0xc3c3e6, 0x594330, 0xa0bdc4];

# Create a PieChart object of size 280 x 240 pixels
my $c = new PieChart(280, 240);

# Set the center of the pie at (140, 120) and the radius to 80 pixels
$c->setPieSize(140, 120, 80);

# Draw the pie in 3D
$c->set3D();

# Set the coloring schema
if ($query->param("img") eq "0") {
    $c->addTitle("Custom Colors");
    # set the LineColor to light gray
    $c->setColor($perlchartdir::LineColor, 0xc0c0c0);
    # use given color array as the data colors (sector colors)
    $c->setColors2($perlchartdir::DataColor, $colors);
} elsif ($query->param("img") eq "1") {
    $c->addTitle("Dark Background Colors");
    # use the standard white on black palette
    $c->setColors($perlchartdir::whiteOnBlackPalette);
} elsif ($query->param("img") eq "2") {
    $c->addTitle("Wallpaper As Background");
    $c->setWallpaper(dirname($0)."/bg.png");
} else {
    $c->addTitle("Transparent Colors");
    $c->setWallpaper(dirname($0)."/bg.png");
    # use semi-transparent colors to allow the background to be seen
    $c->setColors($perlchartdir::transparentPalette);
}

# Set the pie data and the pie labels
$c->setData($data, $labels);

# Explode the 1st sector (index = 0)
$c->setExplode(0);

# output the chart
binmode(STDOUT);
print "Content-type: image/gif\n\n";
print $c->makeChart2($perlchartdir::GIF);


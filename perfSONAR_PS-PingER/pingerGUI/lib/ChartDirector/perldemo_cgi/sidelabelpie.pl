#!/usr/bin/perl

# Include current script directory in the module path (needed on Microsoft IIS).
# This allows this script to work by copying ChartDirector to the same directory
# as the script (as an alternative to installation in Perl module directory)
use File::Basename;
use lib dirname($0);

use perlchartdir;

# The data for the pie chart
my $data = [25, 18, 15, 12, 8, 30, 35];

# The labels for the pie chart
my $labels = ["Labor", "Licenses", "Taxes", "Legal", "Insurance", "Facilities",
    "Production"];

# Create a PieChart object of size 500 x 230 pixels
my $c = new PieChart(500, 230);

# Set the center of the pie at (250, 120) and the radius to 100 pixels
$c->setPieSize(250, 120, 100);

# Add a title box using 15 points Times Bold Italic as font
$c->addTitle("Project Cost Breakdown", "timesbi.ttf", 15);

# Draw the pie in 3D
$c->set3D();

# Use the side label layout method
$c->setLabelLayout($perlchartdir::SideLayout);

# Set the pie data and the pie labels
$c->setData($data, $labels);

# output the chart
binmode(STDOUT);
print "Content-type: image/png\n\n";
print $c->makeChart2($perlchartdir::PNG);


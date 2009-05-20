#!/usr/bin/perl

# Include current script directory in the module path (needed on Microsoft IIS).
# This allows this script to work by copying ChartDirector to the same directory
# as the script (as an alternative to installation in Perl module directory)
use File::Basename;
use lib dirname($0);

use perlchartdir;

# In this example, the data points are unevenly spaced on the x-axis
my $dataY = [4.7, 4.7, 6.6, 2.2, 4.7, 4.0, 4.0, 5.1, 4.5, 4.5, 6.8, 4.5, 4, 2.1, 3,
    2.5, 2.5, 3.1];
my $dataX = [perlchartdir::chartTime(1999, 7, 1), perlchartdir::chartTime(2000, 1, 1
    ), perlchartdir::chartTime(2000, 2, 1), perlchartdir::chartTime(2000, 4, 1),
    perlchartdir::chartTime(2000, 5, 8), perlchartdir::chartTime(2000, 7, 5),
    perlchartdir::chartTime(2001, 3, 5), perlchartdir::chartTime(2001, 4, 7),
    perlchartdir::chartTime(2001, 5, 9), perlchartdir::chartTime(2002, 2, 4),
    perlchartdir::chartTime(2002, 4, 4), perlchartdir::chartTime(2002, 5, 8),
    perlchartdir::chartTime(2002, 7, 7), perlchartdir::chartTime(2002, 8, 30),
    perlchartdir::chartTime(2003, 1, 2), perlchartdir::chartTime(2003, 2, 16),
    perlchartdir::chartTime(2003, 11, 6), perlchartdir::chartTime(2004, 1, 4)];

# Data points are assigned different symbols based on point type
my $pointType = [0, 1, 0, 1, 2, 1, 0, 0, 1, 1, 2, 2, 1, 0, 2, 1, 2, 0];

# Create a XYChart object of size 600 x 300 pixels, with a light purple (ffccff)
# background, black border, 1 pixel 3D border effect and rounded corners.
my $c = new XYChart(600, 300, 0xffccff, 0x000000, 1);
$c->setRoundedFrame();

# Set the plotarea at (55, 58) and of size 520 x 195 pixels, with white (ffffff)
# background. Set horizontal and vertical grid lines to grey (cccccc).
$c->setPlotArea(55, 58, 520, 195, 0xffffff, -1, -1, 0xcccccc, 0xcccccc);

# Add a legend box at (55, 30) (top of the chart) with horizontal layout. Use 10 pts
# Arial Bold Italic font. Set the background and border color to Transparent.
$c->addLegend(55, 30, 0, "arialbi.ttf", 10)->setBackground($perlchartdir::Transparent
    );

# Add a title box to the chart using 15 pts Times Bold Italic font. The text is white
# (ffffff) on a purple (400040) background, with soft lighting effect from the right
# side.
$c->addTitle("Multi-Symbol Line Chart Demo", "timesbi.ttf", 15, 0xffffff
    )->setBackground(0x400040, -1, perlchartdir::softLighting($perlchartdir::Right));

# Set the y axis label format to display a percentage sign
$c->yAxis()->setLabelFormat("{value}%");

# Set axis titles to use 9pt Arial Bold Italic font
$c->yAxis()->setTitle("Axis Title Placeholder", "arialbi.ttf", 9);
$c->xAxis()->setTitle("Axis Title Placeholder", "arialbi.ttf", 9);

# Set axis labels to use Arial Bold font
$c->yAxis()->setLabelStyle("arialbd.ttf");
$c->xAxis()->setLabelStyle("arialbd.ttf");

# We add the different data symbols using scatter layers. The scatter layers are
# added before the line layer to make sure the data symbols stay on top of the line
# layer.

# We select the points with pointType = 0 (the non-selected points will be set to
# NoValue), and use yellow (ffff00) 15 pixels high 5 pointed star shape symbols for
# the points. (This example uses both x and y coordinates. For charts that have no x
# explicitly coordinates, use an empty array as dataX.)
$c->addScatterLayer($dataX, new ArrayMath($dataY)->selectEQZ($pointType,
    $perlchartdir::NoValue)->result(), "Point Type 0", perlchartdir::StarShape(5),
    15, 0xffff00);

# Similar to above, we select the points with pointType - 1 = 0 and use green (ff00)
# 13 pixels high six-sided polygon as symbols.
$c->addScatterLayer($dataX, new ArrayMath($dataY)->selectEQZ(new ArrayMath($pointType
    )->sub(1)->result(), $perlchartdir::NoValue)->result(), "Point Type 1",
    perlchartdir::PolygonShape(6), 13, 0x00ff00);

# Similar to above, we select the points with pointType - 2 = 0 and use red (ff0000)
# 13 pixels high X shape as symbols.
$c->addScatterLayer($dataX, new ArrayMath($dataY)->selectEQZ(new ArrayMath($pointType
    )->sub(2)->result(), $perlchartdir::NoValue)->result(), "Point Type 2",
    perlchartdir::Cross2Shape(), 13, 0xff0000);

# Finally, add a blue (0000ff) line layer with line width of 2 pixels
my $layer = $c->addLineLayer($dataY, 0x0000ff);
$layer->setXData($dataX);
$layer->setLineWidth(2);

# output the chart
binmode(STDOUT);
print "Content-type: image/png\n\n";
print $c->makeChart2($perlchartdir::PNG);


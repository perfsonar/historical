#!/usr/bin/perl
print "Content-type: text/html\n\n";
print <<EndOfHTML
<html>
<head>
<script language="Javascript">
var charts = [
    ['', "Pie Chart Samples"],
    ['simplepie.pl', "Simple Pie Chart", 1],
    ['threedpie.pl', "3D Pie Chart", 1],
    ['multidepthpie.pl', "Multi-Depth Pie Chart", 1],
    ['sidelabelpie.pl', "Side Label Layout", 1],
    ['smallsectorpie.pl', "Pie with Small Sectors", 1],
    ['circlelabelpie.pl', "Circular Label Layout", 2],
    ['legendpie.pl', "Pie Chart with Legend", 1],
    ['iconpie.pl', "Icon Pie Chart", 1],
    ['iconpie2.pl', "Icon Pie Chart (2)", 1],
    ['multipie.pl', "Multi-Pie Chart", 3],
    ['donut.pl', "Donut Chart", 1],
    ['icondonut.pl', "Icon Donut Chart", 1],
    ['texturedonut.pl', "Texture Donut Chart", 1],
    ['concentric.pl', "Concentric Donut Chart", 1],
    ['fontpie.pl', "Text Style and Colors", 1],
    ['colorpie.pl', "Coloring and Wallpaper", 4],
    ['threedanglepie.pl', "3D Angle", 7],
    ['threeddepthpie.pl', "3D Depth", 5],
    ['shadowpie.pl', "3D Shadow Mode", 4],
    ['anglepie.pl', "Start Angle and Direction", 2],
    ['donutwidth.pl', "Donut Width", 5],
    ['', ""],
    ['', "Bar Chart Samples"],
    ['simplebar.pl', "Simple Bar Chart", 1],
    ['colorbar.pl', "Multi-Color Bar Chart", 1],
    ['softlightbar.pl', "Soft Bar Shading", 1],
    ['glasslightbar.pl', "Glass Bar Shading", 1],
    ['cylinderlightbar.pl', "Cylinder Bar Shading", 1],
    ['threedbar.pl', "3D Bar Chart", 1],
    ['cylinderbar.pl', "Cylinder Bar Shape", 1],
    ['polygonbar.pl', "Polygon Bar Shapes", 1],
    ['stackedbar.pl', "Stacked Bar Chart", 1],
    ['percentbar.pl', "Percentage Bar Chart", 1],
    ['multibar.pl', "Multi-Bar Chart", 1],
    ['softmultibar.pl', "Soft Multi-Bar Chart", 1],
    ['glassmultibar.pl', "Glass Multi-Bar Chart", 1],
    ['multicylinder.pl', "Multi-Cylinder Chart", 1],
    ['multishapebar.pl', "Multi-Shape Bar Chart", 1],
    ['overlapbar.pl', "Overlapping Bar Chart", 1],
    ['multistackbar.pl', "Multi-Stacked Bar Chart", 1],
    ['depthbar.pl', "Depth Bar Chart", 1],
    ['posnegbar.pl', "Positive Negative Bars", 1],
    ['hbar.pl', "Borderless Bar Chart", 1],
    ['dualhbar.pl', "Dual Horizontal Bar Charts", 1],
    ['pareto.pl', "Pareto Chart", 1],
    ['gapbar.pl', "Bar Gap", 6],
    ['', ""],
    ['', "Line Chart Samples"],
    ['simpleline.pl', "Simple Line Chart", 1],
    ['compactline.pl', "Compact Line Chart", 1],
    ['threedline.pl', "3D Line Chart", 1],
    ['multiline.pl', "Multi-Line Chart", 1],
    ['symbolline.pl', "Symbol Line Chart", 1],
    ['symbolline2.pl', "Symbol Line Chart (2)", 1],
    ['splineline.pl', "Spline Line Chart", 1],
    ['stepline.pl', "Step Line Chart", 1],
    ['linecompare.pl', "Line Comparison", 1],
    ['errline.pl', "Line with Error Symbols", 1],
    ['multisymbolline.pl', "Multi-Symbol Line Chart", 1],
    ['customsymbolline.pl', "Custom Symbols", 1],
    ['rotatedline.pl', "Rotated Line Chart", 1],
    ['xyline.pl', "Arbitrary XY Line Chart", 1],
    ['discontline.pl', "Discontinuous Lines", 1],
    ['', ""],
    ['', "Trending and Curve Fitting"],
    ['trendline.pl', "Trend Line Chart", 1],
    ['scattertrend.pl', "Scatter Trend Chart", 1],
    ['confidenceband.pl', "Confidence Band", 1],
    ['curvefitting.pl', "General Curve Fitting", 1],
    ['', ""],
    ['', "Scatter/Bubble/Vector Charts"],
    ['scatter.pl', "Scatter Chart", 1],
    ['builtinsymbols.pl', "Built-in Symbols", 1],
    ['scattersymbols.pl', "Custom Scatter Symbols", 1],
    ['scatterlabels.pl', "Custom Scatter Labels", 1],
    ['bubble.pl', "Bubble Chart", 1],
    ['bubblescale.pl', "Bubble XY Scaling", 1],
    ['vector.pl', "Vector Chart", 1],
    ['', ""],
    ['', "Area Chart Samples"],
    ['simplearea.pl', "Simple Area Chart", 1],
    ['enhancedarea.pl', "Enhanced Area Chart", 1],
    ['threedarea.pl', "3D Area Chart", 1],
    ['patternarea.pl', "Pattern Area Chart", 1],
    ['stackedarea.pl', "Stacked Area Chart", 1],
    ['threedstackarea.pl', "3D Stacked Area Chart", 1],
    ['percentarea.pl', "Percentage Area Chart", 1],
    ['deptharea.pl', "Depth Area Chart", 1],
    ['rotatedarea.pl', "Rotated Area Chart", 1],
    ['', ""],
    ['', "Floating Box/Waterfall Charts"],
    ['boxwhisker.pl', "Box-Whisker Chart", 1],
    ['boxwhisker2.pl', "Horizontal Box-Whisker Chart", 1],
    ['floatingbox.pl', "Floating Box Chart", 1],
    ['waterfall.pl', "Waterfall Chart", 1],
    ['posnegwaterfall.pl', "Pos/Neg Waterfall Chart", 1],
    ['', ""],
    ['', "Gantt Charts"],
    ['gantt.pl', "Simple Gantt Chart", 1],
    ['colorgantt.pl', "Multi-Color Gantt Chart", 1],
    ['layergantt.pl', "Multi-Layer Gantt Chart", 1],
    ['', ""],
    ['', "Finance Charts"],
    ['hloc.pl', "Simple HLOC Chart", 1],
    ['candlestick.pl', "Simple Candlestick Chart", 1],
    ['finance.pl', "Finance Chart (1)", 1],
    ['finance2.pl', "Finance Chart (2)", 1],
    ['<a href="javascript:window.open(\\'financedemo.pl\\', \\'financedemo\\').focus();">', "Interactive Financial Chart", -1],
    ['', ""],
    ['', "Other XY Chart Features"],
    ['markzone.pl', "Marks and Zones", 1],
    ['markzone2.pl', "Marks and Zones (2)", 1],
    ['yzonecolor.pl', "Y Zone Coloring", 1],
    ['xzonecolor.pl', "X Zone Coloring", 1],
    ['dualyaxis.pl', "Dual Y-Axis", 1],
    ['dualxaxis.pl', "Dual X-Axis", 1],
    ['multiaxes.pl', "Multiple Axes", 1],
    ['fourq.pl', "4 Quadrant Chart", 1],
    ['fontxy.pl', "Text Style and Colors", 1],
    ['background.pl', "Background and Wallpaper", 4],
    ['logaxis.pl', "Log Scale Axis", 2],
    ['axisscale.pl', "Y-Axis Scaling", 5],
    ['ticks.pl', "Tick Density", 2],
    ['', ""],
    ['', "Polar Charts"],
    ['simpleradar.pl', "Simple Radar Chart", 1],
    ['multiradar.pl', "Multi Radar Chart", 1],
    ['stackradar.pl', "Stacked Radar Chart", 1],
    ['polarline.pl', "Polar Line Chart", 1],
    ['polararea.pl', "Polar Area Chart", 1],
    ['polarspline.pl', "Polar Spline Chart", 1],
    ['polarscatter.pl', "Polar Scatter Chart", 1],
    ['polarbubble.pl', "Polar Bubble Chart", 1],
    ['polarvector.pl', "Polar Vector Chart", 1],
    ['rose.pl', "Simple Rose Chart", 1],
    ['stackrose.pl', "Stacked Rose Chart", 1],
    ['polarzones.pl', "Circular Zones", 1],
    ['polarzones2.pl', "Sector Zones", 1],
    ['', ""],
    ['', "Meters/Dials/Guages"],
    ['semicirclemeter.pl', "Semi-Circle Meter", 1],
    ['roundmeter.pl', "Round Meter", 1],
    ['wideameter.pl', "Wide Angular Meters", 6],
    ['squareameter.pl', "Square Angular Meters", 4],
    ['multiameter.pl', "Multi-Pointer Angular Meter", 1],
    ['iconameter.pl', "Icon Angular Meter", 1],
    ['hlinearmeter.pl', "Horizontal Linear Meter", 1],
    ['vlinearmeter.pl', "Vertical Linear Meter", 1],
    ['multihmeter.pl', "Multi-Pointer Horizontal Meter", 1],
    ['multivmeter.pl', "Multi-Pointer Vertical Meter", 1],
    ['linearzonemeter.pl', "Linear Zone Meter", 1],
    ['', ""],
    ['', "Clickable Charts"],
    ['clickbar.pl', "Simple Clickable Charts", 0],
    ['jsclick.pl', "Javascript Clickable Chart", 0],
    ['customclick.pl', "Custom Clickable Objects", 0],
    ['', ""],
    ['', "Working With Database"],
    ['dbdemo1_intro.pl', "Database Integration (1)", 0],
    ['dbdemo2_intro.pl', "Database Integration (2)", 0],
    ['dbdemo3_intro.pl', "Database Clickable Charts", 0],
    ['', ""],
    ['', "Zooming and Scrolling"],
    ['<a href="javascript:window.open(\\'zoomscrolldemo.pl\\', \\'zoomscrolldemo\\').focus();">', "Zoom/Scroll Demo (1)", -1],
    ['<a href="javascript:window.open(\\'zoomscrolldemo2.pl\\', \\'zoomscrolldemo\\').focus();">', "Zoom/Scroll Demo (2)", -1],
    ['', ""],
    ['', "Realtime Charts"],
    ['<a href="javascript:window.open(\\'realtimedemo.pl\\', \\'realtimedemo\\').focus();">', "Realtime Chart Demo", -1],
    ['', ""]
    ];
function setChart(c)
{
    var doc = top.indexright.document;
    doc.open();
    doc.writeln('<body topmargin="5" leftmargin="5" rightmargin="0" marginwidth="5" marginheight="5">');
    doc.writeln('<div style="font-size:18pt; font-family:verdana; font-weight:bold">');
    doc.writeln('    ' + charts[c][1]);
    doc.writeln('</div>');
    doc.writeln('<hr color="#000080">');
    doc.writeln('<div style="font-size:10pt; font-family:verdana; margin-bottom:20">');
    doc.writeln('    <a href="viewsource.pl?file=' + charts[c][0] + '">View Chart Source Code</a>');
    doc.writeln('</div>');
    if (charts[c][2] > 1)
    {
        for (var i = 0; i < charts[c][2]; ++i)
            doc.writeln('<img src="' + charts[c][0] + '?img=' + i + '">');
    }
    else
        doc.writeln('<img src="' + charts[c][0] + '">');
    doc.writeln('</body>');
    doc.close();
}
</script>
<style type="text/css">
p.demotitle {margin-top:1; margin-bottom:2; padding-left:1; font-family:verdana; font-weight:bold; font-size:9pt;}
p.demolink {margin-top:0; margin-bottom:0; padding-left:3; padding-top:2; padding-bottom:1; font-family:verdana; font-size:8pt;}
</style>
</head>
<body topmargin="0" leftmargin="0" rightmargin="0" marginwidth="0" marginheight="0">
<table width="100%" border="0" cellpadding="0" cellspacing="0" style="font-family:verdana; font-size:8pt;">
<script language="Javascript">
for (var c in charts)
{
    if (charts[c][1] == "")
        document.writeln('<tr><td><p class="demolink">&nbsp;</p></td></tr>');
    if (charts[c][0] == "")
        document.writeln('<tr><td colspan="2" bgcolor="#9999FF"><p class="demotitle">' + charts[c][1] + '</p></td></tr>');
    else
    {
        document.write('<tr valign="top"><td><p class="demolink">&#8226;</p></td><td><p class="demolink">');
        if (charts[c][2] > 0)
            document.write('<a href="javascript:;" onclick="setChart(\\'' + c + '\\');">');
        else if (charts[c][2] == 0)
               document.write('<a href="' + charts[c][0] + '" target="indexright">');
        else
               document.write(charts[c][0]);
           document.write(charts[c][1]);
           document.writeln('</a></p></td></tr>');
    }
}
</script>
</table>
</body>
</html>
EndOfHTML
;

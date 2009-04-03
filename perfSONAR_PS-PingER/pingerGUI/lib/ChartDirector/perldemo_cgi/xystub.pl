#!/usr/bin/perl

# Get HTTP query parameters
use CGI;
my $query = new CGI;

print "Content-type: text/html\n\n";
print <<EndOfHTML
<html>
<body topmargin="5" leftmargin="5" rightmargin="0" marginwidth="5" marginheight="5">
<div style="font-size:18pt; font-family:verdana; font-weight:bold">
    Simple Clickable XY Chart Handler
</div>
<hr color="#000080">
<div style="font-size:10pt; font-family:verdana; margin-bottom:20">
    <a href="viewsource.pl?file=$ENV{"SCRIPT_NAME"}">View Source Code</a>
</div>
<div style="font-size:10pt; font-family:verdana;">
<b>You have clicked on the following chart element :</b><br>
<ul>
    <li>Data Set : @{[$query->param("dataSetName")]}</li>
    <li>X Position : @{[$query->param("x")]}</li>
    <li>X Label : @{[$query->param("xLabel")]}</li>
    <li>Data Value : @{[$query->param("value")]}</li>
</ul>
</body>
</html>
EndOfHTML
;

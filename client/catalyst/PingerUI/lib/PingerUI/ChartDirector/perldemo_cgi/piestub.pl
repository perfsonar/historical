#!/usr/bin/perl

# Get HTTP query parameters
use CGI;
my $query = new CGI;

print "Content-type: text/html\n\n";
print <<EndOfHTML
<html>
<body topmargin="5" leftmargin="5" rightmargin="0" marginwidth="5" marginheight="5">
<div style="font-size:18pt; font-family:verdana; font-weight:bold">
    Simple Clickable Pie Chart Handler
</div>
<hr color="#000080">
<div style="font-size:10pt; font-family:verdana; margin-bottom:20">
    <a href="viewsource.pl?file=$ENV{"SCRIPT_NAME"}">View Source Code</a>
</div>
<div style="font-size:10pt; font-family:verdana;">
<b>You have clicked on the following sector :</b><br>
<ul>
    <li>Sector Number : @{[$query->param("sector")]}</li>
    <li>Sector Name : @{[$query->param("label")]}</li>
    <li>Sector Value : @{[$query->param("value")]}</li>
    <li>Sector Percentage : @{[$query->param("percent")]}%</li>
</ul>
</body>
</html>
EndOfHTML
;

#!/usr/bin/perl -w

use strict;
use warnings;
use CGI;
use XML::Twig;

use lib "/usr/local/DCN_LS/merge/lib";
use perfSONAR_PS::Client::DCN;

my $cgi = new CGI;
if ( $cgi->param('dcn') and $cgi->param('ts') ) {
  my $dcn = new perfSONAR_PS::Client::DCN(
    { instance => $cgi->param('dcn') }
  );
  my $result = $dcn->queryTS( { topology => $cgi->param('ts') } );
  my $t= XML::Twig->new;
  $t->parse($result->{response});
  print "Content-type: text/xml\n\n";
  print $t->toString;
}
else {
  print "Content-type: text/html\n\n";
  print "<html><head><title>DCN Topology Display</title></head>";
  print "<body><h2 align=\"center\">Error in topology display.</h2></body></html>";
}

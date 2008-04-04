#!/usr/bin/perl -w

use strict;
use warnings;

while(<>) {
  chop;
  if ($_ =~ m/<inlineschema /) {
    my ($fn) = m/"(.*)"/;
    open F, "< $fn";
    print "\# Begin Schema\n\n";
    while(<F>) {
      print $_;
    }
    print "\n\# End Schema\n";
  }
  elsif ($_ =~ m/<inlinexml /) {
    my ($fn) = m/"(.*)"/;
    open F, "< $fn";
    print "<!-- Begin XML -->\n\n";
    while(<F>) {
      print $_;
    }
    print "\n<!-- End XML -->\n";
  }
  elsif ($_ =~ m/<inline /) {
    my ($fn) = m/"(.*)"/;
    open F, "< $fn";
    print "\# Begin \n\n";
    while(<F>) {
      print $_;
    }
    print "\n\# End \n";
  }
  else { 
    print "$_\n"; 
  }
}


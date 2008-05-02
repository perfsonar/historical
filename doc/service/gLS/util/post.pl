#!/usr/bin/perl -w

use strict;
use warnings;

my $flag = 0;
while(<>) {
  chop;
  
  if( $_ =~ m/^\# Begin Schema/ or $_ =~ m/^<!-- Begin Schema/ ) {
    $flag = 1;
  }

  if ( $flag == 1 ) {

    if($_ =~ m/^\s*\#.*/) {
      print "<font color=red>" , $_ , "</font>\n";
    }
    elsif($_ =~ m/^.*=.*/) {
      print "<font color=orange>" , $_ , "</font>\n";
    }
    else {
      # syntax hightly these ...
      my @keywords = ('element', 'include', 'grammar');
      
      # and the next word after these...
      my @keywords_next = ('element');
      
      # tokenize the string, get rid of the crap first
      my $test = $_;
      $test =~ s/^\s*//;
      $test =~ s/\s*$//;
      $test =~ s/\n$//;
      
      # make sure we get the correct number of indent spaces
      my $prefix = "";
      my @things = split(/ /,$_);
      foreach my $t (@things) {
        if(!$t) {
          $prefix = $prefix . " ";
        }
      }
      
      # split and see if we match a token
      my @tokens = split(/ /, $test);
      my $found = 0;
      my $keyword = "";	
      foreach my $k (@keywords) {
	      foreach my $t (@tokens) {
	        if($k eq $t) {
	          $found = 1;
	          $keyword = $k;
	          last;
	        }
        }  	
      }
      
      if($found) {     
	      # we found a token, print it and see if we
	      # need to highlight the next word
	      print $prefix , "<font color=green>" , $tokens[0] , "</font> ";   
	
	      if($#tokens > 1) {
          my $found2 = 0;	
          foreach my $k (@keywords_next) {
	          if($k eq $keyword) {
	            $found2 = 1;
	            last;
	          }
          }	
	
	        if($found2) {
	  
	          # we can highlight the next word
	          print "<font color=blue>" , $tokens[1] , "</font> ";   	  
            for(my $x = 2; $x <= $#tokens; $x++) {
	            print $tokens[$x] , " ";
	          }
	        }
	        else {
            for(my $x = 1; $x <= $#tokens; $x++) {
	            print $tokens[$x] , " ";
	          }
	        }
	
	      }
	      else {
          for(my $x = 1; $x <= $#tokens; $x++) {
	          print $tokens[$x] , " ";
	        }
	      }
	
	      print "\n";
      }
      else {
        print $_ , "\n";
      }
    }    
  }
  else {
    print $_ , "\n";
  }
  
  if($_ =~ m/^\# End Schema/ or $_ =~ m/^<!-- End Schema/) {
    $flag = 0;
  }  

}

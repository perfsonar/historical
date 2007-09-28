package TimeUtils;
use strict;
###############################################################################
#
# MPG, maxim@fnal.gov
# Fermilab, Batavia, IL
############################################################################### 
use Exporter;
use vars qw(@ISA @EXPORT_OK  &check_time  &message_html  &die_html &max &min   &fix_regexp);
@ISA = qw(Exporter);
@EXPORT_OK = qw( &check_time  &message_html  &die_html &max &min  &fix_regexp  );
use Time::Local;
use CGI qw(:standard);

use PingerConf qw(%mn2nm  $dbh $debug);




#  time conversion module  -- all input from web form -- returns time window in seconds

 

sub check_time {
  my($start_sec, $start_min, $start_hr, $start_day, $start_month, $start_year,
     $end_sec, $end_min, $end_hr, $end_day, $end_month, $end_year, $gmt_off) = @_;
 $start_year -= 1900;
 $end_year -= 1900;
 (my $ret_gmt = $gmt_off) =~ s/(curr)?//;
 if($ret_gmt && $ret_gmt > 0) {
     $ret_gmt = 'GMT+' . $ret_gmt ;
 } else {
      $ret_gmt = 'GMT' . $ret_gmt;
 }
 $gmt_off =~ s/(curr)?//g;
 $gmt_off = 0 unless $gmt_off;
 
 return undef  unless my $tm_s = timegm($start_sec, $start_min, $start_hr , $start_day, $mn2nm{$start_month},  $start_year );
 return undef  unless my $tm_d = timegm($end_sec, $end_min, $end_hr , $end_day, $mn2nm{$end_month},   $end_year ); 
  if($gmt_off) {
   $gmt_off *= 3600;
  # $tm_s += $gmt_off;
  # $tm_d += $gmt_off;
 }
  print " GMT = $gmt_off $tm_s $tm_d <br>" if $debug;
  return ($tm_s, $tm_d,  $gmt_off, $ret_gmt);
}
#
#   graceful exit
#
sub die_html {
  my $string  = shift;
  $dbh->disconnect if $dbh;
  print p(" !!! $string  !!!"), end_html();
  message_html(" Some error occurred: $string ");
  die;
   
}
#
#    some message to to webpage
#
sub message_html {
   my $mess = shift;
   
   warn " $mess";

}
#
#     maximum function
#
sub max {
  return   $_[0] > $_[1] ? $_[0] : $_[1]; 
}
#
#  minimum  function
#
sub min {
  return  $_[0] < $_[1] ? $_[0] : $_[1] ;

}
#
#   fixing regular expression for link names from list_pars.txt file
#
sub fix_regexp {
  my $reg_exp = shift;
   unless($reg_exp) {
      return undef;
    }

    #escape all meta characters
    $reg_exp =~ s/([^A-Za-z0-9_])/\\$1/g;

    #except for *, translate it to .*
    $reg_exp =~ s/(\\\*)/\.\*/g;
    $reg_exp =~ s/(\\)([\^\$])/$2/g;
    return $reg_exp;
}



1;


=pod

=head1 NAME

     
     TimeUtils  - package with several auxiliary functions

=head1 DESCRIPTION

       
     TimeUtils  module is supplemental for graph_pings_gd.pl CGI script
         

=head1 SYNOPSIS

       
     use TimeUtils qw(&check_time  &message_html  &die_html &max &min  &fix_regexp);
       
       
       $max = max(arg1,arg2) -  returns maximum of two variables  
       
       $min = min(arg1,arg2) -  returns minimum of two variables  
       
       ($time_start, $time_end,  $gmt_off, $printable_gmt) = 
       check_time($start_sec, $start_min, $start_hr, $start_day, $start_month, $start_year,
                  $end_sec, $end_min, $end_hr, $end_day, $end_month, $end_year, $gmt_off)  -  returns 
       starting wnd finishing times in seconds for MySQL query and GMT offset 
      
       message_html($message) - prints message on the webpage
        
       die_html($message) - prints message on the webpage and gracefully dies
      
       $fixed_regexp = fix_regexp($reg_exp) - returns fixed regular expression
       
       


=head1   AUTHOR

    MPG, 2001
    Documented by MPG   11/7/01

=head1 BUGS

    Hopefully None

=head1 DEPENDENCIES

  
    Time::Local 
    Apache::Reload 
    CGI qw(:standard) 
    PingerConf qw(%mn2nm  $dbh  $debug) 
   
=head1 LICENSE

 Fermitools Software Legal Information (Modified BSD License)

 COPYRIGHT STATUS: Dec 1st 2001, Fermi National Accelerator Laboratory (FNAL) documents 
 and software are sponsored by the U.S. Department of Energy under Contract No. DE-AC02-76CH03000. 
 Therefore, the U.S. Government retains a world-wide non-exclusive, royalty-free license to 
 publish or reproduce these documents and software for U.S. Government purposes. 
 All documents and software available from this server are protected under the U.S. and 
 Foreign Copyright Laws, and FNAL reserves all rights.

    * Distribution of the software available from this server is free of charge subject to 
    the user following the terms of the Fermitools Software Legal Information.

    * Redistribution and/or modification of the software shall be accompanied by the
     Fermitools Software Legal Information (including the copyright notice).

    * The user is asked to feed back problems, benefits, and/or suggestions about the 
    software to the Fermilab Software Providers.

    * Neither the name of Fermilab, the FRA, nor the names of the contributors may be used
     to endorse or promote products derived from this software without specific prior written permission.

 DISCLAIMER OF LIABILITY (BSD): THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
  IN NO EVENT SHALL FERMILAB, OR THE FRA, OR THE U.S. DEPARTMENT of ENERGY, OR CONTRIBUTORS 
  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
   WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING 
   IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 Liabilities of the Government: This software is provided by FRA, independent from its 
 Prime Contract with the U.S. Department of Energy. FRA is acting independently from the 
 Government and in its own private capacity and is not acting on behalf of the U.S. Government,
  nor as its contractor nor its agent. Correspondingly, it is understood and agreed that 
  the U.S. Government has no connection to this software and in no manner whatsoever shall 
  be liable for nor assume any responsibility or obligation for any claim, cost, or damages 
  arising out of or resulting from the use of the software available from this server.

 Export Control: All documents and software available from this server are subject to 
 U.S. export control laws. Anyone downloading information from this server is obligated 
 to secure any necessary Government licenses before exporting documents or software 
 obtained from this server.    
   

=cut


package TimeUtils;
use strict;
use Exporter ();

=head1 NAME

     
     TimeUtils  - package with few  auxiliary functions

=head1 DESCRIPTION

       
     TimeUtils  module is supplemental for pignerGUI  CGI script
         

=head1 SYNOPSIS

       
     use TimeUtils qw(&check_time   &max &min  );
        
=head1 EXPORTED


=cut
       
use base Exporter;
 
our @EXPORT_OK = qw(check_time  max min);
use Time::Local;
use English qw( -no_match_vars );
use POSIX qw(strftime); 
use PingerConf qw(%mn2nm $LOGGER);
 
 
=head2   check_time 

  time conversion module  -- all input from web form -- returns time window in seconds

=cut

sub check_time {
    my( $start_hour, $start_day, $start_month, $start_year,
        $end_hour, $end_day, $end_month, $end_year, $gmt_off) = @_;
     
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
    my($tm_s, $tm_d);
    eval {
        $tm_s = timegm(0, 0, $start_hour , $start_day, $mn2nm{$start_month},  $start_year );
        $tm_d = timegm(59, 59, $end_hour , $end_day, $mn2nm{$end_month},   $end_year ); 
    };
    if($EVAL_ERROR) {
        $LOGGER->logdie(" Bad argument for timegm ". $EVAL_ERROR);
    }
    if($gmt_off) {
        $gmt_off *= 3600;
    }
    return ($tm_s, $tm_d,  $gmt_off, $ret_gmt);
}

=head2
 
     maximum function

=cut

sub max {
  return   $_[0] > $_[1] ? $_[0] : $_[1]; 
}

=head2
 
   minimum  function

=cut

sub min {
  return  $_[0] < $_[1] ? $_[0] : $_[1] ;

}

 

1;

__END__


=head1   AUTHOR

    Maxim Grigoriev, 2001-2008 
 
=cut


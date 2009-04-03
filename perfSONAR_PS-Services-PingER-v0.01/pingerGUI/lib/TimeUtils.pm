package TimeUtils;
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '0.09';

=head1 NAME

     
     TimeUtils  - package with several auxiliary functions

=head1 DESCRIPTION

       
     TimeUtils  module is supplemental for graph_pings_gd.pl CGI script
      
=head1 EXPORTED 

=cut

use Exporter (); 
use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(check_time get_time_hash  max min);
use Time::Local; 
use POSIX qw(strftime);  
use Date::Manip;

use Log::Log4perl  qw(get_logger); 

our $LOGGER = get_logger(__PACKAGE__);

=head2 get_time_hash

  accepts time start and time end in epoch
  and returns time hash:
    $tm_hash{start_month}
    $tm_hash{end_month}
    $tm_hash{start_year}
    $tm_hash{end_year}
    $tm_hash{start_day}
    $tm_hash{end_day} 

=cut

sub get_time_hash {
    my($tm_s, $tm_d) = @_;
    my %tm_hash;
    $tm_hash{start_month} =  strftime "%m", gmtime($tm_s);
    $tm_hash{end_month} = strftime "%m", gmtime($tm_d);
    $tm_hash{start_year} =  strftime "%Y", gmtime($tm_s);
    $tm_hash{end_year} =  strftime "%Y", gmtime($tm_d);
    $tm_hash{start_day} = strftime "%d", gmtime($tm_s);
    $tm_hash{end_day} = strftime "%d", gmtime($tm_d);
    return \%tm_hash;
    
}

=head2 check_time 

    accepts  time start and time end as trings and GMT offset as string
    returns time start , time end as epoch and gmt as positive/negative offset in seconds 
    and GMT label with sign 
   
=cut


sub check_time {
    my( $start_time,  $end_time, $gmt_off) = @_;
     
    
    (my $ret_gmt = $gmt_off) =~ s/(curr)?//;
    if($ret_gmt && $ret_gmt > 0) {
        $ret_gmt = 'GMT+' . $ret_gmt ;
    } else {
        $ret_gmt = 'GMT' . $ret_gmt;
    }
    $gmt_off =~ s/(curr)?//g;
    $gmt_off = 0 unless $gmt_off;
    if($gmt_off) {
        $gmt_off *= 3600;
    }  
    my($tm_s, $tm_d);
    eval {
        $tm_s = UnixDate(ParseDate(" $start_time") , "%s");
        $tm_d = UnixDate(ParseDate("$end_time"), "%s");
    };
    if($EVAL_ERROR) {
        $LOGGER->logdie("   ParseDate failed to parse: $start_time  $end_time". $EVAL_ERROR);
    }
   
    return ($tm_s, $tm_d,  $gmt_off, $ret_gmt);
}

=head2 max

    maximum function

=cut

sub max {
  return   $_[0] > $_[1] ? $_[0] : $_[1]; 
}

=head2 min

  minimum  function

=cut

sub min {
  return  $_[0] < $_[1] ? $_[0] : $_[1] ;

}




1;


__END__


=head1   AUTHOR

    Maxim Grigoriev, 2001-2008, maxim@fnal.gov
         

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 
 
   

=cut


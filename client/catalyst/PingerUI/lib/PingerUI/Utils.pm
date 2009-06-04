package PingerUI::Utils;
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '3.2';

=head1 NAME

     
    PingerUI::Utils  - package with several auxiliary functions

=head1 DESCRIPTION

       
   Utils  module is supplemental for  pigner gui
      
=head1 EXPORTED 

=cut

use Exporter (); 
use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(check_time   get_time_hash $SCRATCH_DIR $MYPATH max min $BUILD_IN_KEY validURL getURL  fix_regexp);
use Time::Local; 
use POSIX qw(strftime);  
use Date::Manip;

use Log::Log4perl  qw(get_logger); 

our $BUILD_IN_KEY = 'jh34587wuhlkh789hbyf78343gort03idjuhf3785t0gfgofbf78o4348orgofg7o4fg7';
our $MYPATH = '/home/netadmin/LHCOPN/perfSONAR-PS/trunk/client/catalyst/PingerUI';
our $SCRATCH_DIR =  '/tmp';


our $LOGGER = get_logger(__PACKAGE__);

=head2 validURL 

    parse Ma url, return  1 if URL is valid and undef otherwise

=cut

sub validURL {
    my ($remote_ma) = @_;
    return 0 unless $remote_ma;
    my ($server,$port,$endpoint) = $remote_ma =~ m/http:\/\/([^:\/]+):?(\d+)?(\/.+)$/is;
    return 1 if($server && $endpoint);
    return 0;
}
  
=head2 fix_regexp
 
   fixing regular expression for link names from list_pars.txt file

=cut

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
    
    return qr{$reg_exp};
}

=head2 getURL 
 
   get URL by the link ID from the stash

=cut
 
sub getURL {
   my ($stash, $link) = @_;
    # $c->log->debug(" Looking for MA URL:  $link  - \n", sub{Dumper($LINKS )});
   foreach my $url (keys %{$stash}) {
        return $url if($stash->{$url}{$link});
   }
   return;

}


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

    Maxim Grigoriev, 2001-2009, maxim@fnal.gov
         

=head1 COPYRIGHT

Copyright (c) 2009, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 
 
   

=cut


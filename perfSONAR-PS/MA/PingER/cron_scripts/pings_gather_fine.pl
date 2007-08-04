#! /usr/local/bin/perl 
# version 2.2
#
#   Redone for perl 5.005 and updated CGI.pm
#              by MPG, 2001
##########################################################################
# based on work done by Connie Logg and Les Cottrell at the Stanford Linear
# Accelerator Center
#
# usage: ping_gather.pl offset list
# This script will retrieve data for the last *offset* days (GMT time) from
# the URLs listed in the file *list*.
#
# makes heavy use of libww-perl-0.40 libraries
# for some wierd reason timelocal must be required before the www libraries
require "timelocal.pl";
use LWP::UserAgent;
use strict;
#use LWP::Authen::Basic;
use HTTP::Request;
use HTTP::Response;
 
use Fcntl;
use Carp;
use vars qw($opt_i   $opt_d   $opt_s  $opt_t $opt_h); 
use Getopt::Std;
getopts("hi:t:ds:");

$SIG{ALRM} =  sub{die "2 min timeout"};
select(STDOUT);
$| =1;



my $ping_data_dir = $opt_i;
my $minutes_back =   $opt_t?$opt_t:'60';
my $collecting_sites = $opt_s;
my $debug =   $opt_d;
my $now_time = time;
 
if (!$collecting_sites || !$ping_data_dir || $opt_h) {
   croak "Usage:: $0 [-d debug flag] [-s <filename> file with list of sites to gather pings] [-t <number> minutes back from now] [-i <filename> data dir name where to look for add-xxxx-xx.txt files] ";
} 
 
my $start_time = $now_time - (60 * $minutes_back);
 
open COLLECTING_SITES, $collecting_sites   or
  die "Can't open  $collecting_sites ";
my %zeroliner = ();
my %badsite = ();
my %goodsite = ();
 
my $timefm = "begin=$start_time&end=$now_time&in_form=1";

while (<COLLECTING_SITES>) {
  chomp;

  next if (/^#/);
  next if (!/^http/);
  my ($site) = split /\s/, $_;

#  $url = "$site?begin=$begin_start_day&end=$end_yesterday&in_form=1";
  
   my $url = "$site?$timefm";
  $url = "$site&$timefm" if $site =~ /\?/;
   
  print "$site is proccessing \n" if $debug;
  my $content = undef;
  eval  {
    alarm(120); # 2 minute per site 
    my $ua= LWP::UserAgent->new;
    $ua->agent("MOMspider/0.1 library");
    $ua->timeout('60');
    # define who we tell servers we are
   
    my $req = HTTP::Request->new(GET=> $url);
   
    my $response = $ua->request($req);
   
    if ($response->is_error()) {
       $badsite{$site} .=  "$site: " .  $response->status_line . "\n";  
    } else {
       $goodsite{$site} .=  "$site: http response - " . $response->status_line . "\n" ;
    }
   $content = $response->content();
   alarm(0)
   };
   if($@ && $@  =~ /timeout/) {
        $goodsite{$site}  .= " --- $site: 2 min timeout occured, check this site !!!\n";
    }
        
  my $lines = 0;
  # go through each line of response
  for (split(/\n/, $content)) {
    # get components of each line
   
    my ($src_name, $src_ip, $dest_name, $dest_ip, $ping_size, $time, $packets_sent , $packets_rcvd, $min, $avg, $max, @pckts) = split / /;
    # check to make sure everything is there. If not, skip it
    if (!defined $src_name || !defined $src_ip || !defined $dest_name || !defined $dest_ip 
        || !defined $ping_size || !defined $time || $src_name eq '' || $src_ip eq '' || $dest_name eq '' || !($ping_size > 0) || !($time >0)) {
       $badsite{$site}  .= "$site:   Bad line: $_\n";
       next;
    }

    if ($dest_ip eq '') {
       $dest_ip = '.';
    }

    if ($time <= 0) {
       $badsite{$site}  .= "$site:   Bad line: $_\n";
      next;
    }
    if($debug) {
      # log it to a file
     print " Logging: $src_name, $src_ip, $dest_name, $dest_ip, $ping_size, $time, $packets_sent , $packets_rcvd, $min, $avg, $max \n";
    } else {
     # log it to a file
      &log_it($src_name, $src_ip, $dest_name, $dest_ip, $ping_size, $time, $packets_sent , $packets_rcvd, $min, $avg, $max, @pckts) ;  
    }
    $lines++;
  }
  unless($lines) {
    $zeroliner{$site} = "$site:  0 lines \n";
  } else {
    $goodsite{$site} .=  "$site:  $lines lines retrieved\n \n ";  
  } 
}
  print " All sites were contacted with next parameters: \n";
  print " ++++   $timefm ++++ \n";
  print "###------------------  UNREACHABLE/BAD FORMAT  SITES ----------------###- \n";
   foreach my $bd (keys %badsite) {print $badsite{$bd};}
  print "###--------------------------- NO INFO SITES ------------------------###- \n";
   foreach my $bd (keys %zeroliner) {print $zeroliner{$bd} ;}
  print "###--------------------------   GOOD SITES --------------------------###- \n";
   foreach my $bd (keys %goodsite) {print $goodsite{$bd};}
  
# this subroutine logs entries to the ping record file
# it opens the file exclusively so that other processes will have to wait until
# this write is finished
sub log_it {
  my ($src_name, $src_ip, $dest_name, $dest_ip, $ping_size, $time, $packets_sent, $packets_rcvd, $min, $avg, $max, @pckts) = @_;
 
  # figure out which file to open (of the format ping-YYYY-MM.txt)
  my ($sec, $minutes, $hour, $mday, $month, $year, $wday, $yday, $isdst) = gmtime($time);
  $month++;
  $year += 1900;
  if ($year <1990) {
    print "Bad year: $year \n";
    return;
  }
  my($ping_data_fn) = sprintf "%s/add-ping-%4d-%2.2d\.txt", $ping_data_dir, $year, $month;

  # try to open the file assuming it exists (this will be true most of
  # the time, so we try it first)
  if (!sysopen PINGDATA, $ping_data_fn, O_RDWR | O_EXCL | O_APPEND) {

    # file doesn't exist, so try creating it
    if (!(sysopen(PINGDATA, $ping_data_fn, (O_RDWR | O_EXCL | O_CREAT)))) {

      # file appeared sometime between the first and second sysopen calls,
      # try opening it again
      if (!sysopen PINGDATA, $ping_data_fn, O_RDWR | O_EXCL | O_APPEND){

	print STDERR "Can't open $ping_data_fn: $!\n";
	return -1; # return error code
      }
    }
  }

  print PINGDATA "$src_name $src_ip $dest_name $dest_ip $ping_size $time ";
    if (defined $packets_sent) {
    print PINGDATA "$packets_sent $packets_rcvd ";
    if ($packets_rcvd && $packets_rcvd > 0) {
      print PINGDATA "$min $avg $max ", join " ", @pckts; 
    }
  }

  print PINGDATA "\n";

  close(PINGDATA);
  return 0;
} # end of log_it subroutine

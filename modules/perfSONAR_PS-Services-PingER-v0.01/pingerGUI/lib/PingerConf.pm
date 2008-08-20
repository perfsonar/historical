package PingerConf;
 
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '0.09'; 


=head1 NAME

     
     PingerConf  - main config module

=head1 DESCRIPTION

       loads config parameters from the 'etc/GeneralSystem.conf', sets defaults, major helper functions 
   

=head1 SYNOPSIS

       
       use PingerConf qw( %GENERAL_CONFIG $LOGGER $COOKIE $SESSION $CGI $PARAMS $REMOTE_MA $MENU BASEDIR $LINKS  get_links  set_defaults
 	                 %Y_label %legends $build_in_key  storeSESSION  get_data updateParams updateMenu fix_regexp ) 
        
=head1 EXPORTED 


=cut

use CGI::Carp;
use CGI qw/:standard/;
use CGI::Session; 
use FindBin qw($Bin);
use lib "$Bin/../../lib";
use Config::Interactive; 
use File::Path qw(mkpath);
use POSIX qw(strftime);
use perfSONAR_PS::Client::PingER;
use perfSONAR_PS::ParameterValidation;
use Data::Dumper; 
use Log::Log4perl  qw(:easy);
 
use Exporter ();
use base 'Exporter';  
 
our @EXPORT    = qw();
our @EXPORT_OK = qw(%GENERAL_CONFIG $LOGGER $COOKIE $SESSION $CGI $PARAMS $REMOTE_MA $MENU BASEDIR $LINKS  get_links  set_defaults
 	                 %Y_label %legends $build_in_key   storeSESSION  get_data updateParams updateMenu fix_regexp);     
 
our (%GENERAL_CONFIG, $CGI, $COOKIE, %Y_label,   $SESSION,  %legends, $PARAMS, $LINKS, $MENU, $REMOTE_MA,  $LOGGER); 
 
use constant BASEDIR => "$Bin/..";
 
   
# legends fro different graphs
%legends = (
               rt   =>  "Average RTT (ms)",
               loss =>  "Percentage of Packets Loss", 
	       wb   =>  "Calculated TCP troughput",
	       clp =>   "Conditional Packets Loss",
	       ipdv =>  "mean IPD delay",
	       iqr =>  "InterQuantile IPD",
	       dupl =>  "Indicator of reorderd/duplicated packets"     	        
	      );
# OY labels  
%Y_label = (
                rt     => 'ms',
                loss   => '%',      
	        rtloss => 'ms %',
	        wb     => 'Kbps',
		ipdv   =>  'ms',
		dupl   =>  'N per 10 packets'
	       );
	       
######   config	       
my $CONFIG_FILE = BASEDIR . '/etc/GeneralSystem.conf';     		
my $conf_obj =  new Config::Interactive( {file =>   $CONFIG_FILE } );
$conf_obj->parse;
%GENERAL_CONFIG  =  %{$conf_obj->getNormalizedData};

my $level = $DEBUG;
# $level =  $GENERAL_CONFIG{log_level} if $GENERAL_CONFIG{log_level};
 
Log::Log4perl->easy_init($level);
$LOGGER = get_logger("pingerUI");
$LOGGER->debug(Dumper $conf_obj->getNormalizedData);
 
$CGI =   CGI->new();
our $build_in_key = 'jh34587wuhlkh789hbyf78343gort03idjuhf3785t0gfgofbf78o4348orgofg7o4fg7';

$GENERAL_CONFIG{scratch_dir} = '/tmp' unless  -d $GENERAL_CONFIG{scratch_dir};
unless($CGI->param &&   $CGI->param('get_it') && $CGI->param('get_it') eq $build_in_key) {
    $SESSION =  new CGI::Session("driver:File;serializer:Storable",  $CGI, {Directory =>  $GENERAL_CONFIG{scratch_dir}}); ## to keep our session 
    $COOKIE =   $CGI->cookie(CGISESSID => $SESSION->id);
    $COOKIE->path('/gui-bin/');
    unless($SESSION  && !$SESSION->is_expired && $SESSION->param( "LINKS" )) {
	 ($LINKS, $MENU, $REMOTE_MA, $PARAMS) = set_defaults(); 
	 storeSESSION();   
    }   else {
        $LOGGER->debug("found session ", Dumper $REMOTE_MA);
    }
    ($LINKS, $MENU, $REMOTE_MA, $PARAMS) = ($SESSION->param( "LINKS" ), $SESSION->param( "MENU" ), $SESSION->param( "REMOTE_MA" ), $SESSION->param( "PARAMS" ));
}
mkpath([ "$GENERAL_CONFIG{scratch_dir}/$GENERAL_CONFIG{gout_dir}"],1,0755)  unless -d  "$GENERAL_CONFIG{scratch_dir}/$GENERAL_CONFIG{gout_dir}";

=head2 storeSESSION
 
    store current session params
    
=cut    
    
sub storeSESSION {
   $SESSION->param("MENU", $MENU);
   $SESSION->param("LINKS", $LINKS );
   $SESSION->param("REMOTE_MA",  $REMOTE_MA );
   $SESSION->param("PARAMS",  $PARAMS );  
}   
 
=head2 set_defaults

   set session data structures with default values

=cut

sub set_defaults {
    my $links = {};
    my $menu = {src_regexp => '*', dst_regexp => '*', packetsize => '*'};
    my $remote_ma = {ma_urls =>  ''};
    my $params = {};
    # list the months, with $start_default_month the default
    
    my (@times_gmt,@rtt_times);   
    for(my $i=-12;$i<13;$i++) {    
        push @times_gmt, ($i?{gmt_time => $i . '"', gmt_time_label => ($i<0?'GMT' . $i:'GMT+' . $i)}:{gmt_time => 'curr" SELECTED', gmt_time_label => 'GMT'});
    }	
    for(my $i= 50;$i<1000;$i+=50) {    
        push @rtt_times, { rtt_time => $i . '"', rtt_time_label => "$i ms"};
    }	 
    push @rtt_times,  { rtt_time => 'auto" SELECTED', rtt_time_label => "Auto"};
    $params->{gmt_options}  = \@times_gmt;
    $params->{rt_times}  = \@rtt_times; 
    $LOGGER->debug( 'links: ' . Dumper($links) . "\n menu: " . Dumper($menu) . "\n remote_ma: " . Dumper($remote_ma) . "\n params: " . Dumper($params));
    return $links, $menu, $remote_ma, $params;
}

=head2 updateParams 

  update $PARAMS ans store into the session   

=cut

sub updateParams {
    my (  @args  ) = @_;
    my $parameters = validateParams( @args, {start_time => 1, end_time => 1, gmt_offset => 0, upper_rt => 0} );
      
      # list the months, with $start_default_month the default
     
    foreach my $gmt (@{$PARAMS->{gmt_options}}) {
        if($parameters->{gmt_offset} && $gmt->{gmt_time} eq $parameters->{gmt_offset} ) {
	    $gmt->{gmt_time}  .=    ' SELECTED';
        } else {
	    $gmt->{gmt_time}  =~ s/ SELECTED//;
        }    
    }
    foreach my $upr (@{$PARAMS->{rt_times}}) {
        if($parameters->{upper_rt} && $upr->{rtt_time} eq $parameters->{upper_rt} ) {
	    $upr->{rtt_time}  .=    ' SELECTED';
        } else {
	    $upr->{rtt_time}  =~ s/ SELECTED//;
        }    
    }
    storeSESSION(); 
    return;
}

=head2 updateMenu

  update $MENU ans store into the session   

=cut

sub updateMenu {
    my (  @args  ) = @_;
    my $parameters = validateParams( @args, {  src_regexp => 0,   dst_regexp => 0,  packetsize  => 0, ma_urls => 0} );
    
    foreach my $param (qw/src_regexp dst_regexp packetsize/) {
        if($parameters->{$param}) {     
            $MENU->{$param} = $parameters->{$param};
	    $parameters->{$param} =  fix_regexp( $parameters->{$param} );
	    $LOGGER->debug(' $param : ' . $parameters->{$param} );
	}
    }    
    my @links = ();
    $REMOTE_MA->{ma_urls} =  $parameters->{ma_urls}  if($parameters->{ma_urls});
    my @ma_url_array = split /\s+/,  $REMOTE_MA->{ma_urls};
    $LOGGER->debug('URLS: ' . Dumper \@ma_url_array);
    my $got_links = get_links({remote_ma => \@ma_url_array, src_regexp =>  $parameters->{src_regexp},  dst_regexp =>  $parameters->{dst_regexp}, packetsize  =>   $parameters->{packetsize}});
    unless(ref $got_links eq 'HASH') {
        $LOGGER->error(" Failed to retrieve links from MAs:" . (join "\n", @ma_url_array));
	return { links => [ { meta_link  => 'foo',  meta_link_label => "NO Metadata: $got_links" }]};
    }
    foreach my $link (keys %{$got_links}) {         
         push @links, {meta_link =>  "$link", meta_link_label => $got_links->{$link}{src_name}  ." -&gt; ". $got_links->{$link}{dst_name}." (".  $got_links->{$link}{packetSize}  . ")\n"};
    }  
    
    storeSESSION(); 
    return  {links => \@links}; 
}

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

=head2  get_links
  
   get metaids ( links ) from remote ma

=cut

sub get_links {
    my (  @args  ) = @_;
    #  start a transport agent
    
    my $parameters = validateParams( @args, { remote_ma => 1, src_regexp => 0, dst_regexp => 0,  packetsize  => 0 } );
    my $param = {};
    $param = { parameters => { packetSize => $parameters->{packetsize}} } if $parameters->{packetsize} && $parameters->{packetsize} =~ /^\d+$/;
    my %truncated = ();   
    foreach my $url (@{$parameters->{remote_ma}}) {  
        my $remote_links = {};
        unless(validURL($url)) {
	    $LOGGER->warn(" Malformed remote MA URL: $url ");
	    next;
	}
	if($LINKS && $LINKS->{$url} && ref  $LINKS->{$url} eq 'HASH') {
            $remote_links = $LINKS->{$url};
	} else {
	    my $metaids = {};
	    eval {
                my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
	        #$LOGGER->debug(' MA connected: ' . Dumper $ma);
                my $result = $ma->metadataKeyRequest($param);
	        #$LOGGER->debug(' result from ma: ' . Dumper $result); 
	        $metaids = $ma->getMetaData($result);
	    };
	    if($EVAL_ERROR) {
	       $LOGGER->error(" Problem with MA $EVAL_ERROR ");
	        return  "  Problem with MA $EVAL_ERROR";
	    
	    }
           # $LOGGER->debug(' Metaids: ' . Dumper $metaids);
            foreach  my $meta  (keys %{$metaids}) {
               $LINKS->{$url}{$meta} =  $metaids->{$meta} unless   $LINKS->{$url}{$meta}; 
            }
	    $remote_links =  $metaids;
	}  
	foreach my $meta  (keys %{$remote_links}) {
	    $truncated{$meta} = $remote_links->{$meta} if ((!$parameters->{src_regexp} ||  $remote_links->{$meta}->{src_name}  =~ $parameters->{src_regexp}) &&
							   (!$parameters->{dst_regexp} ||  $remote_links->{$meta}->{dst_name}  =~ $parameters->{dst_regexp}) &&
							   (!$parameters->{packetize} ||  $remote_links->{$meta}->{packetSize} =~ $parameters->{packetsize}) 
							  );	    
	}	
    } 
    return \%truncated;
}  

=head2 get_data
 
  get  data fir the array of links and time range ( start / end )

=cut


sub get_data {
    my (  @args  ) = @_;
    #  start a transport agent    
    my $param = validateParams( @args, {   link => 1, start  => 0, end => 0 } );
    my $link = $param->{link};
    my $url =  getURL($link);
    $LOGGER->logdie(" Malformed remote MA URL: $url ") unless  validURL($url);
    my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
    
    my $dresult = $ma->setupDataRequest( { 
    	 start =>  $param->{start}, 
	 cf => 'AVERAGE',
	 resolution => '100',
    	 end =>    $param->{end}, 
    	 keys =>   $LINKS->{$url}{$link}{keys},
       });    
     my $metaids    = $ma->getData($dresult);   
     my @data =();
     foreach my $key_id  (keys %{$metaids}) {
	foreach my $id ( keys %{$metaids->{$key_id}{data}}) {
	   foreach my $timev   (sort {$a <=> $b} keys %{$metaids->{$key_id}{data}{$id}}) {
	            push   @data,  [$timev ,  $metaids->{$key_id}{data}{$id}{$timev}];
	    }  
	   
	 } 
      }
     $LINKS->{$url}{$link}{data} = \@data;    
     return \@data;
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
#
#   get URL by the link ID
# 
sub getURL {
   my ($link) = @_;
   foreach my $url (keys %{$LINKS}) {
     return $url if($LINKS->{$url}{$link});
   }
   return;

}


1;

__END__
 
=head1   AUTHOR

    Maxim Grigoriev, 2001-2008, maxim_at_fnal.gov
         

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 
    

=cut











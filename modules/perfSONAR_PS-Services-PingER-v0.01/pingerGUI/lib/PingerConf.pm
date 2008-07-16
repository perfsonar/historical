package PingerConf;
use warnings;
use strict;

=head1 NAME

     
     PingerConf  - main config module

=head1 DESCRIPTION

       loads config parameters from the 'etc/GeneralSystem.conf' , provides helper subs
   

=head1 SYNOPSIS

       
       use PingerConf qw(%GENERAL_CONFIG  BASEDIR $CGI $LINKS  $PARAMS $MENU $SESSION $COOKIE $REMOTE_MA  $LOGGER get_links  
                     &defaults get_data updateParams updateMenu storeSESSION) 
       
        
        See inline documentation for description of each parameter 


=head1 EXPORTED
       
=cut

use FindBin qw($Bin);
use lib "$Bin/../lib";
 
use CGI::Carp;
use CGI qw/:standard/;
use CGI::Session; 
 
use Config::Interactive; 
use File::Path qw(mkpath);
use POSIX qw(strftime);
use perfSONAR_PS::Client::PingER;
use perfSONAR_PS::ParameterValidation;
use Data::Dumper;
use English qw( -no_match_vars );

use Log::Log4perl  qw(:easy);

BEGIN {
        use Exporter ();
        use base 'Exporter';  
        our ($VERSION,  @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
      
     
        # if using RCS/CVS, this may be preferred
        $VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)/g;
        # set the version for version checking
        $VERSION     ||= 1.00;
       
        @EXPORT      = qw( );
        %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
                        
        # your exported package globals go here,
        # as well as any optionally exported functions
        @EXPORT_OK   = qw(   %GENERAL_CONFIG $LOGGER  $COOKIE $SESSION $CGI $PARAMS $REMOTE_MA $MENU BASEDIR $LINKS  get_links  defaults
	         %Y_label %legends  %mn2nm  &storeSESSION %selection get_data updateParams updateMenu fix_regexp);     
                   
};

our (@EXPORT_OK, %GENERAL_CONFIG, $CGI, $COOKIE, %Y_label, %selection,  $SESSION,  %legends,$PARAMS, $LINKS, $MENU, $REMOTE_MA, %mn2nm, $LOGGER); 
 
use constant BASEDIR => "$Bin/../lib";
 
=head2  %mn2nm

    Month to number lookup

=cut


%mn2nm = (         "Jan" => 0,
		   "Feb" => 1,
		   "Mar"=> 2,
		   "Apr"=> 3,
		   "May"=> 4,
		   "Jun"=> 5,
		   "Jul"=> 6,
		   "Aug"=> 7,
		   "Sep"=> 8,
		   "Oct"=> 9,
		   "Nov"=> 10,
		   "Dec"=> 11    
        ); 
	
=head2 %selection

  if you planning to have logs then you can see it there 
  month name --> number conversion hash 

=cut

%selection = (
    rt   => 'minRtt, meanRtt, maxRtt, ',
    loss => 'lossPercent, clp, ',
    rtloss => ' lossPercent, clp, meanRtt, ',
    ipdv   => 'minIpd, meanIpd, maxIpd, iqrIpd, ',
    dupl => 'duplicates, ',
    all =>
        ' lossPercent,  minRtt, meanRtt, maxRtt, minIpd,  meanIpd, maxIpd, duplicates,'
);
 
=head2   %legends 

legends fro different graphs

=cut

%legends = (
               rt   =>  "Average RTT (ms)",
               loss =>  "Percentage of Packets Loss", 
	       wb   =>  "Calculated TCP troughput",
	       clp =>   "Conditional Packets Loss",
	       ipdv =>  "mean IPD delay",
	       iqr =>  "InterQuantile IPD",
	       dupl =>  "Indicator of reorderd/duplicated packets"     	        
	      );
	      
=head2  %Y_label 

  OY labels  

=cut

%Y_label = (
                rt     => 'ms',
                loss   => '%',      
	        rtloss => 'ms %',
	        wb     => 'Kbps',
		ipdv   =>  'ms',
		dupl   =>  'N per 10 packets'
	       );

# time related defaults
my %months = reverse %mn2nm;
my $year = strftime "%Y", gmtime(time);
my %boundaries = (hour => [0,23], day => [1, 31], month => [0,11], year => [1998, $year]);
######   config	       
my $CONFIG_FILE = BASEDIR . '/etc/GeneralSystem.conf';     		
my $conf_obj =  new Config::Interactive( {file =>   $CONFIG_FILE } );
$conf_obj->parse;

=head2 %GENERAL_CONFIG 

    normalized configuration structure

=cut

%GENERAL_CONFIG  =  %{$conf_obj->getNormalizedData};

my $level = $INFO;
# $level =  $GENERAL_CONFIG{log_level} if $GENERAL_CONFIG{log_level};
 
Log::Log4perl->easy_init($level);
$LOGGER = get_logger("pingerUI");
$LOGGER->debug(Dumper $conf_obj->getNormalizedData);
 
$CGI =   CGI->new();

$GENERAL_CONFIG{scratch_dir} = '/tmp' unless  -d $GENERAL_CONFIG{scratch_dir};
$SESSION =  new CGI::Session("driver:File;serializer:Storable",  $CGI, {Directory =>  $GENERAL_CONFIG{scratch_dir}}); ## to keep our session 
$COOKIE =   $CGI->cookie(CGISESSID => $SESSION->id);
$COOKIE->path('/pinger/');
unless($SESSION  && !$SESSION->is_expired && $SESSION->param( "LINKS" )) {
     ($LINKS, $MENU, $REMOTE_MA, $PARAMS) = defaults(); 
     storeSESSION();   
}  
($LINKS, $MENU, $REMOTE_MA, $PARAMS) = ($SESSION->param( "LINKS" ), $SESSION->param( "MENU" ), $SESSION->param( "REMOTE_MA" ), $SESSION->param( "PARAMS" ));
 

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

=head2   defaults 
 
    fill data structures with deafult values

=cut

sub defaults {
    my $links = {  };
    my $menu = {src_regexp => '*', dst_regexp => '*', packetsize => '*'};
    my $remote_ma = {ma_urls =>  'http://lhcopnmon1-mgm.fnal.gov:8075/perfSONAR_PS/services/pinger/ma'};
    my $params = {};
    # list the months, with $start_default_month the default
   
    foreach my $when (qw/From To/) {
        my @date_parts = ();    
        foreach my $type (qw/hour day month year/) {
            my @time_options = ();
            for(my $ik=$boundaries{$type}->[0] ;$ik <= $boundaries{$type}->[1]; $ik++)  {
	        my $tm = (($type eq 'month')?$months{$ik}:$ik);
		 
                push @time_options, { time_option => $tm . '"', time_option_label => $tm};
            } 
	    $time_options[$#time_options-1]->{time_option} = $time_options[$#time_options-1]->{time_option} . ' SELECTED';
	    push @date_parts, {when_type =>   "$when\:$type", time_options => \@time_options};  
        }
        push @{$params->{time_params}},  {'when' => $when, date_parts =>   \@date_parts}; 
    }
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

=head2  updateParams

    update data structure for params.tmpl template

=cut

sub updateParams {
    my (  @args  ) = @_;
    my $parameters = validateParams( @args, {from_hour => 1,from_day => 1,  from_month => 1, from_year => 1,
                                             to_hour => 1,  to_day => 1, to_month => 1, to_year => 1, gmt_offset => 0, upper_rt => 0} );
      
      # list the months, with $start_default_month the default
    
    foreach my $time_part (@{$PARAMS->{time_params}}) {
        my $when =   $time_part->{when};
        next unless  $when =~ /From|To/;
        my @date_parts =  @{$time_part->{date_parts}};  
	
	foreach my $type (@date_parts) {
	    
            my @time_options =  @{$type->{time_options}};
	    my $when_type = $type->{when_type};
	    my $id = "\l$when\_\l$when_type";
	    
            foreach my $tm (@time_options ) {
	        if($parameters->{$id} &&  $tm->{time_option_label} eq  $parameters->{$id}) {
	            $tm->{time_option} .= ' SELECTED';
		} else {
		    $tm->{time_option} =~ s/ SELECTED//;
		}    
            } 
        }     
    }
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

     update data structure for menu.tmpl template

=cut

sub updateMenu {
    my (  @args  ) = @_;
    my $parameters = validateParams( @args, {  src_regexp => 0,   dst_regexp => 0,  packetsize  => 0, ma_urls => 0} );
    
    foreach my $param (qw/src_regexp dst_regexp packetsize/) {
        if($parameters->{$param}) {     
            $MENU->{$param} = $parameters->{$param};
	    $parameters->{$param} = &fix_regexp( $parameters->{$param} );
	    $LOGGER->debug(' $param : ' . $parameters->{$param} );
	}
    }    
    my @links = ();
    $REMOTE_MA->{ma_urls} =  $parameters->{ma_urls}  if($parameters->{ma_urls});
    my @ma_url_array = split /\n/,  $REMOTE_MA->{ma_urls};
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
 
      get metadata ( links ) from remote ma

=cut

sub get_links {
    my (  @args  ) = @_;
    #  start a transport agent
    
    my $parameters = validateParams( @args, { remote_ma => 1, src_regexp => 0, dst_regexp => 0,  packetsize  => 0 } );
    my $param = {};
    $param = { parameters => { packetSize => $parameters->{packetsize}} } if $parameters->{packetsize} =~ /^\d+$/;
    my %truncated = ();   
    foreach my $url (@{$parameters->{remote_ma}}) {  
        my $remote_links = {};
	$LOGGER->logdie(" Malformed remote MA URL: $url ") unless validURL($url);
	if($LINKS && $LINKS->{$url} && ref  $LINKS->{$url} eq 'HASH') {
            $remote_links = $LINKS->{$url};
	} else {
	    my $metaids = {};
	    eval {
                my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
	        $LOGGER->debug(' MA connected: ' . Dumper $ma);
                my $result = $ma->metadataKeyRequest($param);
	        $LOGGER->debug(' result from ma: ' . Dumper $result); 
	        $metaids = $ma->getMetaData($result);
	    };
	    if($EVAL_ERROR) {
	       $LOGGER->error(" Problem with MA $EVAL_ERROR ");
	        return  "  Problem with MA $EVAL_ERROR";
	    
	    }
            $LOGGER->debug(' Metaids: ' . Dumper $metaids);
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
    storeSESSION(); 
    return \%truncated;
}
  
=head2 get_links 

    get  data for the array of links and time range ( start / end )

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
     storeSESSION(); 
     return \@data;
}

=head2  fix_regexp {
 
  fixing regular expression for link names  

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
  
     get remote MA URL by link id
     
=cut
 
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

    MPG, 2001-2008
 

=head1 BUGS

    Hopefully None

=cut











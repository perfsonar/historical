#!/usr/bin/perl 
#
# version 3.05 

=head1 NAME

     
     pingerUI.pl -   CGI script 

=head1 DESCRIPTION

       
       script for generating  PingER graphs on fly  for remote MAs, based on CGI::Ajax
       and HTML::Template
         
=cut

 
use FindBin qw($Bin);
use lib "$Bin/../lib";

use strict;
use warnings;

use Data::Dumper;
use HTML::Template;

use CGI::Ajax;
 
  
use PingerConf qw( %GENERAL_CONFIG  BASEDIR $CGI $LINKS  $PARAMS $MENU $SESSION $COOKIE $REMOTE_MA  $LOGGER get_links  
                     &defaults get_data updateParams updateMenu storeSESSION);
use TimeUtils qw(check_time); 
use GraphUtils_MA qw(build_graph); 
 
 
#### to make it interactive ( registering perl calls as javascript functions)
##      
my $ajax = CGI::Ajax->new(
    'displayGraph'  => \&displayGraph,
    'displayLinks' => \&displayLinks,
    'resetSession' => \&resetSESSION, 
);
   
 
my $ssid = sprintf("%d", 1E6*rand());
my $TEMPLATE_HEADER =  HTML::Template->new( filename =>   BASEDIR . $GENERAL_CONFIG{what_template_header} );
$TEMPLATE_HEADER->param(   'Title' => "PingER  GUI" );
my $TEMPLATE_FOOTER =  HTML::Template->new( filename => BASEDIR . $GENERAL_CONFIG{what_template_footer} );

my $myhtml =   $TEMPLATE_HEADER->output() . displayRemoteMA() . displayMenu()  . displayLinks()     . displayParams() .
               $TEMPLATE_FOOTER->output();    ##### get html
#$ajax->DEBUG(1);
#$ajax->JSDEBUG(1); 
print $ajax->build_html( $CGI, $myhtml,  {'-Expires' => '1d',   '-cookie' =>  $COOKIE}  );

#  reset session 
sub resetSESSION {
  ($LINKS, $MENU, $REMOTE_MA, $PARAMS) = defaults(); 
   storeSESSION();
   return (displayRemoteMA(), displayMenu(), '<div id="graph">&nbsp;</div>', displayLinks(), displayParams());
   
}  
 
sub displayRemoteMA{ 
    my $TEMPLATE  = HTML::Template->new(filename =>    BASEDIR . $GENERAL_CONFIG{what_template_remote_ma});
    $TEMPLATE->param(  $REMOTE_MA );    
    return $TEMPLATE->output();
}

sub displayMenu  {
    my $TEMPLATE= HTML::Template->new(filename =>    BASEDIR . $GENERAL_CONFIG{what_template_menu});    
    $TEMPLATE->param( $MENU );   
    return $TEMPLATE->output();
}

sub displayGraph {
    my  ($from_hour, $from_day, $from_month, $from_year,
         $to_hour,  $to_day, $to_month, $to_year, $gmt_offset,  $gtype , $upper_rt, $gpresent,  @links) = @_;
    my $TEMPLATE= HTML::Template->new(filename =>   BASEDIR . $GENERAL_CONFIG{what_template_graph});
    my $graphs = [{ image => "", title => " Submit request to see graphs" }];
    if($from_hour && $from_day && $from_month && $from_year  && 
       $to_hour && $to_day  && $to_month  && $to_year) {
       updateParams({ from_hour => $from_hour, from_day => $from_day, from_month => $from_month, from_year => $from_year, 
                      to_hour => $to_hour,  to_day => $to_day, to_month => $to_month, to_year => $to_year, 
		      gmt_offset => $gmt_offset, upper_rt => $upper_rt}); 
       my ($time_start, $time_end, $gmt_off, $ret_gmt) =   check_time($from_hour, $from_day, $from_month, $from_year,
                                                                      $to_hour, $to_day, $to_month, $to_year, $gmt_offset);
       $graphs  = build_graph({gtype => $gtype , 
                                            upper_rtt => $upper_rt,
                                            gpresent => $gpresent, 
                                            time_start =>$time_start, 
					    time_end => $time_end,  
					    gmt_offset=> $gmt_off,
					    time_label =>  $ret_gmt},
					    \@links
                                        );
    } 
    $TEMPLATE->param(graphs => $graphs);
    return $TEMPLATE->output();
}
 
sub displayLinks { 
    my  ($src_regexp, $dst_regexp, $packetsize, $ma_urls) = @_;
    my $TEMPLATE_l = HTML::Template->new(filename =>   BASEDIR . $GENERAL_CONFIG{what_template_links});
    
    my $links = updateMenu({ src_regexp => $src_regexp, dst_regexp => $dst_regexp, 
                             packetsize => $packetsize, ma_urls => $ma_urls});
    $TEMPLATE_l->param($links);  
    return $TEMPLATE_l->output();
}

sub displayParams {
    my $TEMPLATE= HTML::Template->new(filename =>    BASEDIR . $GENERAL_CONFIG{what_template_params});
    
    $TEMPLATE->param( $PARAMS);
    
    return $TEMPLATE->output(); 
}

 

1;

__END__



=head1   AUTHOR

    Maxim Grigoriev  2008

=head1 BUGS

    Hopefully None

 

=cut




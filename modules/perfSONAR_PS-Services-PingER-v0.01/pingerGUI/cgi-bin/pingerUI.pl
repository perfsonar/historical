#!/usr/local/bin/perl 
#
 
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '0.09';

=head1 NAME

     
     pingerUI.pl -   PingER GUI CGI script 

=head1 DESCRIPTION

       
       script for generating  PingER graphs on fly  for remote MAs, based on CGI::Ajax
       and HTML::Template, works with remote MAs
         
=cut

 
use FindBin qw($Bin);
use lib "$Bin/../lib";

use Data::Dumper;
use HTML::Template;
use CGI::Ajax;
  
use PingerConf qw(%GENERAL_CONFIG $build_in_key  BASEDIR $CGI $LINKS  $PARAMS $MENU $SESSION $COOKIE $REMOTE_MA  $LOGGER get_links  
                     set_defaults get_data updateParams updateMenu storeSESSION fix_regexp);
use TimeUtils qw(check_time); 
use GraphUtils_MA qw(build_graph);  

#### to make it interactive ( registering perl calls as javascript functions)
## 

 ## link:  lhcopnmon1-mgm.fnal.gov:pinger.fnal.gov:1000
if($CGI->param && $CGI->param('get_it') && $CGI->param('get_it') eq $build_in_key) {
    my %cgi_hash = ( );
    foreach my $cgi_param (qw/link ma  time_start  time_end upper_rtt gmt_offset gtype gpresent/) {
       $cgi_hash{$cgi_param} = $CGI->param($cgi_param) if $CGI->param($cgi_param); 
    }
     $LOGGER->logdie(" Number of supplied parameters less than required " . scalar (keys %cgi_hash)) if (keys %cgi_hash) != 8;
     my ($src_name, $dst_name, $packetsize) = split ':', $cgi_hash{link};
     $LOGGER->logdie(" link parser failed $cgi_hash{link} ") unless $src_name &&  $dst_name && $packetsize;
     get_links({remote_ma => [$cgi_hash{ma}],  src_regexp => &fix_regexp($src_name),  dst_regexp => &fix_regexp($dst_name), packetsize  => &fix_regexp($packetsize)});
    ($cgi_hash{time_start}, $cgi_hash{time_end}, $cgi_hash{gmt_offset}, $cgi_hash{time_label}) = 
          check_time($cgi_hash{time_start}, $cgi_hash{time_end}, $cgi_hash{gmt_offset});  
	
    my $graphs = build_graph(\%cgi_hash,  [$cgi_hash{link}]);
    $LOGGER->info( " graphs:: " . Dumper $graphs);
    binmode STDOUT;
    local *IMAGE;
    my $buffer="";
    my $file = $GENERAL_CONFIG{scratch_dir} . $graphs->[0]->{image}; 
    open IMAGE,  "$file" or  $LOGGER->logdie("Cannot open file $file ");
    print $CGI->header( -type => "image/png", -expires => "-1d" );
    while ( read( IMAGE, $buffer, 4096 ) ) {
        print $buffer;
    }
    close IMAGE;
    exit 0;
}
     
my $ajax = CGI::Ajax->new(
    'displayGraph'  => \&displayGraph,
    'displayLinks' => \&displayLinks,
    'resetSession' => \&resetSESSION, 
);

my $TEMPLATE_HEADER =  HTML::Template->new( filename =>   $GENERAL_CONFIG{what_template_header} );
$TEMPLATE_HEADER->param(   'Title' => "PingER  GUI" );
my $TEMPLATE_FOOTER =  HTML::Template->new( filename => $GENERAL_CONFIG{what_template_footer} );

my $myhtml =   $TEMPLATE_HEADER->output() . displayRemoteMA() . displayMenu() . displayLinks()  . displayParams() .
               $TEMPLATE_FOOTER->output();    ##### get html
#  $ajax->DEBUG(1);
# $ajax->JSDEBUG(1);

print $ajax->build_html( $CGI, $myhtml,  {'-Expires' => '1d',   '-cookie' =>  $COOKIE}  );

#  reset session 
sub resetSESSION {
  ($LINKS, $MENU, $REMOTE_MA, $PARAMS) = set_defaults(); 
   storeSESSION();
   return (displayRemoteMA(), displayMenu(), displayLinks() );
   
}  
 
sub displayRemoteMA{ 
    my $TEMPLATE  = HTML::Template->new(filename =>    $GENERAL_CONFIG{what_template_remote_ma});
    $LOGGER->debug("REMOTE_MA: ", Dumper $REMOTE_MA);
    $TEMPLATE->param(  $REMOTE_MA );    
    return $TEMPLATE->output();
}

sub displayMenu  {
    my $TEMPLATE= HTML::Template->new(filename =>    $GENERAL_CONFIG{what_template_menu});    
    $TEMPLATE->param( $MENU );   
    return $TEMPLATE->output();
}

sub displayGraph {
    my  ($start_time, $end_time, $gmt_offset,  $gtype , $upper_rt, $gpresent,  @links) = @_;
    my $TEMPLATE= HTML::Template->new(filename =>   $GENERAL_CONFIG{what_template_graph});
    my $graphs = [{ image => "", alt => " Submit request to see graphs" }];
    if($start_time && $end_time) {
       updateParams({ start_time => $start_time, end_time =>  $end_time, 
		      gmt_offset => $gmt_offset, upper_rt => $upper_rt}); 
       my ($time_start, $time_end, $gmt_off, $ret_gmt) =   check_time($start_time, $end_time, $gmt_offset);
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
    storeSESSION(); 
    $graphs = [{ image => "", alt => " No graphs " }] unless @{$graphs}; 
    $TEMPLATE->param(graphs => $graphs);
    return $TEMPLATE->output();
}
 
sub displayLinks { 
    my  ($src_regexp, $dst_regexp, $packetsize, $ma_urls) = @_;
    my $TEMPLATE_l = HTML::Template->new(filename =>   $GENERAL_CONFIG{what_template_links});
    
    my $links = updateMenu({ src_regexp => $src_regexp, dst_regexp => $dst_regexp, packetsize => $packetsize, ma_urls => $ma_urls});
    $TEMPLATE_l->param($links);  
    return (displayRemoteMA, $TEMPLATE_l->output());
}

sub displayParams {
    my $TEMPLATE= HTML::Template->new(filename =>    $GENERAL_CONFIG{what_template_params});
    
    $TEMPLATE->param( $PARAMS);
    storeSESSION();  
    return $TEMPLATE->output(); 
}
 

1;

__END__



=head1   AUTHOR

Maxim Grigoriev,  2008, maxim_at_fnal.gov

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 

=cut




package PingerConf;
use strict;
use Exporter;
use vars qw(@ISA @EXPORT_OK $dbh $server_name $list_pairs $list_good_pairs $scratch_dir $gout_dir
	                    $mailto $user_name $db_server_name  $db_name $debug
			    %Y_label %legends $NUM_DOTS
			    $img_magic_convert $gr_height $gr_width  %debug_env @debug_links 
			    $graph_base_url  $log_base_url %mn2nm $css_style);
@ISA = qw(Exporter);
@EXPORT_OK = qw($dbh $server_name   $scratch_dir  
	        $mailto $user_name  $db_server_name $db_name $debug
	        FONT_STD FONT_NAR FONT_IT FONT_BLD %Y_label %legends 
		$NUM_DOTS $img_magic_convert $gr_height $gr_width %debug_env @debug_links
	        $graph_base_url  $log_base_url  %mn2nm $css_style);

########### Are we debugging ? #######################

$debug = 0;
#  fake set of parameters for debugging
%debug_env = (start_hr=>'00',
                  end_year=>'2001',start_sec=>'00',gtype=>'rtloss',  
                  inform=>'y',start_day=>'4',gmt_offset=>'0', 
                  end_hr=>'23',gformat=>'jpg',end_sec=>'59',upper_rt=>'auto',
                  start_min=>'00',start_month=>'Jul',end_day=>'28',gpresent=>'bars',
                  end_min=>'59',end_month=>'Jul', start_year=>'2000', only_one => '1',
                 );
$debug_links[0] = ('hepnrc.hep.net:ping.slac.stanford.edu:1000');
$debug_links[1] = ('hepnrc.hep.net:ping.slac.stanford.edu:100');
   		
############# Server related settings ################ 
#  webserver name
$server_name = 'http://lhcopnmon1-mgm.fnal.gov:9090';
# webadmin mailing address
$mailto = 'mailto:maxim@fnal.gov';

#output directories
$scratch_dir = '/tmp';
 
# url to see graphs
$graph_base_url = "$server_name/graphs";  # base url for graphs
# if you planning to have logs then you can see it there
$log_base_url = "$server_name/network/logs";      # base url for logs
#  month name --> number conversion hash 
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
		   "Dec"=> 11    );
$css_style =  qq{ 
<!--                        
                    .smver_1 {font-weight: bolder; font-family: Verdana,  Arial, serif; font-size:  12px }
                    .smver_2 {font-weight: normal; font-family: Verdana,  Times, serif; font-size:  12px }
                    .nblue {color: blue; font-style: normal; text-align: center}
                    .snbld {font-weight: bold; font-family:   Verdana, serif; font-size: 70%}
                    .bars  {scrollbar-face-color:#102132; scrollbar-track-color:#D7E5F2;scrollbar-arrow-color:#A02132;}
                    .arn {font-family: Verdana, Arial, serif;   font-style:normal}
                     .buttons {  font-family: Verdana, Geneva, Arial, Helvetica; font-size: 14px; 
                                 background-color: #D7E5F2; 
                                 color: #000000; 
                                 scrollbar-face-color:#102132; scrollbar-track-color:#D7E5F2;scrollbar-arrow-color:#A02132;
                                 margin-top: 3px;
                                 margin-bottom: 3px;
                                 margin-left: 3px;
                                 margin-right: 3px; text-align: center}   
                     table { background-color: #F8F8FF;  color: #000000;   border: 1px solid #D7E5F2; border-collapse: collapse; }  
                     td {  border: 1px solid #D7E5F2; padding-left: 4px; }
                     .lc_st{  font: 12px Verdana, Geneva, Arial, Helvetica, sans-serif; color: #000000;   } 
                    .fc_st { background-color: #F2F7FB; color: #000000;  text-align: left;  margin-right: 0px; padding-right: 0px; } 
   
		    .lc_st input {  width: 120px; font: 12px Verdana, Geneva, Arial, Helvetica, sans-serif; text-align: left;
  		     background-color: #D7E5F2; color: #102132;   border: 1px solid #284279;  margin-right: 0px; } 
                    .smver_1 input {   font: 12px Verdana, Geneva, Arial, Helvetica, sans-serif; text-align: left;
  		     background-color: #D7E5F2; color: #102132;   border: 1px solid #284279;  margin-right: 0px; } 

                    .smlc_st {  font: 11px Verdana, Geneva, Arial, Helvetica, sans-serif;  background-color: transparent;color: #3670A7;  width: 100px; }
                    .smfc_st {  background-color: #F2F7FB;  color: #000000;  text-align: right; }   
                    .fc_st  input {  width: 70%;  font: 14px Verdana, Geneva, Arial, Helvetica, sans-serif;  background-color: #FFFFFF; color: #102132;   border: 1px solid #284279;  margin-right: 0px; } 
                      .smfc_st input { width: 120px;  font: 11px Verdana, Geneva, Arial, Helvetica, sans-serif;
                                     background-color: #D7E5F2; color: #102132;  border: 1px solid #284279;}       
                                     
--!>               
};
my $home_head = '/usr/X11R6/lib/X11/fonts/TTF';		   
################# TrueType fonts ##################### 
# change if you want see graphs with other type of fonts
use constant FONT_STD=> "$home_head/luximr.ttf"; 
use constant FONT_NAR=> "$home_head/luxisr.ttf"; 
use constant FONT_IT=> "$home_head/luxisri.ttf"; 
use constant FONT_BLD=> "$home_head/luxirb.ttf"; 
#######################  Graphics related #### othe parameters located in the graph_it() function
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
# number  of data points for graph
$NUM_DOTS = 200;
# you have to obtain ocnvert from Image Magic package befor installing this script
$img_magic_convert = '/usr/bin/convert';
#   number of pixels for OY dimension
$gr_height = 300;
# number of pixels for OX dimension
$gr_width = $NUM_DOTS*4;
######################################################
#
#    Perfsonar stuff
#
# 
#
#    TODO



################# MySQL stuff ########################
# 
$user_name = 'www';
#
$db_server_name = 'localhost';
#
$db_name ='pingerMA';
##  all tables named as pairs_YYYYMM #################

1;



=pod

=head1 NAME

     
     PingerConf  - main config module, all you need to change about PingER cgi script is HERE

=head1 DESCRIPTION

       
     PingerConf  module is supplemental for graph_pings_gd.pl CGI script
                 with major purpose of keeping all configuration data in one place
         

=head1 SYNOPSIS

       
     use PingerConf qw($dbh $server_name $list_pairs $scratch_dir $gout_dir
	                    $mailto $user_name $db_server_name  $db_name $debug
			    %Y_label %legends $NUM_DOTS
			    $img_magic_convert $gr_height $gr_width  %debug_env @debug_links 
			    $graph_base_url  $log_base_url %mn2nm) 
       
       
        
      See inline documentation for description of each parameter 
       


=head1   AUTHOR

    MPG, 2007
    Documented by MPG   

=head1 BUGS

    Hopefully None

=head1 DEPENDENCIES

  
    None
   
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











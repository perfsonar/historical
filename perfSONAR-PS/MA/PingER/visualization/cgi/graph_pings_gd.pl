#!/usr/bin/perl 
#
# version 2.1 
#
 
use lib qw(/home/netadmin/PingER_lib); 
use strict;
use Data::Dumper;

#use Apache::Registry;
use CGI::Carp; 
use CGI qw(:standard); 
use PingerConf qw( $dbh    $scratch_dir   $server_name $css_style   $mailto 
                   $debug  %debug_env @debug_links $graph_base_url  $log_base_url);
use TimeUtils qw(&die_html &message_html  &fix_regexp); 
use GraphUtils qw(&build_graph %metaData); 
END {
 
   $dbh->disconnect() if $dbh;
 }
my  ($this_pgm, $links_f,  %cmd_env, $gfn_base,   $cmd_env_l ) =();

# location of this CGI script

$this_pgm = "$server_name/pinger/graph_pings_gd.pl";
  
#  some way of assigning uniq ID to log and generated graph files
 
my $gout_dir = "$scratch_dir/graphs";
mkdir $gout_dir unless -d $gout_dir;
my $ssid = sprintf("%d", 1E6*rand());
$gfn_base = "graph_$ssid";
  
# flush buffer after each line
$| = 1;

# put all values from command line into $in associative array
my  @my_keys;
my  @links;

if ((param('link')  && param('inform') && (param('inform') eq 'y')) || $debug) {
   @links = param('link');
   @my_keys =  param();
   print header('text/html');
   print start_html({-bgcolor => 'white', -title => 'Network Performance Graphs'}),
         h1({-align=> 'center', -style => $css_style},
	     ' Network Performance Graphs '), hr() unless param('gformat') =~ /csv/i;
   die_html("Error: Please go back and chose a link to get a graph for\n") if (!param('link') && !$debug);
   if($debug) {      
      %cmd_env = %debug_env;
      @links   = @debug_links; 
      foreach my $key (sort keys %cmd_env) {print p("$cmd_env{$key}  $key") ;}
   } else {
      foreach my $key (@my_keys) {
          $cmd_env{$key} =  param($key)    unless $key eq 'link';       
      }
   } 
   my $time = time; 
   carp( " GFN base = " . $gfn_base);  
   $cmd_env{'gfn_base'} = $gfn_base;
   $cmd_env{'links_f'} = $links_f;   
   $cmd_env{'gout_dir'} = $gout_dir;
#
#    invocation of the graph on fly module 
# 
   my ($ret_fln, $links_arr) = &build_graph(\@links,  \%cmd_env);  
    
   my  $tot_time = time - $time; 
   my $graph_count;
# if it returned several files, then make it 
   if($cmd_env{'only_one'}) {
      if( $links_arr && -e "$ret_fln")  {
 	 my $gformat = $cmd_env{'gformat'};
 	 $ret_fln =~ s/$gout_dir/$graph_base_url/;
	 
 	if($ret_fln  =~ /\.(pdf|png|jpe?g)/) {
 	    print "<BR><P><IMG SRC=\"$ret_fln\">\n";
 	 } else {
 	    print "<BR><P><a HREF=\"$ret_fln\">You can save this graph or view it if your web browser allows it (just click)</a>\n";
 	 }
      } else {
 	 print p("Pinger was unable to collect data");
      }
   } elsif(ref($ret_fln) eq 'ARRAY') {
       foreach my $fln (@{$ret_fln}) {
       
       if( $links_arr && -e "$fln")  {
 	    my $gformat = $cmd_env{'gformat'};
 	    $fln =~ s/$gout_dir/$graph_base_url/;
	    if($fln =~ /\.(pdf|png|jpe?g)/) {
 	      print "<BR><P><IMG SRC=\"$fln\">\n";
 	    } else {
 	      print "<BR><P><a HREF=\"$fln\">You can save this graph or view it if your web browser allows it (just click)</a>\n";
 	    }
	 } else {
 	     print p("Pinger was unable to collect data");
	 }
       }
  }
  print end_html() unless param('gformat') =~ /csv/i;
}   # this is the first time through this script, so send the blank form
 else {
   my  @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   my  $now = time;
   my $ignore;
   my($start_default_day, $start_default_month, $start_default_year, $end_default_day, $end_default_month, $end_default_year);
  # give one hour (3600 seconds) to allow data to be collected and stored
  ($ignore, $ignore, $ignore, $start_default_day, $start_default_month, $start_default_year, $ignore, $ignore, $ignore) = gmtime($now - (86400 *7) - 3600);
  ($ignore, $ignore, $ignore, $end_default_day, $end_default_month, $end_default_year, $ignore, $ignore, $ignore) = gmtime($now - 86400 - 3600);

  print  header('text/html'), start_html({ -title => 'Generate Network Performance Graphs'}), 
         style({-type=>'text/css'}, $css_style),
       h1('Generate Network Performance Graphs');
   print  hr(), div({-class => 'box'},
       p({-class => 'nblue'},' 
        You can cut down the list of choices shown in the scroll-list below by entering 
        the perl\'s style regular expression that matching your choice.
        You can use <I>*</I> to match any string. Or, for example <I>hep.net$</I> will match
        any node ending in <I>hep.net</I>.Also, you can set the desirable packetsize ( for example 100$ for 100 bytes).'));
   print "<FORM ACTION=\"$this_pgm\">\n";
   print <<'EOM6';
<TABLE CELLPADDING="0"> 
<TR>
<TD class="snbld">
 Source Contains: 
</TD>
<TD VALIGN="Middle">
<INPUT TYPE="text" NAME="src_regexp" SIZE=15
EOM6
 
  unless (defined param('src_regexp')) {
     print "VALUE=\"*\">\n";
  }
  else {
     print "VALUE=\"" . param('src_regexp') . "\">\n";
  }
 
print <<'EOM5';
</TD>

<TD class="snbld">
Destination Contains
</TD>
<TD VALIGN="Middle">
<INPUT TYPE="text" NAME="dest_regexp" SIZE=15
EOM5
  unless(defined param('dest_regexp')) {
     print "VALUE=\"*\">\n";
  }  
  else {
     print "VALUE=\"" . param('dest_regexp') . "\">\n";
  }

print '</TD><TD class="snbld" VALIGN="Middle">&nbsp; Packetsize:<INPUT TYPE="text" NAME="packetsize" SIZE=5';
 unless(defined param('packetsize')) {
     print "VALUE=\"*\">\n";
  }  
  else {
     print "VALUE=\"" . param('packetsize') . "\">\n";
  } 
print <<'EOM4';
</TD>
<TD VALIGN="middle">
<INPUT TYPE=submit VALUE="Match It" class="buttons">
</TD>
</TR>
</TABLE>
</FORM>
EOM4

print qq(<p><FORM ACTION="$this_pgm" METHOD="POST"  class="arn">
         <TABLE>
             <TR>
	         <TD><span class="snbld">Links:</span>
                       <TABLE>
		            <TR>
			        <TD>
                           	 <SELECT NAME="link" SIZE="15" MULTIPLE class="fc_st">);

   
   my $sregxp = &param('src_regexp') || '*';
   my $src_regexp = &fix_regexp($sregxp);
   my $dstregxp = &param('dest_regexp') || '*';
   my $dest_regexp = &fix_regexp($dstregxp); 
   my $pcktsz =  &param('packetsize') || '*';
      $pcktsz  = &fix_regexp($pcktsz); 
     
  foreach my $metaID (sort {$metaData{$a}->{src_name}.$metaData{$a}->{dst_name} cmp $metaData{$b}->{src_name}.$metaData{$b}->{dst_name} } keys %metaData) {
  
    next unless ( $metaData{$metaID}->{src_name}  && $metaData{$metaID}->{dst_name}  && $metaData{$metaID}->{packet_size} ); 
    # cut down list based on src_regexp and dst_regexp entered
    next if( (  $metaData{$metaID}->{src_name} !~ /$src_regexp/i) || 
             (  $metaData{$metaID}->{dst_name}  !~ /$dest_regexp/i) ||
	     (  $metaData{$metaID}->{packet_size} !~ /$pcktsz/) );
   #    print " ------------------- $src_site: $dest_site: $packet_size \n" if  $llink =~ /(?:^|\s+)(\S{6,})\1\S+/;  
     print "                       <OPTION VALUE=\"$metaID\" selected>" .
			 $metaData{$metaID}->{src_name}  ." -&gt; ". $metaData{$metaID}->{dst_name}." (". $metaData{$metaID}->{packet_size}  ." byte count=".$metaData{$metaID}->{count} .")\n";
  }
  close SITELIST;

  print <<"EOM3";
                                 </SELECT>
                              </TD>
			  </tr>
		     </table>
             </TD>
	     <td valign='top'>
                 <TABLE>
		     <tr><span class="snbld">From:</span>
		        <td class="smver_2">Month:<SELECT NAME="start_month" class =  "fc_st">
EOM3

  # list the months, with $start_default_month the default
  for(my $i=0;$i < 12; $i++)  {
    print "                  <OPTION VALUE=\"" . $months[$i] . "\"";
    if ($i == $start_default_month) {
      print " SELECTED";
    }
    print ">" .  $months[$i] . "\n";
  }
  print "                   </SELECT><br>Day:<SELECT NAME=\"start_day\" class =  \"fc_st\">\n";  
  for(my $i = 1;$i < 32; $i++)  {
    print "                 <OPTION VALUE=\"$i\"";
    if ($i == $start_default_day) {
      print " SELECTED";
    }
    print ">$i\n";
  }
  print "                   </SELECT><br>Year:<SELECT NAME=\"start_year\" class =  \"fc_st\">\n";
  my $x;
  for ($x = 2003; $x < ($start_default_year +1900); $x++) {
    print "                <OPTION VALUE=\"$x\">$x";
  }
  print "                  <OPTION VALUE=\"$x\" SELECTED>$x\n";
  print "                  </SELECT>\n";
  print  qq(           </TD>
                   </TR>
	       </table></td><td valign='top'>);
 
print <<"EOM0"; 
              <TABLE>
	         <tr><span class="snbld">To:</span>
		    <td class="smver_2">Month:<SELECT NAME="end_month" class =  "fc_st">
EOM0

  # list the months, with $end_default_month the default
  for(my $i=0;$i < 12; $i++)  {
    print "             <OPTION VALUE=\"" . $months[$i] . "\"";
    if ($i == $end_default_month) {
      print " SELECTED";
    }
    print ">" .  $months[$i] . "\n";
  } 
  print "               </SELECT><br>Day:<SELECT NAME=\"end_day\" class =  \"fc_st\">\n";
  for(my $i = 1;$i < 32; $i++)  {
    print "             <OPTION VALUE=\"$i\"";
    if ($i == $end_default_day) {
      print " SELECTED";
    }
    print ">$i\n";
  } 
  print "               </SELECT><br>Year:<SELECT NAME=\"end_year\" class =  \"fc_st\">\n";
  
  for ($x = 2003; $x < ($end_default_year +1900); $x++) {
    print "             <OPTION VALUE=\"$x\">$x";
  }
  print "               <OPTION VALUE=\"$x\" SELECTED>$x\n";
  print "               </SELECT>\n";
  print qq(         </TD>
                </TR>
	      </TABLE></td><td valign='top'>
	     <TABLE border cellpadding='2'>
	          <tr> <span class="snbld">Time Zone:</span>);
  
 my @times_gmt;  my %labels_gmt;   
  for(my $i=-12;$i<13;$i++) {    
    unless($i){
      push @times_gmt, 'curr';
     $labels_gmt{'curr'} = 'GMT';
    } else {
     push @times_gmt, $i; 
     $labels_gmt{$i} =   $i<0?'GMT' . $i:'GMT+' . $i; 
    }
  }
  print             '<TD>',   scrolling_list(-name => 'gmt_offset' ,  
                         -values => \@times_gmt,
                         -default => 'curr',
			 -multiple => 0,
			 -size=>3, -class => "fc_st",
			 -labels => \%labels_gmt), 
		  qq(</TD>
		</TR>
	    </TABLE>);     
print <<"EOM1";
        </TD>
      </TR>
  </TABLE>
  <P>
  <TABLE border='1' cellpadding='4'>
     <TR><span class="snbld">Graph parameters:</span>
        <TD><span class="snbld">Type of metric:</span><br>
	   <SELECT NAME="gtype" class="fc_st">
	   <OPTION VALUE="ipdv">MIN/MAX/MEAN/IQR IPD
	   <OPTION VALUE="dupl">DUPL/REORDERED packets
	   <OPTION VALUE="rt">Round Trip Time (RTT)
	   <OPTION VALUE="loss">Loss/Conditional Loss
	   <OPTION VALUE="rtloss" SELECTED>RTT/Loss/Conditional Loss
	  </SELECT>
	 </TD>
	 <TD><span class="snbld">Upper RTT(or IPD) Limit:</span><br>
EOM1

my @times_ms;  my %labels_ms;
  push @times_ms, 'auto'; 
  $labels_ms{'auto'}= 'Auto Range';
  for(my $i=10;$i<100;$i+=10) {
     push @times_ms, $i; 
    $labels_ms{$i} = '0...' . $i . ' ms';
  }
  for(my $i=100;$i<1600;$i+=100) {
     push @times_ms, $i; 
    $labels_ms{$i} = '0...' . $i . ' ms';
  }
  print  scrolling_list(-name => 'upper_rt' ,  
                         -values => \@times_ms,
                         -default => $times_ms[0],
			 -multiple => 0,
			 -size=>3, -class => "fc_st",
			 -labels => \%labels_ms); 
print <<"EOM2";	
       </TD>
       <TD>
	   <span class="snbld">File Format:</span><br>
	  <SELECT NAME="gformat" class="fc_st">
	  <OPTION VALUE="csv">CSV text file
	  <OPTION VALUE="png" SELECTED>PNG
	  <OPTION VALUE="jpg">JPEG
	  </SELECT>
	</TD>
	<TD>
	   <span class="snbld">Graph type:</span><br>
	  <SELECT NAME="gpresent" class="fc_st">
	  <OPTION VALUE="bars">BARS
	  <OPTION VALUE="lines" SELECTED>LINES
	  <OPTION VALUE="area">AREA
	  <OPTION VALUE="points">POINTS
	  </SELECT>
      </TD>
      <TD> <span class="smver_2"> 
        <INPUT TYPE="radio" NAME="only_one" VALUE="1"> Any Graph(s) -> 1 file  <br>  
        <INPUT TYPE="radio" NAME="only_one" VALUE="0" CHECKED>Separate file for each Graph  
      
         </span> 
      </TD>
  </TR>
 </TABLE>
 <p>

 <p>
  <INPUT TYPE=submit VALUE="Generate Graph(s)" class="buttons">
  <INPUT TYPE=reset VALUE="Clear Form" class="buttons">
  <INPUT TYPE=HIDDEN NAME="inform" VALUE="y">
  <INPUT TYPE=HIDDEN NAME="start_hr" VALUE="00">
  <INPUT TYPE=HIDDEN NAME="start_min" VALUE="00">
  <INPUT TYPE=HIDDEN NAME="start_sec" VALUE="00">
  <INPUT TYPE=HIDDEN NAME="end_hr" VALUE="23">
  <INPUT TYPE=HIDDEN NAME="end_min" VALUE="59">
  <INPUT TYPE=HIDDEN NAME="end_sec" VALUE="59">
</FORM>
<P>
<HR>
Version 2.6
<BR>
 <A HREF="$mailto">PingER Support</A>
EOM2
print end_html();
}

1;

=pod

=head1 NAME

     
     graph_pings_gd.pl -   CGI script, works under mod_perl as well, generates graphs on fly

=head1 DESCRIPTION

       
       script for generating  PingER graphs on fly, based on GD v2_x graphical library,
       MySQL Perl DBI, GD::Graph, perl CGI package v2_78 ( dont try it with CGI v3_0x)
       and Apache mod_perl ( Apache::Regitry)
         

=head1 SYNOPSIS

       
      place script in the cgi_bin directory with PingerConf.pm, TimeUtils.pm and GraphUtils.pm
      modules ( one can place modules in the usual perl libs place )
      add into httpd.conf:
       
         PerlFreshRestart On 
         <Perl>
                use lib qw(/www_server_path/cgi-bin);
         </Perl>
         <Location /cgi-bin>
        	 SetHandler perl-script
        	 PerlHandler Apache::Registry	
		 PerlInitHandler Apache::Reload
        	 PerlSetVar ReloadAll Off
        	 PerlSendHeader On
        	 Options +ExecCGI
	 </Location>
         ------------------------------------------
	 
	 customize all parameters in the PingerConf.pm  
	 
       


=head1   AUTHOR

    MPG, 2001
    Documented by MPG   11/7/01

=head1 BUGS

    Hopefully None

=head1 DEPENDENCIES

   Apache::Registry 
   CGI::Carp  
   CGI qw(:standard)  
   PingerConf qw( $dbh $list_pairs  $scratch_dir   $server_name  $gout_dir $mailto 
                   $debug  %debug_env @debug_links $graph_base_url  $log_base_url) 
   TimeUtils qw(&die_html &message_html  &fix_regexp)  
   GraphUtils qw(&build_graph)  
     
   ---------------------------
   
   for running this script one need to install:
   
   Apache web server -- v1.3.19
   Apache::Registry module
   mod_perl -- v1.26
   Apache::Reload module ( optional, if not installed then:
                          comment all 'use Apache::Reload;' in the modules  and
			     PerlInitHandler Apache::Reload
        	             PerlSetVar ReloadAll Off     -- in the httpd.conf) 
   
   perl 5.6.1
   jpeg6 libs
   zlib libs
   Xpm libs v4.1
   PNG libs
   ttf(freetype2) libs
   TrueType fonts
   gd 2.0.1 lib
   GD - v1.33 perl module
   GD::Graph - v1.33 perl module
   MySQL server with all PingER data
   DBI -- v1.20 perl module with MySQL driver DBD-mysql-v2.09
   CGI -- v2,78 perl module
   ImageMagic -- to provide 'convert' utility
   -------------------------------------------
   Some of the perl modules above could be dependable on others, some libraries could pre-exists
   
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




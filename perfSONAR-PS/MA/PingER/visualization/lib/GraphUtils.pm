package GraphUtils;
use strict; 

################################################################################
#
# Maxim Grigoriev, 2004 --  maxim@fnal.gov
# Fermilab, Batavia, IL
###############################################################################
#
#          docs at the bottom, use pod2text or pod2html
###############################################################################
 
use GD;
use CGI qw(:standard);
use DBI;


use Exporter;
use vars qw(@ISA @EXPORT_OK  &build_graph );
@ISA = qw(Exporter);
@EXPORT_OK = qw( &build_graph  %metaData );  
use Time::gmtime; 
use PingerConf qw($dbh $mailto $db_name  $debug $db_server_name $user_name 
                  FONT_STD FONT_NAR FONT_IT FONT_BLD %Y_label %legends 
		  $NUM_DOTS $gr_width $gr_height $img_magic_convert %mn2nm); 
use TimeUtils qw(&check_time  &message_html  &die_html &max &min);
use POSIX qw(strftime);

my %selection = ( rt     => 'minRtt, meanRtt, maxRtt, ',  
                  loss   => 'lossPercent, clp, ', 
                  
		  rtloss => ' lossPercent, clp, meanRtt, ',
		  ipdv   => 'minIpd, meanIpd, maxIpd, iqrIpd, ',
	          
		  dupl   =>  'duplicates, ',
		  all =>    ' lossPercent,  minRtt, meanRtt, maxRtt, minIpd,  meanIpd, maxIpd, duplicates,'
		  );
my $upper_rt = 0; 
$dbh =  DBI->connect("DBI:mysql:$db_name\:$db_server_name", $user_name, '',
                                                {RaiseError => 0,
						 PrintError => 0}) or 
           die_html("Cant connect to database, please try later or send message to $mailto" . $DBI::errstr)  unless $dbh;

our %metaData =   () ;
getMetaData();

sub getMetaData {
    
    my $sth = $dbh->prepare("select  metaID, ip_name_src,  ip_name_dst,  packetSize, count from metaData");
       $sth->execute() or   die_html(" OOops , cant query MySQl DB: ". $DBI::errstr);
  
    while(my($metaID, $src, $dst, $pkgsz, $count) = $sth->fetchrow_array()) {
       $metaData{$metaID}  = { src_name => $src , dst_name => $dst ,packet_size => $pkgsz, count => $count};  
   }
   $sth->finish();
   
} 
#
#  main module for parsing DB and gathering all data, it builds graphical files at the very end
#
sub build_graph{
   my ($links, $envs) = @_;
   
  ### checking variables  ( they parsed at CGI script as CGI parameters)  
   my $nograph = 0;
   my $gformat =  $envs->{'gformat'};   ##  graph format ( gif, pdf,   cgm, jpg, bmp, png) , CSV added recently, MPG 200 3  
   my $gfn_base = $envs->{'gfn_base'}; ##  base fn for assembling graph filenames  
   my $gout_dir = $envs->{'gout_dir'}; ##  directory name for storing graphs
   my $gtype =    $envs->{'gtype'};       ##  'rt' 'loss' rtloss   ipdv
      $upper_rt = $envs->{'upper_rt'}; ##  'auto', 100(0-100)....1500(0-1500) 
   my $gpr = $envs->{'gpresent'};## bars, lines, points, area         
   my($rt_selecth, $loss_selecth, $rtloss_selecth, $missing_selecth);
   my $st_mnth =  $envs->{'start_month'};
   my $en_mnth =  $envs->{'end_month'}; 
   my $st_year =  $envs->{'start_year'};
   my $en_year =  $envs->{'end_year'}; 
   my $only_one = $envs->{'only_one'}; 
   die_html("Wrong graphical format: $gformat") unless($gformat =~ /^(gif|pdf|cgm|jpg|bmp|png|csv)$/i); 
   if($gformat =~ /^csv/){
           $nograph++;  $gtype = 'all';
   }
   die_html("Wrong file base pathname: $gfn_base ") unless($gfn_base =~ /^graph_\d+$/); 
   die_html("Wrong file  pathname: $gout_dir") unless($gout_dir =~ /^[\/\w]+$/);  
   my ($tm_s,$tm_d, $gmt_off, $time_label) =   check_time($envs->{'start_sec'},  $envs->{'start_min'}, $envs->{'start_hr'},
		               $envs->{'start_day'},             $st_mnth ,            $st_year,
			         $envs->{'end_sec'},    $envs->{'end_min'},   $envs->{'end_hr'},
		                 $envs->{'end_day'},              $en_mnth,            $en_year,
				 $envs->{'gmt_offset'}
			       ); 
    die_html("  Illegal time supplied, try again ") unless ($tm_s && $tm_d);
   
    my $num_grs =  min(scalar @{$links}, 4);  ## only graphs for 4 links will be created
   
    die_html(" Choose one or  more sites to be tested from previous page ") unless $num_grs;
  
    my @tables_lst;
   
   
   
    # going over all  dates to get list of tables
    for(my $iy =$st_year;  $iy<=$en_year;  $iy++) {
        for(my $im =  1;  $im<=12;  $im++) {
	  
          if( ( ($st_year == $en_year)  && $im>$mn2nm{$st_mnth} &&  $im<=($mn2nm{$en_mnth}+1) ) ||
	     ( ($st_year < $en_year) && 
	       ( ($iy>$st_year && $iy<$en_year) || 
		 ($iy == $en_year && $im<=($mn2nm{$en_mnth}+1)) ||
		 ($iy == $st_year   &&  $im>$mn2nm{$st_mnth})
	       )
	     )  
	   ) {  
	         (my $pr_mn = $im) =~ s/^(\d)$/0$1/;
		 my $table_add =  "data_$iy$pr_mn";
		 my $show_sth = $dbh->prepare("desc $table_add");
		 warn("-------------------desc $table_add \n\n");
                 $show_sth->execute();
                 my @arr_desc =  $show_sth->fetchrow_array();
                 $show_sth->finish or die_html("Cant  check info about DB table:  " . $DBI::errstr);  
		  
                unless(@arr_desc == 0 || $DBI::err) {			         
	            push @tables_lst, $table_add;
		} else {
		   print p("Dataset for $pr_mn/$iy  will be missed in the produced graph");
		   print p("Perhaps DB error: " . $DBI::err ) if $DBI::err; 
		}
            }
	}
    }
    
   
    ######## graph related initilaization
    my $diff_t = int(($tm_d - $tm_s)/$NUM_DOTS);  
    my @img_flns =();
    my $filename_g = "$gout_dir/$gfn_base-ALL";
    my @out_files =();
    
    ## main cycle for every link     
    for(my $i=0; $i <  $num_grs; $i++)  {
      my $local_filename = "$gout_dir/$gfn_base-";  
      my $metaID =   $links->[$i];     
      my $filename = "$gout_dir/$gfn_base-$metaID";
      $local_filename .=  $metaID;
      $filename_g .= "-$metaID" if $filename_g !~ /$metaID/;
       
      ## Query database and create   Image for every link
       
      my @o_y_rt = ();  
      my %csv_list =();       
      my @o_y_rtloss_it = ();
      
      my @o_y_los = ();     my @o_y_clp = ();      
      
      my @o_y_ipdv = (); my @o_y_mind = ();     my @o_y_maxd = ();    my @o_y_iqr = (); 
      my @o_y_dupl = (); 
      my @o_x = ();        
      my $total_pnts = 0;
     foreach my $tabl (@tables_lst) {
       my $sel_stm =   "SELECT  " . $selection{$gtype} . " timestamp  from  $tabl   WHERE  metaID = '$metaID' AND timestamp BETWEEN \? AND \? "; 
       # warn("-------------------Select:  $sel_stm  times:$tm_s, $tm_d\n\n");
	$rt_selecth = $dbh->prepare($sel_stm) or  die_html("Cant  prepare query, please try later or send message to $mailto" . $DBI::errstr);
        $tm_s=~ s/\s+//g;  $tm_d=~ s/\s+//g; 
	$rt_selecth->execute( $tm_s, $tm_d) or die_html("Cant execute select with: $tabl  :: " .  $DBI::errstr);
	  
	my $previous_ind =0;
	while(my(@paramss) = $rt_selecth->fetchrow_array()) {
         my ( $losspercent, $min_t, $av_t, $max_t, $tm_st, $min_d, $ipdv, $max_d, $dupck, $clp, $iqrIpd);
	
	 if($gtype =~ /rtloss/) {
	        ( $losspercent,  $clp, $av_t, $tm_st) = @paramss;
	 }  elsif($gtype eq 'rt') {
	        ($min_t, $av_t, $max_t, $tm_st) = @paramss;
	 } elsif($gtype eq 'loss') {
	        ($losspercent , $clp,  $tm_st) = @paramss;
	 }  elsif($gtype eq 'ipdv') {   
	        ( $min_d, $ipdv, $max_d, $iqrIpd, $tm_st)= @paramss;
	 } elsif($gtype eq 'dupl') {   
	        ( $dupck, $tm_st)= @paramss;
         } elsif ($gtype eq 'all') {
	    ( $losspercent, $min_t, $av_t,  $max_t, $min_d, $ipdv, $max_d, $dupck, $tm_st) = @paramss;
	 }
    
	   my $i_y = min(max(0.,int(( $tm_st - $tm_s)/max(1.,$diff_t))),($NUM_DOTS-1)); 
	   if(!$previous_ind) {
	     $previous_ind = $i_y;
	   }  
	   for(my $ind_y = $previous_ind +1;  $ind_y<=$i_y;$ind_y++) {
	   $o_y_rtloss_it[$ind_y]++ if( ($gtype =~ /^rt/ && $av_t > 0.) 
				  || ($gtype eq 'ipdv' && ($ipdv > 0.|| $min_d > 0. || $iqrIpd > 0.))
				  || ($gtype eq 'dupl' && $dupck ) ||  ($gtype =~ /loss$/ && ($clp > 0. || $losspercent > 0.) )); 
	   
	   ####   depends on type of graph
	   if( $gtype  eq 'rt') { 	 	   
	      $o_y_rt[$ind_y] += $av_t; 
	      $o_y_mind[$ind_y] += $min_t; 
	      $o_y_maxd[$ind_y]  += $max_t; 
	                
	   }
	   if( $gtype eq 'rtloss') { 	 	   
	      $o_y_rt[$ind_y] += $av_t; 
	   }
	   if( $gtype eq 'ipdv' ) { 	 	   
	      $o_y_ipdv[$ind_y] += $ipdv;  	
	      $o_y_mind[$ind_y] += $min_d;  	
	      $o_y_maxd[$ind_y] += $max_d;  
	      $o_y_iqr[$ind_y]  += $iqrIpd ;  	         
	   }
	   if( $gtype eq 'dupl') { 	 	   	      
	      $o_y_dupl[$ind_y]  = $dupck | 0.;  	         
	   }
	
	   $total_pnts++  if($#paramss);
        
	   push @{$csv_list{$total_pnts}},  ($metaData{$metaID}->{src_name} , $metaData{$metaID}->{dst_name} , $metaData{$metaID}->{packet_size},  @paramss) if $nograph;
	  
	   if($gtype =~ /loss$/ ) { 
	      $o_y_clp[$ind_y] += $clp ;  
	      $o_y_los[$ind_y] += $losspercent ;   
	   }
	  
	   
	 }
	  $previous_ind = $i_y;
       }
      
       $rt_selecth->finish  or die_html("Cant retrive all info from DB table: $tabl :: " .  $DBI::errstr) if $rt_selecth;

    } 
    my $src_dest_string = $metaData{$metaID}->{src_name}." - " .$metaData{$metaID}->{dst_name};
   print  " \n Graph: <em>   $src_dest_string </em> by <b> " . $metaData{$metaID}->{packet_size} .
   " bt </b> was generated over <b> $total_pnts </b> data points <br>\n" unless $nograph;
 
   my %o_y_max = ( rt =>1, loss =>1,  ipdv => 1, dupl => 1);         
   my $new_fl = '';
   if(( $#o_y_rt >1    && $gtype =~ /^rt/)   ||  
      ($#o_y_los >1  &&  $gtype =~ /loss$/) || ($#o_y_ipdv > 1 && $gtype eq 'ipdv') || ($#o_y_dupl > 1 && $gtype eq 'dupl')) {
     for(my $id=0;$id<$NUM_DOTS;$id++) { 
         my $tml =  gmtime($tm_s +   $id*$diff_t    + $gmt_off);  
	 my @core_tml =  CORE::gmtime($tm_s +  $diff_t*$id + $gmt_off); 
         if($id>0) {
	    for (my $ii=0; $ii<$diff_t ;$ii++) {
             $tml =  gmtime($tm_s +  ($id -1)*$diff_t  + $ii + $gmt_off);
	     @core_tml = CORE::gmtime($tm_s +  ($id -1)*$diff_t  + $ii + $gmt_off); 
             last unless ( $tml->min % 10);
           }
	 }   
     
        $o_x[$id]  =  strftime "%m/%d/%y", @core_tml   ;
        $o_x[$id]  =  strftime "%m/%d-%H", @core_tml     if($st_year eq $en_year);
	$o_x[$id]  =  strftime "%d/%H:%M",  @core_tml    if(($st_mnth eq $en_mnth) && $st_year eq $en_year);
        $o_x[$id]  =  strftime "%H:%M",    @core_tml   if($envs->{'start_day'} eq $envs->{'end_day'} && ($st_mnth eq $en_mnth) && ($st_year eq $en_year));
       
        if($gtype =~ /^rt/ || $gtype =~ /loss$/) {
            if($gtype =~ 'rt') { 
 	      $o_y_rt[$id]  =  $o_y_rt[$id]>0?$o_y_rt[$id]/($o_y_rtloss_it[$id] || 1.):0;
	      $o_y_rt[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_rt[$id]; 
	   
	      $o_y_mind[$id]  = $o_y_mind[$id]>0?$o_y_mind[$id]/($o_y_rtloss_it[$id] || 1.):0; 
	      $o_y_mind[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_mind[$id]; 
	     
	      $o_y_maxd[$id]  =  $o_y_maxd[$id]>0?$o_y_maxd[$id]/($o_y_rtloss_it[$id] || 1.):0;
	      $o_y_maxd[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_maxd[$id]; 
	       
	      $o_y_max{rt}  = max(($o_y_max{rt} || 0.), $o_y_rt[$id]);  
	      $o_y_max{rt}  = max(($o_y_max{rt} || 0.), $o_y_maxd[$id]);  
	      $o_y_max{rt}  = max(($o_y_max{rt} || 0.), $o_y_mind[$id]);  
	    
            }   
            if($gtype =~ /loss$/) { 
	    #  $o_y_rt[$id]  =  ($o_y_rt[$id] || 0.)/($o_y_rtloss_it[$id] || 1.);
	    #  $o_y_rt[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_rt[$id]; 
	      $o_y_los[$id]  = $o_y_los[$id]>0?$o_y_los[$id]/($o_y_rtloss_it[$id] || 1.):0;	     
	      $o_y_clp[$id]  = $o_y_clp[$id]>0?$o_y_clp[$id]/($o_y_rtloss_it[$id] || 1.):0;	     
	    
	      $o_y_max{loss}  = max(($o_y_max{loss} || 0.), $o_y_los[$id]); 
	      $o_y_max{loss}  = max(($o_y_max{loss} || 0.), $o_y_clp[$id]); 
	      
            }
	 
	} elsif($gtype eq 'ipdv') {
	       $o_y_ipdv[$id]  =   $o_y_ipdv[$id]>0?$o_y_ipdv[$id]/($o_y_rtloss_it[$id] || 1.):0;
	       $o_y_ipdv[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_ipdv[$id]; 
	   
	       $o_y_mind[$id]  =   $o_y_mind[$id]>0?$o_y_mind[$id]/($o_y_rtloss_it[$id] || 1.):0;
	       $o_y_mind[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_mind[$id]; 
	  
	       $o_y_maxd[$id]  =   $o_y_maxd[$id]>0?$o_y_maxd[$id]/($o_y_rtloss_it[$id] || 1.):0;
	       $o_y_maxd[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_maxd[$id]; 
	  
	       $o_y_iqr[$id]  =   $o_y_iqr[$id]>0?$o_y_iqr[$id]/($o_y_rtloss_it[$id] || 1.):0;
	       $o_y_iqr[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $upper_rt < $o_y_iqr[$id]; 
	      
	       $o_y_max{ipdv}  = max(($o_y_max{ipdv} || 0.), $o_y_maxd[$id]);   
	       $o_y_max{ipdv}  = max(($o_y_max{ipdv} || 0.), $o_y_mind[$id]);  
	       $o_y_max{ipdv}  = max(($o_y_max{ipdv} || 0.), $o_y_ipdv[$id]); 
	       $o_y_max{ipdv}  = max(($o_y_max{ipdv} || 0.), $o_y_iqr[$id]); 
	} elsif($gtype eq 'dupl') {
	       $o_y_dupl[$id]  =  undef unless  $o_y_dupl[$id]>0;       
	       $o_y_max{dupl}  = max(($o_y_max{dupl} || 0.), $o_y_dupl[$id]) if $o_y_dupl[$id];  
        }
		
     } 
     my $title = "RTT(MIN/AVERAGE/MAX)\n $src_dest_string, pinged  by ".$metaData{$metaID}->{packet_size}." bytes, count=".$metaData{$metaID}->{count} if $gtype eq 'rt';
	$title = "RTT \& Loss/Conditional Loss(in %):\n $src_dest_string, pinged  by ".$metaData{$metaID}->{packet_size}." bytes, count=".$metaData{$metaID}->{count}  if $gtype eq 'rtloss'; 
	$title =  "Loss/Conditional Loss(in %)\n  $src_dest_string, pinged  by ".$metaData{$metaID}->{packet_size}." bytes, count=".$metaData{$metaID}->{count}  if $gtype  eq 'loss'; 	   
        $title =  "MIN/MAX/MEAN/InterQuantile IPD(inter packet delay):\n $src_dest_string, pinged by ".$metaData{$metaID}->{packet_size}." bytes, count=".$metaData{$metaID}->{count}  if $gtype  eq 'ipdv'; 	   
        $title =  "Duplicated/Reordered packets\n $src_dest_string, pinged by ".$metaData{$metaID}->{packet_size}." bytes, count=".$metaData{$metaID}->{count}  if $gtype  eq 'dupl'; 
		   
     $o_y_max{rt} = $upper_rt  if($upper_rt ne 'auto' && $gtype =~ /^rt/);  
     $new_fl = &graph_it($gpr,   $title, $gtype, \@o_x, \@o_y_rt,\@o_y_los, \@o_y_clp, \@o_y_mind, \@o_y_ipdv, \@o_y_iqr, \@o_y_dupl, \@o_y_maxd, \%o_y_max,  'Date, ' . $time_label, $Y_label{$gtype}, $filename) unless $gformat eq 'csv';     
     
     push @img_flns, $new_fl  unless -z $new_fl;
     $title = undef;
   
  } else {
        $links->[$i] = undef;
    #    &message_html(" Empty dataset for PingER between:$src and $dest, tested by $packet_size bytes packages")
  } 
  if( $new_fl && !(-z $new_fl)) {   
    unless($nograph) {
      my $size = 0;
      if($gformat !~ /png/i && !$only_one) {
             my $cmd = "$img_magic_convert  $new_fl $local_filename.$gformat";
	     my $resp = `$cmd`;	   
	     die_html("1 $cmd Couldnt convert internal PNG graph to --> $gformat` :: $resp") if $resp; 
	     push @out_files, "$local_filename.$gformat"; 
	     unlink $new_fl  or warn " cant unlink";  
      }  else {
	    push @out_files,  $new_fl; 
      }
     
     
     } else {
        foreach my $tmps (sort {$a <=> $b} keys %csv_list) { 
         my $tmpss = join ',', @{$csv_list{$tmps}};
          print "$tmpss\n"; 
        }
     }
   }
 } # end of image creation
 unless($nograph) {
   if(scalar @img_flns > 0 ) {
     $dbh->disconnect() if $dbh;   
     if($only_one) {
        my $images_str = join ' ', @img_flns;
        $filename_g .=  ".$gformat";
        my $resp = `$img_magic_convert  -append $images_str  $filename_g`;
        die_html("2 Couldnt convert internal PNG graph to --> $gformat` :: $resp") if $resp; 
        unlink  or warn " cant unlink"  foreach (@img_flns);    
       return  $filename_g, $links;     
     } else {   
        return  \@out_files, $links;
     }
  } else {
      &message_html(" _________________________________________________ ");  
      &message_html(" Dataset(s) empty or all values are equal to zero,");  
      &message_html(" try another link or choose more loose timing");   
  }
 }
}
#
#    make  graph here, by utilizing GD.pm module
#     
sub graph_it{
my ($gpr, $title, $gtyp, $ox, $oy_rt, $oy_los,  $oy_clp,  $oy_mind,  $oy_ipdv, $oy_iqr, $oy_dupl, $oy_maxd, $y_max, $x_l, $y_l,   $fl_name) = @_;
no strict 'refs';
require 'GD/Graph/' . "$gpr.pm";
my $gif_image =("GD::Graph::" . $gpr)->new($gr_width, $gr_height) or  &message_html(" Due some system errors couldnt create image");  
use strict;
use Carp;
carp     ("Title:$title");
 $gif_image->set(	
	title => $title,	
	y_ticks => 1,
	y_tick_number => 10,
	long_ticks => 0,
	tick_length => 10,
 	x_label_skip => int($NUM_DOTS/10),	
	x_tick_offset => 5, 
	zero_axis => 0,
	x_ticks => 1,
	t_margin => 1,
	r_margin => 30,
	l_margin => 20,
 	text_space => 30,
	y_label_position => 1,
	x_labels_vertical => 1,
	x_label_position => 1,
        dclrs => [qw(blue lgreen lred cyan lorange)],	
	bgclr => 'white',
	fgclr => 'black',
	boxclr =>  'white', 
	transparent => 0,
	markers => [4, 2, 1, 5, 3],
        marker_size => '1',
	line_types => [1, 3, 2, 4],
	line_width => '2',
	line_type_scale => '4',
	y_number_format => "%6.1f",
  );
   $gif_image->set_title_font(FONT_IT,12);
   $gif_image->set_legend_font(FONT_STD,10);
   $gif_image->set_x_label_font(FONT_STD,10);
   $gif_image->set_y_label_font(FONT_STD,10);
   $gif_image->set_x_axis_font(FONT_NAR,8);
   $gif_image->set_y_axis_font(FONT_NAR,8);

  if($gtyp eq 'rtloss') {
     my ($y1_l, $y2_l) = $y_l =~ /(\S+)\s+(\S+)/;
     my $loss_max = $y_max->{loss}*1.2;
     $gif_image->set_legend( $legends{'rt'}, $legends{'loss'},  $legends{'clp'});   
     $gif_image->set(dclrs => [qw(blue lred lgreen cyan lorange black)],
                      two_axes => 1,
		      use_axis => [1, 2, 2 ],
                     
		      x_label =>   $x_l,	
                      y1_max_value => int($y_max->{rt}*1.2),  y2_max_value =>  ($loss_max>100)?100:$loss_max, 
                      y1_min_value => 0,          y2_min_value => 0,   
		      y1_label =>   $y1_l,        y2_label =>   $y2_l );
  } elsif($gtyp eq 'ipdv')  {  
     $gif_image->set_legend( "MIN delay", $legends{'ipdv'}, "MAX delay", $legends{'iqr'});   
     $gif_image->set(dclrs => [qw(blue lred lgreen cyan lorange black)], 
                      x_label =>   $x_l,	
                      y_max_value => int($y_max->{ipdv}*1.2),
		      y_min_value => 0,
		      y_label =>   $y_l,  );
     
 
  } elsif($gtyp eq 'rt') {
      $gif_image->set_legend('MIN RTT', $legends{$gtyp}, 'MAX RTT');   
     my $maxx =  $y_max->{$gtyp};
        $maxx = $maxx*1.2 if $maxx%100;
     $gif_image->set(dclrs => [qw(blue lred lgreen cyan lorange black)], 
                     
                     x_label =>   $x_l,	
		     y_label =>   $y_l, y_min_value => 0, y_max_value =>  $maxx );
  
  
  }elsif($gtyp eq 'loss'){
     $gif_image->set_legend($legends{loss},$legends{clp} ); 
     
     my  $loss_max =  $y_max->{'loss'}*1.2;
         
     $gif_image->set(dclrs => [qw(blue lred lgreen cyan lorange black)], 
                     x_label =>   $x_l,	
		     y_label =>   $y_l, y_min_value => 0, y_max_value => ($loss_max>100)?100:$loss_max );
  
  } else {
     $gif_image->set_legend($legends{$gtyp}); 
     
     my $maxx =  $y_max->{$gtyp};
        $maxx = $maxx*1.2;
     $gif_image->set(dclrs => [qw(blue lred lgreen cyan lorange black)], 
                     x_label =>   $x_l,	
		     y_label =>   $y_l, y_min_value => 0, y_max_value =>  $maxx );
  
  }
  
   my @line100;
   my $up_lmt = $upper_rt;
      $up_lmt =  $y_max->{rt} if $gtyp eq 'rt' && $upper_rt ne 'auto';
       for(my $i1 = 0;$i1<$NUM_DOTS;$i1++){
                $line100[$i1] =   $up_lmt;}
   my @data_xy;
      @data_xy = ( [@{$ox}],[@{$oy_mind}],  [@{$oy_rt}], [@{$oy_maxd}]) if $gtyp eq 'rt';
      @data_xy = ( [@{$ox}],[@{$oy_mind}],  [@{$oy_rt}], [@{$oy_maxd}], [@line100]) if $gtyp eq 'rt' && $upper_rt ne 'auto';
      @data_xy = ( [@{$ox}], [@{$oy_los}], [@{$oy_clp}]) if $gtyp eq 'loss';
      @data_xy = ( [@{$ox}], [@{$oy_rt}], [@{$oy_los}], [@{$oy_clp}]  ) if $gtyp eq 'rtloss';
      @data_xy = ( [@{$ox}], [@{$oy_mind}], [@{$oy_ipdv}], [@{$oy_maxd}], [@{$oy_iqr}]) if $gtyp eq 'ipdv';
       @data_xy = ( [@{$ox}], [@{$oy_mind}], [@{$oy_ipdv}], [@{$oy_maxd}], [@{$oy_iqr}], [@line100]) if $gtyp eq 'ipdv' && $upper_rt ne 'auto';
      @data_xy = ( [@{$ox}], [@{$oy_dupl}]) if $gtyp eq 'dupl';
   my $gd = $gif_image->plot(\@data_xy);   
   
   open(IMG, ">$fl_name.png") or die_html("Couldnt open file:$fl_name.png due  $!");
   binmode IMG; 
   print IMG  $gd->png;
   close IMG;
    
   return  "$fl_name.png";
}      

 

1;

=pod

=head1 NAME

     
     GraphUtils -  module to build graphs on-fly (  in different graphical formats ) or generate CSV report by quering data from Pinger DB  

=head1 DESCRIPTION

       
      GraphUtils  module is main supplemental for graph_pings_gd.pl CGI script
      
       it parses Pinger DB ( MySQL ) where table names are  'data_yyyymm' 
    
       See how it works at:
       http://lhcopnmon1-mgm.fnal.gov:9090/pinger/graph_pings_gd.pl?src_regexp=hep.net&dest_regexp=*   
	 
=head1 SYNOPSIS

       
     use GraphUtils qw(&build_graph);
    
    ($returned_filename, $links_array_ref) = &build_graph(\@links,  \%cmd_env);  
    
     where  \@links  is reference on links array 
             \%cmd_env is reference on hash with all environment settings ( start time, end time, type of graph ... etc)
       
      
       
       


=head1   AUTHOR

    Maxim Grigoriev, 2004, maxim@fnal.gov
    
=head1 BUGS

    Hopefully None

=head1 DEPENDENCIES

  
    GD ( and GD graphical library)
    GD::Graph 
    CGI qw(:standard) 
    DBI 
    Time::gmtime 
    POSIX qw(strftime)
    PingerConf qw($dbh $mailto $db_name  $debug $db_server_name $user_name 
                  FONT_STD FONT_NAR FONT_IT FONT_BLD %Y_label %legends 
		  $NUM_DOTS $gr_width $gr_height $img_magic_convert %mn2nm) 
    TimeUtils qw(&check_time  &message_html  &die_html &max &min)  
   
   
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





package GraphUtils_MA;
use strict;
use warnings;

=head1 NAME

     
     GraphUtils -  module to build graphs on-fly

=head1 DESCRIPTION

       
      GraphUtils  module is main supplemental for pingerUI  CGI script, based on ChartDirector GUI API
      
      
=head1 SYNOPSIS

       
     use GraphUtils_MA qw(&build_graph);
    
    my  $graphs = &build_graph({gtype => $gtype , 
                                            upper_rtt => $upper_rt,
                                            gpresent => $gpresent, 
                                            time_start =>$time_start, 
					    time_end => $time_end,  
					    gmt_offset=> $gmt_off,
					    time_label =>  $ret_gmt},
					    \@links  );  
    #returns array of such pairs :  { image => $local_filename};
    
      
=head1 EXPORTED 

=cut

use FindBin qw($Bin);
use lib "$Bin/../lib";  
###use GD;
use CGI qw(:standard);
use GraphIt qw(graph_it2);
use Data::Dumper;
 
use Exporter ();
use base Exporter;
 
our @EXPORT_OK = qw(build_graph);
use Time::gmtime;
use PingerConf qw(%GENERAL_CONFIG $LOGGER  $COOKIE $SESSION $CGI $PARAMS $REMOTE_MA $MENU BASEDIR $LINKS  get_data  get_links  defaults
	         %Y_label %legends  %mn2nm   storeSESSION %selection );
use TimeUtils qw(max min);
use POSIX qw(strftime);

  
=head2  build_graph 

       accepts hash ref to the parameters and hashref to the links
       returns arrayref to the {image => <URL> } 
 
=cut

sub build_graph {
    my ($params, $links) = @_;
    $LOGGER->logdie("  Parameters must be passed as hash ref") unless ref $params eq 'HASH'; 
    my $gfn_base  = $GENERAL_CONFIG{'gfn_base'};    ##  base fn for assembling graph filenames
    my $gout_dir =  $GENERAL_CONFIG{'gout_dir'};    ##  directory name for storing graphs
    
    my $gtype = $params->{gtype};
    my $upper_rt =  $params->{upper_rtt};
    my $gpr =  $params->{gpresent};
    my $tm_s =  $params->{time_start};
    my $tm_d =  $params->{time_end};
    my $gmt_off =  $params->{gmt_offset};
    my $time_label  =  $params->{time_label};
    my $only_one = 1;
    
    my %time_hash  = %{ get_time_hash( $tm_s, $tm_d ) };
    $LOGGER->logdie("  Illegal time supplied, try again ") unless ( $tm_s && $tm_d );
    $LOGGER->logdie(" links ?: " . Dumper $links) unless ref $links  eq 'ARRAY';
 
    my $num_grs = min( scalar @{$links}, 10 );
    ## only graphs for 10 links will be created
 
    ######## graph related initilaization
    my $diff_t     = int( ( $tm_d - $tm_s ) /  $GENERAL_CONFIG{NUM_DOTS});
    my @img_flns   = ();
    
    my @out_files  = ();
    
    no  warnings;
    my @datums = qw/meanRtt minRtt maxRtt meanIpd minIpd maxIpd iqrIpd clp lossPercent duplicates/;
    ## main cycle for every link
    my $ssid = sprintf("%d", 1E6*rand());
    for ( my $i = 0; $i < $num_grs; $i++ ) {
        my $metaID_key=  $links->[$i];
        my($src_name, $dst_name, $packet_size) = split ':', $metaID_key;
	my $local_filename = "/$gout_dir/$gfn_base-$ssid-$metaID_key";  
        my $filename       = "$GENERAL_CONFIG{scratch_dir}/$local_filename";
        $local_filename .=  '.png';
        my %o_y_max = ( rt => 1, loss => 1, ipdv => 1, dupl => 1 );
        my $new_fl = '';
        ## Query database and create   Image for every link

        my @o_x;
        my $total_pnts = 0;
	my %summ  = ();   
        my $results = get_data({ link =>   $metaID_key, start =>  $tm_s, end => $tm_d } );
	my $previous_ind = 0;
	foreach my $data_row (@{$results}) {
	    my  $tm_st =  $data_row->[0];
	    my  $datum_href =	$data_row->[1];
	
            my $i_y = min( max( 0., int( ( $tm_st - $tm_s ) / max( 1., $diff_t )
            			       )
            		      ),   ( $GENERAL_CONFIG{NUM_DOTS} - 1 )
            		  );
            $previous_ind = $i_y if ( !$previous_ind ); 
            for ( my $ind_y = $previous_ind + 1; $ind_y <= $i_y; $ind_y++ )   {
            	$summ{it_y}{count}->[$ind_y] ++
            	if (
            	    ( $gtype =~ /^rt/ && $datum_href->{meanRtt} > 0. )
            	      || ( $gtype eq 'ipdv'
            		   && (     $datum_href->{meanIpd}  > 0. 
	    			||  $datum_href->{minIpd} > 0.
	    			||  $datum_href->{iqrIpd} > 0. 
	    		      ) 
	    		 )
            	      || ( $gtype eq 'dupl' && $datum_href->{duplicates} )
            	      || ( $gtype =~ /loss$/
            		   && ( $datum_href->{clp} > 0. || $datum_href->{lossPercent} > 0. ) )
            	);

            	####   depends on type of graph
	    	foreach my $datum_type (@datums) {
	    	    $summ{$datum_type}{count}->[$ind_y] += $datum_href->{$datum_type} 
            	}
            	$total_pnts++ if ( %{$datum_href} );  
            }
            $previous_ind = $i_y;
        }
        my $src_dest_string = "$src_name -  $dst_name";
        my $title_h3 = " \n Graph: <em>   $src_dest_string </em> by <b>  $packet_size  bt </b> was generated over <b> $total_pnts </b> data points <br>\n";
        for ( my $id = 0; $id < $GENERAL_CONFIG{NUM_DOTS}; $id++ ) {
            my $tml	 = gmtime( $tm_s + $id * $diff_t + $gmt_off );
            my @core_tml = CORE::gmtime( $tm_s + $diff_t * $id + $gmt_off );
            if ( $id > 0 ) {
        	for ( my $ii = 0; $ii < $diff_t; $ii++ ) {
        	    @core_tml = CORE::gmtime(  $tm_s + ( $id - 1 ) * $diff_t + $ii + $gmt_off );
        	    last unless ( $tml->min % 10 );
        	}
            }

            $o_x[$id] = strftime "%m/%d/%y", @core_tml;
            if ( $time_hash{start_year} eq $time_hash{end_year} ) {
        	$o_x[$id] = strftime "%m/%d-%H", @core_tml;
        	if ( $time_hash{start_month} eq $time_hash{end_month} ) {
        	    $o_x[$id] = strftime "%d/%H:%M", @core_tml;
        	    if ( $time_hash{start_day} eq $time_hash{end_day} ) {
        		$o_x[$id] = strftime "%H:%M", @core_tml;
        	    }
        	}
            }
	    foreach my $datum_type (@datums) {
	        $summ{$datum_type}{count}->[$id]  =  $summ{$datum_type}{count}->[$id] > 0?$summ{$datum_type}{count}->[$id]/($summ{it_y}{count}->[$id] || 1.):0;
		$summ{$datum_type}{count}->[$id]  =  $upper_rt if $upper_rt ne 'auto' &&  $summ{$datum_type}{count}->[$id] > $upper_rt;
		$summ{$datum_type}{max}  =   $summ{$datum_type}{count}->[$id] if  ($summ{$datum_type}{max} || 0. ) <  $summ{$datum_type}{count}->[$id];		    
            }
       
        }
         my $title
             = "RTT(MIN/AVERAGE/MAX)\n $src_dest_string, pinged  by  $packet_size  bytes"
             if $gtype eq 'rt';
         $title
             = "RTT \& Loss/Conditional Loss(in %):\n $src_dest_string, pinged  by  $packet_size  bytes"
             if $gtype eq 'rtloss';
         $title
             = "Loss/Conditional Loss(in %)\n  $src_dest_string, pinged  by  $packet_size  bytes"
             if $gtype eq 'loss';
         $title
             = "MIN/MAX/MEAN/InterQuantile IPD(inter packet delay):\n $src_dest_string, pinged by  $packet_size bytes"
             if $gtype eq 'ipdv';
         $title
             = "Duplicated/Reordered packets\n $src_dest_string, pinged by $packet_size   bytes"
             if $gtype eq 'dupl';
 
         $new_fl = &graph_it2( $gpr, $title, $gtype, \@o_x,  \%summ,  "Date, $time_label", $Y_label{$gtype}, $filename);
        if ( $new_fl && !( -z $new_fl ) ) {
            push  @img_flns, { image => $local_filename};
        }
    }   
    
    return \@img_flns; 
  
}

1;


=head1   AUTHOR

    Maxim Grigoriev, 2004-2008, maxim@fnal.gov
    

=head1 BUGS

    Hopefully None

 
=cut


package PingerGUI::GraphUtils_MA;

 

use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '0.09';

=head1 NAME

     
     GraphUtils -  module to build graphs on-fly

=head1 DESCRIPTION

       
      GraphUtils  module is main supplemental for pingerUI  CGI script, based on ChartDirector GUI API
      
      
=head1 SYNOPSIS

       
     use GraphUtils_MA qw(build_graph);
    
     my $images =  build_graph(\%params, \@links); 
         
      
=head1 EXPORTED 


=cut
 
 
use PingerGUI::GraphIt qw(graph_it2);
use Data::Dumper;
use Exporter ();  
use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(build_graph);
use Time::gmtime;
use File::Path qw(mkpath);
use perfSONAR_PS::Client::PingER;
use Utils qw(max min get_time_hash getURL validURL);
use POSIX qw(strftime);
# OY labels 
 
my %Y_label = (
                rt     => 'ms',
                loss   => '%',      
	        rtloss => 'ms %',
	        wb     => 'Kbps',
		ipdv   =>  'ms',
		dupl   =>  'N per 10 packets'
	       );
	       
#   graphs filename base
my $GFN_BASE = 'graph';

#
my $NUM_DOTS = 100;


=head2 get_data
 
  get  data fir the array of links and time range ( start / end )

=cut

##############   adapt to Catalyst:: stash etc
sub get_data {
    my ( $c ) = @_;
    #  start a transport agent    
   
    my $link = $c->stash->{link};
    my $url =  getURL($c->stash->{stored_links}, $link);
    $c->log->fatal(" Malformed remote MA URL: $url ") unless  $url && validURL($url);
    my $ma = new perfSONAR_PS::Client::PingER( { instance =>  $url } );
    
    my $dresult = $ma->setupDataRequest( { 
    	 start =>   $c->stash->{start}, 
	 cf => 'AVERAGE',
	 resolution =>  $NUM_DOTS,
    	 end =>    $c->stash->{end}, 
    	 keys =>   $c->stash->{stored_links}{$url}{$link}{keys},
       });    
     my $metaids    = $ma->getData($dresult);   
     my @data =();
     ###$c->log->debug(" DATA :: " . Dumper $metaids   );
     foreach my $key_id  (keys %{$metaids}) {
	foreach my $id ( keys %{$metaids->{$key_id}{data}}) {
	   foreach my $timev   (sort {$a <=> $b} keys %{$metaids->{$key_id}{data}{$id}}) {
	            push   @data,  [$timev ,  $metaids->{$key_id}{data}{$id}{$timev}];
	    }  
	   
	 } 
      }
     $c->stash->{stored_links}{$url}{$link}{data} = \@data;    
     return \@data;
} 

##############   adapt to Catalyst:: stash etc
=head2  build_graph

   pre-processing and call for actual graphing function
   accepts two parameters - hashref to parameyers and arrayref to the link pairs
   returns arrayref with each arrays element as hashref of form:
    { key => $local_filename, alt => $title}
   
=cut 

sub build_graph {
    my ($c) = @_; 
      
    my $gtype = $c->stash->{gtype};
    my $upper_rt =   $c->stash->{upper_rt};
    my $gpr =  $c->stash->{gpresent};
    my $tm_s =   $c->stash->{time_start};
    my $tm_d =   $c->stash->{time_end};
    my $gmt_off =   $c->stash->{gmt_off};
    my $time_label  =   $c->stash->{time_label};
    my $only_one = 1;
    
    my %time_hash  = %{ get_time_hash( $tm_s, $tm_d ) };
    $c->log->fatal("  Illegal time supplied, try again ") unless ( $tm_s && $tm_d );
    $c->stash->{links} =  [$c->stash->{links} ] unless ref $c->stash->{links}  eq 'ARRAY';
    ##$c->log->debug(" links ?: " . Dumper  $c->stash->{links});
 
    my $num_grs = min( scalar @{$c->stash->{links}}, 10 );
    ## only graphs for 10 links will be created
 
    ######## graph related initilaization
    my $diff_t     = int( ( $tm_d - $tm_s ) /  $NUM_DOTS);
    my @img_flns   = ();
    my @out_files  = ();
    
    no  warnings;
    my @datums = qw/meanRtt minRtt maxRtt meanIpd minIpd maxIpd iqrIpd clp lossPercent duplicates/;
    ## main cycle for every link
    my $ssid = sprintf("%d", 1E6*rand());
    $ENV{PATH} = "/bin";
    for ( my $i = 0; $i < $num_grs; $i++ ) {
        my $metaID_key=  $c->stash->{links}->[$i];
        my($src_name, $dst_name, $packet_size) = split ':', $metaID_key;
	my $local_filename = "$GFN_BASE-$ssid-$metaID_key";  
        my $filename       = $c->config->{GRAPH_DIR} . "/$local_filename";
	mkpath($c->config->{GRAPH_DIR},1,0755) unless -d  $c->config->{GRAPH_DIR};
        my %o_y_max = ( rt => 1, loss => 1, ipdv => 1, dupl => 1 );
         
        ## Query database and create   Image for every link
        my @o_x;
        my $total_pnts = 0;
	my %summ  = (); 
	$c->stash->{link}  = $metaID_key;
	$c->stash->{start} = $tm_s;
	$c->stash->{end}   = $tm_d;
        my $results = get_data($c);
	my $previous_ind = 0;
	foreach my $data_row (@{$results}) {
	    my  $tm_st =  $data_row->[0];
	    my  $datum_href =	$data_row->[1];
	   
            my $i_y = min( max( 0., int( ( $tm_st - $tm_s ) / max( 1., $diff_t )
            			       )
            		      ),   ( $NUM_DOTS - 1 )
            		  );
	    ##$c->log->debug(" -- $gtype  $i_y = DATA : " . Dumper $data_row);	  
            $previous_ind = $i_y if ( !$previous_ind ); 
            for ( my $ind_y = $previous_ind + 1; $ind_y <= $i_y; $ind_y++ )   {
            	next if $datum_href->{clp} > 99;
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
            	) { 
                    $summ{it_y}{count}->[$ind_y] ++;
            	    ####   depends on type of graph
	    	    foreach my $datum_type (@datums) {
	    	        $summ{$datum_type}{count}->[$ind_y] += $datum_href->{$datum_type} 
            	    }
		}
            	$total_pnts++ if ( %{$datum_href} );  
            }
            $previous_ind = $i_y;
        }
        my $src_dest_string = "$src_name -  $dst_name";
        for ( my $id = 0; $id < $NUM_DOTS; $id++ ) {
            my $tml	 = gmtime( $tm_s + $id * $diff_t + $gmt_off );
            my @core_tml = CORE::gmtime( $tm_s + $diff_t * $id + $gmt_off );
            if ( $id > 0 ) {
        	for ( my $ii = 0; $ii < $diff_t; $ii++ ) {
        	    @core_tml = CORE::gmtime(  $tm_s + ( $id - 1 ) * $diff_t + $ii + $gmt_off );
        	    last unless ( $tml->min % 10 );
        	}
            }
            if( ($tm_d - $tm_s) > 86400*31 ) {
	      $o_x[$id] = strftime "%m/%d/%y", @core_tml;   
            }
	    elsif (($tm_d - $tm_s) > 86400*14) {
	     $o_x[$id] = strftime "%m/%d-%H", @core_tml;
	    }
	    elsif (($tm_d - $tm_s) > 86400*3) {
	     $o_x[$id] = strftime "%d/%H:%M", @core_tml;
	    }
	    else {
	     $o_x[$id] = strftime "%H:%M", @core_tml;
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
         ##$c->log->info('DATA : ' . Dumper      $summ{meanRtt}{count});
         my $image_obj = &graph_it2( $c, $gpr, $title, $gtype, \@o_x,  \%summ,  "Date, $time_label", $Y_label{$gtype});
        if ( $image_obj ) {
	    if($c->stash->{get_files}) {
	        $image_obj->makeChart("$filename.png");
                push  @img_flns, { key => $local_filename, alt => $title} unless -z  $local_filename;
	    }
	    elsif($c->stash->{get_stream}) {
	        return $image_obj;
	    }
        }
    }   
    
    return \@img_flns; 
  
}

1;


=head1   AUTHOR

    Maxim Grigoriev, 2004-2008, maxim@fnal.gov
    
=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 

 

=cut


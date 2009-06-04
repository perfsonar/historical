package PingerUI::Controller::Gui;

use strict;
use warnings;

use PingerUI::Utils qw(check_time validURL   $BUILD_IN_KEY $SCRATCH_DIR fix_regexp);
use PingerUI::GraphUtils_MA  qw(build_graph);
use perfSONAR_PS::Utils::DNS qw/reverse_dns resolve_address/;
use JSON::XS;
use Data::Dumper;
use perfSONAR_PS::Client::PingER; 
use parent 'Catalyst::Controller';
use English qw( -no_match_vars );
use Log::Log4perl  qw(:easy);

=head1 NAME

PingerUI::Controller::Gui - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.for PingER UI

=head1 METHODS

=cut


=head2 index

=cut

Log::Log4perl->easy_init($ERROR);


sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
    $c->response->body('Matched PingerUI::Controller::Gui in Gui.');
}

=head2 display
    
       render pigner UI web interface

=cut

sub display : Local {
    my ( $self, $c ) = @_;
    $c->forward('_set_defaults');
    $c->stash->{title} = "PingER Data Charts";
    $c->stash->{template} = 'gui/header_new.tmpl';
}
 

sub _process_params : Private {
    my ( $self,   $c ) = @_;
   foreach my $name (qw/src_regexp get_it ma  dst_regexp packetsize ma_urls select_url start_time end_time gmt_offset gtype upper_rt gpresent links/) {
        $c->stash->{$name} = $c->req->param($name);
   }
   if( !$c->stash->{'stored_links'} && $c->req->param('stored_links') ) {
        $c->stash->{'stored_links'}   = $c->req->param('stored_links');
        $c->stash->{'stored_links'}   =~ s/'/"/gm;
        $c->stash->{'stored_links'} = decode_json     $c->stash->{'stored_links'}  ;
   }
}

sub _set_defaults : Private {
    my ( $self,   $c ) = @_;
    # list the months, with $start_default_month the default
    my (@times_gmt,@rtt_times);   
    for(my $i=-12;$i<13;$i++) {    
        push @times_gmt, ($i?{gmt_time => $i . '"', gmt_time_label => ($i<0?'GMT' . $i:'GMT+' . $i)}:
	                         {gmt_time => 'curr" SELECTED', gmt_time_label => 'GMT'});
    }	
    for(my $i= 50;$i<1000;$i+=50) {    
        push @rtt_times, { rtt_time => $i . '"', rtt_time_label => "$i ms"};
    }	 
    push @rtt_times,  { rtt_time => 'auto" SELECTED', rtt_time_label => "Auto"};
    $c->stash->{gmt_options}  = \@times_gmt;
    $c->stash->{rt_times}  = \@rtt_times;
    $c->stash->{links} = {};
    $c->stash->{remote_ma} = {ma_urls =>  []};
    $c->stash->{menu} =  {src_regexp => '*', dst_regexp => '*', packetsize => '*'};
    $c->stash->{stored_links} = {};
    $c->stash->{projects} = {};
    $c->stash->{project_table} = {};
    #readgLSSites($c);  
    my @tmp = ();
    #$c->log->debug("" . Dumper $c->stash->{projects});
    if(-e '/var/lib/perfsonar/list.pinger') {
        open IN, '/var/lib/perfsonar/list.pinger' or $c->log->logdie(" Global lookup cache failed to poen");
       
	my $string = join "", <IN>;
	close IN;
	$c->log->debug(" JOSN:: $string ");
        my $data_struct = decode_json $string;
	foreach my $ma (@{$data_struct}) {
	    my $url;
   	    foreach my $key (keys %{$ma}) {
	        if($key !~ /^(name|type|desc|keywords)/) {
		   $url =  $key;
		   last;
		}
	    }
	    foreach my $link  (keys %{$ma->{$url}}) {
	        next unless $link  && %{$ma->{$url}{$link}};
                push @{$c->stash->{remote_ma}{$url}}, { meta_link => $link, 
		                                        keys =>  $ma->{$url}{$link}{keys},
	                                                meta_link_label =>   $ma->{$url}{$link}{src_name}  . 
		                                                             " -&gt; ".
	                                                                     $ma->{$url}{$link}{dst_name} . 
					                                     " (" .
					                                     $ma->{$url}{$link}{packetSize}  . ")\n"
		                                      };
            } 	  
            my ($domain) =  $url  =~ /http\:\/\/([^\/]+)\//xsm;
            $ma->{desc}  =~ s/^.+\ at\ (.+)$/$1/xsm;
            if($ma->{keywords} && ref $ma->{keywords} eq 'ARRAY') {
	         foreach my $keyword (@{$ma->{keywords}}) {
		      $keyword =~ s/^project\://;
                      $c->stash->{projects}{$ma}{$keyword}++;
		      $c->stash->{project_table}{$keyword}++;
		 }
	     }   
   	     push  @tmp, {url => $url, url_label => $ma->{desc} . "($domain)"} if $url;    
        }
    }
    foreach my $local_koi (qw|http://lhc-cms-latency.fnal.gov:8075/perfSONAR_PS/services/pinger/ma 
                              http://lhc-dmz-latency.deemz.net:8075/perfSONAR_PS/services/pinger/ma|) {   
        next if($c->stash->{projects}{$local_koi});
        push  @tmp, {url =>  $local_koi, url_label => 'Fermilab Tier-1 USCMS in Batavia, IL'};     
        $c->stash->{projects}{$local_koi}{LHC}++;
        $c->stash->{projects}{$local_koi}{LHCOPN}++;
        $c->stash->{projects}{$local_koi}{USCMS}++;
    }
    @{$c->stash->{remote_urls}} = sort {$a->{url_label} cmp $b->{url_label}} @tmp  if @tmp;     
}

sub _updateParams : Private {
    my ( $self,   $c ) = @_;
       # list the months, with $start_default_month the default
    $c->log->error(" Missing  start_time and  end_time ") unless $c->stash->{start_time} && $c->stash->{end_time};
    foreach my $gmt (@{$c->stash->{gmt_options}}) {
        if( $c->stash->{gmt_offset} && $gmt->{gmt_time} eq  $c->stash->{gmt_offset} ) {
	    $gmt->{gmt_time}  .=    ' SELECTED';
        } else {
	    $gmt->{gmt_time}  =~ s/ SELECTED//;
        }    
    }
    foreach my $upr (@{$c->stash->{rt_times}}) {
        if($c->stash->{upper_rt} && ($upr->{rtt_time} eq $c->stash->{upper_rt}) ) {
	    $upr->{rtt_time}  .=    ' SELECTED';
        } else {
	    $upr->{rtt_time}  =~ s/ SELECTED//;
        }    
    }
}

sub _updateMenu : Private {
    my (  $self,   $c    ) = @_;
    foreach my $param (qw/src_regexp dst_regexp packetsize/) {
        if($c->stash->{$param}) {     
            $c->stash->{menu}{$param} = $c->stash->{$param};
	    $c->stash->{$param} =  fix_regexp( $c->stash->{$param} );
	    $c->log->debug(" $param : " . $c->stash->{$param} );
	}
    }    
    my @links = ();
    $c->stash->{remote_ma}{ma_urls} = [];
    if($c->stash->{ma_urls}) {
        my @ma_url_array = split /\s+/,  $c->stash->{ma_urls};
        $c->log->debug('entered URLS: ' . Dumper \@ma_url_array);
        push @{$c->stash->{remote_ma}{ma_urls}},   @ma_url_array;
    }
    if($c->stash->{select_url}) {
        my @ma_url_array = split /\s+/,  $c->stash->{select_url};
        $c->log->debug(' selected  URLS: ' . Dumper \@ma_url_array);
        push @{$c->stash->{remote_ma}{ma_urls}},  @ma_url_array;
    } 
    $c->forward('_get_links');
    unless($c->stash->{got_links} && ref $c->stash->{got_links} eq 'HASH') {
        $c->log->error(" Failed to retrieve links from MAs:" . (join "\n", @{$c->stash->{remote_ma}{ma_urls}}));
	$c->stash->{links} =  [ { meta_link  => 'foo',  meta_link_label => "NO Metadata: " . $c->stash->{got_links}  }];
    }
    foreach my $link (keys %{$c->stash->{got_links}}) {         
        push @links, { meta_link =>  "$link", 
	               meta_link_label => $c->stash->{got_links}{$link}{src_name}  . 
		                              " -&gt; ".
	                                      $c->stash->{got_links}{$link}{dst_name} . 
					      " (" .
					      $c->stash->{got_links}{$link}{packetSize}  . ")\n"
		     };
    } 
    $c->stash->{links} = \@links; 
}


sub _get_links : Private {
    my (  $self,   $c    ) = @_;
    #  start a transport agent
    my $param = {};
    $param =  { parameters => { packetSize => $c->stash->{packetsize}} } if $c->stash->{packetsize} && 
                                                                            $c->stash->{packetsize} =~ /^\d+$/;
    my %truncated = ();   
    foreach my $url (@{$c->stash->{remote_ma}{ma_urls}}) {
        unless(validURL($url)) {
	    $c->log->warn(" Malformed remote MA URL: $url ");
	    next;
	}
	my $metaids = {};
	eval {
            my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
	    $c->log->debug(" MA $url  connected: " . Dumper $ma);
            my $result = $ma->metadataKeyRequest($param);
	    $c->log->debug(' result from ma: ' . Dumper $result); 
	    $metaids = $ma->getMetaData($result);
	};
	if($EVAL_ERROR) {
	    $c->log->fatal(" Problem with MA $EVAL_ERROR ");
	}
         $c->log->debug(' Metaids: ' . Dumper $metaids);
        foreach  my $meta  (keys %{$metaids}) {
           $c->stash->{stored_links}{$url}{$meta} =  $metaids->{$meta} unless $c->stash->{stored_links}{$url}{$meta}; 
        }
	my $remote_links = $c->stash->{stored_links}{$url};
	
	foreach my $meta  (keys %{$remote_links}) {
	    $truncated{$meta} = $remote_links->{$meta} if ((!$c->stash->{src_regexp} ||  $remote_links->{$meta}->{src_name}  =~  $c->stash->{src_regexp}) &&
							   (!$c->stash->{dst_regexp} ||  $remote_links->{$meta}->{dst_name}  =~  $c->stash->{dst_regexp}) &&
							   (!$c->stash->{packetize}  ||  $remote_links->{$meta}->{packetSize} =~  $c->stash->{packetsize}) 
							  );	    
	}	
    } 
    $c->stash->{got_links} = \%truncated;
}  

=head2 displayGraph
    
      create graph with pinger's data, used in ajax call

=cut

sub displayGraph : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    my $graphs = [{ image => "", alt => " Submit request to see graphs" }];
    $c->stash->{get_files} = 1;    
    if($c->stash->{start_time} && $c->stash->{end_time}) {
        $c->forward('_updateParams');
        ( $c->stash->{time_start}, $c->stash->{time_end}, 
	  $c->stash->{gmt_off}, $c->stash->{time_label})     =    check_time($c->stash->{start_time}, 
	                                                                  $c->stash->{end_time},
								          $c->stash->{gmt_offset});
        $graphs  = build_graph($c);
    }
  
    $graphs = [{ image => "", alt => " No graphs " }] unless @{$graphs};
    $c->stash->{graphs} =  $graphs;
    $c->stash->{template} =  'gui/graph.tmpl';
}

=head2 getGraph
    
      create graph with pinger's data, used in GET request only

=cut
 
sub getGraph : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    $c->log->logdie(" Keys is not supplied   ") unless $c->stash->{get_it} &&
                                                       $c->stash->{get_it} eq $BUILD_IN_KEY &&
						       $c->stash->{links} &&
						       $c->stash->{ma} ;
    $c->stash->{get_stream} = 1;
    if($c->stash->{start_time} && $c->stash->{end_time}) {
        push @{$c->stash->{remote_ma}{ma_urls}}, $c->stash->{ma};
        $c->forward('_get_links');
        ( $c->stash->{time_start}, $c->stash->{time_end}, 
	  $c->stash->{gmt_off}, $c->stash->{time_label})     =    check_time($c->stash->{start_time}, 
	                                                                  $c->stash->{end_time},
								          $c->stash->{gmt_offset});
									  
        my $graph_obj = build_graph($c);
	if($graph_obj) {
	    $c->response->content_type('image/jpg');
	    $c->response->body($graph_obj->makeChart2(2));
	}
    }
   
}


=head2 displayLinks
    
      send MDK request to remote MA and get listof pinger pairs, used in ajax call

=cut 

sub displayLinks : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    $c->forward('_updateMenu');
    $c->stash->{stored_links} = encode_json  $c->stash->{stored_links} if ref $c->stash->{stored_links};
    $c->stash->{stored_links} =~ s/"/'/gm;
    $c->stash->{template} =  'gui/links.tmpl'; 
}

1;


__END__


=head1   AUTHOR

    Maxim Grigoriev, 2009, maxim@fnal.gov
         

=head1 COPYRIGHT

Copyright (c) 2009, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
  

=cut

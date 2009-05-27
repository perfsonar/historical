package PingerUI::Controller::Gui;

use strict;
use warnings;

use PingerUI::Utils qw(check_time validURL   fix_regexp);
use PingerUI::GraphUtils_MA  qw(build_graph);
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
    $c->stash->{title} = "PingER GUI";
    $c->stash->{template} = 'gui/header.tmpl';
}
 

sub _process_params : Private {
    my ( $self,   $c ) = @_;
   foreach my $name (qw/src_regexp dst_regexp packetsize ma_urls start_time end_time gmt_offset gtype upper_rt gpresent links/) {
        $c->stash->{$name} = $c->req->param($name);
   }
   if($c->req->param('stored_links')) {
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
    my @ma_url_array = split /\s+/,  $c->stash->{ma_urls};
    $c->log->debug('URLS: ' . Dumper \@ma_url_array);
    $c->stash->{remote_ma}{ma_urls} =  \@ma_url_array;
     
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

=head2 displayLinks
    
      send MDK request to remote MA and get listof pinger pairs, used in ajax call

=cut 

sub displayLinks : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    $c->forward('_updateMenu');
    $c->stash->{stored_links} = encode_json  $c->stash->{stored_links};
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

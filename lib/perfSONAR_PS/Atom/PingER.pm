package perfSONAR_PS::Atom::PingER;

our $VERSION = 0.001;

=head1 NAME

    perfSONAR_PS::Atom::PingER-  Atom 1.0 feed publisher for PingER MA ( THIS IS PROOF OF CONCEPT MODULE !)

=head1 DESCRIPTION

  Atom feed publisher for PingER MA, implemented as mod_perl2 handler,  gets list of metadata from pre-configured
  remote MAs and checks if lossPercent was > 5 then reports that link is having a problem
  updates for the past 30 minutes
  For startup.pl script see trunk/startup.pl

=head METHODS

=head2 handler

 standard mod_perl2 handler

=cut


use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::Const -compile => qw(:common :context HTTP_BAD_REQUEST OR_ALL EXEC_ON_READ RAW_ARGS);
use Cache::FileCache;
use Storable qw(freeze thaw);

use perfSONAR_PS::Client::PingER;
use Data::Dumper;
use Log::Log4perl qw( get_logger);
use Data::UUID;
use POSIX qw(strftime);
use XML::Atom::SimpleFeed; 

 
$LOGGER = get_logger("perfSONAR_PS::Atom::PingER");  
 

sub handler {
    my $req = shift;
   
    $req->content_type('application/atom+xml');
    printFeed($req);  
    return Apache2::Const::OK; 
} 

=head2 printFeed

 prints feed for the supplied request object

=cut

sub printFeed {
 my $req = shift;
    
 my $uuid_obj = Data::UUID->new();
 my $uuid =  $uuid_obj->create_from_name('http://ggf.org/ns/nmwg/base/2.0/', 'pinger'); 
 my $now = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
 my $feed = XML::Atom::SimpleFeed->new(
     title   => 'Fermilab and BNL T1 Pinger MA metadata updated in the past 30 minutes',
   #    link    => 'http://lhcopnmon1-mgm.fnal.gov:8075/perfSONAR_PS/services/pinger/ma',
     link    => { rel => 'self', href => 'http://lhcopnmon1-mgm.fnal.gov:9090/atom', },
     updated =>  $now,
     author  => 'Maxim Grigoriev',
     id      => "urn:uuid:" . $uuid_obj->to_string($uuid),
 );
 my $error = setMetaFeed($req, $feed, $uuid_obj, $now);
 if($error) { 
     $req->print(" No data available or error <b>$error</b> ");
 } else {
    $feed->print;
 }
}

=head2  setMetaFeed

 for current $feed object, $uuid object and current timestamp 
 sets entries for the feed

=cut


sub  setMetaFeed {
   my ($req, $feed, $uuid_obj, $now) = @_;
   my   $time_start =	time() -  1800;
   my   $time_end   =	time();
   my   $cache = new Cache::FileCache( { 'namespace' => 'pingerMA',
                                   'default_expires_in' => 300 } );
   my ($CACHED_MDKR, $CACHED_SDR) = ();  
   unless ($cache) {
      $LOGGER->error(" Could not instantiate FileCache.");
      return Apache2::Const::SERVER_ERROR; 
   } else {
      my $stored = $cache->get('hashed_mdkr');
      $CACHED_MDKR =  thaw($stored) if $stored; 
      #$LOGGER->info(" MD dump:" . Dumper   $CACHED_MDKR);
    
      $stored = $cache->get('hashed_sdr');
      $CACHED_SDR =  thaw($stored) if $stored; 
      #$LOGGER->info(" Data dump:" . Dumper   $CACHED_SDR);
      
   }
 
   ########## http://newmon.bnl.gov:8075/perfSONAR_PS/services/pinger/ma
   foreach my $url (qw{ http://lhcopnmon1-mgm.fnal.gov:8075/perfSONAR_PS/services/pinger/ma http://newmon.bnl.gov:8075/perfSONAR_PS/services/pinger/ma})  {
      my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
      $ma->setLOGGER($LOGGER);
     
      if( !$CACHED_MDKR  || !$CACHED_MDKR->{$url}) { 
         my $result = $ma->metadataKeyRequest();
         $CACHED_MDKR->{$url} = $ma->getMetaData($result);	 
      } 
    
      my (@keys_send,$data) = ();
      ## getting keys to send SDR
      foreach my $id (keys %{$CACHED_MDKR->{$url}}) {
          next if (%{$CACHED_SDR->{$url}{$id}{data}} || !@{$CACHED_MDKR->{$url}{$id}{keys}});  
          push @keys_send, @{$CACHED_MDKR->{$url}{$id}{keys}};
      }
   
      if(@keys_send) {
          my $dresult = $ma->setupDataRequest( { 
                  start => $time_start, 
                  end =>   $time_end,  
                  keys =>  \@keys_send,

          });
         $data = $ma->getData($dresult);
      }
      foreach $id (sort keys %{$CACHED_MDKR->{$url}}) {
         next unless  $CACHED_MDKR->{$url}{$id};
         my $src   =    $CACHED_MDKR->{$url}{$id}{src_name};
	 my $dst   =    $CACHED_MDKR->{$url}{$id}{dst_name};
	 my $pkgsz =    $CACHED_MDKR->{$url}{$id}{packetSize};
   
      # 
        $LOGGER->info(" Next::id = $id  $src - $dst  $pkgsz");
       

        $CACHED_SDR->{$url}{$id}{data} = $data->{$id}{data} if(!$CACHED_SDR->{$url}{$id}{data}); 
	my $loss_flag=0;
	foreach my $key (@{$CACHED_MDKR->{$url}{$id}{keys}}) {
	   foreach my $timev (keys %{$CACHED_SDR->{$url}{$id}{data}{$key}}) {
	      $loss_flag =   $CACHED_SDR->{$url}{$id}{data}{$key}{$timev}{'lossPercent'} 
	                         if $loss_flag &&
	                            $loss_flag <  $CACHED_SDR->{$url}{$id}{data}{$key}{$timev}{'lossPercent'};
   	   }
	}   
        my $uuid = $uuid_obj->create_from_name('http://ggf.org/ns/nmwg/base/2.0/',  $CACHED_MDKR->{$url}{$id}{keys}[0]);     
        $feed->add_entry(
            title     =>"Link: ( $src - $dst ) and  PacketSize = $pkgsz bytes",
            link      => "http://lhcopnmon1-mgm.fnal.gov:9090/pinger/gui?src_regexp=$src\&dest_regexp=$dst\&packetsize=$pkgsz",
            id        => "urn:uuid:". $uuid_obj->to_string($uuid),
            summary   => "Link " . ($loss_flag>5?$loss_flag>95?'is <red>DOWN</red>':" is OK, BUT packets loss=$loss_flag\% is observed":" is OK"),
            updated   => $now ,
            category  => 'perfSONAR-PS',
        );
     }
   }
    
   $cache->set('hashed_mdkr',  freeze($CACHED_MDKR));
   $cache->set('hashed_sdr',  freeze($CACHED_SDR)); 
   return;
}
 
 
1;

__END__

 

=head1 AUTHOR

Maxim Grigoriev, maxim_at_fnal_gov

=head1 LICENSE

You should have received a copy of the Fermitools license
along with this software.  

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

All rights reserved.

=cut

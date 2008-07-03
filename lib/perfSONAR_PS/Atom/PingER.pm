package perfSONAR_PS::Atom::PingER;

use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::Const -compile => qw(OK);

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


sub printFeed {
 my $req = shift;
 my $uuid_obj = Data::UUID->new();
 my $uuid =  $uuid_obj->create_from_name('http://ggf.org/ns/nmwg/base/2.0/', 'pinger'); 
 my $now = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
 my $feed = XML::Atom::SimpleFeed->new(
     title   => 'Fermilab and BNL T1 Pinger MA metadata updated in the past 24 hours',
     link    => 'http://lhcopnmon1-mgm.fnal.gov:8075/perfSONAR_PS/services/pinger/ma',
   #  link    => { rel => 'self', href => 'http://lhcopnmon1-mgm.fnal.gov:9090/atom', },
     updated =>  $now,
     author  => 'Maxim Grigoriev',
     id      => "urn:uuid:" . $uuid_obj->to_string($uuid),
 );
 my $error = setMetaFeed($feed, $uuid_obj, $now);
 if($error) { 
     $req->print(" No data available or error <b>$error</b> ");
 } else {
    $feed->print;
 }
}

sub  setMetaFeed {
   my ($feed, $uuid_obj, $now) = @_;
   my     $time_start =   time() -  86400;
   my     $time_end   =   time();
   foreach my $url (qw{http://newmon.bnl.gov:8075/perfSONAR_PS/services/pinger/ma http://lhcopnmon1-mgm.fnal.gov:8075/perfSONAR_PS/services/pinger/ma})  {
   my $ma = new perfSONAR_PS::Client::PingER( { instance => $url } );
            my $result = $ma->metadataKeyRequest( );
	   
	    my $metaids = $ma->getMetaData($result);
    
    
   my $last_id;
   foreach my $id (keys %{$metaids}) {
        my $src = $metaids->{$id}{src_name};
	my $dst = $metaids->{$id}{dst_name};
	my $pkgsz = $metaids->{$id}{packetSize};
	
      #
	my $metaID = unshift @{$metaids->{$id}{metaIDs}};
        if ( !$last_id || $id ne $last_id ) {
	   my $dresult = $ma->setupDataRequest( { 
              start => $time_start, 
              end =>  $time_end, 
              keys => [ ( $metaID )],
            } );
	    my $data = $ma->getData($dresult);
	    my $loss_flag=0;
	    foreach my $timev (keys %{$data->{$id}{data}{$metaID}}) {
	        $loss_flag = $data->{$id}{data}{$metaID}{$timev}{'loosPercent'} if $loss_flag < $data->{$id}{data}{$metaID}{$timev}{'loosPercent'};
	    }
	    
            $last_id = $id;
	    my $uuid = $uuid_obj->create_from_name('http://ggf.org/ns/nmwg/base/2.0/',  $metaID);     
           $feed->add_entry(
              title     =>"Link: ( $src - $dst ) and  PacketSize = $pkgsz bytes",
              link      => "http://lhcopnmon1-mgm.fnal.gov:9090/pinger/gui?src_regexp=$src\&dest_regexp=$dst\&packetsize=$pkgsz",
              id        => "urn:uuid:". $uuid_obj->to_string($uuid),
              summary   => "Metadata ID:$metaID is active, " . ($loss_flag>5?" BUT packets loss=$loss_flag\% is observed":" connectivity is OK"),
              updated   => $now ,
              category  => 'perfSONAR-PS',
           
          );
     
       }
    }
    }
    return;
}
 
 
1;

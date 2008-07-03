package perfSONAR_PS::Client::PingER;
 
use strict;
use warnings;

our $VERSION = 0.10;

=head1 NAME

perfSONAR_PS::Client::PingER - client API for calling PingER MA from a client or another  service.

=head1 DESCRIPTION

Module inherits from perfSONAR_PS::Client::MA and overloads callMA,  metadataKeyRequest and  setupDataRequest
Also it provides handy helper methods to get normalized metadata and data


=cut

use Log::Log4perl qw( get_logger );
use English qw( -no_match_vars );

use perfSONAR_PS::Common qw( genuid );
use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Client::MA;

use  aliased 'perfSONAR_PS::Datatypes::EventTypes';
 
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message'; 
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Key' => 'MetaKey';
 
use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Parameters' => 'MessageParams';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Parameters' => 'PingerParams';

use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Subject' => 'MetaSubj';  

use  aliased 'perfSONAR_PS::Datatypes::v2_0::select::Message::Metadata::Parameters' => 'SelectParams';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::select::Message::Metadata::Subject' => 'SelectSubj';

use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Dst';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Src';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair';


use base 'perfSONAR_PS::Client::MA';

=head2 callMA($self { message })

Calls the MA instance with  request message DOM and returns the response message object. 

=cut

sub callMA {
    my ( $self, $message_dom ) = @_; 
   my $msg = $self->SUPER::callMA( { message =>  $message_dom->asString  } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }
    return  Message->new($msg);
}



=head2 metadataKeyRequest($self, { subject, eventType,  metadata, src_name => 0, dst_name => 0,   parameters })

  Perform a MetadataKeyRequest, the result returned as message DOM
  subject - subject XML
  metadata -  metadata- XML
  eventType - if other than pinger eventtype 
  src_name and dst_name are optionla hostname pair
  parameters is hashref with pinger parameters from this list:  count packetSize interval 
  
=cut

sub metadataKeyRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { xml => 0, metadata => 0, subject => 0,  src_name => 0, dst_name => 0,   parameters => 0 } );
    my $eventType =  EventTypes->new();
    my $metaid = genuid();
    my $message = Message->new( { 'type' =>  'MetadataKeyRequest', 'id' =>  'message.' .  genuid() });
    if($parameters->{xml})  {
       $message = Message->new( { xml => $parameters->{xml}});
    } else {
        $parameters->{id} = $metaid;
	$parameters->{eventType} = $eventType->tools->pinger; 
        my $metadata = $self->getMetaSubj( $parameters );
	 
	# create the  element
	my $data =  Data->new({ 'metadataIdRef' =>  "metaid$metaid", 	'id' =>  "data$metaid" });
	 
	$message->metadata( [$metadata] );	
	$message->data( [$data] );
    }	
    $self->{LOGGER}->debug("MDKR: " . $message->asString);
    return  $self->callMA($message);
}

=head2 getMetaSubj ($self,   { id , metadata , subject ,  key , src_name  , dst_name ,   parameters  })
   
   returns metadata object with pinger subj and pinger parameters 
   
   mundatory:
   
   id => id of the metadata,
   eventType => pigner eventtype
   
   optional:
   
   metadata => XML string of the whole metadata, if supplied then the rest of parameters dont matter
   key => key value, if supplied then the rest of parameters dont matter
   subject => XML string of the subject, if supplied then the rest of parameters dont matter
   src_name =>  source nostname
   dst_name => destination hostname
   parameters => pinger parameters from this list:  count packetSize interval 
   
=cut

sub getMetaSubj {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 1, metadata => 0,  start => 0, end => 0, 
                                              eventType =>  1, subject => 0,  key => 0, 
					      src_name => 0, dst_name => 0,   parameters => 0 } );
  
    my $metaid = $parameters->{id};
    my $md; 
    if($parameters->{metadata})  {
       $md = Metadata->new( { xml => $parameters->{metadata}});
    } elsif($parameters->{key}) {
       $md = Metadata->new( { key => MetaKey->new( {
                                                    id => $parameters->{key}
						 } )
			 } );
       
    } else  {
        $md  =  Metadata->new(); 
    	my $subject =  MetaSubj->new({ id => "subj$metaid" });
	if ( $parameters->{subject} ) {    
            $subject =  MetaSubj->new({xml => $subject});
	} else {

	    if($parameters->{src_name} ||  $parameters->{dst_name}) {
	      my $endpoint =  EndPointPair->new();	
              $endpoint->src(Src->new({ value =>   $parameters->{src_name}, type => 'hostname'})) if $parameters->{src_name};
              $endpoint->dst(Dst->new({ value =>  $parameters->{dst_name}, type => 'hostname'})) if $parameters->{dst_name};
              $subject->endPointPair($endpoint); 
	    }
	}
	$md->subject( $subject );
	if($parameters->{parameters} && ref $parameters->{parameters} eq 'HASH') {
	    my   @params;
	    my $meta_params =  PingerParams->new({ id => "params$metaid" });
	    foreach my $p ( qw/ count packetSize interval  / ) {
        	if($parameters->{parameters}->{$p}) {
        	    my $param =  Parameter->new({ 'name' => $p });
        	    $param->text( $parameters->{parameters}->{$p} );
        	    push @params, $param;
        	}
	    }
	      # add the params to the parameters
	    if(@params) {   
    		$meta_params->parameter( @params );
    		$md->parameters( $meta_params );
	    }
	} 	 
    }
    $md->id("metaid". $parameters->{id});
    $md->eventType($parameters->{eventType});
    return $md;

}


=head2 getMetaTime 
   
   returns metadata object with select subj and time range parameters
   
   mundatory:
   
   id => 1, 
   idRef => 1,
   
   optional:
    
   metadata => 0,  
   start => start time in seconds since epoch ( GMT )
   end => end  time in seconds since epoch ( GMT )
   
=cut

sub getMetaTime  {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 1, idRef => 1, eventType => 1,  metadata => 0,   start => 0, end => 0, 
                                              subject => 0,  key => 0, 
					      src_name => 0, dst_name => 0,   parameters => 0 } );
  
    my $metaid = $parameters->{id};
   
    my $md;
    if($parameters->{metadata})  {
       $md = Metadata->new({xml => $parameters->{metadata}});
    } else {      
        $md  =  Metadata->new(); 
    	my $subject =  SelectSubj->new({ id => "subj$metaid" , metadataIdRef => $parameters->{idRef}});
	 
        my  @params;
        my $time_params =  SelectParams->new({ id => "params$metaid" });
        if($parameters->{start}) {
          push @params,   Parameter->new({ name => 'startTime', text =>  $parameters->{start} });
        }
        if($parameters->{end}) {
          push @params,   Parameter->new({ name => 'endTime', text =>  $parameters->{end} });
        }
          # add the params to the parameters
        if(@params) {	
            $time_params->parameter( @params );
            $md->parameters( $time_params );
        }  
	 
    }
    $md->id("metaid". $parameters->{id});
    $md->eventType($parameters->{eventType});
    return $md;

}

=head2 setupDataRequest($self, { subject, eventType, src_name => 0, dst_name => 0,  parameters, start, end  })

Perform a SetupDataRequest, the result is returned  as message DOM
  subject - subject XML
  keys - one or more keys to query, multiple keys will result in multiple subject metadatas and data elements
  eventType - if other than pinger eventtype 
  start, end   are optional time range parameters
  src_name and dst_name are optionla hostname pair
  parameters is hashref with pinger parameters from this list:  count packetSize interval 
  

=cut

sub setupDataRequest {
    my ( $self, @args ) = @_;   
    my $parameters = validateParams( @args, { xml => 0, metadata => 0,  subject => 0,  keys => 0, 
                                              start => 0, end => 0, src_name => 0, dst_name => 0,   parameters => 0 } );
    
    my $metaid = genuid();
    my $message = Message->new( { 'type' =>  'SetupDataRequest', 'id' =>  'message.' .  genuid() });
    if($parameters->{xml})  {
       $message = Message->new( { xml => $parameters->{xml}});
    } elsif($parameters->{keys} && ref $parameters->{keys} eq 'ARRAY') {
         my @keys = @{ delete $parameters->{keys} };
        foreach my $key (@keys) {
	  $parameters->{key} = $key;
	  $parameters->{id} =  genuid();
	  $parameters->{message} =  $message;
          $message = $self->getPair( $parameters);
	 
	}  
    } else {  
         $parameters->{id} =  genuid();
         $message = $self->getPair($parameters); 
    }	  
    $self->{LOGGER}->debug("SDR: " . $message->asString);
    return  $self->callMA($message);
   
}

=head2 getPair
 
     helper method
     accepts parameters , 
     
     returns subject md / select md and data pair

=cut

sub getPair {
    my ( $self, @args ) = @_;      
     my $parameters = validateParams( @args, { message => 1, id => 0, metadata => 0,  subject => 0,  key => 0, 
                                              start => 0, end => 0, src_name => 0, dst_name => 0,   parameters => 0 } );
          my $eventType =  EventTypes->new();
          my $message =  delete $parameters->{message}; 
	  $parameters->{eventType} = $eventType->tools->pinger; 
          my $md_pinger = $self->getMetaSubj( $parameters );
	  delete $parameters->{parameters} if $parameters->{parameters};
	  
  	
	  $parameters->{idRef} =     $parameters->{id};
	  $parameters->{id} = genuid();  
	  $parameters->{eventType} = $eventType->ops->select; 
	  my $md_time =  $self->getMetaTime( $parameters );
	  # create the  element
	  my $data =  Data->new({ 'metadataIdRef' =>  "metaid$parameters->{id}", 	'id' =>  "data$parameters->{id}" });
          $message->addMetadata($md_pinger);  
	  $message->addMetadata($md_time);	
	  $message->addData($data);
	  return $message;
 
}
=head2 getMetaID ($message_response_object)
 
     helper method, accepts response object
     return ref to hash:
     'src:dst:packetSize' => { 
          src_name    => $src,
          dst_name    => $dst,
          packet_size => $pkgsz,
          metaIDs	 => [ ($metaID) ]
     }

=cut

sub getMetaData {
    my ($self, $response) = @_;
    my $metaids = {};
    $self->{LOGGER}->error("Must be perfSONAR_PS::Datatypes::v2_0::nmwg::Message object") unless $response && 
                                                                                                 blessed $response &&
											         $response->isa('perfSONAR_PS::Datatypes::v2_0::nmwg::Message');
    foreach my $md (@{$response->metadata}) {
        unless ($md->key &&$md->key->id  ) {
	    $self->{LOGGER}->error("Malformed metadata in response - key is missing ");
	    next;
	}
       
        my $key = $md->key->id;
        my $subject = $md->subject; #first subj
        my $endpoint = $subject->endPointPair; # first endpoint
        my $src = $endpoint->src->value;
        my $dst= $endpoint->dst->value;
        my $packetSize;  
       # foreach my $params (@{$md->parameters}) {
            foreach my $param (@{ $md->parameters->parameter}) {
                if($param->name eq 'packetSize') {
		    $packetSize = $param->value?$param->value:$param->text;
		    last;
		}
	    }
      #  }
        my $composite_key = "$src:$dst:$packetSize"; 
        if( exists $metaids->{$composite_key}) { 
            push @{ $metaids->{$composite_key}{metaIDs}}, $key;
        } else { 
            $metaids->{$composite_key} = {
                                src_name    => $src,
                                dst_name    => $dst,
                                packetSize =>  $packetSize,
                                metaIDs     => [ ($key) ]
            };
        }   
    }
    return $metaids; 
}


=head2 getData ($message_response_object)
   
     helper method
     returns extended metaids hashref ( see getMetaData) with extra subkey - data which is 
     ref to hash with epoch time as a key and value is ref to hash with datums ( name => value )

=cut

sub getData {
    my ($self, $response) = @_;
 
    $self->{LOGGER}->error("Must be perfSONAR_PS::Datatypes::v2_0::nmwg::Message object") unless $response && 
                                                                                                 blessed $response &&
											         $response->isa('perfSONAR_PS::Datatypes::v2_0::nmwg::Message');
    my $metaids = $self->getMetaData($response);
    foreach my $meta  (keys %{$metaids}) {
        my $ids = $metaids->{$meta}->{metaIDs};
	my $data = {};
        foreach my $id (@{$ids}) {
	    my $data_obj = $response->getDataByMetadataIdref($id);
	    foreach my $ctime (@{$data_obj->commonTime}) {
	        my $timev = $ctime->value;
                foreach my $datum (@{$ctime->datum}) {
	           $data->{$id}{$timev}{$datum->name} =   $datum->value; 
	        }  
	   
	    } 
        }
	$metaids->{$meta}{data} = $data;
    }
    return $metaids;
}



1;

__END__

=head1 SYNOPSIS

    #!/usr/bin/perl -w

    use strict;
    use warnings;
    use perfSONAR_PS::Client::PingER;

    my $metadata = qq{ <nmwg:metadata id="metaBase">
        <pinger:subject xmlns:pinger="http://ggf.org/ns/nmwg/tools/pinger/2.0/" id="subject1">
         <nmwgt:endPointPair xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
            <nmwgt:src type="hostname" value="newmon.bnl.gov"/> 
             <nmwgt:dst type="hostname" value="pinger.slac.stanford.edu"/> 
        </nmwgt:endPointPair>
       </pinger:subject>
       <nmwg:eventType>http://ggf.org/ns/nmwg/tools/pinger/2.0/</nmwg:eventType>
       </nmwg:metadata>
  };
   

    my $ma = new perfSONAR_PS::Client::PingER(
      { instance => "http://packrat.internet2.edu:8082/perfSONAR_PS/services/pigner/ma"}
    );

    
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $result = $ma->metadataKeyRequest( { 
        metadata => $metadata 
     );
     #
     #   or 
     #
     $result = $ma->metadataKeyRequest( { 
        src_name => 'www.fnal.gov', dst_name => 'some.lab.gov'
     );
     #
     #   or  with parameters
     #
     $result = $ma->metadataKeyRequest( { 
        src_name => 'www.fnal.gov', dst_name => 'some.lab.gov',
	parameters => { count => 10, packetSize => 1000 }
     );
     #
     #   get data for metadata snippet
     #
    $result = $ma->setupDataRequest( { 
         start => ($sec-3600), 
         end => $sec, 
         metadata => $metadata 
         parameters => {count => 10}
      } );
     #
     #   or with all parameters 
     #
    
     $result = $ma->setupDataRequest( { 
         start => ($sec-3600), 
         end => $sec, 
        src_name => 'www.fnal.gov', 
	dst_name => 'some.lab.gov',
        parameters => {count => 10}
      } );
      #
      #  or by Key
      #
       $result = $ma->setupDataRequest( { 
         start => ($sec-3600), 
         end => $sec, 
         key => '123456',
      } );
      #
      #   normilize metadata and print src_dst_packetsize 
      #
      
      foreach my $src_dst_packetsize (keys %{$self->getMetaData($result)})
           print "Src:DST:packetsize key = $src_dst_packetsize \n";
      }

=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<English>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Transport> , L<perfSONAR_PS::Datatypes>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id: LS.pm 1877 2008-03-27 16:33:01Z aaron $

=head1 AUTHOR

Maxim Grigoriev, maxim_at_fnal_gov

=head1 LICENSE

You should have received a copy of the Fermitools license
along with this software.  

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

All rights reserved.

=cut

package perfSONAR_PS::Client::PingER;
 
use strict;
use warnings;

our $VERSION = 0.10;

=head1 NAME

perfSONAR_PS::Client::PingER - API for calling an PingER MA from a client or another 
service.

=head1 DESCRIPTION

Module with a very basic API to some common MA functions.

=cut

use Log::Log4perl qw( get_logger );
use Params::Validate qw( :all );
use English qw( -no_match_vars );

use perfSONAR_PS::Common qw( genuid makeEnvelope find extract );
use perfSONAR_PS::Transport;
use perfSONAR_PS::Client::Echo;
use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Client::MA;

use  aliased 'perfSONAR_PS::Datatypes::EventTypes';
use  aliased 'perfSONAR_PS::Datatypes::Namespace';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message'; 
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Key' => 'MetaKey';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data::Key' => 'DataKey';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Data::CommonTime';

use  aliased 'perfSONAR_PS::Datatypes::v2_0::nmwgr::Message::Data::Datum' => 'DataDatum';

use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Parameters' => 'MessageParams';
use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Parameters' => 'PingerParams';

use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Subject' => 'MetaSubj'; 
use  aliased 'perfSONAR_PS::Datatypes::v2_0::pinger::Message::Data::CommonTime::Datum' => 'CTimeDatum';

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
    my $parameters = validateParams( @args, { xml => 0, metadata => 0,  subject => 0,  src_name => 0, dst_name => 0,   parameters => 0 } );
  
    my $metaid = genuid();
    my $message = Message->new( { 'type' =>  'MetadataKeyRequest', 'id' =>  'message.' .  genuid() });
    if($parameters->{xml})  {
       $message = Message->new( { xml => $parameters->{xml}});
    } else {
        $parameters->{id} = $metaid;
        my $metadata = $self->getMetaSubj( $parameters );
	 
	# create the  element
	my $data =  Data->new({ 'metadataIdRef' =>  "md$metaid", 	'id' =>  "data$metaid" });
	 
	$message->metadata( [$metadata] );	
	$message->data( [$data] );
    }	
    return  $self->callMA($message);
}

=head2 getMetaSubj 
   
   returns metadata object with pinger subj and pinger parameters 
   id => 1, metadata => 0, subject => 0,  src_name => 0, dst_name => 0,   parameters => 0
   
=cut

sub getMetaSubj {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 1, metadata => 0, subject => 0,  src_name => 0, dst_name => 0,   parameters => 0 } );
  
    my $metaid = $parameters->{id};
    my $md;
    if($parameters->{metadata})  {
       $md = Metadata->new( { metadata => $parameters->{xml}});
    } else {
        $md  =  Metadata->new({ id => "md$metaid"}); 
    	my $subject =  MetaSubj->new({ id => "subj$metaid" });
	if ( $parameters->{"subject"} ) {    
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
	my $eventType =  EventTypes->new();
	$md->eventType( $eventType->tools->pinger );
	if($parameters->{eventType}) {
            $md->eventType( $parameters->{eventType} );
	}   
    }
    return $md;

}


=head2 getMetaTime 
   
   returns metadata object with select subj and time range parameters
   id => 1, idRef => 1, metadata => 0,     parameters => 0
   
=cut

sub getMetaTime  {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { id => 1, idRef => 1,  metadata => 0,   start => 0, end => 0 } );
  
    my $metaid = $parameters->{id};
    my $md;
    if($parameters->{metadata})  {
       $md = Metadata->new( { metadata => $parameters->{xml}});
    } else {
        
        $md  =  Metadata->new({ id => "md$metaid"}); 
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
	my $eventType =  EventTypes->new();
	$md->eventType( $eventType->ops->select );
	   
    }
    return $md;

}

=head2 setupDataRequest($self, { subject, eventType, src_name => 0, dst_name => 0,  parameters, start, end  })

Perform a SetupDataRequest, the result is returned  as message DOM
  subject - subject XML
  eventType - if other than pinger eventtype 
  start, end   are optional time range parameters
  src_name and dst_name are optionla hostname pair
  parameters is hashref with pinger parameters from this list:  count packetSize interval 
  

=cut

sub setupDataRequest {
    my ( $self, @args ) = @_;   
    my $parameters = validateParams( @args, { xml => 0, metadata => 0,  subject => 0, 
                                              start => 0, end => 0, src_name => 0, dst_name => 0,   parameters => 0 } );
  
    my $metaid = genuid();
    my $message = Message->new( { 'type' =>  'SetupDataRequest', 'id' =>  'message.' .  genuid() });
    if($parameters->{xml})  {
       $message = Message->new( { xml => $parameters->{xml}});
    } else {
        $parameters->{id} = $metaid;
        my $md_pinger = $self->getMetaSubj( $parameters );
	delete $parameters->{parameters} if $parameters->{parameters};
	  
	$parameters->{id} = genuid();
	$parameters->{idRef} =  $metaid;
	my $md_time =  $self->getMetaTime( $parameters );
	  
	# create the  element
	my $data =  Data->new({ 'metadataIdRef' =>  "md$parameters->{id}", 	'id' =>  "data$parameters->{id}" });
	 
	$message->metadata( [$md_pinger, $md_time] );	
	$message->data( [$data] );
    }	
    return  $self->callMA($message);
   
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

    my $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s-in-16\">\n";
    $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
    $subject .= "        <nmwgt:hostName>nms-rexp.salt.net.internet2.edu</nmwgt:hostName>\n";
    $subject .= "        <nmwgt:ifName>eth0</nmwgt:ifName>\n";
    $subject .= "        <nmwgt:direction>in</nmwgt:direction>\n";
    $subject .= "      </nmwgt:interface>\n";
    $subject .= "    </netutil:subject>\n";
   
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $result = $ma->metadataKeyRequest( { 
        metadata => $metadata 
     );
     #
     #   or 
     #
     $result = $ma->metadataKeyRequest( { 
        src_name 'www.fnal.gov', dst_name => 'some.lab.gov'
     );

    $result = $ma->setupDataRequest( { 
         start => ($sec-300), 
         end => $sec, 
          metadata => $metadata 
         parameters => {count => 10}
      } );

=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<English>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Transport>, L<perfSONAR_PS::Client::Echo>

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

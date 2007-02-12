#!/usr/bin/perl

package perfSONAR_PS::Transport;
use Carp;
use HTTP::Daemon;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use XML::XPath;
@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::Transport";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $port && $port ne "") {
    $hash{"PORT"} = $port;
  }
  if(defined $listenEndPoint && $listenEndPoint ne "") {
    $hash{"LISTEN_ENDPOINT"} = $listenEndPoint;
  } 
  if(defined $contactHost && $contactHost ne "") {
    $hash{"CONTACT_HOST"} = $contactHost;
  }
  if(defined $contactPort && $contactPort ne "") {
    $hash{"CONTACT_PORT"} = $contactPort;
  }     
  if(defined $contactEndPoint && $contactEndPoint ne "") {
    $hash{"CONTACT_ENDPOINT"} = $contactEndPoint;
  }  
  $hash{"SOAP_ENV"} = "http://schemas.xmlsoap.org/soap/envelope/";
  $hash{"SOAP_ENC"} = "http://schemas.xmlsoap.org/soap/encoding/";
  $hash{"XSD"} = "http://www.w3.org/2001/XMLSchema";
  $hash{"XSI"} = "http://www.w3.org/2001/XMLSchema-instance";
  $hash{"NAMESPACE"} = "http://ggf.org/ns/nmwg/base/2.0/";
  
  bless \%hash => $package;
}


sub setPort {
  my ($self, $port) = @_;  
  $self->{FUNCTION} = "\"setPort\"";  
  if(defined $port) {
    $self->{PORT} = $port;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setListenEndPoint {
  my ($self, $listenEndPoint) = @_;  
  $self->{FUNCTION} = "\"setListenEndPoint\"";  
  if(defined $listenEndPoint) {
    $self->{LISTEN_ENDPOINT} = $listenEndPoint;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setContactHost {
  my ($self, $contactHost) = @_;  
  $self->{FUNCTION} = "\"setContactHost\"";  
  if(defined $contactHost) {
    $self->{HOST} = $contactHost;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setContactPort {
  my ($self, $contactPort) = @_;  
  $self->{FUNCTION} = "\"setContactPort\"";  
  if(defined $contactPort) {
    $self->{PORT} = $contactPort;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setContactEndPoint {
  my ($self, $contactEndPoint) = @_;  
  $self->{FUNCTION} = "\"setContactEndPoint\"";  
  if(defined $contactEndPoint) {
    $self->{CONTACT_ENDPOINT} = $contactEndPoint;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub startDaemon {
  my ($self) = @_;  
  $self->{FUNCTION} = "\"startDaemon\"";  
  $self->{DAEMON} = HTTP::Daemon->new(
    LocalPort => $self->{PORT},
    Reuse => 1
  ) or croak($self->{FILENAME}.":\tCannot start daemon in ".$self->{FUNCTION});
  return;
}


sub acceptCall {
  my ($self) = @_; 
  $self->{FUNCTION} = "\"acceptCall\"";    
  $self->{CALL} = $self->{DAEMON}->accept;
  $self->{REQUEST} = $self->{CALL}->get_request;
  $self->{RESPONSE} = HTTP::Response->new();
  $self->{RESPONSE}->header('Content-Type' => 'text/xml');
  $self->{RESPONSE}->header('user-agent' => 'Netradar/'.$VERSION);
  $self->{RESPONSE}->code("200");

  if($self->{REQUEST}->uri eq $self->{LISTEN_ENDPOINT} && $self->{REQUEST}->method eq "POST") {
    $action = $self->{REQUEST}->headers->{"soapaction"} ^ $self->{NAMESPACE};
    if (!$action =~ m/^.*message\/$/) {
      return -1;
    }
    else {
      return 1;
    }   
  }
  else {
    return -1;      
  }
}


sub getRequest {
  my ($self) = @_;
  $self->{FUNCTION} = "\"getRequest\"";  
  $xp = XML::XPath->new( xml => $self->{REQUEST}->content );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  $nodeset = $xp->find('//nmwg:message');

  if($nodeset->size() <= 0) {
    croak($self->{FILENAME}.":\tMessage element not found or in wrong namespace in ".$self->{FUNCTION});
  }
  elsif($nodeset->size() >= 2) {
    croak($self->{FILENAME}.":\tToo many Message elements found in ".$self->{FUNCTION});
  }
  else {
    return XML::XPath::XMLParser::as_string($nodeset->get_node(1));
  }
}


sub setResponse {
  my ($self, $content) = @_;  
  $self->{FUNCTION} = "\"setResponse\"";  
  if(defined $content) {
    $self->{RESPONSE} = $content;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub closeCall {
  my ($self) = @_;
  $self->{FUNCTION} = "\"closeCall\"";    
  $self->{CALL}->send_response($self->{RESPONSE});    
  $self->{CALL}->close;
  undef($self->{CALL});  
  return;
}


sub makeEnvelope {
  my($self, $content) = @_;
  $self->{FUNCTION} = "\"makeEnvelope\"";    
  my $envelope = XML::Writer::String->new();
  my $writer = new XML::Writer(NAMESPACES => 4,
                            PREFIX_MAP => {$self->{SOAP_ENV} => "SOAP-ENV",
                                           $self->{SOAP_ENC} => "SOAP-ENC",
                                           $self->{XSD} => "xsd",
                                           $self->{XSI} => "xsi",
                                           $self->{NAMESPACE} => "message"},
                            UNSAFE => 1,
                            OUTPUT => $envelope,
                            DATA_MODE => 1,
                            DATA_INDENT => 3);
  $writer->startTag([$self->{SOAP_ENV}, "Envelope"],
                    "xmlns:SOAP-ENC" => $self->{SOAP_ENC},
                    "xmlns:xsd" => $self->{XSD},
                    "xmlns:xsi" => $self->{XSI});
  $writer->emptyTag([$self->{SOAP_ENV}, "Header"]);
  $writer->startTag([$self->{SOAP_ENV}, "Body"]);
  $writer->raw($content);
  $writer->endTag([$self->{SOAP_ENV}, "Body"]);
  $writer->endTag([$self->{SOAP_ENV}, "Envelope"]);
  $writer->end();
  return $envelope->value;
}


sub sendReceive {
  my($self, $envelope, $timeout) = @_;
  $self->{FUNCTION} = "\"sendReceive\"";  
  $method_uri = "http://ggf.org/ns/nmwg/base/2.0/message/";
  $method_name = "";

  my $httpEndpoint = qq[http://$self->{CONTACT_PORT}:$self->{CONTACT_HOST}$self->{CONTACT_ENDPOINT}];

  my $userAgent = "";
  if(defined $timeout && $timeout ne "") {
    $userAgent = LWP::UserAgent->new('timeout'=>$timeout);
  }
  else {
    $userAgent = LWP::UserAgent->new('timeout'=>5000);
  }  
  
  my $sendSoap = HTTP::Request->new('POST', $httpEndpoint, new HTTP::Headers, $envelope);
  $sendSoap->header('SOAPAction' => $method_uri);
  $sendSoap->content_type  ('text/xml');
  $sendSoap->content_length(length($envelope));
  
  my $httpResponse = $userAgent->request($sendSoap);
  my $responseCode = $httpResponse->code();
  my $responseContent = $httpResponse->content();

  return $responseContent;
}


1;


__END__
=head1 NAME

perfSONAR_PS::Transport - A module that provides methods for listening and contacting SOAP endpoints.  

=head1 DESCRIPTION

...

=head1 SYNOPSIS

    use perfSONAR_PS::Transport;
    
    my $listener = new perfSONAR_PS::Transport("8080", "/service/MA", "", "", "");
    
    $listener->startDaemon;
    while(1) {
      my $responseContent = "";
      if($listener->acceptCall == 1) {
        print "Request Message Was:\n" , $listener->getRequest , "\n";  
      
        #...      
  
        $listener->setResponse($responseContent);
      }
      else {
        print "Error\n";  

        #...

        $listener->setResponse($responseContent);
      }
      $listener->closeCall;
    }
    
    my $sender = new perfSONAR_PS::Transport("", "", "localhost", "8080", "/service/MA");
    
=head1 DETAILS

...

=head1 API

The API of the transport class is meant to simplfy common information transportation issues in
WS envirnments.  

=head2 new($port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint)

The 'port' and 'listenEndPoint' arguments set values that will be used if the object
will be used to listen for and accept incomming calls.  The 'contactHost', 'contactPort', 
and 'contactEndPoint' set the values that are used if the object is used to send 
information to a remote host.  All values can be left blank and set via the various 
set functions.

=head2 setPort($port)

(Re-)Sets the listen port argument.  This value represents which particular TCP port 
on the host that will have the listening service.  

=head2 setListenEndPoint($listenEndPoint)

(Re-)Sets the listen endPoint argument.  This value represents which particular 'endPoint'
(path) the service will be hosting.  For example the host 'localhost' may be listening on
'8080' for a particular service, and there may be several services that can be handled on
a specific machine such as an LS, or MP.  So a sample 'endPoint' for this service:

http://localhost:8080/services/MP

Would be '/services/MP'.

=head2 setContactHost($contactHost)

(Re-)Sets the contact host argument.  The contact host is the hostname of a remote host
that is supplying a service.

=head2 setContactPort($contactPort)

(Re-)Sets the contact port argument.  The contact port is the port on a remote host
that is supplying a service.

=head2 setContactEndPoint($contactEndPoint)
  
(Re-)Sets the contact endPoint argument.  The contact endPoint is the endPoint on a remote host
that is supplying a service.  See 'setListenEndPoint' for a more detailed description.
  
=head2 startDaemon()

Starts an HTTP daemon on the given host listening to the specified port.  This method will
cause the program to halt if the port in question is not available.

=head2 acceptCall()

Listens on the 'host:port/endPoint' for any requests.  The requests are checked for validity
and a -1 is returned on error, a 1 is returned on success.  On success the request message
can be parsed via the getRequest() method. 

=head2 getRequest()

Returns the nmwg:message from a given request.  If there is no message, or too many message 
elements present, the object will halt.

=head2 setResponse($content)

Sets the content of a response messages.

=head2 closeCall()

Closes a given call to the service by sending a response message.

=head2 makeEnvelope($content)

Makes a SOAP formated envelope.

=head2 sendReceive($envelope, $timeout)

Sents a soap formated envelope, and a timeout value to the contact host/port/endPoint.

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, 
L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::MP::SNMP>

To join the 'netradar' mailing list, please visit:

  http://moonshine.pc.cis.udel.edu/mailman/listinfo/netradar

The netradar subversion repository is located at:

  https://damsl.cis.udel.edu/svn/netradar/
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

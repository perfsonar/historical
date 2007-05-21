#!/usr/bin/perl

package perfSONAR_PS::Transport;
use Carp qw( carp );
use HTTP::Daemon;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use XML::XPath;
use XML::Writer;
use XML::Writer::String;
use LWP::UserAgent;

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;


@ISA = ('Exporter');
@EXPORT = ();
$VERSION = "1";

sub new {
  my ($package, $log, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint, $debug) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::Transport";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }    
  if(defined $port and $port ne "") {
    $hash{"PORT"} = $port;
  }
  if(defined $listenEndPoint and $listenEndPoint ne "") {
    $listenEndPoint =~ s/^(\/)+//g;
    $hash{"LISTEN_ENDPOINT"} = $listenEndPoint;
  } 
  if(defined $contactHost and $contactHost ne "") {
    $hash{"CONTACT_HOST"} = $contactHost;
  }
  if(defined $contactPort and $contactPort ne "") {
    $hash{"CONTACT_PORT"} = $contactPort;
  }     
  if(defined $contactEndPoint and $contactEndPoint ne "") {
    $hash{"CONTACT_ENDPOINT"} = $contactEndPoint;
  }  
  if(defined $debug and $debug ne "") {
    $hash{"DEBUG"} = $debug;  
  } 
    
  $hash{"SOAP_ENV"} = "http://schemas.xmlsoap.org/soap/envelope/";
  $hash{"SOAP_ENC"} = "http://schemas.xmlsoap.org/soap/encoding/";
  $hash{"XSD"} = "http://www.w3.org/2001/XMLSchema";
  $hash{"XSI"} = "http://www.w3.org/2001/XMLSchema-instance";
  $hash{"NAMESPACE"} = "http://ggf.org/ns/nmwg/base/2.0/";
  $hash{"PREFIX"} = "nmwg";
  
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {
    error($self, "Missing argument", __LINE__);   
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  
  $self->{FUNCTION} = "\"setPort\"";  
  if(defined $port) {
    $self->{PORT} = $port;
  }
  else {
    error($self, "Missing argument", __LINE__);   
  }
  return;
}


sub setListenEndPoint {
  my ($self, $listenEndPoint) = @_;  
  $self->{FUNCTION} = "\"setListenEndPoint\"";  
  if(defined $listenEndPoint) {
    $listenEndPoint =~ s/^(\/)+//g;
    $self->{LISTEN_ENDPOINT} = $listenEndPoint;
  }
  else {
    error($self, "Missing argument", __LINE__);  
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
    error($self, "Missing argument", __LINE__);   
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
    error($self, "Missing argument", __LINE__);   
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
    error($self, "Missing argument", __LINE__);  
  }
  return;
}


sub setDebug {
  my ($self, $debug) = @_;  
  $self->{FUNCTION} = "\"setDebug\"";  
  if(defined $debug and $debug ne "") {
    $self->{DEBUG} = $debug;
  }
  else {
    error($self, "Missing argument", __LINE__);    
  }
  return;
}


sub startDaemon {
  my ($self) = @_;  
  $self->{FUNCTION} = "\"startDaemon\"";
  print $self->{FILENAME}.":\tstarting daemon in ".$self->{FUNCTION}."\n" if($self->{DEBUG});  
  $self->{DAEMON} = HTTP::Daemon->new(
    LocalPort => $self->{PORT},
    Reuse => 1
  ) or 
    error($self, "Cannot start daemon", __LINE__);
  return;
}


sub acceptCall {
  my ($self) = @_; 
  my @nodelist = ();
  $self->{FUNCTION} = "\"acceptCall\"";    
  print $self->{FILENAME}.":\taccepting calls in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
  $self->{CALL} = $self->{DAEMON}->accept;
  $self->{REQUEST} = $self->{CALL}->get_request;

  $self->{RESPONSE} = HTTP::Response->new();
  $self->{RESPONSE}->header('Content-Type' => 'text/xml');
  $self->{RESPONSE}->header('user-agent' => 'perfSONAR-PS/'.$VERSION);
  $self->{RESPONSE}->code("200");
   
  # lets strip out the first '/' to enable less stringent check on the endpoint
  (my $requestEndpoint = $self->{REQUEST}->uri) =~ s/^(\/)+//g;

  if($requestEndpoint eq $self->{LISTEN_ENDPOINT} and $self->{REQUEST}->method eq "POST") {
    $action = $self->{REQUEST}->headers->{"soapaction"} ^ $self->{NAMESPACE};    
    if (!$action =~ m/^.*message\/$/) {
      error($self, "Received 'INVALID ACTION TYPE':".$action."\"", __LINE__);      
      return 'INVALID ACTION TYPE';
    }
    else {
      print $self->{FILENAME}.":\tcall accepted in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
        
      my $parser = XML::LibXML->new();
      $self->{REQUESTDOM} = $parser->parse_string($self->{REQUEST}->content);   
#      undef @nodelist;
      @nodelist = $self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "message");      

      if($#nodelist <= -1) {
        my $msg = "Message element not found within request";
        error($self, $msg, __LINE__);  
        $self->{RESPONSE} = getResultCodeMessage(genuid(), "", "response", "error.mp.snmp", $msg);  
        return 2;
      }
      elsif($#nodelist >= 1) {
        my $msg = "Too many message elements found within request";
        error($self, $msg, __LINE__);  
        $self->{RESPONSE} = getResultCodeMessage(genuid(), "", "response", "error.mp.snmp", $msg);  
        return 2;
      }
      else {      
        if($self->{PREFIX} ne $nodelist[0]->prefix) {
          $self->{PREFIX} = $nodelist[0]->prefix;
        }           
        my $messageId = $nodelist[0]->getAttribute("id");
        my $messageType = $nodelist[0]->getAttribute("type");
        
        if($messageType eq "EchoRequest") {
          foreach my $d ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "data")) {  
            foreach my $m ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "metadata")) {  
              if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) { 
                my $eventType = extract($m->find("./nmwg:eventType")->get_node(1));
                if($eventType =~ m/^echo.*/) {
	                my $msg = "The echo request has passed.";
                  $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "EchoResponse", "success.echo", $msg);		  	
                }
                else {
	                my $msg = "The echo request has failed.";
                  error($self, $msg, __LINE__);  
                  $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "EchoResponse", "failure.echo", $msg);		        
                }
              }   
            }
          }
          return 2;
        }
        else {          
          undef $self->{REQUESTDOM};
          $self->{REQUESTDOM} = $parser->parse_string($nodelist[0]->toString);
          $self->{REQUESTDOM} = chainMetadata($self->{REQUESTDOM}, $self->{NAMESPACE});
          foreach my $m ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "metadata")) {
            if(countRefs($m->getAttribute("id"), $self->{REQUESTDOM}, $self->{NAMESPACE}, "data", "metadataIdRef") == 0) {
              $self->{REQUESTDOM}->getDocumentElement->removeChild($m);
            }
          }
          return 1;  
        }   
      }     
    }   
  }
  else {
    error($self, "Reveived 'INVALID ENDPOINT':".$requestEndpoint."\"", __LINE__);  
    return 'INVALID ENDPOINT';      
  }
}


sub getResponse {
  my ($self) = @_;
  $self->{FUNCTION} = "\"getResponse\"";
  if($self->{RESPONSE}) {
    return $self->{RESPONSE};
  }
  else {
    error($self, "Response not found", __LINE__);
    return "";
  }
}


sub getRequestAsXPath {
  my ($self) = @_;
  $self->{FUNCTION} = "\"getRequestAsXPath\"";
  my $xp = XML::XPath->new( xml => $self->{REQUEST}->content );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  return $xp;
}


sub getRequest {
  my ($self) = @_;
  $self->{FUNCTION} = "\"getRequest\"";  

  my $xp = $self->getRequestAsXPath();
  $nodeset = $xp->find('//nmwg:message');
  if($nodeset->size() <= 0) {
    error($self, "Message element not found or in wrong namespace", __LINE__);      
  }
  elsif($nodeset->size() >= 2) {
    error($self, "Too many Message elements found", __LINE__);
  }
  else {
    return XML::XPath::XMLParser::as_string($nodeset->get_node(1));
  }
  return "";
}


sub getRequestDOM {
  my ($self) = @_;
  $self->{FUNCTION} = "\"getRequestDOM\"";
  if($self->{REQUESTDOM}) {
    return $self->{REQUESTDOM};
  }
  else {
    error($self, "Request DOM not found", __LINE__);
    return "";
  }
}


sub setResponseAsXPath {
  my ($self, $xpath) = @_; 
  $self->{FUNCTION} = "\"setResponseAsXPath\"";
  error($self, "Missing argument", __LINE__)
    unless defined $xpath;
  my $content = XML::XPath::XMLParser::as_string( $xpath->findnodes( '/') );
  return $self->setResponse( $content );
}


sub setResponse {
  my ($self, $content, $envelope) = @_;  
  $self->{FUNCTION} = "\"setResponse\"";  
  if(defined $content and $content ne "") {
    if(defined $envelope and $envelope ne "") {
      $content = $self->makeEnvelope($content) ;
    }
    $self->{RESPONSE} = HTTP::Response->parse($content);
  }
  else {
    error($self, "Missing argument", __LINE__);    
  }
  return;
}


sub closeCall {
  my ($self) = @_;
  $self->{FUNCTION} = "\"closeCall\"";    
  if(defined $self->{CALL} and $self->{CALL} ne "") {
    $self->{CALL}->send_response($self->{RESPONSE});    
    $self->{CALL}->close;
    undef($self->{CALL});  
    print $self->{FILENAME}.":\tclosing call in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
  }
  else {
    error($self, "Call not established", __LINE__);  
  }
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

  my $httpEndpoint = qq[http://$self->{CONTACT_HOST}:$self->{CONTACT_PORT}/$self->{CONTACT_ENDPOINT}];

  my $userAgent = "";
  if(defined $timeout and $timeout ne "") {
    $userAgent = LWP::UserAgent->new('timeout' => $timeout);
  }
  else {
    $userAgent = LWP::UserAgent->new('timeout' => 3000);
  }  
  
  print $self->{FILENAME}.":\tsending info in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
  
  my $sendSoap = HTTP::Request->new('POST', $httpEndpoint, new HTTP::Headers, $envelope);
  $sendSoap->header('SOAPAction' => $method_uri);
  $sendSoap->content_type  ('text/xml');
  $sendSoap->content_length(length($envelope));
  
  my $httpResponse = $userAgent->request($sendSoap);
  my $responseCode = $httpResponse->code();
  my $responseContent = $httpResponse->content();
  
  print $self->{FILENAME}.":\tresponse seen in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
  
  return $responseContent;
}


sub error {
  my($self, $msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{"DEBUG"});
  perfSONAR_PS::Common::printError($self->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::Transport - A module that provides methods for listening and contacting 
SOAP endpoints as well as performing other 'transportation' needs for communication in
the perfSONAR-PS framework.

=head1 DESCRIPTION

This module is to be treated a single object, capable of interacting with a given
service (specified by information at creation time).  

=head1 SYNOPSIS

    use perfSONAR_PS::Transport;
    
    my %conf = ();
    %conf{"LOGFILE"} = "./error.log";
    
    my $listener = new perfSONAR_PS::Transport("./error.log", "8080", "/service/MA", "", "", "");
    
    # or also:
    # 
    # my $listener = new perfSONAR_PS::Transport;
    # $listener->setLog("./error.log");
    # $listener->setPort("8080"); 
    # $listener->setListenEndPoint("/service/MA");
    # $listener->setContactHost("");
    # $listener->setContactPort("");
    # $listener->setContactEndPoint("");
    # $listener->setDebug($debug);     
                        
    $listener->startDaemon;
    while(1) {
      my $responseContent = "";
      if($listener->acceptCall == 1) {
        print "Request Message Was:\n" , $listener->getRequest , "\n";  
 
        # or
	#
        # print "Request Message Was:\n" , $listener->getRequestAsXPath , "\n"; 
      
        #...      
  
  	# we want to have an envelope made...
        $listener->setResponse($responseContent, 1);

        # or
	#
        # $listener->setResponseAsXPath($XPathResponse);	
      }
      else {
        print "Error\n";  

        #...

        # we will make our own envelope...
        $listener->setResponse($listener->makeEnvelope($responseContent));

        # or
	#
        # $listener->setResponseAsXPath($XPathResponse);
      }
      $listener->closeCall;
    }
    
    my $sender = new perfSONAR_PS::Transport("./error.log", "", "", "localhost", "8080", "/service/MA");
    
    my $reply = $sender->sendReceive($listener->makeEnvelope($request), 2000);
    
=head1 DETAILS

The API for this module aims to be simple and robust.  This module may be used in place
of other SOAP implementations (SOAP::Lite for example) when it is necessary to use a 
Document-Literal message structure.

=head1 API

The API of the transport class is meant to simplfy common information transportation issues in
WS envirnments.  

=head2 new(\%conf, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint)

The 'log' argument is the name of the log file where error or warning information may be 
recorded.  The 'port' and 'listenEndPoint' arguments set values that will be used if the 
object will be used to listen for and accept incomming calls.  The 'contactHost', 
'contactPort', and 'contactEndPoint' set the values that are used if the object is used 
to send information to a remote host.  All values can be left blank and set via the 
various set functions.

=head2 setLog($log)

(Re-)Sets the name of the log file to be used.  

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
  
=head2 setDebug($debug)

(Re-)Sets the value of the $debug switch.
  
=head2 startDaemon()

Starts an HTTP daemon on the given host listening to the specified port.  This method will
cause the program to halt if the port in question is not available.

=head2 acceptCall()

Listens on the 'host:port/endPoint' for any requests.  The requests are checked for validity
and a message is returned on error, a 1 is returned on success.  On success the request message
can be parsed via the getRequest() method. The possible messages that may be returned on error
are:
	
	'INVALID ACTION TYPE'
	'INVALID ENDPOINT'
	
These correspond to the obvious errors.
	
=head2 getRequest()

Returns the nmwg:message from a given request.  If there is no message, or too many message 
elements present, the object will halt.

=head2 getRequestAsXPath()

Returns the nmwg:message from a given request in the form of an XPath object.  If there is no 
message, or too many message elements present, the object will halt.

=head2 setResponse($content, $envelope)

Sets the content of a response messages.  'envelope' is a boolean value indicating if we need
an envelope to be constructed.  

=head2 setResponseAsXPath($xpath)

Sets the content of a response messages where the input is an XPath object.

=head2 closeCall()

Closes a given call to the service by sending a response message.

=head2 makeEnvelope($content)

Makes a SOAP formated envelope.

=head2 sendReceive($envelope, $timeout)

Sents a soap formated envelope, and a timeout value to the contact host/port/endPoint.

=head2 error($self, $msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<Carp>, L<HTTP::Daemon>, L<HTTP::Response>, L<HTTP::Headers>, L<HTTP::Status>, 
L<XML::XPath>, L<XML::Writer>, L<XML::Writer::String>, L<LWP::UserAgent>, 
L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

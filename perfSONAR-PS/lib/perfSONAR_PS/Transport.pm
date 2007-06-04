#!/usr/bin/perl -w

package perfSONAR_PS::Transport;

use warnings;
use Carp qw( carp );
use Exporter;

use HTTP::Daemon;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use XML::XPath;
use XML::Writer;
use XML::Writer::String;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ();
$VERSION = "1";

sub new {
  my ($package, $ns, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint) = @_; 
  
  my %hash = ();
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = $ns;
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
    
  $hash{"SOAP_ENV"} = "http://schemas.xmlsoap.org/soap/envelope/";
  $hash{"SOAP_ENC"} = "http://schemas.xmlsoap.org/soap/encoding/";
  $hash{"XSD"} = "http://www.w3.org/2001/XMLSchema";
  $hash{"XSI"} = "http://www.w3.org/2001/XMLSchema-instance";
  $hash{"NAMESPACE"} = "http://ggf.org/ns/nmwg/base/2.0/";
  $hash{"PREFIX"} = "nmwg";
  $hash{"REQUESTNAMESPACES"} = "";
  
  bless \%hash => $package;
}


sub setNamespaces {
  my ($self, $ns) = @_;    
  my $logger = get_logger("perfSONAR_PS::Transport");
   
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if(defined $port) {
    $self->{PORT} = $port;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub setListenEndPoint {
  my ($self, $listenEndPoint) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if(defined $listenEndPoint) {
    $listenEndPoint =~ s/^(\/)+//g;
    $self->{LISTEN_ENDPOINT} = $listenEndPoint;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setContactHost {
  my ($self, $contactHost) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if(defined $contactHost) {
    $self->{HOST} = $contactHost;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setContactPort {
  my ($self, $contactPort) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if(defined $contactPort) {
    $self->{PORT} = $contactPort;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setContactEndPoint {
  my ($self, $contactEndPoint) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
   
  if(defined $contactEndPoint) {
    $self->{CONTACT_ENDPOINT} = $contactEndPoint;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub startDaemon {
  my ($self) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  $logger->debug("Starting daemon."); 
  $self->{DAEMON} = HTTP::Daemon->new(
    LocalPort => $self->{PORT},
    ReuseAddr => 1
  ) or $logger->error("Cannot start daemon.");
  return;
}


sub acceptCall {
  my ($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::Transport");
     
  $logger->debug("Accepting calls.");

  delete $self->{CALL};
  $self->{CALL} = $self->{DAEMON}->accept;
  delete $self->{REQUEST};
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
      $logger->error("Received message with 'INVALID ACTION TYPE'.");     
      return 'INVALID ACTION TYPE';
    }
    else {
      $logger->debug("Accepted call.");

   	  my $xp = XML::XPath->new( xml => $self->{REQUEST}->content );
      my $nodeset = $xp->find("//nmwg:message");
      if($nodeset->size() <= 0) {
        my $msg = "Message element not found within request";
        $logger->error($msg);
        $self->{RESPONSE} = getResultCodeMessage(genuid(), "", "response", "error.mp.snmp", $msg);  
        return 0;
      }
      elsif($nodeset->size() > 1) {
        my $msg = "Too many message elements found within request";
        $logger->error($msg); 
        $self->{RESPONSE} = getResultCodeMessage(genuid(), "", "response", "error.mp.snmp", $msg);  
        return 0;      
      }    
      else {   
        my $parser = XML::LibXML->new(); 
        delete $self->{REQUESTDOM}; 
        
        $self->{REQUESTDOM} = $parser->parse_string(XML::XPath::XMLParser::as_string($nodeset->get_node(1)));
        $self->{REQUESTNAMESPACES} = reMap(\%{$self->{REQUESTNAMESPACES}}, \%{$self->{NAMESPACES}}, $self->{REQUESTDOM}->getDocumentElement);          

        my $messageId = $self->{REQUESTDOM}->getDocumentElement()->getAttribute("id");
        my $messageType = $self->{REQUESTDOM}->getDocumentElement()->getAttribute("type");

        if($messageType eq "EchoRequest") {              
          if($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "data")->get_node(1)->getAttribute("metadataIdRef") eq
             $self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "metadata")->get_node(1)->getAttribute("id")) {
            my $eventType = extract($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "metadata")->get_node(1)->find("./nmwg:eventType")->get_node(1));
            if($eventType =~ m/^echo.*/) {
	            my $msg = "The echo request has passed.";
	            $logger->debug($msg);
              $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "EchoResponse", "success.echo", $msg);		  	                 
            }
            else {
	            my $msg = "The echo request has failed.";
              $logger->error($msg);
              $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "EchoResponse", "failure.echo", $msg);		        
            }          
          }
          return 0;
        }
        else {  
          $self->{REQUESTDOM} = chainMetadata($self->{REQUESTDOM}, $self->{NAMESPACE});   
          foreach my $m ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACE}, "metadata")) {
            if(countRefs($m->getAttribute("id"), $self->{REQUESTDOM}, $self->{NAMESPACE}, "data", "metadataIdRef") == 0) {
              $logger->debug("Removing child metadata \"".$m->getAttribute("id")."\" from the DOM.");
              $self->{REQUESTDOM}->getDocumentElement->removeChild($m); 
            }
          }    
          return 1;  
        }         
      } 
    }   
  }
  else { 
    $logger->error("Received message with 'INVALID ENDPOINT'.");
    return 'INVALID ENDPOINT';      
  }
}


sub getResponse {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if($self->{RESPONSE}) {
    return $self->{RESPONSE};
  }
  else {
    $logger->error("Response not found.");
    return "";
  }
}


sub getRequestNamespaces {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if($self->{REQUESTNAMESPACES}) {
    return $self->{REQUESTNAMESPACES};
  }
  else {
    $logger->error("Request namespace object not found.");
    return "";
  }
}


sub getRequestAsXPath {
  my ($self) = @_;
  
  my $xp = XML::XPath->new( xml => $self->{REQUEST}->content );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  return $xp;
}


sub getRequest {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");

  my $xp = $self->getRequestAsXPath();
  $nodeset = $xp->find('//nmwg:message');
  if($nodeset->size() <= 0) {
    $logger->error("Message element not found or in wrong namespace.");     
  }
  elsif($nodeset->size() >= 2) {
    $logger->error("Too many Message elements found.");  
  }
  else {
    return XML::XPath::XMLParser::as_string($nodeset->get_node(1));
  }
  return "";
}


sub getRequestDOM {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if($self->{REQUESTDOM}) {
    return $self->{REQUESTDOM};
  }
  else {
    $logger->error("Request DOM not found.");
    return "";
  }
}


sub setResponseAsXPath {
  my ($self, $xpath) = @_; 
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  $logger->error("Missing argument.") unless defined $xpath;
  my $content = XML::XPath::XMLParser::as_string( $xpath->findnodes( '/') );
  return $self->setResponse( $content );
}


sub setResponse {
  my ($self, $content, $envelope) = @_;  
  my $logger = get_logger("perfSONAR_PS::Transport");
   
  if(defined $content and $content ne "") {
    if(defined $envelope and $envelope ne "") {
      $content = $self->makeEnvelope($content) ;
    }
    $self->{RESPONSE} = HTTP::Response->parse($content);
  }
  else {
    $logger->error("Missing argument.");    
  }
  return;
}


sub closeCall {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
 
  if(defined $self->{CALL} and $self->{CALL} ne "") {
    $self->{CALL}->send_response($self->{RESPONSE});    
    $self->{CALL}->close;
    delete $self->{CALL};  
    $logger->debug("Closing call.");    
  }
  else {
    $logger->error("Call not established.");      
  }
  return;
}


sub makeEnvelope {
  my($self, $content) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
   
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
  $logger->debug("Envelope created."); 
  return $envelope->value;
}


sub sendReceive {
  my($self, $envelope, $timeout) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
   
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
  
  $logger->debug("Sending information to \"".$httpEndpoint."\"."); 
  
  my $sendSoap = HTTP::Request->new('POST', $httpEndpoint, new HTTP::Headers, $envelope);
  $sendSoap->header('SOAPAction' => $method_uri);
  $sendSoap->content_type  ('text/xml');
  $sendSoap->content_length(length($envelope));
  
  my $httpResponse = $userAgent->request($sendSoap);
  my $responseCode = $httpResponse->code();
  my $responseContent = $httpResponse->content();
  
  $logger->debug("Response returned."); 
  
  return $responseContent;
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

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $listener = new perfSONAR_PS::Transport(\%{ns}, $conf{"LOGFILE"}, "8080", "/service/MA", "", "", "", 1);
    
    # or also:
    # 
    # my $listener = new perfSONAR_PS::Transport;
    # $listener->setNamespaces(\%{ns});
    # $listener->setLog("./error.log");
    # $listener->setPort("8080"); 
    # $listener->setListenEndPoint("/service/MA");
    # $listener->setContactHost("");
    # $listener->setContactPort("");
    # $listener->setContactEndPoint("");
    # $listener->setDebug($debug);     
                        
    $listener->startDaemon;
    
    while(1) {
      my $readValue = $listener->acceptCall;
      my $responseContent = "";
      if($readValue == 0) {

        print "The \"perfSONAR_PS::Transport\" has taken care of this request.\n";    
        $responseContent = $listener->getResponse();

  	    # we want to have an envelope made...
        $listener->setResponse($responseContent, 1);
      }
      elsif($readValue == 1) {
        print "Request Message Was:\n" , $listener->getRequest , "\n";  
 
        # or
        # print "Request Message Was:\n" , $listener->getRequestAsXPath , "\n"; 
      
        #...      
  
  	    # we want to have an envelope made...
        $listener->setResponse($responseContent, 1);

        # or
        # $listener->setResponseAsXPath($XPathResponse);	
      }
      else {
        print "Error\n";  

        #...

        # we will make our own envelope...
        $listener->setResponse($listener->makeEnvelope($responseContent));

        # or
        # $listener->setResponseAsXPath($XPathResponse);
      }
      $listener->closeCall;
    }
    
    my $sender = new perfSONAR_PS::Transport("", $conf{"LOGFILE"}, "", "", "localhost", "8080", "/service/MA", 1);
    
    my $reply = $sender->sendReceive($listener->makeEnvelope($request), 2000);
    
=head1 DETAILS

The API for this module aims to be simple and robust.  This module may be used in place
of other SOAP implementations (SOAP::Lite for example) when it is necessary to use a 
Document-Literal message structure.

=head1 API

The API of the transport class is meant to simplfy common information transportation issues in
WS envirnments.  

=head2 new(\%ns, $log, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint, $debug) 

The 'ns' argument is a hash of namespace to prefix mappings.  The 'log' argument is the name of 
the log file where error or warning information may be recorded.  The 'port' and 'listenEndPoint' 
arguments set values that will be used if the object will be used to listen for and accept 
incomming calls.  The 'contactHost', 'contactPort', and 'contactEndPoint' set the values that 
are used if the object is used to send information to a remote host.  All values can be left 
blank and set via the various set functions.


=head2 setNamespaces($self,\%ns)

(Re-)Sets the value for the 'namespace' hash. 


=head2 setLog($self, $log)  

(Re-)Sets the value for the 'log' variable.


=head2 setPort($self, $port)  

(Re-)Sets the value for the 'port' variable.  This value 
represents which particular TCP port on the host that will 
have the listening service.

  
=head2 setListenEndPoint($self, $listenEndPoint)  

(Re-)Sets the value for the 'listenEndPoint' variable.  This 
value represents which particular 'endPoint' (path) the service 
will be hosting.  For example the host 'localhost' may be 
listening on '8080' for a particular service, and there may 
be several services that can be handled on a specific machine 
such as an LS, or MP.  So a sample 'endPoint' for this service:

http://localhost:8080/services/MP

Would be '/services/MP'.


=head2 setContactHost($self, $contactHost)  

(Re-)Sets the value for the 'contactHost' variable.  The contact 
host is the hostname of a remote host that is supplying a service.


=head2 setContactPort($self, $contactPort)  

(Re-)Sets the value for the 'contactPort' variable.  The 
contact port is the port on a remote host that is supplying a 
service.


=head2 setContactEndPoint($self, $contactEndPoint)  

(Re-)Sets the value for the 'contactEndPoint' variable.  The 
contact endPoint is the endPoint on a remote host that is 
supplying a service.  See 'setListenEndPoint' for a more 
detailed description.


=head2 setDebug($self, $debug)

(Re-)Sets the value for the 'debug' variable.


=head2 startDaemon($self)

Starts an HTTP daemon on the given host listening to the specified port.  
This method will cause the program to halt if the port in question is 
not available.


=head2 acceptCall($self)

Listens on the 'host:port/endPoint' for any requests.  The requests 
are checked for validity and a message is returned on error, a 1 is 
returned on success, or a 0 is returned if the request can be handled 
'locally', without the aide of the upper level service framework.  
On success the request message can be parsed via the getRequest() 
method. The possible messages that may be returned on error are:
	
	'INVALID ACTION TYPE'
	'INVALID ENDPOINT'
	
These correspond to the obvious errors.


=head2 getResponse($self)

Returns a 'prepraed' response, if one exists.  One may exist
due to the echo service making one, or an obvious error seen in
the message.  This response will be used instead of the
upper level being required.


=head2 getRequestNamespaces($self)

Returns a mapping of request namespaces.


=head2 getRequestAsXPath($self)

Returns the nmwg:message from a given request in the form of an XPath 
object.


=head2 getRequest($self)

Returns the nmwg:message from a given request.


=head2 getRequestDOM($self)

Returns the nmwg:message as a LibXML DOM from a given 
request.


=head2 setResponseAsXPath($self, $xpath)

Sets the content of a response messages where the input is an 
XPath object.


=head2 setResponse($self, $content, $envelope)
  
Sets the content of a response messages.  'envelope' is a boolean 
value indicating if we need an envelope to be constructed.    
  
  
=head2 closeCall($self)

Closes a given call to the service by sending a response message.


=head2 makeEnvelope($self, $content)

Makes a SOAP formated envelope.


=head2 sendReceive($self, $envelope, $timeout)

Sents a soap formated envelope, and a timeout value to the contact host/port/endPoint.


=head2 error($self, $msg, $line)

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.


=head1 SEE ALSO

L<Carp>, L<Exporter>, L<HTTP::Daemon>, L<HTTP::Response>, L<HTTP::Headers>, 
L<HTTP::Status>, L<XML::XPath>, L<XML::Writer>, L<XML::Writer::String>, 
L<LWP::UserAgent>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>

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

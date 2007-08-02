#!/usr/bin/perl -w

package perfSONAR_PS::Transport;

use warnings;
use Carp qw( carp );
use Exporter;

use HTTP::Daemon;
use HTTP::Response;
use HTTP::Headers;
use HTTP::Status;
use XML::Writer;
use XML::Writer::String;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger);
use XML::LibXML;

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
   
  if(defined $ns and $ns ne "") {   
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


sub splitURI
{
	my $uri = shift;
	my $host = undef;
	my $port= undef;
	my $endpoint = undef;
	if ( $uri =~ /^http:\/\/([^\/]*)\/?(.*)$/ ) {
		( $host, $port ) = split /:/, $1;
		$endpoint = $2;
	} 
	if ( ! defined $port || $port eq '' ) {
		$port = 80;
	}
	if ( $port =~ m/^:/ ) {
		$port =~ s/^://g;
	}
	$endpoint = '/' . $endpoint unless $endpoint =~ /^\//;

	return ( $host, $port, $endpoint );
}

sub getHttpURI {
	my $host= shift;
	my $port = shift;
	my $endpoint = shift;
	return 'http://' . $host . ':' . $port . '/' . $endpoint;
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
  my ($self, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::Transport");
     
  $logger->debug("Accepting calls.");

  delete $self->{CALL};
  $self->{CALL} = $self->{DAEMON}->accept;
  delete $self->{REQUEST};
  $self->{REQUEST} = $self->{CALL}->get_request;
  my $msg = "";
  
  $$error = "" if (defined $error);

  $self->{RESPONSE} = HTTP::Response->new();
  $self->{RESPONSE}->header('Content-Type' => 'text/xml');
  $self->{RESPONSE}->header('user-agent' => 'perfSONAR-PS/'.$VERSION);
  $self->{RESPONSE}->code("200");

  # lets strip out the first '/' to enable less stringent check on the endpoint
  (my $requestEndpoint = $self->{REQUEST}->uri) =~ s/^(\/)+//g;

  if($requestEndpoint eq $self->{LISTEN_ENDPOINT}) {
    if($self->{REQUEST}->method eq "POST") {
      my $action = $self->{REQUEST}->headers->{"soapaction"} ^ $self->{NAMESPACE};    
      if (!$action =~ m/^.*message\/$/) {
        $msg = "Received message with 'INVALID ACTION TYPE'.";
        $logger->error($msg);     
        $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);       
	      $$error = $msg if (defined $error);
        return 0;
      }
      else {
        $logger->debug("Accepted call.");

        my $parser = XML::LibXML->new(); 
        delete $self->{REQUESTDOM}; 
        eval { 
          $self->{REQUESTDOM} = $parser->parse_string($self->{REQUEST}->content);
        };
        if($@) {
          my $msg = "Parse failed: ".$@;
          $msg =~ s/&/&amp;/g;
          $msg =~ s/</&lt;/g;
          $msg =~ s/>/&gt;/g;
          $msg =~ s/'/&apos;/g;
          $msg =~ s/"/&quot;/g;
          $logger->error($msg);
	        $$error = $msg if (defined $error);
          $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "ErrorResponse", "error.common.parse_error", $msg);
          return 0;
        }

        $self->{REQUESTNAMESPACES} = reMap(\%{$self->{REQUESTNAMESPACES}}, \%{$self->{NAMESPACES}}, $self->{REQUESTDOM}->getDocumentElement);   
        
        if($self->{REQUESTDOM}->getDocumentElement->lookupNamespacePrefix("http://ggf.org/ns/nmwg/base/2.0/")) {
          my $messages = $self->{REQUESTDOM}->getDocumentElement->find(".//nmwg:message");
          if($messages->size() <= 0) {
            my $msg = "Message element not found within request";
            $logger->error($msg);
            $$error = $msg if (defined $error);
            $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);  
            return 0;
          }
          elsif($messages->size() > 1) {
            my $msg = "Too many message elements found within request";
            $logger->error($msg); 
	          $$error = $msg if (defined $error);
            $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);  
            return 0;      
          }    
          else {   
            my $messageId = $messages->get_node(1)->getAttribute("id");
            my $messageType = $messages->get_node(1)->getAttribute("type");
            $self->{REQUESTDOM} = $parser->parse_string($messages->get_node(1)->toString);

            if($messageType eq "EchoRequest") { 
              my $localContent = "";
              foreach my $d ($self->{REQUESTDOM}->getDocumentElement()->getElementsByTagNameNS($self->{NAMESPACE}, "data")) {      
                my $m = $self->{REQUESTDOM}->getDocumentElement()->find("./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]")->get_node(1);
                if(defined $m) {        
                  $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");
                  my $eventType = extract($m->find("./nmwg:eventType")->get_node(1));
                  if($eventType =~ m/^echo.*/ or 
                     $eventType eq "http://schemas.perfsonar.net/tools/admin/echo/2.0") {
	                  my $msg = "The echo request has passed.";
	                  $logger->debug($msg);
	                  my $mdID = "metadata.".genuid();
	                  $localContent = $localContent . getResultCodeMetadata($mdID, $m->getAttribute("id"), "success.echo");
	                  $localContent = $localContent . getResultCodeData("data.".genuid(), $mdID, $msg);
                  }
                  else {
	                  my $msg = "The echo request has failed; using the wrong eventType?";
                    $logger->error($msg);
	                  my $mdID = "metadata.".genuid();
	                  $localContent = $localContent . getResultCodeMetadata($mdID, $m->getAttribute("id"), "failure.echo");
	                  $localContent = $localContent . getResultCodeData("data.".genuid(), $mdID, $msg);
                  }   
                }
              }
              $self->{RESPONSEMESSAGE} = getResultMessage("message.".genuid(), $messageId, "EchoResponse", $localContent);   
              return 0;
            }
            else {  
              $self->{REQUESTDOM} = chainMetadata($self->{REQUESTDOM}, $self->{NAMESPACE});   
              return 1;  
            }         
          } 
        }
        else {
          $msg = "Received message with incorrect message URI.";
          $logger->error($msg);     
          $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);  
	        $$error = $msg if (defined $error);
          return 0;   
        }
      }
    }
    else {
      $msg = "Received message with 'INVALID REQUEST', are you using a web browser?";
      $logger->error($msg);     
      $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);  
      $$error = $msg if (defined $error);
      return 0;
    }   
  }
  else { 
    $msg = "Received message with 'INVALID ENDPOINT'.";
    $logger->error($msg);     
    $self->{RESPONSEMESSAGE} = getResultCodeMessage("message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg);  
    $$error = $msg if (defined $error);
    return 0;
  }
}


sub getResponse {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::Transport");
  
  if($self->{RESPONSEMESSAGE}) {
    return $self->{RESPONSEMESSAGE};
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
  my $nodeset = $xp->find('//nmwg:message');
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
    $self->{RESPONSE}->message("success");
    $self->{RESPONSE}->content($content);
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
  my $method_uri = "http://ggf.org/ns/nmwg/base/2.0/message/";
  my $httpEndpoint = &getHttpURI( $self->{CONTACT_HOST}, $self->{CONTACT_PORT}, $self->{CONTACT_ENDPOINT});

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
  
  # lets do some error checking:
  if ( $responseContent =~ /^500 Cant connect to .* \((.*)\)/ ) {
 	die "Could not connect to $httpEndpoint: $1.\n"; 
  }
  # others?
  
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

The API of the transport class is meant to simplfy common information transportation 
issues in WS envirnments.  

=head2 new($package, $ns, $port, $listenEndPoint, $contactHost, $contactPort, $contactEndPoint) 

The 'ns' argument is a hash of namespace to prefix mappings.  The 'port' and 
'listenEndPoint' arguments set values that will be used if the object will be 
used to listen for and accept incomming calls.  The 'contactHost', 'contactPort', 
and 'contactEndPoint' set the values that are used if the object is used to 
send information to a remote host.  All values can be left blank and set via 
the various set functions.

=head2 setNamespaces($self,\%ns)

(Re-)Sets the value for the 'namespace' hash. 

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

=head2 splitURI($uri)

Splits the contents of a URI into host, port, and endpoint.

=head2 getHttpURI($host, $port, $endpoint)

Creates a URI from a host, port, and endpoint

=head2 startDaemon($self)

Starts an HTTP daemon on the given host listening to the specified port.  
This method will cause the program to halt if the port in question is 
not available.

=head2 acceptCall($self)

Accepts a call from the daemon, and performs the necessary handling 
operations.

=head2 getResponse($self)

Gets and returns the contents of the RESPONSE string.  

=head2 getRequestNamespaces($self)

Gets and returns the contents of the REQUESTNAMESPACE hash.  

=head2 getRequestAsXPath($self)

Gets and returns the request as an XPath object.  

=head2 getRequest($self)

Gets and returns the contents of the REQUEST string.  

=head2 getRequestDOM($self)

Gets and returns the contents of the REQUEST as a DOM object.  

=head2 setResponseAsXPath($self, $xpath) 

Sets the RESPONSE as an XPath object.

=head2 setResponse($self, $content, $envelope) 

Sets the response to the content, allows you to specify if
an envelope is or is not needed.

=head2 closeCall($self)

Closes a call, undefs variables.

=head2 makeEnvelope($self, $content)

Makes a SOAP envelope for some content.
  
=head2 sendReceive($self, $envelope, $timeout)

Sends and receives a SOAP envelope.

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<HTTP::Daemon>, L<HTTP::Response>, L<HTTP::Headers>, 
L<HTTP::Status>, L<XML::XPath>, L<XML::Writer>, L<XML::Writer::String>, 
L<LWP::UserAgent>, L<Log::Log4perl>, L<XML::LibXML>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

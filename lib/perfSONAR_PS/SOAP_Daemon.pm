package perfSONAR_PS::SOAP_Daemon;

use fields 'PORT', 'DAEMON';

use version; our $VERSION = qv("0.01");

use warnings;
use Exporter;
use HTTP::Daemon;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Request;

sub new {
    my ($package, $port) = @_; 

    my $self = fields::new($package);
    if(defined $port and $port ne "") {
        $self->{PORT} = $port;
    }

    return $self;
}

sub setPort {
    my ($self, $port) = @_;  
    my $logger = get_logger("perfSONAR_PS::Transport");
    if(defined $port) {
        $self->{PORT} = $port;
    } else {
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
            ReuseAddr => 1,
            Timeout => 30,
            ); 

    if (!defined $self->{DAEMON}) {
        $logger->error("Cannot start daemon.");
        return -1;
    }

    $logger->info("Started daemon on port:\t".$self->{PORT});

    return 0;
}

sub receive {
    my ($self, $ret_request, $error) = @_; 
    my $logger = get_logger("perfSONAR_PS::Transport");
    my $error_msg;

    $$error = "" if (defined $error);

    $logger->debug("Accepting calls.");

    my $call = $self->{DAEMON}->accept;
    if (!defined $call) {
        my $msg = "Accept returned nothing, likely a timeout occurred";
        $logger->debug($msg);
        return 0;
    }

    $logger->info("Received call from:\t".$call->peerhost());

    my $http_request = $call->get_request;
    if (!defined $http_request) {
        my $msg = "No HTTP Request received from host:\t".$call->peerhost();
        $logger->error($msg);
        $$error = $msg if (defined $error);
        $call->close;
        return -1;
    }

    my $request = perfSONAR_PS::Request->new($call, $http_request);

    $$ret_request = $request;

    my $msg = "";

    if($http_request->method ne "POST") {
        $msg = "Received message with 'INVALID REQUEST', are you using a web browser?";
        $logger->error($msg);     
        $$error = $msg if (defined $error);
        return -1;
    }

    #  my $action = $http_request->headers->{"soapaction"} ^ $self->{NAMESPACE};    
    my $action = $http_request->headers->{"soapaction"};
    if (!$action =~ m/^.*message\/$/) {
        $msg = "Received message with 'INVALID ACTION TYPE'.";
        $logger->error($msg);     
        $$error = $msg if (defined $error);
        return -1;
    }

    $logger->debug("Accepted call.");

    return 0;  
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
        $listener->setResponse(makeEnvelope($responseContent));

        # or
        # $listener->setResponseAsXPath($XPathResponse);
      }
      $listener->closeCall;
    }
    
    my $sender = new perfSONAR_PS::Transport("", $conf{"LOGFILE"}, "", "", "localhost", "8080", "/service/MA", 1);
    my $error;
    my $reply = $sender->sendReceive(makeEnvelope($request), 2000, \$error);
    
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

=head2 splitURI($uri)

Splits the contents of a URI into host, port, and endpoint.

=head2 getHttpURI($host, $port, $endpoint)

Creates a URI from a host, port, and endpoint

=head2 setContactEndPoint($self, $contactEndPoint)  

(Re-)Sets the value for the 'contactEndPoint' variable.  The 
contact endPoint is the endPoint on a remote host that is 
supplying a service.  See 'setListenEndPoint' for a more 
detailed description.

=head2 startDaemon($self)

Starts an HTTP daemon on the given host listening to the specified port.  
This method will return 0 on success and -1 on failure.

=head2 acceptCall($self, $ret_request, $error)

Accepts a call from the daemon, and performs the necessary handling operations.
Returns a perfSONAR_PS::Request object in the $ret_request reference. Returns 0
if a lower layer has handled it, 1 if a response is needed and -1 if the socket
timed out or the incoming connection didn't send an HTTP request.
 
=head2 sendReceive($self, $envelope, $timeout, $error)

Sends and receives a SOAP envelope. $error is a pointer to a variable. If an
error message is generated, it is filled with that message. If not, it is
filled with "".

=head1 SEE ALSO

L<Exporter>, L<HTTP::Daemon>, L<Log::Log4perl>, 
L<XML::XPath>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id: Transport.pm 612 2007-09-26 13:05:28Z aaron $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4

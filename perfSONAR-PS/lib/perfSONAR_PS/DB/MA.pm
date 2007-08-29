#!/usr/bin/perl


=head1 NAME

perfSONAR_PS::DB::MA - A module that provides simple database accessor methods for the 
remote storage of local dom (libXML) to a defined MA.
Could potentially be used as a proxy class in future to redirect storage calls.

=head1 DESCRIPTION

The purpose of this module is to enable the non co-location of a MP and MA instance. For
example, it may be beneficial to house a cental MA for all MP's, and not have MP's actually do 
any storage of data locally on the machines that they are running on. This module allows MPs to 
treat a remote MA instance as if it were a local Storage subsystem.

It bascially works as a proxy for the perfSONAR xml storeRequest messages.

=head1 SYNOPSIS

    use perfSONAR_PS::DB::MA;

	# Preparing data storage for Measurement Archive located at $uri
	my $uri = 'http://localhost:8080/some/endpoint/service
    my ( $host, $port, $endpoint ) = &perfSONAR_PS::Transport::splitURI( $uri );

	# connect to the remote database (opens socket connection to $uri)
	my $db = new perfSONAR_PS::DB::MA( $host, $port, $endpoint );
	$db->openDB();

    # or also:
    # 
    # my $db = new perfSONAR_PS::DB::SQL;
    # $db->setHost("localhost");
    # $db->setPort("8080");
    # $db->setEndPoint("/some/endpoint/service");     

    if ($db->openDB == -1) {
      print "Error opening database\n";
    }

    # data retrival systems not implemented (is there a need?)

    # assume that we have a instance dom storeRequest document from the output of
    # an MP as $dom

    $status = $db->insert( $dom );
    if($status == -1) {
      print "Error executing insert statement\n";
    }

    if ($db->closeDB == -1) {
      print "Error closing database\n";
    }
=cut


package perfSONAR_PS::DB::MA;


use XML::LibXML;
use perfSONAR_PS::Transport;
use Log::Log4perl qw(get_logger);

my $logger = get_logger("perfSONAR_PS::DB::MA");

sub new {
  my ($package, $host, $port, $endpoint ) = @_; 
  my %hash = ();
   if(defined $host and $host ne "") {
    $hash{"HOST"} = $host;
  } 
  if(defined $port and $port ne "") {
    $hash{"PORT"} = $port;
  }
  if(defined $endpoint and $endpoint ne "") {
    $hash{"ENDPOINT"} = $endpoint;
  }
  
  bless \%hash => $package;
}


sub setFile {
  my ($self, $file) = @_;  

  if(defined $file and $file ne "") {
    $self->{FILE} = $file;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}



sub setHost {
  my ($self, $host) = @_;  

  if(defined $host and $host ne "") {
    $self->{HOST} = $host;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  

  if(defined $port and $port ne "") {
    $self->{PORT} = $port;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}

sub setEndpoint {
  my ($self, $endpoint) = @_;  

  if(defined $endpoint and $endpoint ne "") {
    $self->{ENDPOINT} = $endpoint;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}



###
# opens a connection to the remote ma
###
sub openDB {
  my ($self) = @_;
  if(defined $self->{HOST} && defined $self->{PORT} && defined $self->{ENDPOINT}) {
  
    eval {
	    $self->{"TRANSACTION"} = new perfSONAR_PS::Transport("", "", "", $self->{HOST}, $self->{PORT}, $self->{ENDPOINT});
   		#$logger->debug( "SETUP: "  . $self->{"TRANSACTION"});
    };
    # mor specific error?
    if ( $@ ) {
	    $logger->error("Cannot open connection to " . $self->{HOST} . ':' . $self->{PORT} . '/' . $self->{ENDPOINT} . "." );      
    }
  }
  else {
  	$looger->error( "Connection settings missing: ". $self->{HOST} . ':' . $self->{PORT} . '/' . $self->{ENDPOINT} . "."  );
  }                  
  return;
}


sub closeDB {
  my ($self) = @_;

  if(defined $self->{TRANSACTION} and $self->{TRANSACTION} ne "") {
	# no state, so nothing to close
  }
  else {
    $logger->error("No connection to remote MA defined.");  
  }
  return;
}



sub getDOM {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{XML} and $self->{XML} ne "") {
    return $self->{XML};  
  }
  else {
    $logger->error("LibXML DOM structure not defined."); 
  }
  return ""; 
}


sub setDOM {
  my($self, $dom) = @_;
  if(defined $dom and $dom ne "") {    
    $self->{XML} = $dom;
  }
  else {
    $logger->error("Missing argument.");
  }   
  return;
}


###
# set/gets the error message last seen
##
sub error
{
	my $self = shift;
	if ( @_ ) {
		$self->{ERROR} = shift;
	}
	return $self->{ERROR};
}

sub insert
{
	my $self = shift;
	my $dom = shift;
	
	if ( defined $dom ) {
		$self->setDOM( $dom );
	}
	
	if( defined $self->{"TRANSACTION"} ) {
	if ( defined $self->{XML} ) {
		# Make a SOAP envelope, use the XML file as the body.
		#$logger->debug( "TRANSACTION: " . $self->{"TRANSACTION"} );
		my $envelope = $self->{"TRANSACTION"}->makeEnvelope($self->{XML});
		# Send/receive to the server, store the response for later processing
		my $responseContent = $self->{"TRANSACTION"}->sendReceive($envelope);
		
		# TODO: should a remote ma respond with anything? like a confirmation?
		$logger->debug( "RESPONSE: $responseContent");
		
		if ( $responseContent =~ /(The requested URL .* was not found on this server.)/ ) {
			$self->error( "$1" );
			return -1;
		}
	}
	else {
		$logger->error("Could not insert blank document.")
	}

	} else {
		$logger->error("Transaction has not been setup.")
	}
	return 0;
}

1;
#!/usr/bin/perl -w

package perfSONAR_PS::LS::Register;

use strict;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;

our @ISA = ('Exporter');
our @EXPORT = ();


sub new {
  my ($package, $conf, $ns) = @_; 
  my %hash = ();
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }      
  $hash{"ALIVE"} = 0;
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    $logger->error("Missing argument."); 
  }
  return;
}


sub setNamespaces {
  my ($self, $namespaces) = @_;    
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$namespaces};
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}

sub createKeyMetadata($$$$) {
  my($self, $output, $id, $metadataIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
 
  if(!defined $id or $id eq "") {
    $id = "metadata.".genuid();
  }

  startMetadata($output, $id, "", undef);
   $output->startElement("nmwg", "http://ggf.org/ns/nmwg/base/2.0/", "key", { id=>"key.".genuid() }, undef);
    startParameters($output, "parameters.".genuid());
     addParameter($output, "lsKey", $self->{"CONF"}->{"SERVICE_ACCESSPOINT"});
    endParameters($output);
   $output->endElement("key");
  endMetadata($output);
}


sub createServiceMetadata {
  my($self, $output, $id, $metadataIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  if(!defined $id or $id eq "") {
    $id = "metadata.".genuid();
  }

  startMetadata($output, $id, "", undef);
  if((defined $self->{"CONF"}->{"SERVICE_NAME"} and $self->{"CONF"}->{"SERVICE_NAME"} ne "") or
     (defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} and $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} ne "") or 
     (defined $self->{"CONF"}->{"SERVICE_TYPE"} and $self->{"CONF"}->{"SERVICE_TYPE"} ne "") or
     (defined $self->{"CONF"}->{"SERVICE_DESCRIPTION"} and $self->{"CONF"}->{"SERVICE_DESCRIPTION"} ne "")) {
   $output->startElement("perfsonar", "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", "subject", undef, undef);
    $output->startElement("psservice", "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "service", undef, undef);
     if(defined $self->{"CONF"}->{"SERVICE_NAME"} and $self->{"CONF"}->{"SERVICE_NAME"} ne "") {
      $output->createElement("psservice", "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "serviceName", undef, undef, $self->{"CONF"}->{"SERVICE_NAME"});
     }
     if(defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} and $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} ne "") {
      $logger->debug("Adding accesspoint");
      $output->createElement("psservice", "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "accessPoint", undef, undef, $self->{"CONF"}->{"SERVICE_ACCESSPOINT"});
     }
     if(defined $self->{"CONF"}->{"SERVICE_TYPE"} and $self->{"CONF"}->{"SERVICE_TYPE"} ne "") {
      $output->createElement("psservice", "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "serviceType", undef, undef, $self->{"CONF"}->{"SERVICE_TYPE"});
     }
     if(defined $self->{"CONF"}->{"SERVICE_DESCRIPTION"} and $self->{"CONF"}->{"SERVICE_DESCRIPTION"} ne "") {
      $output->createElement("psservice", "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "serviceDescription", undef, undef, $self->{"CONF"}->{"SERVICE_DESCRIPTION"});
     }
    $output->endElement("service");
   $output->endElement("subject");
  } 
  endMetadata($output);
}


sub callLS {
  my($self, $sender, $message) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  my $error;
  my $responseContent = $sender->sendReceive(makeEnvelope($message), "", \$error);  
  if ($error ne "") {
    $logger->error("sendReceive failed: $error");
    return 0;
  }
  my $parser = XML::LibXML->new(); 
  if(defined $responseContent and $responseContent ne "" and !($responseContent =~ m/^\d+/)) { 
    my $output = ""; 
    eval { 
      $output = $parser->parse_string($responseContent); 
    };
    if($@) {
      $logger->error("Parser failed: ".$@);
      return 0; 
    }
    else {
      my $msg = $output->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "message")->get_node(1);
      if($msg) {
        my $eventType = findvalue($msg, "./nmwg:metadata/nmwg:eventType");
        if(defined $eventType and $eventType =~ m/^success/) {
          $logger->debug("Request was successful.");
          return 1;
        }
      }
    }
  }
  $logger->error("Request failed.");
  return 0; 
}



sub register {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");

  (my $host = $self->{"CONF"}->{"LS_INSTANCE"}) =~ s/http:\/\///; 
  (my $port = $host) =~ s/^.*://;
  (my $endpoint = $port) =~ s/^\d+\///; 
  $host =~ s/\/.*//; 
  $host =~ s/:.*//; 
  $port =~ s/\/.*//;

  my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);
  
  if(!$self->{"ALIVE"}) {
    my $output = new perfSONAR_PS::XML::Document_string();
    createEchoRequest($output);
    $self->{"ALIVE"} = callLS($self, $sender, $output->getValue());
  }
  
  if($self->{"ALIVE"}) {
    my $metadatadb;
    if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
      $metadatadb = new perfSONAR_PS::DB::File(
        $self->{CONF}->{"METADATA_DB_FILE"}
      );        
 	  }
	  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
	    $metadatadb = new perfSONAR_PS::DB::XMLDB(
        $self->{CONF}->{"METADATA_DB_NAME"}, 
        $self->{CONF}->{"METADATA_DB_FILE"},
        \%{$self->{NAMESPACES}}
      );	  
	  }
	  $metadatadb->openDB; 
  	$logger->debug("Connecting to \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" database.");  

    my $queryString = "//nmwg:metadata";
    $logger->debug("Query \"".$queryString."\" created.");
    my @resultsString = $metadatadb->query($queryString);   
    if($#resultsString != -1) {
      $logger->debug("Found metadata in metadata storage.");
    }

    my ($output, $msgID, $mdID, $dID, $paramsID); 

    $output = new perfSONAR_PS::XML::Document_string();
    $msgID = "message.".genuid();
    $mdID = "metadata.".genuid();
    $dID = "data.".genuid();
    $paramsID = "parameters.".genuid();


    startMessage($output, $msgID, "", "LSRegisterRequest", "", { perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/" });
     startParameters($output, $paramsID);
       addParameter($output, "lsTTL", $self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"});
     endParameters($output);
     createKeyMetadata($self, $mdID, "", $output);
 
     for(my $x = 0; $x <= $#resultsString; $x++) { 
       createData($output, "data.".genuid(), $mdID, $resultsString[$x], undef);
     }

    endMessage($output);

    if (callLS($self, $sender, $output->getValue())) {
        $logger->debug("LS Registration successful.");
        return 0;
    }

    $output = new perfSONAR_PS::XML::Document_string();
    $msgID = "message.".genuid();
    $mdID = "metadata.".genuid();
    $dID = "data.".genuid();
    $paramsID = "parameters.".genuid();

    startMessage($output, $msgID, "", "LSRegisterRequest", "", { perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/" });
     startParameters($output, $paramsID);
       addParameter($output, "lsTTL", $self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"});
     endParameters($output);
    createServiceMetadata($self, $mdID, "", $output);
 
     for(my $x = 0; $x <= $#resultsString; $x++) { 
       createData($output, "data.".genuid(), $mdID, $resultsString[$x], undef);
     }
    endMessage($output);

   
    if(callLS($self, $sender, $output->getValue())) {
      $logger->debug("LS Registration successful.");
      return 0;
    }
  }

  $logger->error("Unable to register data with LS.");

  return -1;
}

sub register_withData {
  my ($self, $data_ref) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");

  (my $host = $self->{"CONF"}->{"LS_INSTANCE"}) =~ s/http:\/\///; 
  (my $port = $host) =~ s/^.*://;
  (my $endpoint = $port) =~ s/^\d+\///; 
  $host =~ s/\/.*//; 
  $host =~ s/:.*//; 
  $port =~ s/\/.*//;

  my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);
  
  if(!$self->{"ALIVE"}) {
    my $output = new perfSONAR_PS::XML::Document_string();
    createEchoRequest($output);
    $self->{"ALIVE"} = $self->callLS($sender, $output->getValue());
  }
    
  if($self->{"ALIVE"}) {
    my ($output, $msgID, $mdID, $dID, $paramsID); 

    $output = new perfSONAR_PS::XML::Document_string();
    $msgID = "message.".genuid();
    $mdID = "metadata.".genuid();
    $dID = "data.".genuid();
    $paramsID = "parameters.".genuid();

    startMessage($output, $msgID, "", "LSRegisterRequest", "", { perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/" });
     startParameters($output, $paramsID);
       addParameter($output, "lsTTL", $self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"});
     endParameters($output);
     $self->createKeyMetadata($output, $mdID, "");
 
     foreach my $data (@{ $data_ref }) { 
       createData($output, "data.".genuid(), $mdID, $data, undef);
     }

    endMessage($output);

    if (callLS($self, $sender, $output->getValue())) {
        $logger->debug("LS Registration successful.");
        return 0;
    }

    $output = new perfSONAR_PS::XML::Document_string();
    $msgID = "message.".genuid();
    $mdID = "metadata.".genuid();
    $dID = "data.".genuid();
    $paramsID = "parameters.".genuid();

    startMessage($output, $msgID, "", "LSRegisterRequest", "", { perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/" });
     startParameters($output, $paramsID);
       addParameter($output, "lsTTL", $self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"});
     endParameters($output);
     $self->createServiceMetadata($output, $mdID, "");
 
     foreach my $data (@{ $data_ref }) { 
       createData($output, "data.".genuid(), $mdID, $data, undef);
     }
    endMessage($output);

   
    if (callLS($self, $sender, $output->getValue())) {
      $logger->debug("LS Registration successful.");
      return 0;
    }
  }

  $logger->error("Unable to register data with LS.");

  return -1;
}

1;


__END__
=head1 NAME

perfSONAR_PS::LS::Base - A module that provides basic methods for LSs.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::LS::Base;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/LS/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $self = perfSONAR_PS::LS::Base->new(\%conf, \%ns);

    # or
    # $self = perfSONAR_PS::LS::Base->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);              

    $self->init;
    
    my $response = $self->respond;

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an LS.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf, \%ns)

The accepted arguments may also be ommited in favor of the 'set' functions.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 init()

Initialize the underlying transportation medium.  This function depends
on certain conf file values.

=head2 respond()

Send message stored in $self->{RESPONSE}.

=head1 SEE ALSO

L<Exporter>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, <zurawski@internet2.edu>

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

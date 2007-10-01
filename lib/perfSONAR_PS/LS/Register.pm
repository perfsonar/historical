#!/usr/bin/perl -w

package perfSONAR_PS::LS::Register;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ();


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

sub createKeyMetadata {
  my($self, $id, $metadataIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  if(!defined $id or $id eq "") {
    $id = "metadata.".genuid();
  }
  my $metadata = "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"".$id."\"";
  
  if(defined $metadataIdRef and $metadataIdRef ne "") {
    $metadata = $metadata . " metadataIdRef=\"".$metadataIdRef."\">\n";
  }
  else {
    $metadata = $metadata . ">\n";    
  }
  if(defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} and $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} ne "") {
    $metadata = $metadata . "    <nmwg:key id=\"key.".genuid()."\">\n";
    $metadata = $metadata . "      <nmwg:parameters id=\"parameters.".genuid()."\">\n";
    $metadata = $metadata . "        <nmwg:parameter name=\"lsKey\">".$self->{"CONF"}->{"SERVICE_ACCESSPOINT"}."</nmwg:parameter>\n";
    $metadata = $metadata . "      </nmwg:parameters>\n";
    $metadata = $metadata . "    </nmwg:key>\n";  
  } 
  $metadata = $metadata . "  </nmwg:metadata>\n";
  return $metadata;
}


sub createServiceMetadata {
  my($self, $id, $metadataIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  if(!defined $id or $id eq "") {
    $id = "metadata.".genuid();
  }
  my $metadata = "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"".$id."\"";
  if(defined $metadataIdRef and $metadataIdRef ne "") {
    $metadata = $metadata . " metadataIdRef=\"".$metadataIdRef."\">\n";
  }
  else {
    $metadata = $metadata . ">\n";    
  }
  if((defined $self->{"CONF"}->{"SERVICE_NAME"} and $self->{"CONF"}->{"SERVICE_NAME"} ne "") or
     (defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} and $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} ne "") or 
     (defined $self->{"CONF"}->{"SERVICE_TYPE"} and $self->{"CONF"}->{"SERVICE_TYPE"} ne "") or
     (defined $self->{"CONF"}->{"SERVICE_DESCRIPTION"} and $self->{"CONF"}->{"SERVICE_DESCRIPTION"} ne "")) {
    $metadata = $metadata . "    <perfsonar:subject xmlns:perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\">\n";
    $metadata = $metadata . "      <psservice:service xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">\n";
    if(defined $self->{"CONF"}->{"SERVICE_NAME"} and 
       $self->{"CONF"}->{"SERVICE_NAME"} ne "") {
      $metadata = $metadata . "        <psservice:serviceName>".$self->{"CONF"}->{"SERVICE_NAME"}."</psservice:serviceName>\n";
    }
    if(defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} and 
       $self->{"CONF"}->{"SERVICE_ACCESSPOINT"} ne "") {
      $metadata = $metadata . "        <psservice:accessPoint>".$self->{"CONF"}->{"SERVICE_ACCESSPOINT"}."</psservice:accessPoint>\n";
    }
    if(defined $self->{"CONF"}->{"SERVICE_TYPE"} and 
       $self->{"CONF"}->{"SERVICE_TYPE"} ne "") {
      $metadata = $metadata . "        <psservice:serviceType>".$self->{"CONF"}->{"SERVICE_TYPE"}."</psservice:serviceType>\n";
    }
    if(defined $self->{"CONF"}->{"SERVICE_DESCRIPTION"} and 
       $self->{"CONF"}->{"SERVICE_DESCRIPTION"} ne "") {
      $metadata = $metadata . "        <psservice:serviceDescription>".$self->{"CONF"}->{"SERVICE_DESCRIPTION"}."</psservice:serviceDescription>\n";
    }
    $metadata = $metadata . "      </psservice:service>\n";
    $metadata = $metadata . "    </perfsonar:subject>\n";
  } 
  $metadata = $metadata . "  </nmwg:metadata>\n";
  return $metadata;
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
    my $doc = ""; 
    eval { 
      $doc = $parser->parse_string($responseContent); 
    };
    if($@) {
      $logger->error("Parser failed: ".$@);
      return 0; 
    }
    else {
      my $msg = $doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "message")->get_node(1);
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
    $self->{"ALIVE"} = callLS($self, $sender, createEchoRequest("ls"));
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
  
    my $mdID = "metadata.".genuid();
    my $regMetadata = createKeyMetadata($self, $mdID, "");
    my $regData = "";
    
    my $regParam = "  <nmwg:parameters id=\"parameters.".genuid()."\">\n";
    $regParam = $regParam . "    <nmwg:parameter name=\"lsTTL\">".$self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"}."</nmwg:parameter>\n";
    $regParam = $regParam . "  </nmwg:parameters>\n";

    my $queryString = "//nmwg:metadata";
    $logger->debug("Query \"".$queryString."\" created.");
	  my @resultsString = $metadatadb->query($queryString);   
	  if($#resultsString != -1) {
	    $logger->debug("Found metadata in metadata storage.");
	    for(my $x = 0; $x <= $#resultsString; $x++) { 
        $regData = $regData . createData("data.".genuid(), $mdID, $resultsString[$x]);
	    }
    }

    if(!callLS($self, $sender, getResultMessage("message.".genuid(), "", "LSRegisterRequest", $regParam.$regMetadata.$regData, {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"}))) {
      $regMetadata = createServiceMetadata($self, $mdID, "");
      if(!callLS($self, $sender, getResultMessage("message.".genuid(), "", "LSRegisterRequest", $regParam.$regMetadata.$regData, {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"}))) {
        $logger->error("Unable to register data with LS.");
      }
      else {
        $logger->debug("LS Registration successful.");
      }
    }
    else {
      $logger->debug("LS Registration successful.");
    }
  }
  else {
    $logger->error("Unable to register data with LS.");
  }

  return;
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
    $self->{"ALIVE"} = $self->callLS($sender, createEchoRequest("ls"));
  }
  
  if($self->{"ALIVE"}) {
    my $regParam = "";
    $regParam .= "  <nmwg:parameters id=\"parameters.".genuid()."\">\n";
    $regParam .= "    <nmwg:parameter name=\"lsTTL\">".$self->{"CONF"}->{"LS_REGISTRATION_INTERVAL"}."</nmwg:parameter>\n";
    $regParam .= "  </nmwg:parameters>\n";

    my $mdID = "metadata.".genuid();
    my $regMetadata = $self->createKeyMetadata($mdID, "");

    my $regData = "";
    foreach $data (@{ $data_ref }) {
      $regData .= createData("data.".genuid(), $mdID, $data);
    }

    if(!$self->callLS($sender, getResultMessage("message.".genuid(), "", "LSRegisterRequest", $regParam.$regMetadata.$regData,  {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"}))) {
      $regMetadata = createServiceMetadata($self, $mdID, "");
      if(!$self->callLS($sender, getResultMessage("message.".genuid(), "", "LSRegisterRequest", $regParam.$regMetadata.$regData, {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"}))) {
        $logger->error("Unable to register data with LS.");
      }
      else {
        $logger->debug("LS Registration successful.");
      }
    }
    else {
      $logger->debug("LS Registration successful.");
    }
  }
  else {
    $logger->error("Unable to register data with LS.");
  }

  return;
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

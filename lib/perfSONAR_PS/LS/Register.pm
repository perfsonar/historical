#!/usr/bin/perl -w

package perfSONAR_PS::LS::Register;

use strict;
use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;


sub new {
  my ($package, $conf, $ns) = @_; 
  my %hash = ();
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }      

  if (!defined $hash{"CHUNK"} or $hash{"CHUNK"} eq "") {
    $hash{"CHUNK"} = 500;
  }

  $hash{"ALIVE"} = 0;
  $hash{"FIRST"} = 1;

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


sub createKey {
  my($self) = @_;
  my $key = "    <nmwg:key id=\"key.".genuid()."\">\n";
  $key = $key . "      <nmwg:parameters id=\"parameters.".genuid()."\">\n";
  $key = $key . "        <nmwg:parameter name=\"lsKey\">".$self->{"CONF"}->{"SERVICE_ACCESSPOINT"}."</nmwg:parameter>\n";
  $key = $key . "      </nmwg:parameters>\n";
  $key = $key . "    </nmwg:key>\n";  
  return $key;
}


sub createService {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  my $service = "    <perfsonar:subject xmlns:perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\">\n";
  $service = $service . "      <psservice:service xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">\n";
  $service = $service . "        <psservice:serviceName>".$self->{"CONF"}->{"SERVICE_NAME"}."</psservice:serviceName>\n" if (defined $self->{"CONF"}->{"SERVICE_NAME"});
  $service = $service . "        <psservice:accessPoint>".$self->{"CONF"}->{"SERVICE_ACCESSPOINT"}."</psservice:accessPoint>\n" if (defined $self->{"CONF"}->{"SERVICE_ACCESSPOINT"});
  $service = $service . "        <psservice:serviceType>".$self->{"CONF"}->{"SERVICE_TYPE"}."</psservice:serviceType>\n" if (defined $self->{"CONF"}->{"SERVICE_TYPE"});
  $service = $service . "        <psservice:serviceDescription>".$self->{"CONF"}->{"SERVICE_DESCRIPTION"}."</psservice:serviceDescription>\n" if (defined $self->{"CONF"}->{"SERVICE_DESCRIPTION"});  
  $service = $service . "      </psservice:service>\n";
  $service = $service . "    </perfsonar:subject>\n";  
  return $service;
}


sub callLS {
  my($self, $sender, $message) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  my $error;
  my $responseContent = $sender->sendReceive(makeEnvelope($message), "", \$error);  
  if($error ne "") {
    $logger->error("sendReceive failed: $error");
    return 0;
  }
  my $parser = XML::LibXML->new(); 
  if(defined $responseContent and $responseContent ne "" and 
     !($responseContent =~ m/^\d+/)) { 
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
        if(defined $eventType and $eventType =~ m/success/) {
          return 1;
        }
      }
    }
  }
  $logger->error("Request failed.");
  return 0; 
}


sub registerStatic {
  my($self, $data_ref) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  my @lsList = split(/ /, $self->{"CONF"}->{"LS_INSTANCE"});
  foreach my $ls (@lsList) {
    (my $host = $ls) =~ s/http:\/\///;
    (my $port = $host) =~ s/^.*://;
    (my $endpoint = $port) =~ s/^\d+\///; 
    $host =~ s/\/.*//; 
    $host =~ s/:.*//; 
    $port =~ s/\/.*//;
    my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);
  
    if(!$self->{"ALIVE"}) {
      my $doc = perfSONAR_PS::XML::Document_string->new();
      createEchoRequest($doc);
      $self->{"ALIVE"} = callLS($self, $sender, $doc->getValue());
    }
  
    if($self->{"ALIVE"}) {
      if($self->{"FIRST"}) {
	my $doc = perfSONAR_PS::XML::Document_string->new();
        startMessage($doc, "message.".genuid(), "", "LSDeregisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});

        my $mdID = "metadata.".genuid();
        createMetadata($doc, $mdID, "", createKey($self), undef);
        createData($doc, "data.".genuid(), $mdID, "", undef);
        endMessage($doc);

        if(!callLS($self, $sender, $doc->getValue())) { 
          $logger->debug("Nothing registered.");
        }
        else {
          $logger->debug("Removed old registration.");
        }
        
        my @resultsString = ();
      
        @resultsString = @{$data_ref};
      
        if($#resultsString != -1) { 
          my $iterations = int((($#resultsString+1)/$self->{"CHUNK"}));
          my $x = 0;
          for(my $y = 1; $y <= ($iterations+1); $y++) {
	    my $doc = perfSONAR_PS::XML::Document_string->new();
            startMessage($doc, "message.".genuid(), "", "LSRegisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});
            createMetadata($doc, $mdID, "", createService($self), undef); 
            for(; $x < ($y*$self->{"CHUNK"}) and $x <= $#resultsString; $x++) { 
              createData($doc, "data.".genuid(), $mdID, $resultsString[$x], undef);
            }
            endMessage($doc);
            if(!callLS($self, $sender, $doc->getValue())) {
              $logger->error("Unable to register data with LS.");
              $self->{"ALIVE"} = 0;
            }
          }
        }      
      }
      else {
	my $doc = perfSONAR_PS::XML::Document_string->new();
        startMessage($doc, "message.".genuid(), "", "LSKeepaliveRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});
        my $mdID = "metadata.".genuid();
        createMetadata($doc, $mdID, "", createKey($self), undef);
        createData($doc, "data.".genuid(), $mdID, "", undef);
        endMessage($doc);
      
        if(!callLS($self, $sender, $doc->getValue())) {    
          my @resultsString = ();

          @resultsString = @{$data_ref};

          if($#resultsString != -1) { 
            my $iterations = int((($#resultsString+1)/$self->{"CHUNK"}));
            my $x = 0;
            for(my $y = 1; $y <= ($iterations+1); $y++) {
	      my $doc = perfSONAR_PS::XML::Document_string->new();
              startMessage($doc, "message.".genuid(), "", "LSRegisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});
              createMetadata($doc, $mdID, "", createService($self), undef); 
              for(; $x < ($y*$self->{"CHUNK"}) and $x <= $#resultsString; $x++) {
                createData($doc, "data.".genuid(), $mdID, $resultsString[$x], undef);
              }
              endMessage($doc);
              if(!callLS($self, $sender, $doc->getValue())) {
                $logger->error("Unable to register data with LS.");
                $self->{"ALIVE"} = 0;
              }
            }
          }
        }
      }
    }
    else {
      $logger->error("Unable to register data with LS.");
      $self->{"ALIVE"} = 0;
    }
  }
  $self->{"FIRST"}-- if $self->{"FIRST"};
  return;  
}


sub registerDynamic {
  my($self, $data_ref) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Register");
  
  my @lsList = split(/ /, $self->{"CONF"}->{"LS_INSTANCE"});
  foreach my $ls (@lsList) {
    (my $host = $ls) =~ s/http:\/\///; 
    (my $port = $host) =~ s/^.*://;
    (my $endpoint = $port) =~ s/^\d+\///; 
    $host =~ s/\/.*//; 
    $host =~ s/:.*//; 
    $port =~ s/\/.*//;
    my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint);
  
    if(!$self->{"ALIVE"}) {
      my $doc = perfSONAR_PS::XML::Document_string->new();
      createEchoRequest($doc);
      $self->{"ALIVE"} = callLS($self, $sender, $doc->getValue());
    }
  
    if($self->{"ALIVE"}) {
      if($self->{"FIRST"}) {
	my $doc = perfSONAR_PS::XML::Document_string->new();
        startMessage($doc, "message.".genuid(), "", "LSDeregisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});

        my $mdID = "metadata.".genuid();
        createMetadata($doc, $mdID, "", createKey($self), undef);
        createData($doc, "data.".genuid(), $mdID, "", undef);
        endMessage($doc);

        if(!callLS($self, $sender, $doc->getValue())) { 
          $logger->debug("Nothing registered.");
        }
        else {
          $logger->debug("Removed old registration.");
        }

        my @resultsString = @{$data_ref};
        
        if($#resultsString != -1) { 
          my $iterations = int((($#resultsString+1)/$self->{"CHUNK"}));
          my $x = 0;
          for(my $y = 1; $y <= ($iterations+1); $y++) {
	    my $doc = perfSONAR_PS::XML::Document_string->new();
            startMessage($doc, "message.".genuid(), "", "LSRegisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});

            $mdID = "metadata.".genuid();
            createMetadata($doc, $mdID, "", createService($self), undef);
            for(; $x < ($y*$self->{"CHUNK"}) and $x <= $#resultsString; $x++) { 
              createData($doc, "data.".genuid(), $mdID, $resultsString[$x], undef);
            }
            endMessage($doc);
            if(!callLS($self, $sender, $doc->getValue())) {
              $logger->error("Unable to register data with LS.");
              $self->{"ALIVE"} = 0;
            }
          }
        }
      }
      else {
        my @resultsString = @{$data_ref};

	my $doc = perfSONAR_PS::XML::Document_string->new();
        startMessage($doc, "message.".genuid(), "", "LSKeepaliveRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});

        my $mdID = "metadata.".genuid();
        createMetadata($doc, $mdID, "", createKey($self), undef);
        createData($doc, "data.".genuid(), $mdID, "", undef);
        endMessage($doc);
      
        my $subject = "";
        if(!callLS($self, $sender, $doc->getValue())) { 
          $subject = createService($self);
        }
        else {
          $subject = createKey($self)."\n".createService($self);
        }

        if($#resultsString != -1) { 
          my $iterations = int((($#resultsString+1)/$self->{"CHUNK"}));
          my $x = 0;
          for(my $y = 1; $y <= ($iterations+1); $y++) {
	    my $doc = perfSONAR_PS::XML::Document_string->new();
            startMessage($doc, "message.".genuid(), "", "LSRegisterRequest", "", {perfsonar=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/", psservice=>"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"});
            createMetadata($doc, $mdID, "", $subject, undef);  
            for(; $x < ($y*$self->{"CHUNK"}) and $x <= $#resultsString; $x++) { 
              createData($doc, "data.".genuid(), $mdID, $resultsString[$x], undef);
            }            
            endMessage($doc);
            if(!callLS($self, $sender, $doc->getValue())) {
              $logger->error("Unable to register data with LS.");
              $self->{"ALIVE"} = 0;
            }
          }
        }  
      }
    }
    else {
      $logger->error("Unable to register data with LS.");
      $self->{"ALIVE"} = 0;
    }
  }
  $self->{"FIRST"}-- if $self->{"FIRST"};
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

    use perfSONAR_PS::LS::Register;

    my $dirname = dirname($0);
    if (!($dirname =~ /^\//)) {
      $dirname = getcwd . "/" . $dirname;
    }

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/LS/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    $conf{"METADATA_DB_CONTROL_FILE"} = "control.dbxml";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
      select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
      perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
      psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/",
      xquery => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/",
      xpath => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xpath/1.0/"
    );
    
    my $self = perfSONAR_PS::LS::Register->new(\%conf, \%ns);

    # or
    # $self = perfSONAR_PS::LS::Register->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);              

    $self->register;

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an LS.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new($package, \%conf, \%ns)

The accepted arguments may also be ommited in favor of the 'set' functions.

=head2 setConf($self, \%conf)

(Re-)Sets the value for the 'conf' hash.

=head2 setNamespaces($self, \%namespaces)

(Re-)Sets the value for the 'namespace' hash.

=head2 createKey($self)

Creates a 'key' value that is used to access the LS.  We are taking some liberty here and
guessing that the key will ALWAYS be the accessPoint value, this will need to be changed
in the future.  
  
=head2 createService($self)

Creates the 'service' subject (description of the service) for LS registration.  

=head2 callLS($self, $sender, $message)

Given a message and a sender, contact an LS and parse the results.  

=head2 registerStatic($self, $data_ref)

Performs registration of 'static' data with an LS.  Static in this sense indicates that the
data in the underlying storage DOES NOT change.  This function uses special messages that
intend to simply keep the data alive, not worrying at all if something comes in that is
new or goes away that is old.  If a data reference is passed to this function, that
data will be used for registration purposes otherwise the database is consulted.

=head2 registerDynamic($self, $data_ref)

Performs registration of 'dynamic' data with an LS.  Dynamic in this sense indicates that 
the data in the underlying storage DOES change.  This function uses special messages that
will remove all old data and insert everything brand new with each registration.  If a 
data reference is passed to this function, that data will be used for registration purposes 
otherwise the database is consulted.

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<File::Temp>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Transport>, L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut


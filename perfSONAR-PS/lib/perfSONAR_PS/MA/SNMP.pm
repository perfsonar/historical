#!/usr/bin/perl -w

package perfSONAR_PS::MA::SNMP;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);


sub receive {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  my $readValue = $self->{LISTENER}->acceptCall;
  if($readValue == 0) {
    $logger->debug("Received 'shadow' request from below; no action required.");
    $self->{RESPONSE} = $self->{LISTENER}->getResponse();
  }
  elsif($readValue == 1) {      
    $logger->debug("Received request to act on.");
    handleRequest($self);
  }
  else {
    my $msg = "Sent Request has was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
    $logger->error($msg);
    $self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg); 
  }
  return;
}


sub handleRequest {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  delete $self->{RESPONSE};

  $self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file" or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
    my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
    my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");    
    my $messageIdReturn = genuid();    

    if($messageType eq "MetadataKeyRequest" or 
       $messageType eq "SetupDataRequest") {
      $logger->debug("Parsing request.");
      parseRequest($self, $messageIdReturn, $messageId, $messageType);
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      $logger->error($msg);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.type", $msg);
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    $logger->error($msg); 
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "MetadataKeyResponse", "error.mp.snmp", $msg);
  }
  return $self->{RESPONSE};
}


sub parseRequest {
  my($self, $messageId, $messageIdRef, $type) = @_; 
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  my $localContent = "";
  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) { 
      
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
	      
	      if($type eq "MetadataKeyRequest") {
	        $localContent = perfSONAR_PS::MA::Base::keyRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef);	      	      
	      }
	      elsif($type eq "SetupDataRequest") {         
          getTime(\%{$self}, $m->getAttribute("id"));
          if($m->find("//nmwg:metadata/nmwg:key")) {
            $localContent = setupDataKeyRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef);
          }
          else {
            $localContent = setupDataRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef);
          }	
	      }
      }   
    }
  }  
  return;
}


sub setupDataKeyRequest {
  my($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
	my $queryString = "//nmwg:data[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 0) . "]";
  $logger->debug("Query \"".$queryString."\" created."); 


# XXX jason: [6/1/07]
# Adding the 'cooked' md to the request        
#  $localContent = $localContent . $m->toString();
   
   
# XXX jason: [6/1/07]
# Adding the 'original' md to the request
  my $xp = XML::XPath->new( xml => $self->{LISTENER}->getRequest );
  my $nodeset = $xp->find("//nmwg:message/nmwg:metadata");
  if($nodeset->size() <= 0) {
  }
  else {  
    foreach my $node ($nodeset->get_nodelist) {
      $localContent = $localContent . XML::XPath::XMLParser::as_string($node);
    }
  }

   
	my @resultsString = $metadatadb->query($queryString);   
	if($#resultsString != -1) {
    for(my $x = 0; $x <= $#resultsString; $x++) {	
      $localContent = $localContent . handleData($self, $m->getAttribute("id"), $resultsString[$x], $messageId, $messageIdRef);
    } 
    $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "SetupDataResponse", $localContent);       
  }
	else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg);
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);	                   
	}  
  return;
}


sub setupDataRequest {
  my($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
	my $queryString = "//nmwg:metadata[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 1) . "]";
  $logger->debug("Query \"".$queryString."\" created.");
	my @resultsString = $metadatadb->query($queryString);   
	
	if($#resultsString != -1) {
    for(my $x = 0; $x <= $#resultsString; $x++) {	
      my $parser = XML::LibXML->new();
      $doc = $parser->parse_string($resultsString[$x]);  
      my $mdset = $doc->find("//nmwg:metadata");
      my $md = $mdset->get_node(1); 
  
      $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]";
      $logger->debug("Query \"".$queryString."\" created.");
	    my @dataResultsString = $metadatadb->query($queryString);
		
	    if($#dataResultsString != -1) { 


# XXX jason: [6/1/07]
# Adding the 'cooked' md to the request        
#       $localContent = $localContent . $md->toString();

     
# XXX jason: [6/1/07]
# Adding the 'original' md to the request
        my $xp = XML::XPath->new( xml => $self->{LISTENER}->getRequest );
        my $nodeset = $xp->find("//nmwg:message/nmwg:metadata");
        if($nodeset->size() <= 0) {
        }
        else {  
          foreach my $node ($nodeset->get_nodelist) {
            $localContent = $localContent . XML::XPath::XMLParser::as_string($node);
          }
        }
                
        
        for(my $y = 0; $y <= $#dataResultsString; $y++) {
		      $localContent = $localContent . handleData($self, $m->getAttribute("id"), $dataResultsString[$y], $messageId, $messageIdRef);
        } 
        $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "SetupDataResponse", $localContent);  	    	  
	    }
      else {
	      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
        $logger->error($msg);  
        $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);
      } 
	  }
	}
	else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg);
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);	                   
	}  
  return;
}


sub handleData {
  my($self, $id, $dataString, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my $localContent = "";
  $logger->debug("Data \"".$dataString."\" found.");	    
  undef $self->{RESULTS};		    

  my $parser = XML::LibXML->new();
  $self->{RESULTS} = $parser->parse_string($dataString);   
  my $dt = $self->{RESULTS}->find("//nmwg:data")->get_node(1);
  my $type = extract($dt->find("./nmwg:key//nmwg:parameter[\@name=\"type\"]")->get_node(1));
                  
  if($type eq "rrd") {
    $localContent = retrieveRRD($self, $dt, $id);		       
  }
  elsif($type eq "sqlite") {
    $localContent = retrieveSQL($self, $dt, $id);		  		       
  }		
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    $logger->error($msg);    
    $localContent = getResultCodeData(genuid(), $id, $msg);  
  }
  return $localContent;
}


sub retrieveSQL {
  my($self, $d, $mid) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my $responseString = "";
  my @dbSchema = ("id", "time", "value", "eventtype", "misc");
  my $result = getDataSQL($self, $d, \@dbSchema);  
  my $id = genuid();
    
  if($#{$result} == -1) {
    my $msg = "Query \"".$query."\" returned 0 results";
    $logger->error($msg);
    $responseString = $responseString . getResultCodeData($id, $mid, $msg); 
  }   
  else { 
    $logger->debug("Data found.");
    $responseString = $responseString . "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
    for(my $a = 0; $a <= $#{$result}; $a++) {    
      $responseString = $responseString . "    <nmwg:datum";
      $responseString = $responseString." ".$dbSchema[1]."=\"".$result->[$a][1]."\"";
      $responseString = $responseString." ".$dbSchema[2]."=\"".$result->[$a][2]."\"";
      my @misc = split(/,/,$result->[$a][4]);
      foreach my $m (@misc) {
        my @pair = split(/=/,$m);
	      $responseString = $responseString." ".$pair[0]."=\"".$pair[1]."\""; 
      }
      $responseString = $responseString . " />\n";
    }
    $responseString = $responseString . "  </nmwg:data>\n";
    $logger->debug("Data block created.");
  }  
  return $responseString;
}


sub retrieveRRD {
  my($self, $d, $mid) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my $responseString = "";
  $responseString = adjustRRDTime($self);
  if(!$responseString) {
    my $id = genuid();
    
    my %rrd_result = getDataRRD($self, $d, $mid, $id);
    if($rrd_result{ERROR}) {
      $logger->error("RRD error seen.");
      $responseString = $rrd_result{ERROR};
    }
    else {
      $logger->debug("Data found.");
      $responseString = $responseString . "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
      my $dataSource = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"dataSource\"]")->get_node(1));
      my $valueUnits = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"valueUnits\"]")->get_node(1));
    
      foreach $a (sort(keys(%rrd_result))) {
        foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
	        if($b eq $dataSource) {
	          $responseString = $responseString . "    <nmwg:datum time=\"".$a."\" value=\"".$rrd_result{$a}{$b}."\" valueUnits=\"".$valueUnits."\"/>\n";
          }
        }
      }
      $responseString = $responseString . "  </nmwg:data>\n";
      $logger->debug("Data block created.");
    }
  }
  return $responseString;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::SNMP - A module that provides methods for the SNMP MA.  

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::SNMP;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $ma = perfSONAR_PS::MA::SNMP->new(\%conf, \%ns);

    # or
    # $ma = perfSONAR_PS::MA::SNMP->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);      
        
    $ma->init;  
    while(1) {
      $ma->receive;
      $ma->respond;
    }  
  

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 receive($self)

Grabs message from transport object to begin processing.

=head2 handleRequest($self)

Functions as the 'gatekeeper' the the MA.  Will either reject or accept
requets.  will also 'do nothing' in the event that a request has been
acted on by the lower layer.  

=head2 parseRequest($self, $messageId, $messageIdRef, $type)

Processes both the the MetadataKeyRequest and SetupDataRequest messages, which 
preturn either metadata or data to the user.

=head2 setupDataKeyRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

Runs the specific needs of a SetupDataRequest when a key is presented to 
the service.

=head2 setupDataRequest($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

Runs the specific needs of a SetupDataRequest when a key is NOT presented to 
the service.
 
=head2 handleData($self, $id, $dataString, $localContent)

Helper function to extract data from the backed storage.

=head2 retrieveRRD($did)

The data is extracted from the backed storage (in this case RRD). 

=head2 retrieveSQL($did)	

The data is extracted from the backed storage (in this case SQL). 

=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>

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

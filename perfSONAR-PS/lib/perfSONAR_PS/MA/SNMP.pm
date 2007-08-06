#!/usr/bin/perl -w

package perfSONAR_PS::MA::SNMP;

use warnings;
use Carp qw(carp);
use Exporter;
use Log::Log4perl qw(get_logger);
use File::Temp qw(tempfile unlink0);

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
  delete $self->{RESPONSE};
  
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
    $self->{RESPONSE} = getResultCodeMessage("message.".genuid(), "", "response", "error.transport.soap", $msg); 
  }
  return;
}


sub handleRequest {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  $self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();

  my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
  my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");        
  my $messageIdReturn = "message.".genuid(); 
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file" or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
     
    my $msgParams = $self->{LISTENER}->getRequestDOM()->getDocumentElement->find("./nmwg:parameters")->get_node(1); 
    if($msgParams) {
      $logger->debug("Found message parameters.");
      $msgParams = handleMessageParameters($self, $msgParams);
      $msgParams = $msgParams->toString."\n";
    }      
     
    if($messageType eq "MetadataKeyRequest") {
      $logger->debug("Parsing MetadataKey request.");
      my $response = maMetadataKeyRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "MetadataKeyResponse", $msgParams.$response);    
    }
    elsif($messageType eq "SetupDataRequest") {
      $logger->debug("Parsing SetupData request.");
      my $response = maSetupDataRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "SetupDataResponse", $msgParams.$response);  
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      $logger->error($msg);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "", $messageType."Response", "error.ma.message.type", $msg);
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    $logger->error($msg); 
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "MetadataKeyResponse", "error.mp.snmp", $msg);
  }
  return;
}


sub handleMessageParameters {
  my($self, $msgParams) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  foreach my $p ($msgParams->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "parameter")) {
    if($p->getAttribute("name") eq "timeType") {
      $logger->debug("Found timeType parameter.");
      my $type = extract($p);
      if($type =~ m/^unix$/i) {
        $self->{"TIMETYPE"} = "unix";
      }
      elsif($type =~ m/^iso/i) {
        $self->{"TIMETYPE"} = "iso";
      } 
    }
  }
  return $msgParams;
}


sub maMetadataKeyRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my($tempHandle, $tempFilename) = tempfile();
	my $mdId = "";
	my $dId = "";
	  
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

  # MA MetadataKeyRequest Steps
  # ---------------------
  # Is there a key?
  #   Y: do queries against key return key as md AND d
  #   N: Is there a chain?
  #     Y: Is there a key
  #       Y: do queries against key, add in select stuff to key, return key as md AND d
  #       N: do md/d queries against md return results with altered key
  #     N: do md/d queries against md return results

  foreach my $d ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {      
    my $m = $self->{LISTENER}->getRequestDOM()->getDocumentElement->find("./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]")->get_node(1);
    if(defined $m) {        
      $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

      if(getTime(\%{$self}, $m->getAttribute("id"))) {
        if($m->find("./nmwg:key")) {
          $logger->debug("Key found in metadata, proceeding with MetadataKey Request.");
          metadataKeyRetrieveKey(\%{$self}, $metadatadb, $m->find("./nmwg:key")->get_node(1), "", $m->getAttribute("id"), $tempHandle);
        }
        else {
          $logger->debug("Key not found in metadata, proceeding with MetadataKey Request.");
          if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and 
             $m->find("./select:subject")) {
            $logger->debug("Metadata is a subject chain.");
            my $other_md = $self->{LISTENER}->getRequestDOM()->find("//nmwg:metadata[\@id=\"".$m->find("./select:subject")->get_node(1)->getAttribute("metadataIdRef")."\"]")->get_node(1);  
            if($other_md) {
              if($other_md->find("./nmwg:key")) {
                $logger->debug("We are chained to a key, getting chained results.");
                metadataKeyRetrieveKey(\%{$self}, $metadatadb, $other_md->find("./nmwg:key")->get_node(1), $m, $m->getAttribute("id"), $tempHandle);                 
              }
              else {
                $logger->debug("We are chained to metadata, getting chained results.");
                metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $other_md, $m, $m->getAttribute("id"), $tempHandle);
              }
            }
            else {
              my $msg = "Cannot resolve supposed subject chain in metadata.";
              $logger->error($msg);
	            $mdId = "metadata.".genuid();
	            $dId = "data.".genuid();      
              print $tempHandle getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ma.chaining");
              print $tempHandle getResultCodeData($dId, $mdId, $msg);          
            }
          }
          else {
            $logger->debug("No chaining found, getting results.");
            metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $m, "", $m->getAttribute("id"), $tempHandle);
          }
        }
      }
      else {
        my $msg = "Time range error in request.";
        $logger->error($msg);
	      $mdId = "metadata.".genuid();
	      $dId = "data.".genuid();      
        print $tempHandle getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ma.structure");
        print $tempHandle getResultCodeData($dId, $mdId, $msg);
      }
    }
    else {
      my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
      $logger->error($msg);
	    $mdId = "metadata.".genuid();
	    $dId = "data.".genuid();      
      print $tempHandle getResultCodeMetadata($mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
      print $tempHandle getResultCodeData($dId, $mdId, $msg);  
    }
  }
  seek($tempHandle, 0, 0);
  my $localContent = do { local( $/ ); <$tempHandle> };
  close($tempHandle);
  unlink0($tempHandle, $tempFilename) or $logger->error("Unlink0 failure on filehandle for '".$tempFilename."'");
  unlink($tempFilename) or $logger->error("Unlink failure for '".$tempFilename."'");
  return $localContent;
}


sub metadataKeyRetrieveKey {
  my($self, $metadatadb, $key, $chain, $id, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid(); 
  
  my $queryString = "//nmwg:data[" . getDataXQuery($key, "") . "]";
  $logger->debug("Query \"".$queryString."\" created.");
	my @resultsString = $metadatadb->query($queryString);   
	if($#resultsString == 0) {
	  $logger->debug("Found a key in metadata storage.");
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string($resultsString[0]);  
    my $key2 = $doc->find("//nmwg:data/nmwg:key")->get_node(1);	
    if($key2) {   
      if(defined $chain and $chain ne "") {
        $logger->debug("Preparing to search chain for modifications.");
        if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p ($chain->find("./select:parameters")->get_node(1)->childNodes) {
            $logger->debug("Modifying chain.");
            $key2->find(".//nmwg:parameters")->get_node(1)->addChild($p->cloneNode(1));
          }
        }
      }    
      print $tempHandle createMetadata($mdId, $id, $key->toString);
      print $tempHandle createData($dId, $mdId, $key2->toString);
	  }
	  else {
      my $msg = "Key error in metadata storage.";
      $logger->error($msg);     
      print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
      print $tempHandle getResultCodeData($dId, $mdId, $msg);
	  }
	}
	else {
    my $msg = "Key error in metadata storage.";
    $logger->error($msg);     
    print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
    print $tempHandle getResultCodeData($dId, $mdId, $msg); 
	}
  return;
}


#metadataKeyRetrieveMetadataData(
#\%{$self}, 
#$metadatadb, 
#$m, 
#"", 
#$m->getAttribute("id"), 
#$tempHandle
#);

sub metadataKeyRetrieveMetadataData {
  my($self, $metadatadb, $metadata, $chain, $id, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $mdId = "";
  my $dId = ""; 
    
  my $queryString = "//nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  $logger->debug("Query string \"".$queryString."\" created."); 
	my @resultsString = $metadatadb->query($queryString);
	if($#resultsString != -1) {
	  $logger->debug("Found metadata in metadata storage.");
	  for(my $x = 0; $x <= $#resultsString; $x++) {
      my $parser = XML::LibXML->new();
      my $doc = $parser->parse_string($resultsString[$x]);  
      my $md = $doc->find("//nmwg:metadata")->get_node(1);

      $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]"; 
      $logger->debug("Query string \"".$queryString."\" created."); 
	    my @dataResultsString = $metadatadb->query($queryString);	  
	    if($#dataResultsString != -1) {   			  
        $logger->debug("Founding matching data in metadata storage.");

        for(my $y = 0; $y <= $#dataResultsString; $y++) {
          my $parser2 = XML::LibXML->new();
          my $doc2 = $parser2->parse_string($dataResultsString[$y]);  
          my $d = $doc2->find("//nmwg:data")->get_node(1);

          my $eventTypes = $metadata->find("./nmwg:eventType");
          my $eventTypes2 = $metadata->find(".//nmwg:parameter[\@name=\"supportedEventType\"]");
          my $supportedEventTypes = $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"]");
          
          my $match = 0;
          foreach my $set ($supportedEventTypes->get_nodelist) {
            last if($match == 1);
            foreach my $et ($eventTypes->get_nodelist) {
              if(extract($et) eq extract($set)) {
                $match = 1;
                last;
              }
            }
            foreach my $et2 ($eventTypes2->get_nodelist) {
              if(extract($et2) eq extract($set)) {
                $match = 1;
                last;
              }
            }
          }

          if($match) {
            $dId = "data.".genuid();
            $mdId = "metadata.".genuid();
            $d->setAttribute("metadataIdRef", $mdId);
            $d->setAttribute("id", $dId);
            if(defined $chain and $chain ne "") {
              $logger->debug("Preparing to search chain for modifications.");
              if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
                foreach my $p ($chain->find("./select:parameters")->get_node(1)->childNodes) {
                  $logger->debug("Modifying chain.");
                  $d->find(".//nmwg:parameters")->get_node(1)->addChild($p->cloneNode(1));
                }
              }        
            }
            $md->setAttribute("metadataIdRef", $id);
            $md->setAttribute("id", $mdId);        
            print $tempHandle $md->toString; 
         
            print $tempHandle $d->toString; 
          }

        }      
	    }
      else {
	      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for data search";
        $logger->error($msg);  
        $mdId = "metadata.".genuid();
        $dId = "data.".genuid();          
        print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage");
        print $tempHandle getResultCodeData($dId, $mdId, $msg);             
      }  
	  }
  }
	else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for metadata search";
    $logger->error($msg); 
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();      
    print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage");
    print $tempHandle getResultCodeData($dId, $mdId, $msg);       
	}  
	return;
}


sub maSetupDataRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my($tempHandle, $tempFilename) = tempfile();
	my $mdId = "";
	my $dId = "";
	  
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

  # MA SetupDataRequest Steps
  # ---------------------
  # Is there a key?
  #   Y: key in db?
  #     Y: Original MD in db?
  #       Y: add it, extract data
  #       N: use sent md, extract data
  #     N: error out
  #   N: Is it a select?
  #     Y: Is there a matching MD?
  #       Y: Is there a key in the matching md?
  #         Y: Original MD in db?
  #           Y: add it, extract data
  #           N: use sent md, extract data
  #         N: extract md (for correct md), extract data
  #       N: Error out
  #     N: extract md, extract data
  	      
  foreach my $d ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {      
    my $m = $self->{LISTENER}->getRequestDOM()->getDocumentElement->find("./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]")->get_node(1);
    if(defined $m) {        
      $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

      if(getTime(\%{$self}, $m->getAttribute("id"))) {    
        if($m->find("./nmwg:key")) {
          $logger->debug("Key found in metadata, proceeding with SetupData Request.");
          setupDataRetrieveKey(\%{$self}, $metadatadb, $m->find("./nmwg:key")->get_node(1), "", $m->getAttribute("id"), $tempHandle);
        }
        else {
          $logger->debug("Key not found in metadata, proceeding with SetupData Request.");
          if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and 
             $m->find("./select:subject")) {
            my $other_md = $self->{LISTENER}->getRequestDOM()->find("//nmwg:metadata[\@id=\"".$m->find("./select:subject")->get_node(1)->getAttribute("metadataIdRef")."\"]")->get_node(1);  
            if($other_md) {
              if($other_md->find("./nmwg:key")) {
	              setupDataRetrieveKey(\%{$self}, $metadatadb, $other_md->find("./nmwg:key")->get_node(1), $m, $m->getAttribute("id"), $tempHandle);
              }
              else {
	              setupDataRetrieveMetadataData($self, $metadatadb, $other_md, $m->getAttribute("id"), $tempHandle);           
              }
            }
            else {
              my $msg = "Cannot resolve subject chain in metadata.";
              $logger->error($msg);
	            $mdId = "metadata.".genuid();
	            $dId = "data.".genuid();      
              print $tempHandle getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ma.chaining");
              print $tempHandle getResultCodeData($dId, $mdId, $msg);
            }
          }
          else {
	          setupDataRetrieveMetadataData($self, $metadatadb, $m, $m->getAttribute("id"), $tempHandle);
          }              
        }
      }
      else {
        my $msg = "Time range error in request.";
        $logger->error($msg);
	      $mdId = "metadata.".genuid();
	      $dId = "data.".genuid();      
        print $tempHandle getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ma.structure");
        print $tempHandle getResultCodeData($dId, $mdId, $msg);
      }      
    }
    else {
      my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
      $logger->error($msg);
	    $mdId = "metadata.".genuid();
	    $dId = "data.".genuid();      
      print $tempHandle getResultCodeMetadata($mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
      print $tempHandle getResultCodeData($dId, $mdId, $msg);  
    }
  }
  seek($tempHandle, 0, 0);
  my $localContent = do { local( $/ ) ; <$tempHandle> } ;
  close($tempHandle);
  unlink0($tempHandle, $tempFilename) or $logger->error("Unlink0 failure on filehandle for '".$tempFilename."'");
  unlink($tempFilename) or $logger->error("Unlink failure for '".$tempFilename."'");
  return $localContent;
}


sub setupDataRetrieveMetadataData {
  my($self, $metadatadb, $metadata, $id, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $mdId = "";
  my $dId = ""; 

	my $queryString = "//nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  $logger->debug("Query \"".$queryString."\" created.");
	my @resultsString = $metadatadb->query($queryString);   
	
	if($#resultsString != -1) {
	  for(my $x = 0; $x <= $#resultsString; $x++) {	
      my $parser = XML::LibXML->new();
      my $doc = $parser->parse_string($resultsString[$x]);  
      my $md = $doc->find("//nmwg:metadata")->get_node(1);
      $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]";
      $logger->debug("Query \"".$queryString."\" created.");
	    my @dataResultsString = $metadatadb->query($queryString);
	    if($#dataResultsString != -1) {             
        for(my $y = 0; $y <= $#dataResultsString; $y++) {
          my $parser2 = XML::LibXML->new();
          my $doc2 = $parser2->parse_string($dataResultsString[$y]);  
          my $d = $doc2->find("//nmwg:data")->get_node(1);
          my $eventTypes = $metadata->find("./nmwg:eventType");
          my $eventTypes2 = $metadata->find(".//nmwg:parameter[\@name=\"supportedEventType\"]");
          my $supportedEventTypes = $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"]");
          my $match = 0;
          foreach my $set ($supportedEventTypes->get_nodelist) {
            last if($match == 1);
            foreach my $et ($eventTypes->get_nodelist) {
              if(extract($et) eq extract($set)) {
                $match = 1;
                last;
              }
            }
            foreach my $et2 ($eventTypes2->get_nodelist) {
              if(extract($et2) eq extract($set)) {
                $match = 1;
                last;
              }
            }
          }
          if($match) {
            $mdId = "metadata.".genuid();
            $md->setAttribute("metadataIdRef", $id);
            $md->setAttribute("id", $mdId);
		        print $tempHandle $md->toString();  
		        print $tempHandle handleData($self, $md->getAttribute("id"), $dataResultsString[$y], $tempHandle);
          }
        }     	  
      }
      else {
        my $msg = "Data content not found in metadata storage.";
        $logger->error($msg);
        $mdId = "metadata.".genuid();
        $dId = "data.".genuid();     
        print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
        print $tempHandle getResultCodeData($dId, $mdId, $msg);              
      }
	  }
	}
	else {
    my $msg = "Metadata content not found in metadata storage.";
    $logger->error($msg);
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();         
    print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
    print $tempHandle getResultCodeData($dId, $mdId, $msg); 
	}
  return;
}


sub setupDataRetrieveKey {
  my($self, $metadatadb, $metadata, $chain, $id, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $mdId = "";
  my $dId = ""; 

	my $queryString = "//nmwg:data[" . getDataXQuery($metadata, "") . "]";
  $logger->debug("Query \"".$queryString."\" created.");
	my @resultsString = $metadatadb->query($queryString);   
	if($#resultsString == 0) {
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string($resultsString[0]);  
    my $key = $doc->find("//nmwg:data/nmwg:key")->get_node(1);	      

    if($key) {
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();      
      if(defined $chain and $chain ne "") {
        $logger->debug("Preparing to search chain for modifications.");
        if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p ($chain->find("./select:parameters")->get_node(1)->childNodes) {
            $logger->debug("Modifying chain.");
            $key->find(".//nmwg:parameters")->get_node(1)->addChild($p->cloneNode(1));
          }
        }
        print $tempHandle createMetadata($mdId, $id, $key->toString);
  		  print $tempHandle handleData(\%{$self}, $mdId, $resultsString[0], $tempHandle); 
      }       
      else {
        print $tempHandle createMetadata($mdId, $id, $metadata->toString);
  		  print $tempHandle handleData(\%{$self}, $mdId, $resultsString[0], $tempHandle); 
      }
    }
    else {
      my $msg = "Key not found in metadata storage.";
      $logger->error($msg);
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();         
      print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
      print $tempHandle getResultCodeData($dId, $mdId, $msg); 
    }	  
	}
	else {
    my $msg = "Keys error in metadata storage.";
    $logger->error($msg);
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();           
    print $tempHandle getResultCodeMetadata($mdId, $id, "error.ma.storage.result");
    print $tempHandle getResultCodeData($dId, $mdId, $msg); 
	}
  return;
}


sub handleData {
  my($self, $id, $dataString, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  $logger->debug("Data \"".$dataString."\" found.");	    
  undef $self->{RESULTS};		    

  my $parser = XML::LibXML->new();
  $self->{RESULTS} = $parser->parse_string($dataString);   
  my $dt = $self->{RESULTS}->find("//nmwg:data")->get_node(1);
  my $type = extract($dt->find("./nmwg:key//nmwg:parameter[\@name=\"type\"]")->get_node(1));
                  
  if($type eq "rrd") {
    retrieveRRD($self, $dt, $id, $tempHandle);		       
  }
  elsif($type eq "sqlite") {
    retrieveSQL($self, $dt, $id, $tempHandle);		  		       
  }		
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    $logger->error($msg);    
    print $tempHandle getResultCodeData("data.".genuid(), $id, $msg);  
  }
  return;
}


sub retrieveSQL {
  my($self, $d, $mid, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my $responseString = "";
  my @dbSchema = ("id", "time", "value", "eventtype", "misc");
  my $result = getDataSQL($self, $d, \@dbSchema);  
  my $id = "data.".genuid();
    
  if($#{$result} == -1) {
    my $msg = "Query returned 0 results";
    $logger->error($msg);
    print $tempHandle getResultCodeData($id, $mid, $msg); 
  }   
  else { 
    $logger->debug("Data found.");
    print $tempHandle "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";

    for(my $a = 0; $a <= $#{$result}; $a++) {    
      print $tempHandle "    <nmwg:datum timeType=\"";
        
      if($self->{"TIMETYPE"} and $self->{"TIMETYPE"} eq "iso") {      
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($result->[$a][1]);
        print $tempHandle "ISO\" ".$dbSchema[1]."Value=\"";
        printf $tempHandle "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
        print $tempHandle "\"";
      }
      else {
        print $tempHandle "unix\" ".$dbSchema[1]."Value=\"".$result->[$a][1]."\"";
      }
        
      print $tempHandle " ".$dbSchema[2]."=\"".$result->[$a][2]."\"";
      my @misc = split(/,/,$result->[$a][4]);
      foreach my $m (@misc) {
        my @pair = split(/=/,$m);
	      print $tempHandle " ".$pair[0]."=\"".$pair[1]."\""; 
      }
      print $tempHandle " />\n";
    }
    
    print $tempHandle "  </nmwg:data>\n";
    $logger->debug("Data block created.");
  }  
  return $responseString;
}


sub retrieveRRD {
  my($self, $d, $mid, $tempHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my $responseString = "";
  adjustRRDTime($self, $tempHandle);
  if(!$responseString) {
    my $id = "data.".genuid();
    
    my %rrd_result = getDataRRD($self, $d, $mid, $id);
    if($rrd_result{ERROR}) {
      $logger->error("RRD error seen.");
      print $tempHandle $rrd_result{ERROR};
    }
    else {
      $logger->debug("Data found.");
      print $tempHandle "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
      my $dataSource = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"dataSource\"]")->get_node(1));
      my $valueUnits = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"valueUnits\"]")->get_node(1));
    
      foreach $a (sort(keys(%rrd_result))) {
        foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
	        if($b eq $dataSource) {
	          print $tempHandle "    <nmwg:datum timeType=\"";
            if($self->{"TIMETYPE"} and $self->{"TIMETYPE"} eq "iso") {      
              my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($a);
              print $tempHandle "ISO\" timeValue=\"";
              printf $tempHandle "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
              print $tempHandle "\"";
            }
            else {
              print $tempHandle "unix\" timeValue=\"".$a."\"";
            }	          
	          print $tempHandle " value=\"".$rrd_result{$a}{$b}."\" valueUnits=\"".$valueUnits."\"/>\n";
          }
        }
      }
      
      print $tempHandle "  </nmwg:data>\n";
      $logger->debug("Data block created.");
    }
  }
  return;
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

Gets instructions from the perfSONAR_PS::Transport module, and handles the 
request.  

=head2 handleRequest($self)

Functions as the 'gatekeeper' the the MA.  Will either reject or accept
requets.  will also 'do nothing' in the event that a request has been
acted on by the lower layer.  

=head2 maMetadataKeyRequest($self)

Handles the MetadataKeyRequest type of messages and all variants it may take on.

=head2 metadataKeyRetrieveKey($self, $metadatadb, $key, $chain, $id, $tempHandle)

Handles the specific case of MetadataKeyRequest where a key is supplied.  

=head2 metadataKeyRetrieveMetadataData($self, $metadatadb, $metadata, $chain, $id, $tempHandle)

Handles the specific case of MetadataKeyRequest where no key is supplied.  

=head2 maSetupDataRequest($self)

Handles the SetupDataRequest type of messages and all variants it may take on.

=head2 setupDataRetrieveMetadataData($self, $metadatadb, $metadata, $id, $tempHandle)

Handles the specific case of SetupDataRequest where no key is supplied.  

=head2 setupDataRetrieveKey($self, $metadatadb, $metadata, $chain, $id, $tempHandle)

Handles the specific case of SetupDataRequest where a key is supplied.

=head2 handleData($self, $id, $dataString, $tempHandle)

Handles the data portion of a SetupDataRequest by contacting the supported databases.

=head2 retrieveSQL($self, $d, $mid, $tempHandle)

Gathers data from the SQL database and creates XML to return.

=head2 retrieveRRD($self, $d, $mid, $tempHandle)

Gathers data from the RR database and creates XML to return.

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<Log::Log4perl>, L<File::Temp>, L<perfSONAR_PS::MA::Base>, 
L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>, 
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::RRD>, 
L<perfSONAR_PS::DB::SQL>

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

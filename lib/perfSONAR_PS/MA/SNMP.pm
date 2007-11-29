#!/usr/bin/perl -w

package perfSONAR_PS::MA::SNMP;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use File::Temp qw(tempfile);
use Time::HiRes qw(gettimeofday tv_interval);
use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);


sub init {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  if ($self->SUPER::init != 0) {
    $logger->error("Couldn't initialize parent class");
    return -1;
  }

  # values that are deal breakers...

  if(!defined $self->{CONF}->{"ENDPOINT"} or 
     $self->{CONF}->{"ENDPOINT"} eq "") {
    $logger->error("Value for 'ENDPOINT' is not set.");
    return -1;
  }  

  if(!defined $self->{CONF}->{"PORT"} or 
     $self->{CONF}->{"PORT"} eq "") {
    $logger->error("Value for 'PORT' is not set.");
    return -1;
  }  

  if(!defined $self->{CONF}->{"METADATA_DB_TYPE"} or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "") {
    $logger->error("Value for 'METADATA_DB_TYPE' is not set.");
    return -1;
  }    

  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {  
    if(!defined $self->{CONF}->{"METADATA_DB_FILE"} or 
       $self->{CONF}->{"METADATA_DB_FILE"} eq "") {
      $logger->error("Value for 'METADATA_DB_FILE' is not set.");
      return -1;
    }  
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"METADATA_DB_FILE"} =~ "^/")) {
          $self->{CONF}->{"METADATA_DB_FILE"} = $self->{DIRECTORY}."/".$self->{CONF}->{"METADATA_DB_FILE"};
        }
      }
    }
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
    if(!defined $self->{CONF}->{"METADATA_DB_FILE"} or 
       $self->{CONF}->{"METADATA_DB_FILE"} eq "") {
      $logger->error("Value for 'METADATA_DB_FILE' is not set.");
      return -1;
    }  
    if(!defined $self->{CONF}->{"METADATA_DB_NAME"} or 
       $self->{CONF}->{"METADATA_DB_NAME"} eq "") {
      $logger->error("Value for 'METADATA_DB_NAME' is not set.");
      return -1;
    }  
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"METADATA_DB_NAME"} =~ "^/")) {
          $self->{CONF}->{"METADATA_DB_NAME"} = $self->{DIRECTORY}."/".$self->{CONF}->{"METADATA_DB_NAME"};
        }
      }
    }    
  }    
  else {
    $logger->error("Wrong value for 'METADATA_DB_TYPE' set.");
    return -1;    
  }

  if(!defined $self->{CONF}->{"RRDTOOL"} or 
     $self->{CONF}->{"RRDTOOL"} eq "") {
    $logger->error("Value for 'RRDTOOL' is not set.");
    return -1;
  }  

  # values that can be defaulted...

  if(!defined $self->{CONF}->{"MAX_WORKER_LIFETIME"} or 
     $self->{CONF}->{"MAX_WORKER_LIFETIME"} eq "") {
    $self->{CONF}->{"MAX_WORKER_LIFETIME"} = "600";
    $logger->error("Setting 'MAX_WORKER_LIFETIME' to '600'.");
  }  

  if(!defined $self->{CONF}->{"MAX_WORKER_PROCESSES"} or 
     $self->{CONF}->{"MAX_WORKER_PROCESSES"} eq "") {
    $self->{CONF}->{"MAX_WORKER_PROCESSES"} = "32";
    $logger->error("Setting 'MAX_WORKER_PROCESSES' to '32'.");
  }  
  
  if(!defined $self->{CONF}->{"DEFAULT_RESOLUTION"} or 
     $self->{CONF}->{"DEFAULT_RESOLUTION"} eq "") {
    $self->{CONF}->{"DEFAULT_RESOLUTION"} = "300";
    $logger->error("Setting 'DEFAULT_RESOLUTION' to '300'.");
  }  

  if(!defined $self->{CONF}->{"SERVICE_ACCESSPOINT"} or 
     $self->{CONF}->{"SERVICE_ACCESSPOINT"} eq "") {
    $self->{CONF}->{"SERVICE_ACCESSPOINT"} = "http://localhost:".$self->{CONF}->{"PORT"}."/".$self->{CONF}->{"ENDPOINT"}."";
    $logger->error("Setting 'SERVICE_ACCESSPOINT' to 'http://localhost:".$self->{CONF}->{"PORT"}."/".$self->{CONF}->{"ENDPOINT"}."'.");
  }  

  if(!defined $self->{CONF}->{"SERVICE_DESCRIPTION"} or 
     $self->{CONF}->{"SERVICE_DESCRIPTION"} eq "") {
    $self->{CONF}->{"SERVICE_DESCRIPTION"} = "perfSONAR_PS SNMP MA";
    $logger->error("Setting 'SERVICE_DESCRIPTION' to 'perfSONAR_PS SNMP MA'.");
  }  

  if(!defined $self->{CONF}->{"SERVICE_NAME"} or 
     $self->{CONF}->{"SERVICE_NAME"} eq "") {
    $self->{CONF}->{"SERVICE_NAME"} = "SNMP MA";
    $logger->error("Setting 'SERVICE_NAME' to 'SNMP MA'.");
  }      
  
  if(!defined $self->{CONF}->{"SERVICE_TYPE"} or 
     $self->{CONF}->{"SERVICE_TYPE"} eq "") {
    $self->{CONF}->{"SERVICE_TYPE"} = "MA";
    $logger->error("Setting 'SERVICE_TYPE' to 'MA'.");
  }  

  if(!defined $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} or 
     $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} eq "") {
    $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} = "0";
    $logger->error("Setting 'LS_REGISTRATION_INTERVAL' to '0'.");
  }  

  if(defined $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} and 
     $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} =~ m/^\d+$/) {
    if(!defined $self->{CONF}->{"LS_INSTANCE"} or 
       $self->{CONF}->{"LS_INSTANCE"} eq "") {
      $logger->error("Value for 'LS_INSTANCE' is not set.");
      $self->{CONF}->{"LS_REGISTRATION_INTERVAL"} = "0";
      $self->{CONF}->{"LS_INSTANCE"} = "";
    }  
  }
  return 0;
}


sub receive {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $n;
  my $request;
  my $error;
  do {
    $request = undef;
    $n = $self->{LISTENER}->acceptCall(\$request, \$error);
    if($n == 0) {
      $logger->debug("Received 'shadow' request from below; no action required.");
      $request->finish;
    }
    if(defined $error and $error ne "") {
      $logger->error("Error in accept call: $error");
    }
  } 
  while ($n == 0);
  return $request;
}


sub handleRequest {
  my ($self, $request, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  $logger->debug("Handling request");

  my $t0 = [Time::HiRes::gettimeofday];  
  $logger->info("Received Request:\t".$t0->[0].".".$t0->[1]);  
  
  eval {
    local $SIG{ALRM} = sub{ die "Request lasted too long\n" };
    alarm($self->{CONF}->{"MAX_WORKER_LIFETIME"}) if(defined $self->{CONF}->{"MAX_WORKER_LIFETIME"} and $self->{CONF}->{"MAX_WORKER_LIFETIME"} > 0);
    __handleRequest($self, $request, $fileHandle);
  };

  # disable the alarm after the eval is done
  alarm(0);
  
  if($@) {
    my $msg = "Unhandled exception or crash: $@";
    $logger->error($msg);
    $request->setResponse(getResultCodeMessage($fileHandle, "message.".genuid(), "", "response", "error.perfSONAR_PS", $msg));
  }

  seek($fileHandle, 0, 0);
  $request->setResponse(do { local( $/ ); <$fileHandle> });

  my $t1 = [Time::HiRes::gettimeofday];
  my $t0_t1 = Time::HiRes::tv_interval $t0, $t1;
  $logger->info("Request Completed:\t".$t1->[0].".".$t1->[1]);
  $logger->info("Total Service Time:\t".$t0_t1." seconds.");

  $request->finish;
  return;
}


sub __handleRequest {
  my($self, $request, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  $self->{REQUESTNAMESPACES} = $request->getNamespaces();

  my $messageId = $request->getRequestDOM()->getDocumentElement->getAttribute("id");
  my $messageType = $request->getRequestDOM()->getDocumentElement->getAttribute("type");        
  my $messageIdReturn = "message.".genuid(); 
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file" or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {

    my $msgParams = find($request->getRequestDOM()->getDocumentElement, "./nmwg:parameters", 1); 
    if($msgParams) {
      $msgParams = handleMessageParameters($self, $msgParams);
      $msgParams = $msgParams->toString."\n";
    }      
     
    if($messageType eq "MetadataKeyRequest") {
      $logger->debug("Parsing MetadataKey request.");
      startMessage($fileHandle, $messageIdReturn, $messageId, "MetadataKeyResponse");
      if($msgParams) {
        print $fileHandle $msgParams;
      }
      maMetadataKeyRequest($self, $fileHandle, $request);   
      endMessage($fileHandle);
    }
    elsif($messageType eq "SetupDataRequest") {
      $logger->debug("Parsing SetupData request.");
      startMessage($fileHandle, $messageIdReturn, $messageId, "SetupDataResponse");
      if($msgParams) {
        print $fileHandle $msgParams;
      }
      maSetupDataRequest($self, $fileHandle, $request);  
      endMessage($fileHandle);
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      $logger->error($msg);  
      getResultCodeMessage($fileHandle, $messageIdReturn, $messageId, "", $messageType."Response", "error.ma.message.type", $msg);
    }
     
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    $logger->error($msg); 
    getResultCodeMessage($fileHandle, $messageIdReturn, $messageId, "", "Response", "error.ma.snmp", $msg);
  }
  return;
}


sub handleMessageParameters {
  my($self, $msgParams) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  foreach my $p ($msgParams->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "parameter")) {
    if($p->getAttribute("name") eq "timeType") {
      my $type = extract($p);
      if($type =~ m/^unix$/i) {
        $self->{"TIMETYPE"} = "unix";
      }
      elsif($type =~ m/^iso/i) {
        $self->{"TIMETYPE"} = "iso";
      } 
    }
    elsif($p->getAttribute("name") eq "eventNameSpaceSynchronization") {
      my $type = extract($p);
      if($type =~ m/^true$/i) {
        $self->{"DATUMNS"} = "true";
      }
    }  
  }
  return $msgParams;
}


sub maMetadataKeyRequest {
  my($self, $fileHandle, $request) = @_; 
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
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

  # MA MetadataKeyRequest Steps
  # ---------------------
  # Is there a key?
  #   Y: do queries against key return key as md AND d
  #   N: Is there a chain?
  #     Y: Is there a key
  #       Y: do queries against key, add in select stuff to key, return key as md AND d
  #       N: do md/d queries against md return results with altered key
  #     N: do md/d queries against md return results

  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {      
    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    if(defined $m) {        
      if(getTime($request, \%{$self}, $m->getAttribute("id"))) {
        if($m->find("./nmwg:key")) {
          metadataKeyRetrieveKey(\%{$self}, $metadatadb, $m->find("./nmwg:key")->get_node(1), "", $m->getAttribute("id"), $fileHandle);
        }
        else {
          if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and 
             $m->find("./select:subject")) {
            my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".$m->find("./select:subject")->get_node(1)->getAttribute("metadataIdRef")."\"]", 1);  
            if($other_md) {
              if($other_md->find("./nmwg:key")) {
                metadataKeyRetrieveKey(\%{$self}, $metadatadb, $other_md->find("./nmwg:key")->get_node(1), $m, $m->getAttribute("id"), $fileHandle);                 
              }
              else {
                metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $other_md, $m, $m->getAttribute("id"), $fileHandle);
              }
            }
            else {
              my $msg = "Cannot resolve supposed subject chain in metadata.";
              $logger->error($msg);
              $mdId = "metadata.".genuid();
              $dId = "data.".genuid();      
              getResultCodeMetadata($fileHandle, $mdId, $m->getAttribute("id"), "error.ma.chaining");
              getResultCodeData($fileHandle, $dId, $mdId, $msg);          
            }
          }
          else {
            metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $m, "", $m->getAttribute("id"), $fileHandle);
          }
        }
      }
      else {
        my $msg = "Time range error in request.";
        $logger->error($msg);
        $mdId = "metadata.".genuid();
        $dId = "data.".genuid();      
        getResultCodeMetadata($fileHandle, $mdId, $m->getAttribute("id"), "error.ma.structure");
        getResultCodeData($fileHandle, $dId, $mdId, $msg);
      }
    }
    else {
      my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
      $logger->error($msg);
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();      
      getResultCodeMetadata($fileHandle, $mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
      getResultCodeData($fileHandle, $dId, $mdId, $msg);  
    }
  }
  return;
}


sub metadataKeyRetrieveKey {
  my($self, $metadatadb, $key, $chain, $id, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid(); 
 
  my $queryString = "/nmwg:store/nmwg:data[" . getDataXQuery($key, "") . "]";
  my $results = $metadatadb->querySet($queryString);   
  if($results->size() == 1) {
    my $key2 = find($results->get_node(1)->cloneNode(1), "./nmwg:key", 1);  
    if($key2) {   
      if(defined $chain and $chain ne "") {
        if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
            $key2->find(".//nmwg:parameters")->get_node(1)->addChild($p->cloneNode(1));
          }
        }
      }    
      createMetadata($fileHandle, $mdId, $id, $key->toString);
      createData($fileHandle, $dId, $mdId, $key2->toString);
    }
    else {
      my $msg = "Key error in metadata storage.";
      $logger->error($msg);     
      getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage.result");
      getResultCodeData($fileHandle, $dId, $mdId, $msg);
    }
  }
  else {
    my $msg = "Key error in metadata storage.";
    $logger->error($msg);     
    getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage.result");
    getResultCodeData($fileHandle, $dId, $mdId, $msg); 
  }
  return;
}


sub metadataKeyRetrieveMetadataData {
  my($self, $metadatadb, $metadata, $chain, $id, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = ""; 

  my $queryString = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  my $results = $metadatadb->querySet($queryString);

  my %et = ();
  my $eventTypes = find($metadata, "./nmwg:eventType");
  my $supportedEventTypes = find($metadata, ".//nmwg:parameter[\@name=\"supportedEventType\"]");
  foreach my $e ($eventTypes->get_nodelist) {
    my $value = extract($e);
    if($value) {
      $et{$value} = 1;
    }
  }
  foreach my $se ($supportedEventTypes->get_nodelist) {
    my $value = extract($se);
    if($value) {
      $et{$value} = 1;
    }
  }

  $queryString = "/nmwg:store/nmwg:data";
  if($eventTypes->size() or $supportedEventTypes->size()) {
    $queryString = $queryString . "[./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"";    
    foreach my $e (sort keys %et) {
      $queryString = $queryString . " and \@value=\"".$e."\" or text()=\"".$e."\"";  
    }
    $queryString = $queryString . "]]"; 
  }
  my $dataResults = $metadatadb->querySet($queryString);

  my %used = ();
  for(my $x = 0; $x <= $dataResults->size(); $x++) {
    $used{$x} = 0;
  }

  if($results->size() > 0 and $dataResults->size() > 0) {
    foreach my $md ($results->get_nodelist) {
      if($md->getAttribute("id")) {
        my $md_temp = $md->cloneNode(1);
        my $uc = 0;
        foreach my $d ($dataResults->get_nodelist) {
          if(!$used{$uc} and $d->getAttribute("metadataIdRef") and 
             $md_temp->getAttribute("id") eq $d->getAttribute("metadataIdRef")) {
            my $d_temp = $d->cloneNode(1);
            $dId = "data.".genuid();
            $mdId = "metadata.".genuid();
            $d_temp->setAttribute("metadataIdRef", $mdId);
            $d_temp->setAttribute("id", $dId);
            if(defined $chain and $chain ne "") {
              if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
                foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
                  find($d_temp, ".//nmwg:parameters", 1)->addChild($p->cloneNode(1));
                }
              }        
            }
            $md_temp->setAttribute("metadataIdRef", $id);
            $md_temp->setAttribute("id", $mdId);        
            print $fileHandle $md_temp->toString; 
            print $fileHandle $d_temp->toString; 
            $used{$uc}++;
            last;
          } 
          $uc++;
        }
      }      
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg); 
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();      
    getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage");
    getResultCodeData($fileHandle, $dId, $mdId, $msg); 
  }
  return;
}



sub maSetupDataRequest {
  my($self, $fileHandle, $request) = @_; 
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
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
          
  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {      
    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    if(defined $m) {        

      if(getTime($request, \%{$self}, $m->getAttribute("id"))) {    
        if($m->find("./nmwg:key")) {
          setupDataRetrieveKey(\%{$self}, $metadatadb, $m->find("./nmwg:key")->get_node(1), "", $m->getAttribute("id"), $fileHandle);
        }
        else {
          if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and 
             $m->find("./select:subject")) {
            my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".$m->find("./select:subject")->get_node(1)->getAttribute("metadataIdRef")."\"]", 1);  
            if($other_md) {
              if($other_md->find("./nmwg:key")) {
                setupDataRetrieveKey(\%{$self}, $metadatadb, $other_md->find("./nmwg:key")->get_node(1), $m, $m->getAttribute("id"), $fileHandle);
              }
              else {
                setupDataRetrieveMetadataData($self, $metadatadb, $other_md, $m->getAttribute("id"), $fileHandle);           
              }
            }
            else {
              my $msg = "Cannot resolve subject chain in metadata.";
              $logger->error($msg);
              $mdId = "metadata.".genuid();
              $dId = "data.".genuid();      
              getResultCodeMetadata($fileHandle, $mdId, $m->getAttribute("id"), "error.ma.chaining");
              getResultCodeData($fileHandle, $dId, $mdId, $msg);
            }
          }
          else {
            setupDataRetrieveMetadataData($self, $metadatadb, $m, $m->getAttribute("id"), $fileHandle);
          }              
        }
      }
      else {
        my $msg = "Time range error in request.";
        $logger->error($msg);
        $mdId = "metadata.".genuid();
        $dId = "data.".genuid();      
        getResultCodeMetadata($fileHandle, $mdId, $m->getAttribute("id"), "error.ma.structure");
        getResultCodeData($fileHandle, $dId, $mdId, $msg);
      }      
    }
    else {
      my $msg = "Data trigger with id \"".$d->getAttribute("id")."\" has no matching metadata";
      $logger->error($msg);
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();      
      getResultCodeMetadata($fileHandle, $mdId, $d->getAttribute("metadataIdRef"), "error.ma.structure");
      getResultCodeData($fileHandle, $dId, $mdId, $msg);  
    }
  }
  return;
}


sub setupDataRetrieveMetadataData {
  my($self, $metadatadb, $metadata, $id, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = ""; 

  my $queryString = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  my $results = $metadatadb->querySet($queryString);

  my %et = ();
  my $eventTypes = find($metadata, "./nmwg:eventType");
  my $supportedEventTypes = find($metadata, ".//nmwg:parameter[\@name=\"supportedEventType\"]");
  foreach my $e ($eventTypes->get_nodelist) {
    my $value = extract($e);
    if($value) {
      $et{$value} = 1;
    }
  }
  foreach my $se ($supportedEventTypes->get_nodelist) {
    my $value = extract($se);
    if($value) {
      $et{$value} = 1;
    }
  }

  $queryString = "/nmwg:store/nmwg:data";
  if($eventTypes->size() or $supportedEventTypes->size()) {
    $queryString = $queryString . "[./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"supportedEventType\"";    
    foreach my $e (sort keys %et) {
      $queryString = $queryString . " and \@value=\"".$e."\" or text()=\"".$e."\"";  
    }
    $queryString = $queryString . "]]"; 
  }
  my $dataResults = $metadatadb->querySet($queryString);

  my %used = ();
  for(my $x = 0; $x <= $dataResults->size(); $x++) {
    $used{$x} = 0;
  }

  if($results->size() > 0 and $dataResults->size() > 0) {
    foreach my $md ($results->get_nodelist) {

      my %l_et = ();
      my $l_eventTypes = find($md, "./nmwg:eventType");
      my $l_supportedEventTypes = find($md, ".//nmwg:parameter[\@name=\"supportedEventType\"]");
      foreach my $e ($l_eventTypes->get_nodelist) {
        my $value = extract($e);
        if($value) {
          $l_et{$value} = 1;
        }
      }
      foreach my $se ($l_supportedEventTypes->get_nodelist) {
        my $value = extract($se);
        if($value) {
          $l_et{$value} = 1;
        }
      }    
    
      if($md->getAttribute("id")) {
        my $md_temp = $md->cloneNode(1);
        my $uc = 0;
        foreach my $d ($dataResults->get_nodelist) {
          if(!$used{$uc} and $d->getAttribute("metadataIdRef") and 
             $md_temp->getAttribute("id") eq $d->getAttribute("metadataIdRef")) {
            my $d_temp = $d->cloneNode(1);
            $mdId = "metadata.".genuid();
            $md_temp->setAttribute("metadataIdRef", $id);
            $md_temp->setAttribute("id", $mdId);
            print $fileHandle $md_temp->toString();  
            handleData($self, $mdId, $d_temp, $fileHandle, \%l_et);
            $used{$uc}++;
            last;
          } 
          $uc++;
        }
      }      
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg); 
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();      
    getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage");
    getResultCodeData($fileHandle, $dId, $mdId, $msg); 
  }
  return;
}


sub setupDataRetrieveKey {
  my($self, $metadatadb, $metadata, $chain, $id, $fileHandle) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = ""; 

  my $queryString = "/nmwg:store/nmwg:data[" . getDataXQuery($metadata, "") . "]";
  my $results = $metadatadb->querySet($queryString);    
  if($results->size() == 1) {

    my $results_temp = $results->get_node(1)->cloneNode(1);
    my $key = find($results_temp, "./nmwg:key", 1);
    if($key) {
    
      my %l_et = ();
      my $l_supportedEventTypes = find($key, ".//nmwg:parameter[\@name=\"supportedEventType\"]");
      foreach my $se ($l_supportedEventTypes->get_nodelist) {
        my $value = extract($se);
        if($value) {
          $l_et{$value} = 1;
        }
      }        
    
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();      
      if(defined $chain and $chain ne "") {
        if($self->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
            $key->find(".//nmwg:parameters")->get_node(1)->addChild($p->cloneNode(1));
          }
        }
        createMetadata($fileHandle, $mdId, $id, $key->toString);
        handleData(\%{$self}, $mdId, $results_temp, $fileHandle, \%l_et); 
      }       
      else {
        createMetadata($fileHandle, $mdId, $id, $metadata->toString);
        handleData(\%{$self}, $mdId, $results_temp, $fileHandle, \%l_et); 
      }
    }
    else {
      my $msg = "Key not found in metadata storage.";
      $logger->error($msg);
      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();         
      getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage.result");
      getResultCodeData($fileHandle, $dId, $mdId, $msg); 
    }    
  }
  else {
    my $msg = "Keys error in metadata storage.";
    $logger->error($msg);
    $mdId = "metadata.".genuid();
    $dId = "data.".genuid();           
    getResultCodeMetadata($fileHandle, $mdId, $id, "error.ma.storage.result");
    getResultCodeData($fileHandle, $dId, $mdId, $msg); 
  }
  return;
}


sub handleData {
  my($self, $id, $data, $fileHandle, $et) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  undef $self->{RESULTS};        

  $self->{RESULTS} = $data;   
  my $type = extract(find($data, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]", 1));           
  if($type eq "rrd") {
    retrieveRRD($self, $data, $id, $fileHandle, $et);           
  }
  elsif($type eq "sqlite") {
    retrieveSQL($self, $data, $id, $fileHandle, $et);                 
  }    
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    $logger->error($msg);    
    getResultCodeData($fileHandle, "data.".genuid(), $id, $msg);  
  }
  return;
}


sub retrieveSQL {
  my($self, $d, $mid, $fileHandle, $et) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  
  my @dbSchema = ("id", "time", "value", "eventtype", "misc");
  my $result = getDataSQL($self, $d, \@dbSchema);  
  my $id = "data.".genuid();
    
  if($#{$result} == -1) {
    my $msg = "Query returned 0 results";
    $logger->error($msg);
    getResultCodeData($fileHandle, $id, $mid, $msg); 
  }   
  else { 
    my $prefix = "nmwg";
    my $uri = "http://ggf.org/ns/nmwg/base/2.0";
    if($self->{"DATUMNS"} and $self->{"DATUMNS"} eq "true") {
      if(defined $et and $et ne "") {
        foreach my $e (sort keys %{$et}) {
          next if $e eq "http://ggf.org/ns/nmwg/tools/snmp/2.0";
          $uri = $e;
        }
      }
      if($uri ne "http://ggf.org/ns/nmwg/base/2.0") {
        foreach my $r (sort keys %{$self->{NAMESPACES}}) {
          if(($uri."/") eq $self->{NAMESPACES}->{$r}) {
            $prefix = $r;
            last;
          }
        }
        if(!$prefix) {
          $prefix = "nmwg";
          $uri = "http://ggf.org/ns/nmwg/base/2.0";
        }
      }
    } 
  
    print $fileHandle "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
    for(my $a = 0; $a <= $#{$result}; $a++) {    
      print $fileHandle "    <".$prefix.":datum xmlns:".$prefix."=\"".$uri."/\" timeType=\"";
        
      if($self->{"TIMETYPE"} and $self->{"TIMETYPE"} eq "iso") {      
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($result->[$a][1]);
        print $fileHandle "ISO\" ".$dbSchema[1]."Value=\"";
        printf $fileHandle "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
        print $fileHandle "\"";
      }
      else {
        print $fileHandle "unix\" ".$dbSchema[1]."Value=\"".$result->[$a][1]."\"";
      }
      print $fileHandle " ".$dbSchema[2]."=\"".$result->[$a][2]."\"";
      my @misc = split(/,/,$result->[$a][4]);
      foreach my $m (@misc) {
        my @pair = split(/=/,$m);
        print $fileHandle " ".$pair[0]."=\"".$pair[1]."\""; 
      }
      print $fileHandle " />\n";
    } 
    print $fileHandle "  </nmwg:data>\n";
  }  
  return;
}


sub retrieveRRD {
  my($self, $d, $mid, $fileHandle, $et) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my($sec, $frac) = Time::HiRes::gettimeofday;
  
  adjustRRDTime($self);
  my $id = "data.".genuid(); 
  my %rrd_result = getDataRRD($self, $d, $mid, $id);
  if($rrd_result{ERROR}) {
    $logger->error("RRD error seen.");
    print $fileHandle $rrd_result{ERROR};
  }
  else {
    my $prefix = "nmwg";
    my $uri = "http://ggf.org/ns/nmwg/base/2.0";
    if($self->{"DATUMNS"} and $self->{"DATUMNS"} eq "true") {
      if(defined $et and $et ne "") {
        foreach my $e (sort keys %{$et}) {
          next if $e eq "http://ggf.org/ns/nmwg/tools/snmp/2.0";
          $uri = $e;
        }
      }
      if($uri ne "http://ggf.org/ns/nmwg/base/2.0") {
        foreach my $r (sort keys %{$self->{NAMESPACES}}) {
          if(($uri."/") eq $self->{NAMESPACES}->{$r}) {
            $prefix = $r;
            last;
          }
        }
        if(!$prefix) {
          $prefix = "nmwg";
          $uri = "http://ggf.org/ns/nmwg/base/2.0";
        }
      }
    }
    
    print $fileHandle "\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
    my $dataSource = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"dataSource\"]", 1));
    my $valueUnits = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"valueUnits\"]", 1));
    
    foreach $a (sort(keys(%rrd_result))) {
      foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
        if($b eq $dataSource) {
          if($a < $sec) {
            print $fileHandle "    <".$prefix.":datum xmlns:".$prefix."=\"".$uri."/\" timeType=\"";
            if($self->{"TIMETYPE"} and $self->{"TIMETYPE"} eq "iso") {      
              my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($a);
              print $fileHandle "ISO\" timeValue=\"";
              printf $fileHandle "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
              print $fileHandle "\"";
            }
            else {
              print $fileHandle "unix\" timeValue=\"".$a."\"";
            }            
            print $fileHandle " value=\"".$rrd_result{$a}{$b}."\" valueUnits=\"".$valueUnits."\"/>\n";
          }
        }
      }
    }
    print $fileHandle "  </nmwg:data>\n";
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
    
    my $ma = perfSONAR_PS::MA::SNMP->new(\%conf, \%ns, $dirname);
    if($ma->init != 0) {
      print "Couldn't initialize.\n";
      exit(-1);
    }
    
    # or
    # $ma = perfSONAR_PS::MA::SNMP->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);      
        
    $ma->init;  
    while(1) {
      $ma->receive;
    }  
  
=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 init($self)

Calls the upper level init and verifys the config file.

=head2 receive($self)

Gets instructions from the perfSONAR_PS::Transport module, and handles the 
request.

=head2 handleRequest($self, $request, $fileHandle)

Functions as the 'gatekeeper' the the MA.  Will either reject or accept
requets.  will also 'do nothing' in the event that a request has been
acted on by the lower layer.  

=head2 __handleRequest($self, $request, $fileHandle)

Processes the messages that this MA can handle.

=head2 handleMessageParameters($self, $msgParams)

Extracts and acts on special 'Message Level' parameters that may exist and change 
behavior or output.  Not to be used externally.  

=head2 maMetadataKeyRequest($self, $fileHandle, $request)

Handles the steps of a MetadataKeyRequest message.  Not to be used externally.

=head2 metadataKeyRetrieveKey($self, $metadatadb, $key, $chain, $id, $fileHandle)

Helper function for 'maMetadataKeyRequest', handles the case where a 'key' is present
in the request.  

=head2 metadataKeyRetrieveMetadataData($self, $metadatadb, $metadata, $chain, $id, $fileHandle)

Helper function for 'maMetadataKeyRequest', handles the case where a 'key' is not present
in the request. 

=head2 maSetupDataRequest($self, $fileHandle, $request)

Handles the steps of a SetupDataRequest message.  Not to be used externally.  

=head2 setupDataRetrieveMetadataData($self, $metadatadb, $metadata, $id, $fileHandle)

Helper function for 'maSetupDataRequest', handles the case where a 'key' is not present
in the request. 

=head2 setupDataRetrieveKey($self, $metadatadb, $metadata, $chain, $id, $fileHandle)

Helper function for 'maSetupDataRequest', handles the case where a 'key' is present
in the request. 

=head2 handleData($self, $id, $data, $fileHandle, \%et)

Handles the data portion of a SetupDataRequest by contacting the supported databases.

=head2 retrieveSQL($self, $d, $mid, $fileHandle)

Gathers data from the SQL database and creates the necessary XML.  
  
=head2 retrieveRRD($self, $d, $mid, $fileHandle)

Gathers data from the RR database and creates the necessary XML.  

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<File::Temp>, L<Time::HiRes>, 
L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id: SNMP.pm 692 2007-11-02 12:36:04Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut


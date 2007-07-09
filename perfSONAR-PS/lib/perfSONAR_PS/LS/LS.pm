#!/usr/bin/perl -w

package perfSONAR_PS::LS::LS;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::LS::Base;
use perfSONAR_PS::LS::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::XMLDB;


our @ISA = qw(perfSONAR_PS::LS::Base);


sub receive {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

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
    $self->{RESPONSE} = getResultCodeMessage("", "", "", "response", "error.transport.soap", $msg); 
  }
  return;
}


sub handleRequest {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  delete $self->{RESPONSE};

  $self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
    my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
    my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");    
    my $messageIdReturn = genuid();    

    if($messageType eq "LSRegisterRequest") {
      $logger->debug("Parsing LSRegister request.");
      my $response = lsRegisterRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSRegisterResponse", $response);
    }
    elsif($messageType eq "LSDeregisterRequest") {
      $logger->debug("Parsing LSDeregister request.");
      my $response = lsDeregisterRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSDeregisterResponse", $response);
    }
    elsif($messageType eq "LSKeepaliveRequest") {
      $logger->debug("Parsing LSKeepalive request.");
      my $response = lsKeepaliveRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSKeepaliveResponse", $response);
    }
    elsif($messageType eq "LSQueryRequest") {
      $logger->debug("Parsing LSQuery request.");
      my $response = lsQueryRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSQueryResponse", $response);
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      $logger->error($msg);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "", $messageType."Response", "error.ls.message.type", $msg);
    }
  }
  else {
    my $msg = "Internal LS error, Metadata Database choice \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    $logger->error($msg); 
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "", "MetadataKeyResponse", "error.ls", $msg);
  }
  return $self->{RESPONSE};
}



sub lsRegisterRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $localContent = "";
  
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
	$metadatadb->openDB; 
	      
  my $controldb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_CONTROL_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  my %keys = ();
  my $mdKey = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  # LS Registration Steps
  # ---------------------
  # Does MD have a key
  # Y: Is Key in the DB?
  #   Y: Update Control Info
  #      Is Data in DB?
  #     Y: 'success.ls.register'
  #     N: Insert, 'success.ls.register'
  #   N: Send 'error.ls.key_not_found' error
  # N: Is there an access point?
  #   Y: Is key in the DB?
  #     Y: Send 'error.ls.key_in_use' error
  #     N: Update Control Info, insert, 'success.ls.register'
  #   N: Send 'error.ls.registration.access_point_missing' error

  foreach my $d ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
        $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

        $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
        if($mdKey) {
          $logger->debug("Key found in metadata, proceeding with registration update.");
          
          if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
            $keys{$mdKey} = 0;
            my $result = $metadatadb->queryByName($mdKey); 
            if($result) {
              $logger->debug("Key already exists, updating control time information.");     
	            $controldb->updateByName(createControlKey($mdKey, $sec), $mdKey);       
              $keys{$mdKey} = 1;
            }
            else {
              $keys{$mdKey} = -1;
            }            
          }
          
          if($keys{$mdKey} >= 1) {
 	          foreach my $d_md ($d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
              my @resultsString = $metadatadb->queryForName("//nmwg:data[" . getXQuery($d_md) . "]");   
              if($#resultsString == -1) {
	              #$metadatadb->insertIntoContainer(createData($mdKey."/".$sec."/".$keys{$mdKey}, $mdKey, $d_md->toString), $mdKey."/".$sec."/".$keys{$mdKey});

	              $metadatadb->insertIntoElement(createData($mdKey."/".$sec."/".$keys{$mdKey}, $mdKey, $d_md->toString), $mdKey."/".$sec."/".$keys{$mdKey});
	              	              
	              
	              $logger->debug("Inserting measurement metadata as \"".$mdKey."/".$sec."/".$keys{$mdKey}."\" for key \"".$mdKey."\".");
	              $keys{$mdKey}++;              
              }
	          }	
	          $mdId = "resultMetadata.lsKey.".genuid();
	          $dId = "resultData.lsKey.".genuid();
	          $localContent = $localContent . createKey($mdId, $m->getAttribute("id"), $mdKey, "success.ls.register"); 
	          $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been updated with key [".$mdKey."]\" />");         
          }
          elsif($keys{$mdKey} == -1) {
            $logger->error("Key not found in database, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.key_not_found");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
          }
        }
        else {
          $logger->debug("Key not found in message, proceeding with registration.");
          
          $mdKey = extract($m->find("./perfsonar:subject/psservice:service/psservice:accessPoint")->get_node(1));
          if($mdKey) {

            if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
              $keys{$mdKey} = 0;
	            $logger->debug("Found accessPoint \"".$mdKey."\".");
	          
              my $result = $metadatadb->queryByName($mdKey); 
              if($result) {
                $keys{$mdKey} = -1;
                $logger->error("The key seems to be in use already, sending an error mesasge.");
              }
              else {
                $keys{$mdKey} = 1;              
                $logger->debug("New registration info, inserting service metadata and time information.");
              
	              my $service = $m->cloneNode(1);
	              $service->setAttribute("id", $mdKey);
	              $metadatadb->insertIntoContainer($service->toString, $mdKey);
	              $controldb->insertIntoContainer(createControlKey($mdKey, $sec), $mdKey);
	            }  
            }
          
            if($keys{$mdKey} >= 1) {
	            foreach my $d_md ($d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
	              $metadatadb->insertIntoContainer(createData($mdKey."/".$sec."/".$keys{$mdKey}, $mdKey, $d_md->toString), $mdKey."/".$sec."/".$keys{$mdKey});
	              $logger->debug("Inserting measurement metadata as 'data'.");
	              $keys{$mdKey}++;
	            }
	            $mdId = "resultMetadata.lsKey.".genuid();
	            $dId = "resultData.lsKey.".genuid();
	            $localContent = $localContent . createKey($mdId, $m->getAttribute("id"), $mdKey, "success.ls.register"); 
	            $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been registered with key [".$mdKey."]\" />"); 
	            $logger->debug("Adding info to response message.");
            }
            elsif($keys{$mdKey} == -1) {
	            $mdId = "resultMetadata.".genuid();
	            $dId = "resultData.".genuid();      
              $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.key_in_use");
              $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" is already in use.");
            }
          }
          else {
            $logger->error("AccessPoint not found in message to create a key, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.registration.access_point_missing");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "Cannont register data, accessPoint was not supplied.");
          }
        }
      }
    }
  }
  return $localContent;
}



sub lsDeregisterRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $localContent = "";
  
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
	$metadatadb->openDB; 
	      
  my $controldb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_CONTROL_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  my %keys = ();
  my $mdKey = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  # LS Deregistration Steps
  # ---------------------
  # Does MD have a key
  # Y: Is Key in the DB?
  #   Y: Are there metadata blocks in the data section?
  #     Y: Remove ONLY the data for that service/control
  #     N: Deregister the service, all data, and remove the control
  #   N: Send 'error.ls.key_not_found' error
  # N: Send 'error.ls.deregister.key_not_found' error

  foreach my $m ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
    $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
    if($mdKey) {
      $logger->debug("Key found in metadata, proceeding with deregistration."); 
      
      my $result = $metadatadb->queryByName($mdKey); 
      if($result) {

        $logger->debug("Key found in database, searching for data elements.");     
        foreach my $d ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
          if($m->getAttribute("id") eq $d->getAttribute("metadataIdRef")) {      
 	          my @deregs = $d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata");
 	          if($#deregs == -1) {
              $logger->debug("Bare key found, deregistering everything related to \"".$result."\"."); 
              
 	            my @resultsString = $metadatadb->queryForName("//nmwg:data[\@metadataIdRef=\"".$result."\"]");   
              for(my $x = 0; $x <= $#resultsString; $x++) {
                $logger->debug("Removing data \"".$resultsString[$x]."\".");
                $metadatadb->remove($resultsString[$x]);
              }      

              $logger->debug("Removing control info \"".$result."\".");
              $controldb->remove($result);
                            
              $logger->debug("Removing service info \"".$result."\".");
              $metadatadb->remove($result);
              
	            $mdId = "resultMetadata.".genuid();
	            $dId = "resultData.".genuid();      
              $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "success.ls.deregister");
              $localContent = $localContent . getResultCodeData($dId, $mdId, "Removed [".($#resultsString+1)."] data elements and service info for key \"".$result."\".");              
 	          }
 	          else {
 	            $logger->debug("Data found with key, deregistering each individually.");
 	            
 	            foreach my $d_md (@deregs) {
                my @resultsString = $metadatadb->queryForName("//nmwg:data[" . getXQuery($d_md) . "]");   
                for(my $x = 0; $x <= $#resultsString; $x++) {
                  $logger->debug("Removing data \"".$resultsString[$x]."\".");
                  $metadatadb->remove($resultsString[$x]);
                } 
	              $mdId = "resultMetadata.".genuid();
	              $dId = "resultData.".genuid();      
                $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "success.ls.deregister");
                $localContent = $localContent . getResultCodeData($dId, $mdId, "Removed [".($#resultsString+1)."] data elements for key \"".$result."\"."); 
 	            }
 	          }
          }
        }
      }
      else {
        $logger->error("Key not found in database, sending error mesasge.");
	      $mdId = "resultMetadata.".genuid();
	      $dId = "resultData.".genuid();      
        $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.key_not_found");
        $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
      } 
    }
    else {
      $logger->error("Key not found in metadata, sending error mesasge.");
	    $mdId = "resultMetadata.".genuid();
	    $dId = "resultData.".genuid();      
      $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.deregister.key_not_found");
      $localContent = $localContent . getResultCodeData($dId, $mdId, "Key not found in sent metadata.");
    }
  }

  return $localContent;
}


sub lsKeepaliveRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $localContent = "";
  
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
	$metadatadb->openDB; 
	      
  my $controldb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_CONTROL_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  my %keys = ();
  my $mdKey = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  # LS Keepalive Steps
  # ---------------------
  # Does MD have a key
  # Y: Is Key in the DB?
  #   Y: update control info
  # N: Send 'error.ls.keepalive.key_not_found' error

  foreach my $m ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
    $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
    if($mdKey) {
      $logger->debug("Key found in metadata, proceeding with keepalive."); 
      
      my $result = $metadatadb->queryByName($mdKey); 
      if($result) {
        $logger->debug("Updating control time information.");     
	      $controldb->updateByName(createControlKey($mdKey, $sec), $mdKey);
	      $mdId = "resultMetadata.".genuid();
	      $dId = "resultData.".genuid();      
        $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "success.ls.keepalive");
        $localContent = $localContent . getResultCodeData($dId, $mdId, "Key \"".$mdKey."\" was updated.");
      }
      else {
        $logger->error("Key not found in database, sending error mesasge.");
	      $mdId = "resultMetadata.".genuid();
	      $dId = "resultData.".genuid();      
        $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.key_not_found");
        $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
      } 
    }
    else {
      $logger->error("Key not found in metadata, sending error mesasge.");
	    $mdId = "resultMetadata.".genuid();
	    $dId = "resultData.".genuid();      
      $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.keepalive.key_not_found");
      $localContent = $localContent . getResultCodeData($dId, $mdId, "Key not found in sent metadata.");
    }
  }

  return $localContent;
}








sub lsQueryRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $localContent = "";
  
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
	$metadatadb->openDB; 
	      
  my $controldb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_CONTROL_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  # LS Query Steps
  # ---------------------
  # Does MD have an xquery:subject (support more later)
  # Y: does it have an eventType?
  #   Y: Supported eventType?
  #     Y: Send query to DB, perpare results
  #     N: Send 'error.ls.querytype_not_suported' error
  #   N: Send 'error.ls.no_querytype' error
  # N: Send 'error.ls.query.query_not_found' error

  my $query = "";
  my $queryType = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;
	        
  foreach my $d ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
	      $logger->debug("Matched a Pair");

        $query = extract($m->find("./xquery:subject")->get_node(1));
        if($query) {
          $logger->debug("Query found in metadata, proceeding with QueryRequest.");
          
          $queryType = extract($m->find("./nmwg:eventType")->get_node(1));
          if($queryType) {
            if($queryType eq "service.lookup.xquery" or 
               $queryType eq "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0") {
            
              $logger->debug("QueryType is valid, proceeding with QueryRequest."); 

              # some hacky stuff for right now...
              $query =~ s/&lt;/</g;
              $query =~ s/&gt;/>/g;
              $query =~ s/\s{1}\// collection('CHANGEME')\//g;
        
              my @resultsString = $metadatadb->xQuery($query);   
              my $dataString = "";
              for(my $x = 0; $x <= $#resultsString; $x++) {
                $dataString = $dataString . $resultsString[$x];
  	          }
print "\n\n" , $dataString , "\n\n";
	            $mdId = "resultMetadata.lsKey.".genuid();
	            $dId = "resultData.lsKey.".genuid();
	            if($dataString) {
	              $localContent = $localContent . createMetadata($mdId, $m->getAttribute("id")); 
	              $localContent = $localContent . createData($dId, $mdId, $dataString); 
	            }
	            else {
                $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.query.empty_results");
                $localContent = $localContent . getResultCodeData($dId, $mdId, "Nothing returned for search.");	            
	            }
	            $logger->debug("Adding info to response message.");
  	        }
  	        else {
              $logger->error("Query type not found in metadata, sending error mesasge.");
	            $mdId = "resultMetadata.".genuid();
	            $dId = "resultData.".genuid();      
              $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.querytype_not_suported");
              $localContent = $localContent . getResultCodeData($dId, $mdId, "Given query type is not supported ");
  	        }
          }
          else {
            $logger->error("Query type not found in metadata, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.no_querytype");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "No query type in message");
          }
        }
        else {
          $logger->error("Query not found in metadata, sending error mesasge.");
	        $mdId = "resultMetadata.".genuid();
	        $dId = "resultData.".genuid();      
          $localContent = $localContent . getResultCodeMetadata($mdId, $m->getAttribute("id"), "error.ls.query.query_not_found");
          $localContent = $localContent . getResultCodeData($dId, $mdId, "Query not found in sent metadata.");
        }	      
      }   
    }
  }  
  return $localContent;
}





__END__
=head1 NAME

perfSONAR_PS::LS::LS - 

=head1 DESCRIPTION

...  

=head1 SYNOPSIS

    ...
  

=head1 DETAILS

... 

=head1 API

...

=head1 SEE ALSO

L<perfSONAR_PS::LS::Base>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::XMLDB>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, <zurawski@internet2.edu>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

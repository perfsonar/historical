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
    $self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg); 
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
      
      # take the data/metadata and stick them in the XMLDB.  
      # add a time deally into the time DB (has a range from the conf file for now)
      # return a key
      
      my $response = lsRegisterRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSRegisterResponse", $response);
    }
    elsif($messageType eq "LSDeregisterRequest") {
      $logger->debug("Parsing LSDeregister request.");
 
      # given a key, remove the info it pretains to from the
      #   time and xml databaes.
      # return ? 
            
      my $response = lsDeregisterRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSDeregisterResponse", $response);
    }
    elsif($messageType eq "LSKeepaliveRequest") {
      $logger->debug("Parsing LSKeepalive request.");
      
      # given a key, see if its in, and valid 
      # update the time dealy
      # return ?      
      
      my $response = lsKeepaliveRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSKeepaliveResponse", $response);
    }
    elsif($messageType eq "LSQueryRequest") {
      $logger->debug("Parsing LSQuery request.");
      
      # given a xquery/xpath expression, run it on the database.
      # return results
      
      my $response = lsQueryRequest($self);
      $self->{RESPONSE} = getResultMessage($messageIdReturn, $messageId, "LSQueryResponse", $response);
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      $logger->error($msg);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ls.message.type", $msg);
    }
  }
  else {
    my $msg = "Internal LS error, Metadata Database choice \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    $logger->error($msg); 
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "MetadataKeyResponse", "error.ls", $msg);
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
    $self->{CONF}->{"METADATA_DB_TIME_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

	my $key = "";
  my $mdKey = "";
	my $dataCounter = 0;
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
        $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

        $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
        if($mdKey) {
          $dataCounter = 0;
          $logger->debug("Key found, proceeding with registration update.");
          my $result = $metadatadb->queryByName($mdKey); 
          if($result) {
	          $controldb->updateByName(createControlKey($mdKey, $sec), $mdKey);
	          $logger->debug("Key's time information has been updated.");            

 	          foreach my $d_md ($d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
              my @resultsString = $metadatadb->queryForName("//nmwg:data[" . getXQuery($d_md) . "]");   
              if($#resultsString != -1) {
                for(my $x = 0; $x <= $#resultsString; $x++) {	
                  $metadatadb->remove($resultsString[$x]);
                }        
              }
	            $metadatadb->insertIntoContainer(createData($mdKey."/".$sec."/".$dataCounter, $mdKey, $d_md->toString), $mdKey."/".$sec."/".$dataCounter);
	            $logger->debug("Inserting measurement metadata as 'data'.");

	            $mdId = "resultMetadata.lsKey.".genuid();
	            $dId = "resultData.lsKey.".genuid();
	            $localContent = $localContent . createKey($mdId, $mdKey, "success.ls.register"); 
	            $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been updated with key [".$mdKey."]\" />"); 
	            $logger->debug("Adding info to response message.");

	            $dataCounter++;
	          }	      
          }
          else {
            $logger->error("Key not found in database, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.key_not_found");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
          }
        }
        else {
          $logger->debug("Key not found in message; checking for data in database.");
          
	        if($key ne extract($m->find("./perfsonar:subject/psservice:service/psservice:accessPoint")->get_node(1))) {
	          $dataCounter = 0;
	          $key = extract($m->find("./perfsonar:subject/psservice:service/psservice:accessPoint")->get_node(1));

            if($key) {

	            $logger->debug("Found accessPoint \"".$key."\".");
	          
              my $result = $metadatadb->queryByName($key); 
              if($result) {
                $logger->error("The key seems to be in use already, sending an error mesasge.");

	              $mdId = "resultMetadata.".genuid();
	              $dId = "resultData.".genuid();      
                $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.key_in_use");
                $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$key."\" is already in use.");
              }
              else {
                $logger->debug("New registration info, inserting service metadata and time information.");
              
	              my $service = $m->cloneNode(1);
	              $service->setAttribute("id", $key);
	              $metadatadb->insertIntoContainer($service->toString, $key);
	              $controldb->insertIntoContainer(createControlKey($key, $sec), $key);
	          
	              $mdId = "resultMetadata.lsKey.".genuid();
	              $dId = "resultData.lsKey.".genuid();
	              $localContent = $localContent . createKey($mdId, $key, "success.ls.register"); 
	              $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been registered with key [".$key."]\" />"); 
	              $logger->debug("Adding info to response message.");
	            
	              foreach my $d_md ($d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
	                $metadatadb->insertIntoContainer(createData($key."/".$sec."/".$dataCounter, $key, $d_md->toString), $key."/".$sec."/".$dataCounter);
	                $logger->debug("Inserting measurement metadata as 'data'.");
	                $dataCounter++;
	              }
	            }  
	          }
	          else {
              $logger->error("Key not found in message, sending error mesasge.");
	            $mdId = "resultMetadata.".genuid();
	            $dId = "resultData.".genuid();      
              $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.registration.access_point_missing");
              $localContent = $localContent . getResultCodeData($dId, $mdId, "Cannont register data, accessPoint was not supplied.");
	          }
	        }
	        else {
	          $logger->debug("Linking to previous key.");
	          
	          foreach my $d_md ($d->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
	            $metadatadb->insertIntoContainer(createData($key."/".$sec."/".$dataCounter, $key, $d_md->toString), $key."/".$sec."/".$dataCounter);
	            $logger->debug("Inserting measurement metadata as 'data'.");
	            $dataCounter++;
	          }	          
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
    $self->{CONF}->{"METADATA_DB_TIME_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  my $mdKey = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
        $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

        $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
        if($mdKey) {

          $logger->debug("Key found, proceeding with deregistration.");
          my $result = $metadatadb->queryByName($mdKey); 
          if($result) {

            # get the metadata block, them remove metadata, data that it points to, and
            # the control parameters

	          $mdId = "resultMetadata.lsKey.".genuid();
	          $dId = "resultData.lsKey.".genuid();
	          $localContent = $localContent . createKey($mdId, $mdKey, "success.ls.deregister"); 
	          $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been deregistered for key [".$mdKey."]\" />"); 
	          $logger->debug("Adding info to response message.");

	          $dataCounter++;
	          	      
          }
          else {
            $logger->error("Key not found in database, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.key_not_found");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
          }
        }
        else {
          $logger->debug("Key not found in message; checking for data in database.");

	        $mdId = "resultMetadata.".genuid();
	        $dId = "resultData.".genuid();      
          $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.deregister.key_not_found");
          $localContent = $localContent . getResultCodeData($dId, $mdId, "Key not found in message when trying to deregister data");          
        }
      }
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
    $self->{CONF}->{"METADATA_DB_TIME_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $controldb->openDB; 
  $logger->debug("Databases opened, parsing message.");

  my $mdKey = "";
	my $mdId = "";
	my $dId = "";
	my($sec, $frac) = Time::HiRes::gettimeofday;

  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
        $logger->debug("Matching MD/D pair found: data \"".$d->getAttribute("id")."\" and metadata \"".$m->getAttribute("id")."\".");

        $mdKey = extract($m->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]")->get_node(1));
        if($mdKey) {
          $dataCounter = 0;
          $logger->debug("Key found, proceeding with registration update.");
          my $result = $metadatadb->queryByName($mdKey); 
          if($result) {
	          $controldb->updateByName(createControlKey($mdKey, $sec), $mdKey);
	          $logger->debug("Key's time information has been updated.");            

	          $mdId = "resultMetadata.lsKey.".genuid();
	          $dId = "resultData.lsKey.".genuid();
	          $localContent = $localContent . createKey($mdId, $mdKey, "success.ls.register"); 
	          $localContent = $localContent . createData($dId, $mdId, "<nmwg:datum value=\"Data has been updated with key [".$mdKey."]\" />"); 
	          $logger->debug("Adding info to response message.");
          }
          else {
            $logger->error("Key not found in database, sending error mesasge.");
	          $mdId = "resultMetadata.".genuid();
	          $dId = "resultData.".genuid();      
            $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.key_not_found");
            $localContent = $localContent . getResultCodeData($dId, $mdId, "Sent key \"".$mdKey."\" was not registered.");
          }
        }
        else {
          $logger->debug("Key not found in message; checking for data in database.");

	        $mdId = "resultMetadata.".genuid();
	        $dId = "resultData.".genuid();      
          $localContent = $localContent . getResultCodeMetadata.($mdId, "error.ls.keepalive.key_not_found");
          $localContent = $localContent . getResultCodeData($dId, $mdId, "Key not found in message when trying to keepalive data");          
        }
      }
    }
  }
  return $localContent;
}



sub lsQueryRequest {
  my($self) = @_; 
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $localContent = "<nmwg:metadata>success</nmwg:metadata>";
  
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
	$metadatadb->openDB; 
	      
  my $timedb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"METADATA_DB_NAME"}, 
    $self->{CONF}->{"METADATA_DB_TIME_FILE"},
    \%{$self->{NAMESPACES}}
  );	  
  $timedb->openDB; 
	        
  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
	      $logger->debug("Matched a Pair");
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

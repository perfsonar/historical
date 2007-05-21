#!/usr/bin/perl

package perfSONAR_PS::MA::SNMP;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

use threads;

our @ISA = qw(perfSONAR_PS::MA::Base);

sub receive {
  my($self) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";   
  $self->{FUNCTION} = "\"receive\"";   
  print $self->{FILENAME}.":\tAccepting calls in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});  

  my $readValue = $self->{LISTENER}->acceptCall;
  if($readValue == 1) {
    $self->{REQUESTDOM} = $self->{LISTENER}->getRequestDOM();
    print $self->{FILENAME}.":\tReceived request \"".$self->{REQUESTDOM}->toString."\" in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});    
    my $handleThread = threads->new(\&handleRequest, $self);
    if(!defined $handleThread) {
      print "Thread creation has failed...exiting...\n";
      exit(1);
    }
    $self->{RESPONSE} = $handleThread->join();
  }
  elsif($readValue == 2) {
    print $self->{FILENAME}.":\tReceived 'shadow' request from below in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});    
    $self->{RESPONSE} = $self->{LISTENER}->getResponse();
  }
  else {
    my $msg = "Sent Request has was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
    $self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg); 
  }
  undef $self->{REQUEST};
  undef $self->{REQUESTDOM};  
  return;
}


sub handleRequest {
  my($self) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";
  $self->{FUNCTION} = "\"handleRequest\"";   
  undef $self->{RESPONSE};

  reMap($self, $self->{REQUESTDOM}->getDocumentElement);

  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file" or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {

    my $messageId = $self->{REQUESTDOM}->getDocumentElement->getAttribute("id");
    my $messageType = $self->{REQUESTDOM}->getDocumentElement->getAttribute("type");    
    my $messageIdReturn = genuid();    

    if($messageType eq "MetadataKeyRequest") {
      handleKeyRequest($self, $messageIdReturn, $messageId, $self->{CONF}->{"METADATA_DB_TYPE"});
    }
    elsif($messageType eq "SetupDataRequest") {
      handleDataRequest($self, $messageIdReturn, $messageId, $self->{CONF}->{"METADATA_DB_TYPE"}); 
    }
    elsif($messageType eq "MeasurementArchiveStoreRequest") {
      my $msg = "Message type \"MeasurementArchiveStoreRequest\" is not yet supported";
      perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "MeasurementArchiveStoreResponse", "error.ma.message.type", $msg);
    }
    else {
      my $msg = "Message type \"".$messageType."\" is not yet supported";
      perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, $messageType."Response", "error.ma.message.type", $msg);
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not supported";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);   
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "MetadataKeyResponse", "error.mp.snmp", $msg);
  }

  return $self->{RESPONSE};
}


sub handleKeyRequest {
  my($self, $messageId, $messageIdRef, $type) = @_; 
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";
  $self->{FUNCTION} = "\"handleKeyRequest\""; 

  my $localContent = "";
  foreach my $d ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) { 
      
        my $metadatadb;
        if($type eq "file") {
          $metadatadb = new perfSONAR_PS::DB::File(
            $self->{CONF}->{"LOGFILE"},
            $self->{CONF}->{"METADATA_DB_FILE"},
            $self->{CONF}->{"DEBUG"}
          );        
	      }
	      elsif($type eq "xmldb") {
	        $metadatadb = new perfSONAR_PS::DB::XMLDB(
            $self->{CONF}->{"LOGFILE"},
            $self->{CONF}->{"METADATA_DB_NAME"}, 
            $self->{CONF}->{"METADATA_DB_FILE"},
            \%{$self->{NAMESPACES}},
	          $self->{CONF}->{"DEBUG"}
          );	  
	      }
	      $metadatadb->openDB; 
	      my $queryString = "//nmwg:metadata[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 0) . "]";
        print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	      @resultsString = $metadatadb->query($queryString);	
	
	      if($#resultsString != -1) {
	        for(my $x = 0; $x <= $#resultsString; $x++) {
            my $parser = XML::LibXML->new();
            $doc = $parser->parse_string($resultsString[$x]);  
            my $mdset = $doc->find("//nmwg:metadata");
            my $md = $mdset->get_node(1); 

            print "DEBUG:\tMetadata \"".$md->toString()."\" created.\n" if($self->{CONF}->{"DEBUG"});
            $localContent = $localContent . $md->toString;  
            $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]";  
            
            print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	          my @dataResultsString = $metadatadb->query($queryString);	  
	      	    
	          if($#dataResultsString != -1) {    			  
              for(my $y = 0; $y <= $#dataResultsString; $y++) {
		            print "DEBUG:\tData \"".$dataResultsString[$y]."\" created.\n" if($self->{CONF}->{"DEBUG"});
                $localContent = $localContent . $dataResultsString[$y]; 
                $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "MetadataKeyResponse", $localContent);
              }       
	          }
            else {
	            my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
              perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
              $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "MetadataKeyResponse", "error.mp.snmp", $msg);
            }  
	        }
	      }
	      else {
	        my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
          perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
          $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "MetadataKeyResponse", "error.mp.snmp", $msg);	     
	      }		  	
      }   
    }
  }
}


sub handleDataRequest {
  my($self, $messageId, $messageIdRef, $type) = @_; 
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";
  $self->{FUNCTION} = "\"handleDataRequest\""; 
  
  my $localContent = "";
  foreach my $d ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{REQUESTDOM}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) { 
      
        my $metadatadb;
        if($type eq "file") {
          $metadatadb = new perfSONAR_PS::DB::File(
            $self->{CONF}->{"LOGFILE"},
            $self->{CONF}->{"METADATA_DB_FILE"},
            $self->{CONF}->{"DEBUG"}
          );     
        }
        elsif($type eq "xmldb") {
	        $metadatadb = new perfSONAR_PS::DB::XMLDB(
            $self->{CONF}->{"LOGFILE"},
            $self->{CONF}->{"METADATA_DB_NAME"}, 
            $self->{CONF}->{"METADATA_DB_FILE"},
            \%{$self->{NAMESPACES}},
	          $self->{CONF}->{"DEBUG"}
          );	  
        }
        $metadatadb->openDB;  
        
        if($m->find("//nmwg:metadata/nmwg:key")) {
	        my $queryString = "//nmwg:data[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 0) . "]";
          print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
          
          getTime(\%{$self}, $m->getAttribute("id"));
          
          $localContent = $localContent . $m->toString();
          
	        my @resultsString = $metadatadb->query($queryString);   
	        if($#resultsString != -1) {
            for(my $x = 0; $x <= $#resultsString; $x++) {	
              handleData($self, $m->getAttribute("id"), $resultsString[$x], $localContent);
            }        
          }
	        else {
	          my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
            perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
            $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);	                   
	        }                  
        }
        else {
	        my $queryString = "//nmwg:metadata[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 1) . "]";
          print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	        my @resultsString = $metadatadb->query($queryString);   
	
	        if($#resultsString != -1) {
            for(my $x = 0; $x <= $#resultsString; $x++) {	
              my $parser = XML::LibXML->new();
              $doc = $parser->parse_string($resultsString[$x]);  
              my $mdset = $doc->find("//nmwg:metadata");
              my $md = $mdset->get_node(1); 
  
              $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]";
              print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	            my @dataResultsString = $metadatadb->query($queryString);
		
	            if($#dataResultsString != -1) { 
                $localContent = $localContent . $m->toString;                
                for(my $y = 0; $y <= $#dataResultsString; $y++) {
		              handleData($self, $m->getAttribute("id"), $dataResultsString[$y], $localContent);
                }   	    	  
	            }
              else {
	              my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
                perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
                $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);
              } 
	          }
	        }
	        else {
	          my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
            perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
            $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);	                   
	        }
        }		
      }   
    }
  }
}


sub handleData {
  my($self, $id, $dataString, $localContent) = @_;
  
  print "DEBUG:\tData \"".$dataString."\" created.\n" if($self->{CONF}->{"DEBUG"});		    
  undef $self->{RESULTS};		    

  my $parser = XML::LibXML->new();
  $self->{RESULTS} = $parser->parse_string($dataString);   
  my $dt = $self->{RESULTS}->find("//nmwg:data")->get_node(1);
  		 		
  my $type = extract($dt->find("./nmwg:key//nmwg:parameter[\@name=\"type\"]")->get_node(1));
                  
  if($type eq "rrd") {
    $localContent = $localContent . retrieveRRD($self, $dt, $id);		       
    $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "SetupDataResponse", $localContent);		    
  }
  elsif($type eq "sqlite") {
    $localContent = $localContent . retrieveSQL($self, $dt, $id);		  		       
    $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "SetupDataResponse", $localContent);	
  }		
  elsif(($type eq "mysql") or ($type eq "xmldb") or ($type eq "file")){
    my $msg = "Database \"".$type."\" is not yet supported";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);
  }
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.mp.snmp", $msg);
  }
  return;
}


sub retrieveSQL {
  my($self, $d, $mid) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";
  $self->{FUNCTION} = "\"retrieveSQL\""; 
  my $responseString = "";

  my @dbSchema = ("id", "time", "value", "eventtype", "misc");

  my $file = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"file\"]")->get_node(1));
  my $table = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"table\"]")->get_node(1));
    
  my $id = genuid();
  my $datadb = new perfSONAR_PS::DB::SQL(
    $self->{CONF}->{"LOGFILE"},
    "DBI:SQLite:dbname=".$file,
    "", 
    "",
    \@dbSchema,
    $self->{CONF}->{"DEBUG"}
  );
		      
  $datadb->openDB();
  
  my $query = "";
  if($self->{TIME}->{"START"} or $self->{TIME}->{"END"}) {
    $query = "select * from ".$table." where id=\"".$d->getAttribute("metadataIdRef")."\" and";
    my $queryCount = 0;
    if($self->{TIME}->{"START"}) {
      $query = $query." time > ".$self->{TIME}->{"START"};
      $queryCount++;
    }
    if($self->{TIME}->{"END"}) {
      if($queryCount) {
        $query = $query." and time < ".$self->{TIME}->{"END"}.";";
      }
      else {
        $query = $query." time < ".$self->{TIME}->{"END"}.";";
      }
    }
  }
  else {
    $query = "select * from ".$table.";"
  }  

  print "DEBUG:\tQuery \"".$query."\" created.\n" if($self->{CONF}->{"DEBUG"});  
  
  my $result = $datadb->query($query);
  if($#{$result} == -1) {
    my $msg = "Query \"".$query."\" returned 0 results";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
    $responseString = $responseString . getResultCodeData($id, $mid, $msg); 
  }   
  else { 
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
  }  

  $datadb->closeDB();	  
  return $responseString;
}


sub retrieveRRD {
  my($self, $d, $mid) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::SNMP\"";
  $self->{FUNCTION} = "\"retrieveRRD\"";   
  my $responseString = "";

  my $file = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"file\"]")->get_node(1));

  my $id = genuid();
  my $datadb = new perfSONAR_PS::DB::RRD(
    $self->{CONF}->{"LOGFILE"},
    $self->{CONF}->{"RRDTOOL"}, 
    $file,
    "",
    1,
    $self->{CONF}->{"DEBUG"}
  );
		      
  $datadb->openDB();


  my $oldStart = $self->{TIME}->{"START"};
  my $oldEnd = $self->{TIME}->{"END"};
  if($self->{TIME}->{"RESOLUTION"}) {
    if($self->{TIME}->{"START"} % $self->{TIME}->{"RESOLUTION"}){
      $self->{TIME}->{"START"} = 
        int($self->{TIME}->{"START"}/$self->{TIME}->{"RESOLUTION"} + 1)*$self->{TIME}->{"RESOLUTION"};
    }
     
    if($self->{TIME}->{"END"} % $self->{TIME}->{"RESOLUTION"}){
      $self->{TIME}->{"END"} = 
        int($self->{TIME}->{"END"}/$self->{TIME}->{"RESOLUTION"})*$self->{TIME}->{"RESOLUTION"};
    }
  }
  
  if($self->{TIME}->{"START"} > $self->{TIME}->{"END"}) {
    my $msg = "Query error; There are no values for resolution \"".$self->{TIME}->{"RESOLUTION"}.
      "\" in range \"".$oldStart."\" to \"".$oldEnd."\".";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
    $responseString = $responseString . getResultCodeData($id, $mid, $msg);
  }
  else {

    if(!$self->{TIME}->{"CF"}) {
      $self->{TIME}->{"CF"} = "AVERAGE";
    }
  
    my %rrd_result = $datadb->query(
      $self->{TIME}->{"CF"}, 
      $self->{TIME}->{"RESOLUTION"}, 
      $self->{TIME}->{"START"}, 
      $self->{TIME}->{"END"}
    );
 
    if($datadb->getErrorMessage()) {
      my $msg = "Query error \"".$datadb->getErrorMessage()."\"; query returned \"".$rrd_result{ANSWER}."\"";
      perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
      $responseString = $responseString . getResultCodeData($id, $mid, $msg); 
    }
    else {
      my @keys = keys(%rrd_result);
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
    }
    $datadb->closeDB();
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
    $conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";
    $conf{"DEBUG"} = 1;
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $ma = perfSONAR_PS::MA::SNMP->new(\%conf, \%ns, "");

    # or
    # $ma = perfSONAR_PS::MA::SNMP->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);    
    # $ma->setStore($store);   
        
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

=head2 new(\%conf, \%ns, $store)

The arguments represent a 'conf' hash from the calling MA, a hash of namespaces, and a LibXML DOM
object for the store file.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 setStore($store) 

(Re-)Sets the value for the 'store' object, which is really just a XML::LibXML::Document

=head2 init()

Initialize transportation medium.

=head2 receive()

Grabs message from transport object to begin processing.

=head2 handleRequest()

Interact with the metadata and data databases (information will be collected from 
the conf hash as well as the backend metadata storage) to create a response for a given 
request.  This response could be the correct data, or it could be a descriptive error 
message if something happened to go wrong. 

=head2 handleMetadataKeyRequest($self, $messageId, $messageIdRef, $type)

Processes the MetadataKeyRequest message, which presents some loose metadata
and requests a data key.

=head2 handleDataRequest($self, $messageId, $messageIdRef, $type)
  
Processes the SetupDataRequest message (with and without a key) which presents
some metadata credentials, and returns a list of data.  

=head2 handleData($self, $id, $dataString, $localContent)

Helper function to extract data from the backed storage.

=head2 retrieveRRD($did)

The data is extracted from the backed storage (in this case RRD). 

=head2 retrieveSQL($did)	

The data is extracted from the backed storage (in this case SQL). 

=head2 respond()

Send message stored in $self->{RESPONSE}.

=head2 error($self, $msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, 
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

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

#!/usr/bin/perl

package perfSONAR_PS::MA::Ping;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MA::Base);


sub receive {
  my($self) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::Ping\"";   
  $self->{FUNCTION} = "\"receive\"";   
  print $self->{FILENAME}.":\tAccepting calls in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});  
  if($self->{LISTENER}->acceptCall == 1) {
    $self->{REQUEST} = $self->{LISTENER}->getRequest;
    print $self->{FILENAME}.":\tReceived request \"".$self->{REQUEST}."\" in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});
    $self->{RESPONSE} = handleRequest($self);
  }
  else {
    my $msg = "Sent Request has was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
    $self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg); 
  }
  undef $self->{REQUEST};
  return;
}


sub handleRequest {
  my($self) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::Ping\"";
  $self->{FUNCTION} = "\"handleRequest\"";   
  undef $self->{RESPONSE};

  my $xp = XML::XPath->new( xml => $self->{REQUEST} );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  my $nodeset = $xp->find('//nmwg:message');

  if($nodeset->size() < 1) {
    my $msg = "Message element not found within request";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
    $self->{RESPONSE} = getResultCodeMessage(genuid(), "", "response", "error.mp.snmp", $msg);  
  }
  elsif($nodeset->size() == 1) {
    my @messages = $nodeset->get_nodelist;
    my $messageId = "";
    my $messageType = "";    
    my $messageIdReturn = genuid();    
    foreach my $attr ($messages[0]->getAttributes) {
      if($attr->getLocalName eq "id") {
        $messageId = $attr->getNodeValue;
      }
      elsif($attr->getLocalName eq "type") {
        $messageType = $attr->getNodeValue;
      }
    }
     
    parse($self->{REQUEST}, \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, "//nmwg:metadata");
    chainMetadata(\%{$self->{METADATA}});
    parse($self->{REQUEST}, \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, "//nmwg:data");   
            
    foreach my $m (keys %{$self->{METADATA}}) {
      if(countRefs($m, \%{$self->{DATA}}, "nmwg:data-metadataIdRef") == 0) {
        delete $self->{METADATA}->{$m};
      }
    }

    if($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql" or 
       $self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite" or 
       $self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {      
      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not yet supported";
      perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    }  
    elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
      handleXMLDB($self, $messageIdReturn, $messageId);
    } 
    else {
      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not yet supported";
      perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);   
      $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    } 
  }
  else {
    my $msg = "Too many message elements found within request";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__); 
    $self->{RESPONSE} = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
  }
  return $self->{RESPONSE};
}


sub handleFile {
  my($self, $messageId, $messageIdRef) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::Ping\"";
  $self->{FUNCTION} = "\"handleFile\""; 
  
  # fill in later
        
  return;  
}


sub handleXMLDB {
  my($self, $messageId, $messageIdRef) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::Ping\"";
  $self->{FUNCTION} = "\"handleXMLDB\"";   

  my $localContent = "";
  foreach my $d (keys %{$self->{DATA}}) {
    foreach my $m (keys %{$self->{METADATA}}) {  
      if($self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"} eq $m) { 

	my $metadatadb = new perfSONAR_PS::DB::XMLDB(
          $self->{CONF}->{"LOGFILE"},
          $self->{CONF}->{"METADATA_DB_NAME"}, 
          $self->{CONF}->{"METADATA_DB_FILE"},
          \%{$self->{NAMESPACES}},
	  $self->{CONF}->{"DEBUG"}
        );	  
        $metadatadb->openDB;              

	my $queryString = "/nmwg:metadata[" . getMetadatXQuery(\%{$self->{METADATA}}, \%{$self->{TIME}}, $m) . "]/\@id";
        print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	my @resultsString = $metadatadb->query($queryString);   
	    
	if($#resultsString != -1) {    
          for(my $x = 0; $x <= $#resultsString; $x++) {	
            $resultsString[$x] =~ s/\{\}id=//;
            $resultsString[$x] =~ s/\"//g;
            $resultsString[$x] =~ s/\n//;	    
	        
            $queryString = "/nmwg:data[\@metadataIdRef='".$resultsString[$x]."']";
            print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
	    my @dataResultsString = $metadatadb->query($queryString);
		
	    if($#dataResultsString != -1) {    
		
              $queryString = "/nmwg:metadata[\@id='".$resultsString[$x]."']";
              print "DEBUG:\tQuery \"".$queryString."\" created.\n" if($self->{CONF}->{"DEBUG"});
              my @metadataResultsString = $metadatadb->query($queryString);		  

              $localContent = $localContent . $metadataResultsString[0];  
              for(my $y = 0; $y <= $#dataResultsString; $y++) {
		    
		print "DEBUG:\tData \"".$dataResultsString[$x]."\" created.\n" if($self->{CONF}->{"DEBUG"});
		    
		undef $self->{RESULTS};		    
		parse($dataResultsString[$x], \%{$self->{RESULTS}}, \%{$self->{NAMESPACES}}, "//nmwg:data");		  
		@dataIds = keys(%{$self->{RESULTS}});
		    
		if($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") {
		  $localContent = $localContent . retrieveSQL($self, $dataIds[0]);
		  $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "response", $localContent);		    
		}
		elsif(($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql") or 
		      ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") or 
	              ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "xmldb") or 
		      ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "file")){
		  my $msg = "Database \"".$self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}.
		    "\" is not yet supported";
		  perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
                  $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "response", "error.mp.snmp", $msg);
		}
		else {
		  my $msg = "Database \"".$self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}.
		    "\" is not yet supported";
		  perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
                  $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "response", "error.mp.snmp", $msg);
		}
              }
	    }
            else {
	      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
              perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
              $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "response", "error.mp.snmp", $msg);
            }		    
	  }	  
	}
        else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
          perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);  
          $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "response", "error.mp.snmp", $msg);
        }
      }   
    }
  }

  return;
}


sub retrieveSQL {
  my($self, $did) = @_;
  $self->{FILENAME} = "\"perfSONAR_PS::MA::Ping\"";
  $self->{FUNCTION} = "\"retrieveSQL\""; 
  my $responseString = "";

  my @dbSchema = ("id", "time", "value", "eventtype", "misc");

  my $id = genuid();
  my $datadb = new perfSONAR_PS::DB::SQL(
    $self->{CONF}->{"LOGFILE"},
    "DBI:SQLite:dbname=".$self->{RESULTS}->{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
    "", 
    "",
    \@dbSchema,
    $self->{CONF}->{"DEBUG"}
  );
		      
  $datadb->openDB();

  my $query = "";
  if($self->{TIME}->{"START"} or $self->{TIME}->{"END"}) {
    $query = "select * from ".$self->{RESULTS}->{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"}." where";
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
    $query = "select * from ".$self->{RESULTS}->{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"}.";"
  }

  print "DEBUG:\tQuery \"".$query."\" created.\n" if($self->{CONF}->{"DEBUG"});

  my $result = $datadb->query($query);
  if($#{$result} == -1) {
    my $msg = "Query \"".$query."\" returned 0 results";
    perfSONAR_PS::MA::Base::error($self, $msg, __LINE__);
    $responseString = $responseString . getResultCodeData($id, $self->{RESULTS}->{$did}->{"nmwg:data-metadataIdRef"}, $msg); 
  }   
  else { 
    $responseString = $responseString . "  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$self->{RESULTS}->{$did}->{"nmwg:data-metadataIdRef"}."\">\n";
    for(my $a = 0; $a <= $#{$result}; $a++) {    
      $responseString = $responseString . "    <ping:datum";
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


1;


__END__
=head1 NAME

perfSONAR_PS::MA::Ping - A module forthe Ping MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::Ping;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Ping/xmldb";
    $conf{"METADATA_DB_FILE"} = "pingstore.dbxml";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );

    my $ma = perfSONAR_PS::MA::Ping->new(\%conf, \%ns);
    
    # or
    # $ma = perfSONAR_PS::MA::Ping->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);
    # $ma->setMetadata(\%metadata);
    # $ma->setData(\%data);
         
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

=head2 new(\%conf)

The only argument represents the 'conf' hash from the calling MA.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 setMetadata(\%metadata)

(Re-)Sets the value for the 'metadata' hash. 

=head2 setData(\%data)

(Re-)Sets the value for the 'data' hash. 

=head2 init()

Initialize transportation medium.

=head2 receive()

Grabs message from transport object to begin processing.

=head2 handleRequest()

Interact with the metadata and data databases (information will be collected from 
the conf hash as well as the backend metadata storage) to create a response for a given 
request.  This response could be the correct data, or it could be a descriptive error 
message if something happened to go wrong. 

=head2 handleFile($messageId, $messageIdRef)
  
Perform the lookup and creation of a message baesd on the backend storage
being a 'file'.  
  
=head2 handleXMLDB($messageId, $messageIdRef)

Perform the lookup and creation of a message baesd on the backend storage
being an 'XMLDB'.  
 
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
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::SQL>

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

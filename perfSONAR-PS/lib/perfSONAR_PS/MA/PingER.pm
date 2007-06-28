package perfSONAR_PS::MA::PingER;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::MA::PingER::DB_Config::DBLoader;

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use POSIX qw(strftime);
  
our @ISA = qw(perfSONAR_PS::MA::Base);




sub init {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::PingER");

	$self->SUPER::init;
        my  $db_name = $self->{CONF}->{"SQL_DB_NAME"};
	my  $db_driver = $self->{CONF}->{"SQL_DB_DRIVER"};
	 
	if (!$db_name ) {
		$logger->error("No database specified");
		return -1;
	}

	if (!$db_driver  ) {
		$logger->error("No database type specified");
		return -1;
	}
	
       $self->{CONF}->{"SQL_DB_NAME"}  = "dbname=$db_name"  if( $db_driver =~ /SQLite|Pg/); 
  
       
	 
	return 0;
}

sub DESTROY {
    my  $self  = shift;
    $self->{DBH}->disconnect if   $self->{DBH};
}

sub receive {
	my($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::PingER");

	my $readValue = $self->{LISTENER}->acceptCall;
	if($readValue == 0) {
		$logger->debug("Received 'shadow' request from below; no action required.");
		$self->{RESPONSE} = $self->{LISTENER}->getResponse();
	} elsif($readValue == 1) {
		$logger->debug("Received request to act on.");
		$self->handleRequest;
	} else {
		my $msg = "Sent Request was not expected: ".$self->{LISTENER}->{REQUEST}->uri.", ".$self->{LISTENER}->{REQUEST}->method.", ".$self->{LISTENER}->{REQUEST}->headers->{"soapaction"}.".";
		$logger->error($msg);
		$self->{RESPONSE} = getResultCodeMessage("", "", "response", "error.transport.soap", $msg);
	}
	return;
}

 sub handleRequest {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  delete $self->{RESPONSE};

  $self->{REQUESTNAMESPACES} = $self->{LISTENER}->getRequestNamespaces();
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file" or 
     $self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
    my $messageId = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("id");
    my $messageType = $self->{LISTENER}->getRequestDOM()->getDocumentElement->getAttribute("type");    
    my $messageIdReturn = genuid();    

    if($messageType eq "MetadataKeyRequest" or 
       $messageType eq "SetupDataRequest" or 
       $messageType eq "MeasurementRequest") {
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
  my $logger = get_logger("perfSONAR_PS::MA::PingER");

  my $localContent = "";
  foreach my $d ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {  
    foreach my $m ($self->{LISTENER}->getRequestDOM()->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {  
      if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) { 
      
        if($type eq "MeasurementRequest") {
          $localContent = measurementRequest($self, $metadatadb, $m, $d, $localContent, $messageId, $messageIdRef);  
        }
        else {
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
  }  
  return;
}
 
 sub measurementRequest {
  my($self, $metadatadb, $m, $d, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  
  $localContent = $localContent. $m->toString();

  my %conf = ();  
  $conf{"METADATA_DB_TYPE"} = "string";
  $conf{"METADATA_DB_NAME"} = "";
  $conf{"METADATA_DB_FILE"} = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}."<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}."            xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}."	           xmlns:ping=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\">\n\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}.$m->toString()."\n\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}.$d->toString()."\n\n";
  $conf{"METADATA_DB_FILE"} = $conf{"METADATA_DB_FILE"}."</nmwg:store>\n";
  $conf{"PING"} = $self->{CONF}->{"PING"};

  $mp = new perfSONAR_PS::MP::PingER(\%conf, \%{$self->{"NAMESPACES"}}, "");
  $mp->parseMetadata;
  $mp->prepareCollector;  

  $localContent = $localContent . "\n  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";

  foreach my $p (keys %{$mp->{AGENT}}) {
    $logger->debug("Collecting for '" , $p , "'.");
    $mp->{AGENT}->{$p}->collect;

    my $results = $mp->{AGENT}->{$d->getAttribute("metadataIdRef")}->getResults;
    $localContent = $localContent . "    <pinger:datum ";
    foreach my $r (sort keys %{$results}) {
      foreach my $r2 (sort keys %{$results->{$r}}) {
        if($r2 eq "time") {
          $localContent = $localContent . "value=\"" . $results->{$r}->{$r2} . "\" ";
        }
        else {
          $localContent = $localContent . $r2 . "=\"" . $results->{$r}->{$r2} . "\" ";
        }
      }
    }
    $localContent = $localContent . "/>\n";
  }
  $localContent = $localContent . "  </nmwg:data>\n";
  
  $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "MeasurementResponse", $localContent); 
  return;
}


sub setupDataKeyRequest {
  my($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  
	my $queryString = "//nmwg:data[" . getMetadatXQuery(\%{$self}, $m->getAttribute("id"), 0) . "]";
  $logger->debug("Query \"".$queryString."\" created."); 


# XXX jason: [6/4/07]
# Adding the 'cooked' md to the request        
#  $localContent = $localContent . $m->toString();
   
   
# XXX jason: [6/4/07]
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
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.ma.pinger", $msg);	                   
	}  
  return;
}

sub setupDataRequest {
  my($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  
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


# XXX jason: [6/4/07]
# Adding the 'cooked' md to the request        
#       $localContent = $localContent . $md->toString();

     
# XXX jason: [6/4/07]
# Adding the 'original' md to the request
        my $xp = XML::XPath->new( xml => $self->{LISTENER}->getRequest );
        my $nodeset = $xp->find("//nmwg:message/nmwg:metadata");
        if($nodeset->size() <= 0) {
        }
        else {  
          foreach my $node ($nodeset->get_nodelist) {
            $localContent .= XML::XPath::XMLParser::as_string($node);
          }
        }
        foreach my $dt (@dataResultsString) {
	   $localContent .=  handleData($self, $m->getAttribute("id"), $dt, $messageId, $messageIdRef);
        } 
        $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "SetupDataResponse", $localContent);  	    	  
	    }
      else {
	      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
        $logger->error($msg);  
        $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.ma.pinger", $msg);
      } 
	  }
	}
	else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg);
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "SetupDataResponse", "error.ma.pinger", $msg);	                   
	}  
  return;
}


sub handleData {
  my($self, $id, $dataString, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  
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
  elsif($type =~ /^sqlite|mysql|pg/) {
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
  my($self, $d, $mid, $type) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::PingER");
  my $responseString = ''; 
  my $responseHeader ="\n  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$mid."\">\n";
  my $responseFooter =  "  </nmwg:data>\n";
  my %db2xml = (
                 'pkgs_rcvd' =>   undef ,
		 'ttl' =>  'ttl',
		 'numBytes' =>   'numBytes' ,
		 'min_time'  => 'minRtt'  ,
                 'avrg_time' =>  'meanRtt',
                 'max_time'  => 'maxRtt' ,
		 'medianRtt'  => 'medianRtt',
                 'timestamp' =>   'timestamp',
	         'iqr_delay' => 'iqrIpd',
	         'lossPercent' => 'lossPercent',
		 'min_delay' => 'minIpd',
		 'ipdv' => 'meanIpd', 
		 'max_delay'  => 'maxIpd',
		 'clp' => 'clp',
		 'pkgs_sent' =>  'count',
		 'pkgs_size' =>  'packetSize',
		 
		 'protocol' => undef, 
		 'interval' => 'interval',
		 'outOfOrder' =>  'outOfOrder' , ## depending on Db engine its going to be
		 'dupl' =>   'duplicates',
		);
  my $file = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"file\"]")->get_node(1));
  my $table = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"table\"]")->get_node(1));
   
  #
  # dbname could be  <DBNAME>:<PORT> or for SQLite - dbname=<FILENAME> , so its driver + storage type
  #  $db_driver could be mysql, SQLite , oracle and so on
  #
  
  ## if there is no 
  if (!$db_name && !$file) {
        $db_name = $self->{CONF}->{SQL_DB_NAME};
        $db_driver = $self->{CONF}->{SQL_DB_DRIVER};
  }
  $db_driver=  'SQLite' if( $db_driver =~ /^sqlite$/i);
  $db_driver=  'Pg' if( $db_driver =~ /^pg$/i);
  $db_name = "dbname=$db_name"  if( $db_driver =~ /SQLite|Pg/); 
  my $query = "";   
  my  $datadb =  perfSONAR_PS::MA::PingER::DB_Config::DBLoader->connect("DBI:$db_driver:$db_name",
                              $self->{CONF}->{SQL_DB_USER},$self->{CONF}->{SQL_DB_PASS}, 
			      {AutoCommit => 1, RaiseError => 1});
   
  my $metaID = $d->getAttribute("metadataIdRef");
  my @tables = _getTables($self->{TIME}->{"START"}, $self->{TIME}->{"END"});
  
  foreach my $table (@tables) {
     my @resultset =  $datadb->resultset($table)->search({metaID => $metaID, timestamp => {'-between' => [$self->{TIME}->{"START"}, $self->{TIME}->{"END"}]}});     
     foreach my  $result (@$resultset) {
      $responseString .=   "    <pinger:datum";
       foreach my $el  (keys %db2xml) {
         if($db2xml{$el} && $result->has_column_loaded($el))  {
            $responseString .=  " ". $db2xml{$el}."=\"".$result->get_column($el)."\"";
         }
       }
       $responseString .=  " />\n";
    } 
  }			      
  
  my $id = genuid();
  $datadb->disconnect(); 
     
  if(!$responseString) {
    my $msg = "Query \"".$query."\" returned 0 results";
    $logger->error($msg);
    $responseString  = getResultCodeData($id, $mid, $msg); 
  }   
  else { 
    $logger->debug("Data found.");
    $logger->debug("Data block created.");
    $responseString  = $responseHeader . $responseString  . $responseFooter; 
  }  
  return $responseString;
}

sub _getTables($$) {
    my($stime, $etime) = @_;
    my %list = ();
    my $One_DAY_inSec = 86400;
    $stime =  $stime?$stime:(14*$One_DAY_inSec);  ## only allow 2 weeks of data by default
    $etime =  $etime?$etime: gmtime(time); ## now in UTC
    for(my $i = $stime; $i<=$etime; $i+= 86400) {
       $list{(strftime "pairs_%Y%m", gmtime($i))} = 1; 
    }
    return (keys %list);
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::PingER - A module that provides methods for the PingER MA.  

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::PingER;
    use perfSONAR_PS::XML::Namespace;
    use perfSONAR_PS::SimpleConfig;
  
    my $ns_obj =  perfSONAR_PS::XML::Namespace->new();
    my %ns = ();
    foreach my $ns_key (qw/nmwg  nmwgt pinger  nmtl3 select/) {
       $ns{$ns_key} = $ns->getNsByKey($ns_key);
    } 
    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/netadmin/LHCOPN/perfSONAR-PS/MP/Ping/xmldb";
    $conf{"METADATA_DB_FILE"} = "pingerstore.dbxml";
    $conf{"SQL_DB_USER"} = "pinger";
    $conf{"SQL_DB_PASS"} = "pinger";
    $conf{"SQL_DB_DB"} = "pinger_pairs";
    
    my $pingerMA_conf = perfSONAR_PS::SimpleConfig->new( -FILE => 'pingerMA.conf', -PROMPTS => \%CONF_PROMPTS, -DIALOG => '1');
    my $config_data = $pingerMA_conf->parse(); 
    $pingerMA_conf->store;
    %conf = %{$pingerMA_conf->getNormalizedData()}; 
    my $ma = perfSONAR_PS::MA::PingER->new( \%con, \%ns);

    # or
    # $self = perfSONAR_PS::MA::PingER->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);      
        
    $self->init;  
    while(1) {
      $self->receive;
      $self->respond;
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

=head2 retrieveSQL($did)	

The data is extracted from the backed storage (in this case SQL). 

=head2 retrieveRRD($did)

The data is extracted from the backed storage (in this case RRD). 

=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::XML::Namespace>, L<perfSONAR_PS::SimpleConfig>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: PingER.pm 227 2007-06-13 12:25:52Z zurawski $

=head1 AUTHOR

Maxim Grigoriev, E<lt>maxim@fnal.govE<gt>
Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

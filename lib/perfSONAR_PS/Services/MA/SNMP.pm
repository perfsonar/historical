package perfSONAR_PS::Services::MA::SNMP;

use base 'perfSONAR_PS::Services::Base';

our $VERSION = 0.02;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use Module::Load;

use perfSONAR_PS::Error_compat qw/:try/;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

sub init($$);
sub needLS($);
sub registerLS($);
sub handleEvent($$$$$$$$$);
sub maMetadataKeyRequest($$$$$);
sub metadataKeyRetrieveKey($$$$$$$);
sub metadataKeyRetrieveMetadataData($$$$$$$);
sub maSetupDataRequest($$$$$);
sub setupDataRetrieveMetadataData($$$$$$);
sub setupDataRetrieveKey($$$$$$$$);
sub handleData($$$$$$);
sub retrieveSQL($$$$$$);
sub retrieveRRD($$$$$$);

sub init($$) {
  my ($self, $handler) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  # values that are deal breakers...

  if(!defined $self->{CONF}->{"snmp"}->{"metadata_db_type"} or
     $self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "") {
    $logger->error("Value for 'metadata_db_type' is not set.");
    return -1;
  }

  if($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file") {
    if(!defined $self->{CONF}->{"snmp"}->{"metadata_db_file"} or
       $self->{CONF}->{"snmp"}->{"metadata_db_file"} eq "") {
      $logger->error("Value for 'metadata_db_file' is not set.");
      return -1;
    }
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"snmp"}->{"metadata_db_file"} =~ "^/")) {
          $self->{CONF}->{"snmp"}->{"metadata_db_file"} = $self->{DIRECTORY}."/".$self->{CONF}->{"snmp"}->{"metadata_db_file"};
        }
      }
    }
  }
  elsif($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb") {
    eval {
      load perfSONAR_PS::DB::XMLDB;
    };
    if ($@) {
      $logger->error("Couldn't load perfSONAR_PS::DB::XMLDB: $@");
      return -1;
    }

    if(!defined $self->{CONF}->{"snmp"}->{"metadata_db_file"} or
       $self->{CONF}->{"snmp"}->{"metadata_db_file"} eq "") {
      $logger->error("Value for 'metadata_db_file' is not set.");
      return -1;
    }
    if(!defined $self->{CONF}->{"snmp"}->{"metadata_db_name"} or
       $self->{CONF}->{"snmp"}->{"metadata_db_name"} eq "") {
      $logger->error("Value for 'metadata_db_name' is not set.");
      return -1;
    }
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"snmp"}->{"metadata_db_name"} =~ "^/")) {
          $self->{CONF}->{"snmp"}->{"metadata_db_name"} = $self->{DIRECTORY}."/".$self->{CONF}->{"snmp"}->{"metadata_db_name"};
        }
      }
    }
  }
  else {
    $logger->error("Wrong value for 'metadata_db_type' set.");
    return -1;
  }

  if(!defined $self->{CONF}->{"snmp"}->{"rrdtool"} or
     $self->{CONF}->{"snmp"}->{"rrdtool"} eq "") {
    $logger->error("Value for 'rrdtool' is not set.");
    return -1;
  }

  if(!defined $self->{CONF}->{"snmp"}->{"default_resolution"} or
     $self->{CONF}->{"snmp"}->{"default_resolution"} eq "") {
    $self->{CONF}->{"snmp"}->{"default_resolution"} = "300";
    $logger->warn("Setting 'default_resolution' to '300'.");
  }

  if (!defined $self->{CONF}->{"snmp"}->{"enable_registration"} or $self->{CONF}->{"snmp"}->{"enable_registration"} eq "") {
	  $self->{CONF}->{"snmp"}->{"enable_registration"} = 0;
  }

  if ($self->{CONF}->{"snmp"}->{"enable_registration"}) {
	  if (!defined $self->{CONF}->{"snmp"}->{"service_accesspoint"} or $self->{CONF}->{"snmp"}->{"service_accesspoint"} eq "") {
		  $logger->error("No access point specified for SNMP service");
		  return -1;
	  }

	  if (!defined $self->{CONF}->{"snmp"}->{"ls_instance"} or $self->{CONF}->{"snmp"}->{"ls_instance"} eq "") {
		  if (defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne "") {
			  $self->{CONF}->{"snmp"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
		  } else {
			  $logger->error("No LS instance specified for SNMP service");
			  return -1;
		  }
	  }

	  if (!defined $self->{CONF}->{"snmp"}->{"ls_registration_interval"} or $self->{CONF}->{"snmp"}->{"ls_registration_interval"} eq "") {
		  if (defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne "") {
			  $self->{CONF}->{"snmp"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
		  } else {
			  $logger->warn("Setting registration interval to 30 minutes");
			  $self->{CONF}->{"snmp"}->{"ls_registration_interval"} = 1800;
		  }
	  }

	  if(!defined $self->{CONF}->{"snmp"}->{"service_accesspoint"} or
			  $self->{CONF}->{"snmp"}->{"service_accesspoint"} eq "") {
		  $self->{CONF}->{"snmp"}->{"service_accesspoint"} = "http://localhost:".$self->{PORT}."/".$self->{ENDPOINT}."";
		  $logger->warn("Setting 'service_accesspoint' to 'http://localhost:".$self->{PORT}."/".$self->{ENDPOINT}."'.");
	  }

	  if(!defined $self->{CONF}->{"snmp"}->{"service_description"} or
			  $self->{CONF}->{"snmp"}->{"service_description"} eq "") {
		  $self->{CONF}->{"snmp"}->{"service_description"} = "perfSONAR_PS SNMP MA";
		  $logger->warn("Setting 'service_description' to 'perfSONAR_PS SNMP MA'.");
	  }

	  if(!defined $self->{CONF}->{"snmp"}->{"service_name"} or
			  $self->{CONF}->{"snmp"}->{"service_name"} eq "") {
		  $self->{CONF}->{"snmp"}->{"service_name"} = "SNMP MA";
		  $logger->warn("Setting 'service_name' to 'SNMP MA'.");
	  }

	  if(!defined $self->{CONF}->{"snmp"}->{"service_type"} or
			  $self->{CONF}->{"snmp"}->{"service_type"} eq "") {
		  $self->{CONF}->{"snmp"}->{"service_type"} = "MA";
		  $logger->warn("Setting 'service_type' to 'MA'.");
	  }
  }

  $handler->addMessageHandler("SetupDataRequest", $self);
  $handler->addMessageHandler("MetadataKeyRequest", $self);

  return 0;
}

sub needLS($) {
	my ($self) = @_;
	return ($self->{CONF}->{"snmp"}->{"enable_registration"});
}

sub registerLS($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::SNMP");
	my ($status, $res);
	my $ls;

	if (!defined $self->{LS_CLIENT}) {
		my %ls_conf = (
				SERVICE_TYPE => $self->{CONF}->{"snmp"}->{"service_type"},
				SERVICE_NAME => $self->{CONF}->{"snmp"}->{"service_name"},
				SERVICE_DESCRIPTION => $self->{CONF}->{"snmp"}->{"service_description"},
				SERVICE_ACCESSPOINT => $self->{CONF}->{"snmp"}->{"service_accesspoint"},
			      );

		$self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"snmp"}->{"ls_instance"}, \%ls_conf, $self->{NAMESPACES});
	}

	$ls = $self->{LS_CLIENT};

        my $queryString = "/nmwg:store/nmwg:metadata";
        my $error = "";            
        my $metadatadb;
	my @resultsString;
      
	if($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file") {
		$metadatadb = new perfSONAR_PS::DB::File( $self->{CONF}->{"snmp"}->{"metadata_db_file"});
		$metadatadb->openDB($error);
		@resultsString = $metadatadb->query($queryString);            
	} elsif($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb") {
		my $dbTr = $metadatadb->getTransaction(\$error);
		if($dbTr and !$error) {         
			$metadatadb = new perfSONAR_PS::DB::XMLDB($self->{CONF}->{"snmp"}->{"metadata_db_name"}, $self->{CONF}->{"snmp"}->{"metadata_db_file"}, $self->{NAMESPACES});
			$metadatadb->openDB($dbTr, $error); 
			@resultsString = $metadatadb->query($queryString, $dbTr, \$error);      

			$metadatadb->commitTransaction($dbTr, \$error);
			undef $dbTr;
			if($error) {
				$logger->error("Database Error: \"" . $error . "\".");                
				$metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
				undef $dbTr;
				return;
			}    
		}
		else { 
			$logger->error("Cound not start database transaction.");
			$metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
			undef $dbTr;
			return;
		}                
	}

	return $ls->registerStatic(\@resultsString);
}

sub handleMessageBegin($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces) = @_;

	return 0;
}

sub handleMessageEnd($$$) {
	my ($self, $ret_message, $messageId) = @_;

	return 0;
}

sub handleEvent($$$$$$$$$) {
	my ($self, $output, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::SNMP");

	if ($messageType eq "MetadataKeyRequest") {
		return $self->maMetadataKeyRequest($output, $md, $raw_request, $message_parameters);
	} else {
		return $self->maSetupDataRequest($output, $md, $raw_request, $message_parameters);
	}
}


sub maMetadataKeyRequest($$$$$) {
  my($self, $output, $md, $request, $message_parameters) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = "";

  my $metadatadb;
  if($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file") {
    $metadatadb = new perfSONAR_PS::DB::File(
      $self->{CONF}->{"snmp"}->{"metadata_db_file"}
    );
  }
  elsif($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb") {
    $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"snmp"}->{"metadata_db_name"},
      $self->{CONF}->{"snmp"}->{"metadata_db_file"},
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

  if(getTime($request, \%{$self}, $md->getAttribute("id"), $self->{CONF}->{"snmp"}->{"default_resolution"})) {
    if(find($md, "./nmwg:key", 1)) {
      metadataKeyRetrieveKey(\%{$self}, $metadatadb, find($md, "./nmwg:key", 1), "", $md->getAttribute("id"), $request->getNamespaces(), $output);
    }
    else {
      if($request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and
         find($md, "./select:subject", 1)) {
        my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".find($md, "./select:subject", 1)->getAttribute("metadataIdRef")."\"]", 1);
        if($other_md) {
          if(find($other_md, "./nmwg:key", 1)) {
            metadataKeyRetrieveKey(\%{$self}, $metadatadb, find($other_md, "./nmwg:key", 1), $md, $md->getAttribute("id"), $request->getNamespaces(), $output);
          }
          else {
            metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $other_md, $md, $md->getAttribute("id"), $request->getNamespaces(), $output);
          }
        }
        else {
          my $msg = "Cannot resolve supposed subject chain in metadata.";
          $logger->error($msg);
	  throw perfSONAR_PS::Error_compat("error.ma.chaining", $msg);
        }
      }
      else {
        metadataKeyRetrieveMetadataData(\%{$self}, $metadatadb, $md, "", $md->getAttribute("id"), $request->getNamespaces(), $output);
      }
    }
  }
}


sub metadataKeyRetrieveKey($$$$$$$) {
  my($self, $metadatadb, $key, $chain, $id, $request_namespaces, $output) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();

  my $queryString = "/nmwg:store/nmwg:data[" . getDataXQuery($key, "") . "]";
  my $results = $metadatadb->querySet($queryString);
  if($results->size() == 1) {
    my $key2 = find($results->get_node(1)->cloneNode(1), "./nmwg:key", 1);
    if($key2) {
      if(defined $chain and $chain ne "") {
        if($request_namespaces->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
            find($key2, ".//nmwg:parameters", 1)->addChild($p->cloneNode(1));
          }
        }
      }
      createMetadata($output, $mdId, $id, $key->toString, undef);
      createData($output, $dId, $mdId, $key2->toString, undef);
    }
    else {
      my $msg = "Key error in metadata storage.";
      $logger->error($msg);
      throw perfSONAR_PS::Error_compat("error.ma.storage_result", $msg);
    }
  }
  else {
    my $msg = "Key error in metadata storage.";
    $logger->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage_result", $msg);
  }
  return;
}


sub metadataKeyRetrieveMetadataData($$$$$$$) {
  my($self, $metadatadb, $metadata, $chain, $id, $request_namespaces, $output) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = "";

  my $queryString = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  my $results = $metadatadb->querySet($queryString);

  my %et = ();
  my $eventTypes = find($metadata, "./nmwg:eventType", 0);
  my $supportedEventTypes = find($metadata, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0);
  foreach my $e ($eventTypes->get_nodelist) {
    my $value = extract($e, 0);
    if($value) {
      $et{$value} = 1;
    }
  }
  foreach my $se ($supportedEventTypes->get_nodelist) {
    my $value = extract($se, 0);
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
              if($request_namespaces->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
                foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
                  find($d_temp, ".//nmwg:parameters", 1)->addChild($p->cloneNode(1));
                }
              }
            }
            $md_temp->setAttribute("metadataIdRef", $id);
            $md_temp->setAttribute("id", $mdId);
            $output->addExistingXMLElement($md_temp);
            $output->addExistingXMLElement($d_temp);
            $used{$uc}++;
            last;
          }
          $uc++;
        }
      }
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"snmp"}->{"metadata_db_file"}."\" returned 0 results for search";
    $logger->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage", $msg);
  }
  return;
}



sub maSetupDataRequest($$$$$) {
  my($self, $output, $md, $request, $message_parameters) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = "";

  my $metadatadb;
  if($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "file") {
    $metadatadb = new perfSONAR_PS::DB::File(
      $self->{CONF}->{"snmp"}->{"metadata_db_file"}
    );
  }
  elsif($self->{CONF}->{"snmp"}->{"metadata_db_type"} eq "xmldb") {
    $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"snmp"}->{"metadata_db_name"},
      $self->{CONF}->{"snmp"}->{"metadata_db_file"},
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

  if(getTime($request, \%{$self}, $md->getAttribute("id"), $self->{CONF}->{"snmp"}->{"default_resolution"})) {
    if(find($md, "./nmwg:key", 1)) {
      setupDataRetrieveKey(\%{$self}, $metadatadb, find($md, "./nmwg:key", 1), "", $md->getAttribute("id"), $message_parameters, $request->getNamespaces(), $output);
    }
    else {
      if($request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"} and
         find($md, "./select:subject", 1)) {
        my $other_md = find($request->getRequestDOM(), "//nmwg:metadata[\@id=\"".find($md, "./select:subject", 1)->getAttribute("metadataIdRef")."\"]", 1);
        if($other_md) {
          if(find($other_md, "./nmwg:key", 1)) {
            setupDataRetrieveKey(\%{$self}, $metadatadb, find($other_md, "./nmwg:key", 1), $md, $md->getAttribute("id"), $message_parameters, $request->getNamespaces(), $output);
          }
          else {
            setupDataRetrieveMetadataData($self, $metadatadb, $other_md, $md->getAttribute("id"), $message_parameters, $output);
          }
        }
        else {
          my $msg = "Cannot resolve subject chain in metadata.";
          $logger->error($msg);
	  throw perfSONAR_PS::Error_compat("error.ma.chaining", $msg);
        }
      }
      else {
        setupDataRetrieveMetadataData($self, $metadatadb, $md, $md->getAttribute("id"), $message_parameters, $output);
      }
    }
  }
}


sub setupDataRetrieveMetadataData($$$$$$) {
  my($self, $metadatadb, $metadata, $id, $message_parameters, $output) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $mdId = "";
  my $dId = "";

  my $queryString = "/nmwg:store/nmwg:metadata[" . getMetadataXQuery($metadata, "") . "]";
  my $results = $metadatadb->querySet($queryString);

  my %et = ();
  my $eventTypes = find($metadata, "./nmwg:eventType", 0);
  my $supportedEventTypes = find($metadata, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0);
  foreach my $e ($eventTypes->get_nodelist) {
    my $value = extract($e, 0);
    if($value) {
      $et{$value} = 1;
    }
  }
  foreach my $se ($supportedEventTypes->get_nodelist) {
    my $value = extract($se, 0);
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
      my $l_eventTypes = find($md, "./nmwg:eventType", 0);
      my $l_supportedEventTypes = find($md, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0);
      foreach my $e ($l_eventTypes->get_nodelist) {
        my $value = extract($e, 0);
        if($value) {
          $l_et{$value} = 1;
        }
      }
      foreach my $se ($l_supportedEventTypes->get_nodelist) {
        my $value = extract($se, 0);
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
            $output->addExistingXMLElement($md_temp);
            handleData($self, $mdId, $d_temp, $output, \%l_et, $message_parameters);
            $used{$uc}++;
            last;
          }
          $uc++;
        }
      }
    }
  }
  else {
    my $msg = "Database \"".$self->{CONF}->{"snmp"}->{"metadata_db_file"}."\" returned 0 results for search";
    $logger->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage", $msg);
  }
  return;
}


sub setupDataRetrieveKey($$$$$$$$) {
  my($self, $metadatadb, $metadata, $chain, $id, $message_parameters, $request_namespaces, $output) = @_;
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
      my $l_supportedEventTypes = find($key, ".//nmwg:parameter[\@name=\"supportedEventType\"]", 0);
      foreach my $se ($l_supportedEventTypes->get_nodelist) {
        my $value = extract($se, 0);
        if($value) {
          $l_et{$value} = 1;
        }
      }

      $mdId = "metadata.".genuid();
      $dId = "data.".genuid();
      if(defined $chain and $chain ne "") {
        if($request_namespaces->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
          foreach my $p (find($chain, "./select:parameters", 1)->childNodes) {
            find($key, ".//nmwg:parameters", 1)->addChild($p->cloneNode(1));
          }
        }
        createMetadata($output, $mdId, $id, $key->toString, undef);
        handleData(\%{$self}, $mdId, $results_temp, $output, \%l_et, $message_parameters);
      }
      else {
        createMetadata($output, $mdId, $id, $metadata->toString, undef);
        handleData(\%{$self}, $mdId, $results_temp, $output, \%l_et, $message_parameters);
      }
    }
    else {
      my $msg = "Key not found in metadata storage.";
      $logger->error($msg);
      throw perfSONAR_PS::Error_compat("error.ma.storage.result", $msg);
    }
  }
  else {
    my $msg = "Keys error in metadata storage.";
    $logger->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage.result", $msg);
  }
  return;
}


sub handleData($$$$$$) {
  my($self, $id, $data, $output, $et, $message_parameters) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  undef $self->{RESULTS};

  $self->{RESULTS} = $data;
  my $type = extract(find($data, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]", 1), 0);
  if($type eq "rrd") {
    retrieveRRD($self, $data, $id, $output, $et, $message_parameters);
  }
  elsif($type eq "sqlite") {
    retrieveSQL($self, $data, $id, $output, $et, $message_parameters);
  }
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    $logger->error($msg);
    getResultCodeData($output, "data.".genuid(), $id, $msg, 1);
  }
  return;
}


sub retrieveSQL($$$$$$) {
  my($self, $d, $mid, $output, $et, $message_parameters) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my $datumns = 0;
  my $timeType = "";

  if (defined $message_parameters->{"eventNameSpaceSynchronization"} and
      	    $message_parameters->{"eventNameSpaceSynchronization"} =~ m/^true$/i) {
      $datumns = 1;
  }

  if (defined $message_parameters->{"timeType"}) {
    if ($message_parameters->{"timeType"} =~ m/^unix$/i) {
      $timeType = "unix";
    } elsif ($message_parameters->{"timeType"} =~ m/^iso/i) {
      $timeType = "iso";
    }
  }

  my @dbSchema = ("id", "time", "value", "eventtype", "misc");
  my $result = getDataSQL($self, $d, \@dbSchema);
  my $id = "data.".genuid();

  if($#{$result} == -1) {
    my $msg = "Query returned 0 results";
    $logger->error($msg);
    getResultCodeData($output, $id, $mid, $msg, 1);
  }
  else {
    my $prefix = "nmwg";
    my $uri = "http://ggf.org/ns/nmwg/base/2.0";

    if($datumns) {
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

    startData($output, $id, $mid, undef);
    for(my $a = 0; $a <= $#{$result}; $a++) {
      print $output "    <".$prefix.":datum xmlns:".$prefix."=\"".$uri."/\" timeType=\"";

      my %attrs = ();
      if($timeType eq "iso") {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($result->[$a][1]);
        $attrs{"timeType"} = "ISO";
        $attrs{$dbSchema[1]."Value"} = sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
      }
      else {
        $attrs{"timeType"} = "unix";
        $attrs{$dbSchema[1]."Value"} = $result->[$a][1];
      }
      $attrs{$dbSchema[2]} = $result->[$a][2];

      my @misc = split(/,/,$result->[$a][4]);
      foreach my $m (@misc) {
        my @pair = split(/=/,$m);
        $attrs{$pair[0]} = $pair[1];
      }

      $output->createElement($prefix, $uri, "datum", \%attrs, undef, "");
    }
    endData($output);
  }
  return;
}


sub retrieveRRD($$$$$$) {
  my($self, $d, $mid, $output, $et, $message_parameters) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");
  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $datumns = 0;
  my $timeType = "";

  if (defined $message_parameters->{"eventNameSpaceSynchronization"} and
      	    $message_parameters->{"eventNameSpaceSynchronization"} =~ m/^true$/i) {
      $datumns = 1;
  }

  if (defined $message_parameters->{"timeType"}) {
    if ($message_parameters->{"timeType"} =~ m/^unix$/i) {
      $timeType = "unix";
    } elsif ($message_parameters->{"timeType"} =~ m/^iso/i) {
      $timeType = "iso";
    }
  }

  adjustRRDTime($self);
  my $id = "data.".genuid();
  my %rrd_result = getDataRRD($self, $d, $mid, $self->{CONF}->{"snmp"}->{"rrdtool"});
  if($rrd_result{ERROR}) {
    $logger->error("RRD error seen: ".$rrd_result{ERROR});
    getResultCodeData($output, $id, $mid, $rrd_result{ERROR}, 1);
  }
  else {
    my $prefix = "nmwg";
    my $uri = "http://ggf.org/ns/nmwg/base/2.0";
    if($datumns) {
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

    my $dataSource = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"dataSource\"]", 1), 0);
    my $valueUnits = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"valueUnits\"]", 1), 0);

    startData($output, $id, $mid, undef);
    foreach $a (sort(keys(%rrd_result))) {
      foreach $b (sort(keys(%{$rrd_result{$a}}))) {
        if($b eq $dataSource) {
          if($a < $sec) {
            my %attrs = ();
            if($timeType eq "iso") {
              my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($a);
              $attrs{"timeType"} = "ISO";
              $attrs{"timeValue"} = sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ\n", ($year+1900), ($mon+1), $mday, $hour, $min, $sec;
            }
            else {
              $attrs{"timeType"} = "unix";
              $attrs{"timeValue"} = $a;
            }
            $attrs{"value"} = $rrd_result{$a}{$b};
            $attrs{"valueUnits"} = $valueUnits;

            $output->createElement($prefix, $uri, "datum", \%attrs, undef, "");
          }
        }
      }
    }
    endData($output);
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
    $conf{"snmp"}->{"metadata_db_type"} = "xmldb";
    $conf{"snmp"}->{"metadata_db_name"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"snmp"}->{"metadata_db_file"} = "snmpstore.dbxml";

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

=head2 handleRequest($self, $request, $output)

Functions as the 'gatekeeper' the the MA.  Will either reject or accept
requets.  will also 'do nothing' in the event that a request has been
acted on by the lower layer.

=head2 __handleRequest($self, $request, $output)

Processes the messages that this MA can handle.

=head2 handleMessageParameters($self, $msgParams)

Extracts and acts on special 'Message Level' parameters that may exist and change
behavior or output.  Not to be used externally.

=head2 maMetadataKeyRequest($self, $output, $request)

Handles the steps of a MetadataKeyRequest message.  Not to be used externally.

=head2 metadataKeyRetrieveKey($self, $metadatadb, $key, $chain, $id, $request_namespaces, $output)

Helper function for 'maMetadataKeyRequest', handles the case where a 'key' is present
in the request.

=head2 metadataKeyRetrieveMetadataData($self, $metadatadb, $metadata, $chain, $id, $output)

Helper function for 'maMetadataKeyRequest', handles the case where a 'key' is not present
in the request.

=head2 maSetupDataRequest($self, $output, $request)

Handles the steps of a SetupDataRequest message.  Not to be used externally.

=head2 setupDataRetrieveMetadataData($self, $metadatadb, $metadata, $id, $output)

Helper function for 'maSetupDataRequest', handles the case where a 'key' is not present
in the request.

=head2 setupDataRetrieveKey($self, $metadatadb, $metadata, $chain, $id, $output)

Helper function for 'maSetupDataRequest', handles the case where a 'key' is present
in the request.

=head2 handleData($self, $id, $data, $output, \%et)

Handles the data portion of a SetupDataRequest by contacting the supported databases.

=head2 retrieveSQL($self, $d, $mid, $output)

Gathers data from the SQL database and creates the necessary XML.

=head2 retrieveRRD($self, $d, $mid, $output)

Gathers data from the RR database and creates the necessary XML.

=head1 SEE ALSO

L<Log::Log4perl>, L<File::Temp>, L<Time::HiRes>,
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


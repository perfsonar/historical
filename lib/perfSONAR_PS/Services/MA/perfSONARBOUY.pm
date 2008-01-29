package perfSONAR_PS::Services::MA::perfSONARBOUY;

use base 'perfSONAR_PS::Services::Base';

use fields 'LS_CLIENT', 'TIME', 'NAMESPACES', 'RESULTS', 'METADATADB';

our $VERSION = 0.01;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use Module::Load;
use OWP;
use OWP::Utils;
use Fcntl ':flock';

use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Error_compat qw/:try/;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::SQL;

sub init($$);
sub createStoreFile($);
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


sub init($$) {
  my ($self, $handler) = @_;
  $self->{CONF}->{"perfsonarbouy"}->{"logger"} = get_logger("perfSONAR_PS::Services::MA::perfSONARBOUY");

  # values that are deal breakers...

  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} or
     $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "") {
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Value for 'metadata_db_type' is not set.");
    return -1;
  }

  if($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "file") {
    if(!defined $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} or
       $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} eq "") {
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Value for 'metadata_db_file' is not set.");
      return -1;
    }
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} =~ "^/")) {
          $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} = $self->{DIRECTORY}."/".$self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"};
        }
      }
    }
  }
  elsif($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "xmldb") {
    eval {
      load perfSONAR_PS::DB::XMLDB;
    };
    if($@) {
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Couldn't load perfSONAR_PS::DB::XMLDB: $@");
      return -1;
    }

    if(!defined $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} or
       $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"} eq "") {
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Value for 'metadata_db_file' is not set.");
      return -1;
    }
    if(!defined $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"} or
       $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"} eq "") {
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Value for 'metadata_db_name' is not set.");
      return -1;
    }
    else {
      if(defined $self->{DIRECTORY}) {
        if(!($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"} =~ "^/")) {
          $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"} = $self->{DIRECTORY}."/".$self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"};
        }
      }
    }
  }
  else {
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Wrong value for 'metadata_db_type' set.");
    return -1;
  }

  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"enable_registration"} or $self->{CONF}->{"perfsonarbouy"}->{"enable_registration"} eq "") {
	  $self->{CONF}->{"perfsonarbouy"}->{"enable_registration"} = 0;
  }

  if($self->{CONF}->{"perfsonarbouy"}->{"enable_registration"}) {
	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"} or $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"} eq "") {
		  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("No access point specified for perfSONARBOUY service");
		  return -1;
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"ls_instance"} or $self->{CONF}->{"perfsonarbouy"}->{"ls_instance"} eq "") {
		  if(defined $self->{CONF}->{"ls_instance"} and $self->{CONF}->{"ls_instance"} ne "") {
			  $self->{CONF}->{"perfsonarbouy"}->{"ls_instance"} = $self->{CONF}->{"ls_instance"};
		  }
		  else {
			  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("No LS instance specified for perfSONARBOUY service");
			  return -1;
		  }
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"ls_registration_interval"} or $self->{CONF}->{"perfsonarbouy"}->{"ls_registration_interval"} eq "") {
		  if(defined $self->{CONF}->{"ls_registration_interval"} and $self->{CONF}->{"ls_registration_interval"} ne "") {
			  $self->{CONF}->{"perfsonarbouy"}->{"ls_registration_interval"} = $self->{CONF}->{"ls_registration_interval"};
		  }
		  else {
			  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->warn("Setting registration interval to 30 minutes");
			  $self->{CONF}->{"perfsonarbouy"}->{"ls_registration_interval"} = 1800;
		  }
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"} or
			 $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"} eq "") {
		  $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"} = "http://localhost:".$self->{PORT}."/".$self->{ENDPOINT}."";
		  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->warn("Setting 'service_accesspoint' to 'http://localhost:".$self->{PORT}."/".$self->{ENDPOINT}."'.");
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"service_description"} or
			 $self->{CONF}->{"perfsonarbouy"}->{"service_description"} eq "") {
		  $self->{CONF}->{"perfsonarbouy"}->{"service_description"} = "perfSONAR_PS perfSONARBOUY MA";
		  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->warn("Setting 'service_description' to 'perfSONAR_PS perfSONARBOUY MA'.");
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"service_name"} or
			 $self->{CONF}->{"perfsonarbouy"}->{"service_name"} eq "") {
		  $self->{CONF}->{"perfsonarbouy"}->{"service_name"} = "perfSONARBOUY MA";
		  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->warn("Setting 'service_name' to 'perfSONARBOUY MA'.");
	  }

	  if(!defined $self->{CONF}->{"perfsonarbouy"}->{"service_type"} or
			 $self->{CONF}->{"perfsonarbouy"}->{"service_type"} eq "") {
		  $self->{CONF}->{"perfsonarbouy"}->{"service_type"} = "MA";
		  $self->{CONF}->{"perfsonarbouy"}->{"logger"}->warn("Setting 'service_type' to 'MA'.");
	  }
  }

  my $metadatadb;
  my $error;
  if($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "file") {
    #if (!(-e $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"})) { 
      createStoreFile(\%{$self});
    #}
    $metadatadb = new perfSONAR_PS::DB::File($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"});
  }
  elsif($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "xmldb") {
    $metadatadb = new perfSONAR_PS::DB::XMLDB( $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"}, $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"}, \%{$self->{NAMESPACES}});
  }
  $metadatadb->openDB(\$error);

  if ($error) {
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Couldn't initialize store file: $error");
    return -1;
  }

  $self->{METADATADB} = $metadatadb;

  $handler->addMessageHandler("SetupDataRequest", $self);
  $handler->addMessageHandler("MetadataKeyRequest", $self);

  return 0;
}


sub createStoreFile($) {
  my($self) = @_;
  
  my %defaults = (
    DBTYPE  =>      "DBI:mysql",
    DBNAME  =>      "bwctl",
    DBUSER  =>      "root",
    DBPASS  =>      undef,
    DBHOST  =>      "localhost",
    CONFDIR =>      "/home/jason/ami/trunk/etc",
  );

  my $conf = new OWP::Conf(%defaults);

  my $dbuser = $defaults{'DBUSER'};
  my $dbpass = $defaults{'DBPASS'};
  my $dbhost = $defaults{'DBHOST'};
  my $dbsource = $defaults{'DBTYPE'} . ":" . $defaults{'DBNAME'} . ":" . $defaults{'DBHOST'};

  my $dbh = DBI->connect($dbsource,
                         $dbuser,
                         $dbpass,
                         {
                           RaiseError      =>      1,
                           PrintError      =>      1
                         }
                        ) or (
                          $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Couldn't connect to database") and 
                          throw perfSONAR_PS::Error_compat("error.ma.database", "Couldn't connect to database")
                        );


  my $i;
  my $sql;
  my $sth;
  my @row;
  my %meshes;
  my %nodes;

  open(STORE, ">".$self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"}) or (
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Couldn't write store file") and 
    throw perfSONAR_PS::Error_compat("error.ma.metadata.database", "Couldn't write store file")
  );
  flock(STORE, LOCK_EX);

  print STORE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  print STORE "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"
            xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"
            xmlns:iperf= \"http://ggf.org/ns/nmwg/tools/iperf/2.0/\">\n\n";

  $sql="select * from meshes";
  $sth = $dbh->prepare($sql) or die "Prep:Select meshes";
  $sth->execute() or die "Select meshes";
  while(@row = $sth->fetchrow_array){
    my %temp = ();
    $temp{"mesh_name"} = $row[1];
    $temp{"mesh_desc"} = $row[2];
    $temp{"mesh_tool_name"} = $row[3];
    $temp{"addr_type"} = $row[4];
    $meshes{$row[0]} = \%temp;
  }

  $sql="select * from nodes";
  $sth = $dbh->prepare($sql) or die "Prep:Select nodes";
  $sth->execute() or die "Select nodes";
  while(@row = $sth->fetchrow_array){
    my %temp = ();
    $temp{"node_name"} = $row[1];
    $temp{"uptime_addr"} = $row[2];
    $temp{"uptime_port"} = $row[3];
    $nodes{$row[0]} = \%temp;
  }

  my $id = 1;

  $sql="select * from node_mesh_map";
  $sth = $dbh->prepare($sql) or die "Prep:Select node_mesh";
  $sth->execute() or die "Select node_mesh";
  while(@row = $sth->fetchrow_array){
    my $sql2="select * from node_mesh_map";
    my $sth2 = $dbh->prepare($sql2) or die "Prep:Select node_mesh";
    $sth2->execute() or die "Select node_mesh";
    my @row2 = ();
    while(@row2 = $sth2->fetchrow_array){
      if($meshes{$row[0]}->{"mesh_name"} eq $meshes{$row2[0]}->{"mesh_name"} and
         $nodes{$row[1]}->{"node_name"} ne $nodes{$row2[1]}->{"node_name"}) { 

        print STORE "  <nmwg:metadata id=\"metadata-".$id."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
        print STORE "    <iperf:subject id=\"subject-".$id."\" xmlns:iperf=\"http://ggf.org/ns/nmwg/tools/iperf/2.0/\">\n";  
        print STORE "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";  

        if($meshes{$row[0]}->{"addr_type"} eq "BWV6") {
          print STORE "        <nmwgt:src type=\"ipv6\" value=\"".$conf->{"NODE-".$nodes{$row[1]}->{"node_name"}}->{"ADDRBWV6"}."\" port=\"".$nodes{$row[1]}->{"uptime_port"}."\" />\n";
          print STORE "        <nmwgt:dst type=\"ipv6\" value=\"".$conf->{"NODE-".$nodes{$row2[1]}->{"node_name"}}->{"ADDRBWV6"}."\" port=\"".$nodes{$row2[1]}->{"uptime_port"}."\" />\n";
        }
        else {
          print STORE "        <nmwgt:src type=\"ipv4\" value=\"".$conf->{"NODE-".$nodes{$row[1]}->{"node_name"}}->{"ADDRBWV4"}."\" port=\"".$nodes{$row[1]}->{"uptime_port"}."\" />\n";
          print STORE "        <nmwgt:dst type=\"ipv4\" value=\"".$conf->{"NODE-".$nodes{$row2[1]}->{"node_name"}}->{"ADDRBWV4"}."\" port=\"".$nodes{$row2[1]}->{"uptime_port"}."\" />\n";
        }

        print STORE "      </nmwgt:endPointPair>\n";
        print STORE "    </iperf:subject>\n";
        print STORE "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/iperf/2.0</nmwg:eventType>\n";
        print STORE "    <nmwg:parameters id=\"parameters-".$id."\">\n";
        print STORE "      <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/iperf/2.0</nmwg:parameter>\n";
        print STORE "    </nmwg:parameters>\n";
        print STORE "  </nmwg:metadata>\n\n";

        print STORE "  <nmwg:data id=\"data-".$id."\" metadataIdRef=\"metadata-".$id."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";  
        print STORE "    <nmwg:key id=\"key-".$id."\">\n";  
        print STORE "      <nmwg:parameters id=\"parameters-key-".$id."\">\n";  
        print STORE "        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/iperf/2.0</nmwg:parameter>\n";
        print STORE "        <nmwg:parameter name=\"type\">mysql</nmwg:parameter>\n";  
        print STORE "        <nmwg:parameter name=\"db\">".$dbsource."</nmwg:parameter>\n";        
        print STORE "        <nmwg:parameter name=\"user\">".$dbuser."</nmwg:parameter>\n" if $dbuser;        
        print STORE "        <nmwg:parameter name=\"pass\">".$dbpass."</nmwg:parameter>\n" if $dbpass;        
        print STORE "        <nmwg:parameter name=\"table\">"."BW_".$meshes{$row[0]}->{"mesh_name"}."_".$nodes{$row[1]}->{"node_name"}."_".$nodes{$row2[1]}->{"node_name"}."</nmwg:parameter>\n";
        print STORE "      </nmwg:parameters>\n";  
        print STORE "    </nmwg:key>\n";  
        print STORE "  </nmwg:data>\n\n";
        $id++;

      }
    }
  }

  print STORE "</nmwg:store>\n";

  flock(STORE, LOCK_UN);
  close(STORE); 

  $dbh->disconnect();

  return;
}


sub needLS($) {
	my ($self) = @_;
	return ($self->{CONF}->{"perfsonarbouy"}->{"enable_registration"});
}


sub registerLS($) {
	my ($self) = @_;
	my ($status, $res);
	my $ls;

	if (!defined $self->{LS_CLIENT}) {
		my %ls_conf = (
		  SERVICE_TYPE => $self->{CONF}->{"perfsonarbouy"}->{"service_type"},
			SERVICE_NAME => $self->{CONF}->{"perfsonarbouy"}->{"service_name"},
			SERVICE_DESCRIPTION => $self->{CONF}->{"perfsonarbouy"}->{"service_description"},
			SERVICE_ACCESSPOINT => $self->{CONF}->{"perfsonarbouy"}->{"service_accesspoint"}
	  );
		$self->{LS_CLIENT} = new perfSONAR_PS::Client::LS::Remote($self->{CONF}->{"perfsonarbouy"}->{"ls_instance"}, \%ls_conf, $self->{NAMESPACES});
	}

	$ls = $self->{LS_CLIENT};

  my $queryString = "/nmwg:store/nmwg:metadata";
  my $error = "";            
  my $metadatadb = $self->{METADATADB};
	my @resultsString;
      
	if($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "file") {
		@resultsString = $metadatadb->query($queryString);            
	}
	elsif($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "xmldb") {
		my $dbTr = $metadatadb->getTransaction(\$error);
		if($dbTr and !$error) {         
			@resultsString = $metadatadb->query($queryString, $dbTr, \$error);      

			$metadatadb->commitTransaction($dbTr, \$error);
			undef $dbTr;
			if($error) {
				$self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Database Error: \"" . $error . "\".");                
				$metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
				undef $dbTr;
				return;
			}    
		}
		else { 
			$self->{CONF}->{"perfsonarbouy"}->{"logger"}->error("Cound not start database transaction.");
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

	if ($messageType eq "MetadataKeyRequest") {
		return $self->maMetadataKeyRequest($output, $md, $raw_request, $message_parameters);
	} 
	else {
		return $self->maSetupDataRequest($output, $md, $raw_request, $message_parameters);
	}
}


sub maMetadataKeyRequest($$$$$) {
  my($self, $output, $md, $request, $message_parameters) = @_;
  my $mdId = "";
  my $dId = "";

  my $metadatadb = $self->{METADATADB};

  # MA MetadataKeyRequest Steps
  # ---------------------
  # Is there a key?
  #   Y: do queries against key return key as md AND d
  #   N: Is there a chain?
  #     Y: Is there a key
  #       Y: do queries against key, add in select stuff to key, return key as md AND d
  #       N: do md/d queries against md return results with altered key
  #     N: do md/d queries against md return results

  if(getTime($request, \%{$self}, $md->getAttribute("id"), $self->{CONF}->{"perfsonarbouy"}->{"default_resolution"})) {
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
          $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
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
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
      throw perfSONAR_PS::Error_compat("error.ma.storage_result", $msg);
    }
  }
  else {
    my $msg = "Key error in metadata storage.";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage_result", $msg);
  }
  return;
}


sub metadataKeyRetrieveMetadataData($$$$$$$) {
  my($self, $metadatadb, $metadata, $chain, $id, $request_namespaces, $output) = @_;
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
    my $msg = "Database \"".$self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"}."\" returned 0 results for search";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage", $msg);
  }
  return;
}



sub maSetupDataRequest($$$$$) {
  my($self, $output, $md, $request, $message_parameters) = @_;
  my $mdId = "";
  my $dId = "";

  my $metadatadb = $self->{METADATADB};
  if($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "file") {
    $metadatadb = new perfSONAR_PS::DB::File(
      $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"}
    );
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->debug("MD File: ".  $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"});
  }
  elsif($self->{CONF}->{"perfsonarbouy"}->{"metadata_db_type"} eq "xmldb") {
    $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_name"},
      $self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"},
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

  if(getTime($request, \%{$self}, $md->getAttribute("id"), $self->{CONF}->{"perfsonarbouy"}->{"default_resolution"})) {
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
          $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
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
    my $msg = "Database \"".$self->{CONF}->{"perfsonarbouy"}->{"metadata_db_file"}."\" returned 0 results for search";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage", $msg);
  }
  return;
}


sub setupDataRetrieveKey($$$$$$$$) {
  my($self, $metadatadb, $metadata, $chain, $id, $message_parameters, $request_namespaces, $output) = @_;
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
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
      throw perfSONAR_PS::Error_compat("error.ma.storage.result", $msg);
    }
  }
  else {
    my $msg = "Keys error in metadata storage.";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    throw perfSONAR_PS::Error_compat("error.ma.storage.result", $msg);
  }
  return;
}


sub handleData($$$$$$) {
  my($self, $id, $data, $output, $et, $message_parameters) = @_;
  undef $self->{RESULTS};

  $self->{RESULTS} = $data;
  my $type = extract(find($data, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]", 1), 0);
  if($type =~ m/sqlite/i or $type =~ m/sql/i or $type =~ m/mysql/i) {
    retrieveSQL($self, $data, $id, $output, $et, $message_parameters);
  }
  else {
    my $msg = "Database \"".$type."\" is not yet supported";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    getResultCodeData($output, "data.".genuid(), $id, $msg, 1);
  }
  return;
}


sub retrieveSQL($$$$$$) {
  my($self, $d, $mid, $output, $et, $message_parameters) = @_;
  my $datumns = 0;
  my $timeType = "";

  if(defined $message_parameters->{"eventNameSpaceSynchronization"} and
     $message_parameters->{"eventNameSpaceSynchronization"} =~ m/^true$/i) {
    $datumns = 1;
  }

  if (defined $message_parameters->{"timeType"}) {
    if ($message_parameters->{"timeType"} =~ m/^unix$/i) {
      $timeType = "unix";
    }
    elsif ($message_parameters->{"timeType"} =~ m/^iso/i) {
      $timeType = "iso";
    }
  }

  my @dbSchema = ("ti", "time", "throughput", "jitter", "lost", "sent");

  my $dbconnect = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"db\"]", 1), 1);
  my $dbuser = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"user\"]", 1), 1);
  my $dbpass = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"pass\"]", 1), 1);
  my $dbtable = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"table\"]", 1), 1);
  my $id = "data.".genuid();

  if(defined $dbconnect and defined $dbtable) {
    my $query = "";
    if($self->{TIME}->{"START"} or $self->{TIME}->{"END"}) {
      $query = "select * from ".$dbtable." where";
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
      $query = "select * from ".$dbtable.";";
    } 
  
    my $datadb = new perfSONAR_PS::DB::SQL(
      $dbconnect,
      $dbuser, 
      $dbpass,
      \@dbSchema
    );
          
    $datadb->openDB();  
    my $result = $datadb->query($query);
    $datadb->closeDB();

    if($#{$result} == -1) {
      my $msg = "Query returned 0 results";
      $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
      getResultCodeData($output, $id, $mid, $msg, 1);
    }
    else {
      my $prefix = "nmwg";
      my $uri = "http://ggf.org/ns/nmwg/base/2.0";

      if($datumns) {
        if(defined $et and $et ne "") {
          foreach my $e (sort keys %{$et}) {
            next if $e eq "http://ggf.org/ns/nmwg/tools/bwctl/2.0";
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
        $attrs{$dbSchema[3]} = $result->[$a][3];
        $attrs{$dbSchema[4]} = $result->[$a][4];
        $attrs{$dbSchema[5]} = $result->[$a][5];

        $output->createElement(prefix => $prefix, namespace => $uri, tag => "datum", attributes => \%attrs);
      }
      endData($output);
    }
  }
  else {
    my $msg = "Metadata db configuration error";
    $self->{CONF}->{"perfsonarbouy"}->{"logger"}->error($msg);
    getResultCodeData($output, $id, $mid, $msg, 1);
  }

  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::Services::MA::perfSONARBOUY - A module that provides methods for the perfSONARBOUY MA.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the
related tasks of interacting with backend storage.

=head1 SYNOPSIS

    use perfSONAR_PS::Services::MA::perfSONARBOUY;

    my %conf = ();
    $conf{"perfsonarbouy"}->{"metadata_db_type"} = "xmldb";
    $conf{"perfsonarbouy"}->{"metadata_db_name"} = "/home/jason/perfSONAR-PS/MP/perfSONARBOUY/xmldb";
    $conf{"perfsonarbouy"}->{"metadata_db_file"} = "perfsonarbouystore.dbxml";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      perfsonarbouy => "http://ggf.org/ns/nmwg/tools/perfsonarbouy/2.0/"
    );

    my $ma = perfSONAR_PS::Services::MA::perfSONARBOUY->new(\%conf, \%ns, $dirname);
    if($ma->init != 0) {
      print "Couldn't initialize.\n";
      exit(-1);
    }

    # or
    # $ma = perfSONAR_PS::Services::MA::perfSONARBOUY->new;
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

=head1 SEE ALSO

L<Log::Log4perl>, L<File::Temp>, L<Time::HiRes>,
L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>,
L<perfSONAR_PS::DB::SQL>

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

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut


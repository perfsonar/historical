package perfSONAR_PS::Services::LS::LS;

use base 'perfSONAR_PS::Services::Base';

use fields;

use version; our $VERSION = qv("0.01");

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Time::HiRes qw(gettimeofday);
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Services::LS::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::XMLDB;

my %ls_namespaces = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  nmtm => "http://ggf.org/ns/nmwg/time/2.0/",
  ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  neterr => "http://ggf.org/ns/nmwg/characteristic/errors/2.0/",
  netdisc => "http://ggf.org/ns/nmwg/characteristic/discards/2.0/" ,
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
  perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
  psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/",
  xquery => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/",
  xpath => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xpath/1.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  nmwgtopo3 => "http://ggf.org/ns/nmwg/topology/base/3.0/",
  ctrlplane => "http://ogf.org/schema/network/topology/ctrlPlane/20070707/",
  CtrlPlane => "http://ogf.org/schema/network/topology/ctrlPlane/20070626/",
  ctrlplane_oct => "http://ogf.org/schema/network/topology/ctrlPlane/20071023/",
  ethernet => "http://ogf.org/schema/network/topology/ethernet/20070828/",
  ipv4 => "http://ogf.org/schema/network/topology/ipv4/20070828/",
  ipv6 => "http://ogf.org/schema/network/topology/ipv6/20070828/",
  nmtb => "http://ogf.org/schema/network/topology/base/20070828/",
  nmtl2 => "http://ogf.org/schema/network/topology/l2/20070828/",
  nmtl3 => "http://ogf.org/schema/network/topology/l3/20070828/",
  nmtl4 => "http://ogf.org/schema/network/topology/l4/20070828/",
  nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
  sonet => "http://ogf.org/schema/network/topology/sonet/20070828/",
  transport => "http://ogf.org/schema/network/topology/transport/20070828/"  
);


sub init($$) {
  my ($self, $handler) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::SNMP");

  # values that are deal breakers...

  if(!defined $self->{CONF}->{"ls"}->{"metadata_db_name"} or
     $self->{CONF}->{"ls"}->{"metadata_db_name"} eq "") {
    $logger->error("Value for 'metadata_db_name' is not set.");
    return -1;
  }
  else {
    if(defined $self->{DIRECTORY}) {
      if(!($self->{CONF}->{"ls"}->{"metadata_db_name"} =~ "^/")) {
        $self->{CONF}->{"ls"}->{"metadata_db_name"} = $self->{DIRECTORY}."/".$self->{CONF}->{"ls"}->{"metadata_db_name"};
      }
    }
  }

  if(!defined $self->{CONF}->{"ls"}->{"metadata_db_file"} or
     $self->{CONF}->{"ls"}->{"metadata_db_file"} eq "") {
    $logger->warn("Setting 'metadata_db_file' to 'store.dbxml'");
    $self->{CONF}->{"ls"}->{"metadata_db_file"} = "store.dbxml";
  }

  if (!defined $self->{CONF}->{"ls"}->{"ls_ttl"} or $self->{CONF}->{"ls"}->{"ls_ttl"} eq "") {
    $logger->warn("Setting 'ls_ttl' to '3600'.");
    $self->{CONF}->{"ls"}->{"ls_ttl"} = 3600;
  }

  if (!defined $self->{CONF}->{"ls"}->{"ls_repear_interval"}
		  or $self->{CONF}->{"ls"}->{"ls_repear_interval"} eq "") {
    $logger->warn("Setting 'ls_repear_interval' to '0'.");
    $self->{CONF}->{"ls"}->{"ls_repear_interval"} = 0;
  }

  $handler->addFullMessageHandler("LSRegisterRequest", $self);
  $handler->addFullMessageHandler("LSDeregisterRequest", $self);
  $handler->addFullMessageHandler("LSKeepaliveRequest", $self);
  $handler->addFullMessageHandler("LSQueryRequest", $self);
  $handler->addFullMessageHandler("LSLookupRequest", $self);

  return 0;
}

sub needLS($) {
	my ($self) = @_;

	return 0;
}

sub handleMessage($$$$$) {
	my ($self, $doc, $messageType, $message, $request) = @_;
	my $logger = get_logger("perfSONAR_PS::LS::LS");

	my $messageId = $request->getRequestDOM()->getDocumentElement->getAttribute("id");
	my $messageIdReturn = "message.".genuid();
	(my $messageTypeReturn = $messageType) =~ s/Request/Response/;

	startMessage($doc, $messageIdReturn, $messageId, $messageTypeReturn, "", undef);

	my $msgParams = find($request->getRequestDOM()->getDocumentElement, "./nmwg:parameters", 1);
	if($msgParams) {
		$msgParams = handleMessageParameters($self, $msgParams);
		$doc->addExistingXMLElement($msgParams);
	}

	if($messageType eq "LSRegisterRequest") {
		$logger->debug("Parsing LSRegister request.");
		lsRegisterRequest($self, $doc, $request);
	}
	elsif($messageType eq "LSDeregisterRequest") {
		$logger->debug("Parsing LSDeregister request.");
		lsDeregisterRequest($self, $doc, $request);
	}
	elsif($messageType eq "LSKeepaliveRequest") {
		$logger->debug("Parsing LSKeepalive request.");
		lsKeepaliveRequest($self, $doc, $request);
	}
	elsif($messageType eq "LSQueryRequest" or
			$messageType eq "LSLookupRequest") {
		$self->lsQueryRequest($doc, $request);
	}
	endMessage($doc);
}


sub handleMessageParameters {
  my($self, $msgParams) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  foreach my $p ($msgParams->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "parameter")) {
    if($p->getAttribute("name") eq "lsTTL") {
      $logger->debug("Found TTL parameter.");
      my $time = extract($p, 0);
      if($time < (int $self->{"CONF"}->{"ls"}->{"ls_ttl"}/2) or $time > $self->{"CONF"}->{"ls"}->{"ls_ttl"}) {
        if($p->getAttribute("value")) {
          $p->setAttribute("value", $self->{"CONF"}->{"ls"}->{"ls_ttl"});
        }
        elsif($p->childNodes) {
          if($p->firstChild->nodeType == 3) {
            my $oldChild = $p->removeChild($p->firstChild);
            $p->appendTextNode($self->{"CONF"}->{"ls"}->{"ls_ttl"});
          }
        }
      }
    }
  }
  return $msgParams;
}


sub prepareDatabases {
  my($self, $doc) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $error = "";

  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"ls"}->{"metadata_db_name"},
    $self->{CONF}->{"ls"}->{"metadata_db_file"},
    \%ls_namespaces,
  );
  $metadatadb->openDB("", \$error);

  if(!$error) {
    return $metadatadb;
  }
  else {
    $logger->error("There was an error opening \"".$self->{CONF}->{"ls"}->{"metadata_db_name"}."/".$self->{CONF}->{"ls"}->{"metadata_db_file"}."\": ".$error);
    statusReport($doc, "metadata.".genuid(), "", "data.".genuid(), "error.ls.xmldb", $error);
    return "";
  }
}


sub isValidKey {
  my($self, $metadatadb, $key) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");
  my $error = "";
  my $result = $metadatadb->queryByName($key, "", \$error);
  $logger->error($error) if $error;
  if($result) {
    $logger->debug("Key \"".$key."\" found in database.");
    return 1;
  }
  $logger->debug("Key \"".$key."\" not found in database.");
  return 0;
}


sub lsRegisterRequest {
  my($self, $doc, $request) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $metadatadb = prepareDatabases(\%{$self}, $doc);
  if(defined $metadatadb and $metadatadb ne "") {
    my %keys = ();
    my %ids = ();
    my $mdKey = "";
    my $mdId = "";
    my $dId = "";
    my($sec, $frac) = Time::HiRes::gettimeofday;

    # LS Registration Steps
    # ---------------------
    # Does MD have a key
    # Y: Is Key in the DB?
    #   Y: Did the key come with service info?
    #     Y: Remove all 'old' data, register the new information
    #     N: Update Control Info
    #        Is Data in DB?
    #       Y: 'success.ls.register'
    #       N: Insert, 'success.ls.register'
    #   N: Send 'error.ls.key_not_found' error
    # N: Is there an access point?
    #   Y: Is key in the DB?
    #     Y: Send 'error.ls.key_in_use' error
    #     N: Update Control Info, insert, 'success.ls.register'
    #   N: Send 'error.ls.registration.access_point_missing' error

    my $counter = 0;
    foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
      $counter++;
      my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
      if(defined $m) {

        # Does MD have a key
        $mdKey = extract(find($m, "./nmwg:key", 1), 0);
        if($mdKey) {

          $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
          if($mdKey) {
            # Y: Is Key in the DB?
            if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
              $keys{$mdKey} = isValidKey($self, $metadatadb, $mdKey);
              $ids{$mdKey} = 0;
            }

            if($keys{$mdKey} == 1 or $keys{$mdKey} == 2) {
              my $error;

              # surround the following things in a transaction that can be reversed
              my $dbTr = $metadatadb->getTransaction(\$error);
              if($dbTr and !$error) {
                my $errorFlag = 0;

                # Y: Did the key come with service info?
                my $service = extract(find($m, "./perfsonar:subject/psservice:service", 1), 0);
                if($service) {
                  # Y: access point valid?
                  my $accessPoint = extract(find($m, "./perfsonar:subject/psservice:service/psservice:accessPoint", 1), 0);
                  if($accessPoint) {
                    # Y: Remove all 'old' data, register the new information

                    if($keys{$mdKey} == 1) {
                      my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]", $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;
                      for(my $x = 0; $x <= $#resultsString; $x++) {
                        $logger->debug("Removing data \"".$resultsString[$x]."\".");
                        $metadatadb->remove($resultsString[$x], $dbTr, \$error);
                        $logger->error($error) and $errorFlag = 1 if $error;
                      }
                      $logger->debug("Removing control info \"".$mdKey."\".");
                      $metadatadb->remove($mdKey."-control", $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;

                      $logger->debug("Removing service info \"".$mdKey."\".");
                      $metadatadb->remove($mdKey, $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;

                      # this key may be gone, but mark it as changed (in case we have
                      #  more stuff in the message)
                      $keys{$mdKey} = 2;
                    }

                    # this is a 'new' key (in case we have more stuff in the message)
                    if(!$keys{$accessPoint}) {
                      $keys{$accessPoint} = 2;
                      $ids{$accessPoint} = 0;
                    }

                    # add metadata and control info
                    my $mdCopy = $m->cloneNode(1);
                    my $deadKey = $mdCopy->removeChild(find($mdCopy, "./nmwg:key", 1));
                    my $queryString = "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[\@id=\"".$accessPoint."\" and " . getMetadataXQuery($mdCopy, "") . "]";

                    my @resultsString = $metadatadb->query($queryString, $dbTr, \$error);
                    $logger->error($error) and $errorFlag = 1 if $error;
                    if($#resultsString == -1) {
                      $logger->debug("New registration info, inserting service metadata and time information.");
                      $mdCopy->setAttribute("id", $accessPoint);
                      $metadatadb->insertIntoContainer(wrapStore($mdCopy->toString, "LSStore"), $accessPoint, $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;
                      $metadatadb->insertIntoContainer(createControlKey($accessPoint, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $accessPoint."-control", $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;
                    }

                    # add data (as long as we don't have it already)
                    my $dCount = 0;
                    foreach my $d_content ($d->childNodes) {
                      if($d_content->getType != 3 and $d_content->getType != 8) {
                        my @dResultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$accessPoint."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, "") . "]", $dbTr, \$error);
                        $logger->error($error) and $errorFlag = 1 if $error;
                        if($#dResultsString == -1) {
                          $metadatadb->insertIntoContainer(createLSData($accessPoint."/".$sec."/".$ids{$accessPoint}, $accessPoint, $d_content->toString), $accessPoint."/".$sec."/".$ids{$accessPoint}, $dbTr, \$error);
                          $logger->error($error) and $errorFlag = 1 if $error;
                          $logger->debug("Inserting measurement metadata as \"".$accessPoint."/".$sec."/".$keys{$accessPoint}."\" for key \"".$accessPoint."\".");
                          $dCount++;
                          $ids{$accessPoint}++;
                        }
                      }
                    }

                    $metadatadb->commitTransaction($dbTr, \$error);
                    undef $dbTr;
                    $errorFlag .= " and " . $error if $error;
                    if(!$errorFlag) {
                      $mdId = "metadata.".genuid();
                      $dId = "data.".genuid();
                      createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($accessPoint, "success.ls.register"), undef);
                      createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$accessPoint."]\" />\n", undef);
                    }
                    else {
                      my $msg = "Database Error: \"" . $error . "\".";
                      $logger->error($error);
                      statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                      undef $dbTr;
                    }
                  }
                  else {
                    # N: Send 'error.ls.registration.access_point_missing' error
                    my $msg = "Cannont register data, accessPoint was not supplied.";
                    $logger->error($msg);
                    statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.access_point_missing", $msg);
                    $metadatadb->commitTransaction($dbTr, \$error);
                    undef $dbTr;
                  }
                }
                else {
                  # N: Update Control Info
                  if($keys{$mdKey} == 1) {
                    $logger->debug("Key already exists, updating control time information.");
                    $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
                    $keys{$mdKey} = 2;
                  }

                  # add data (as long as we don't have it already)
                  my $dCount = 0;
                  foreach my $d_content ($d->childNodes) {
                    if($d_content->getType != 3 and $d_content->getType != 8) {
                      my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, "") . "]", $dbTr, \$error);
                      $errorFlag .= " and " . $error if $error;
                      if($#resultsString == -1) {
                        $metadatadb->insertIntoContainer(createLSData($mdKey."/".$sec."/".$ids{$mdKey}, $mdKey, $d_content->toString), $mdKey."/".$sec."/".$ids{$mdKey}, $dbTr, \$error);
                        $errorFlag .= " and " . $error if $error;
                        $logger->debug("Inserting measurement metadata as \"".$mdKey."/".$sec."/".$keys{$mdKey}."\" for key \"".$mdKey."\".");
                        $dCount++;
                        $ids{$mdKey}++;
                      }
                    }
                  }

                  $metadatadb->commitTransaction($dbTr, \$error);
                  undef $dbTr;
                  if(!$errorFlag) {
                    $mdId = "metadata.".genuid();
                    $dId = "data.".genuid();
                    createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($mdKey, "success.ls.register"), undef);
                    createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been updated with key [".$mdKey."]\" />\n", undef);
                  }
                  else {
                    my $msg = "Database Error: \"" . $error . "\".";
                    $logger->error($error);
                    statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                    $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                    undef $dbTr;
                  }
                }
              }
              else {
                my $msg = "Cound not start database transaction.";
                $logger->error($error) if ($error);
                statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                undef $dbTr;
              }
            }
            else {
              # N: Send 'error.ls.key_not_found' error

              my $msg = "Key not found in database, is key \"".$mdKey."\" registered?";
              $logger->error($msg);
              statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.key_not_found", $msg);
            }
          }
          else {
            my $msg = "lsKey Attribute not found in message.";
            $logger->error($msg);
            statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.key_not_found", $msg);
          }

        }
        else {

          # N: Is there an access point?
          $mdKey = extract(find($m, "./perfsonar:subject/psservice:service/psservice:accessPoint", 1), 0);
          if($mdKey) {

            # Y: Is key in the DB?
            if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
              $keys{$mdKey} = isValidKey($self, $metadatadb, $mdKey);
              $ids{$mdKey} = 0;
            }

            my $error;

            # surround the following things in a transaction that can be reversed
            my $dbTr = $metadatadb->getTransaction(\$error);
            if($dbTr and !$error) {
              my $errorFlag = 0;

              # The item exists already, but lets see if the service info matches exactly,
              #  this is just like the key
              if($keys{$mdKey} == 1) {
                my $queryString = "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[\@id=\"".$mdKey."\" and " . getMetadataXQuery($m, "") . "]";
                my @resultsString = $metadatadb->query($queryString, $dbTr, \$error);
                $logger->error($error) and $errorFlag = 1 if $error;
                if($#resultsString >= 0) {
                  # We will let this slide, its the same stuff, update control info
                  $logger->debug("Key already exists, updating control time information.");
                  $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;
                  $keys{$mdKey} = 2;
                }
              }

              if($keys{$mdKey} == 0 or $keys{$mdKey} == 2) {
                # N: Update Control Info, insert, 'success.ls.register'

                if($keys{$mdKey} == 0) {
                  # set control info & mark us
                  $keys{$mdKey} = 2;

                  $logger->debug("New registration info, inserting service metadata and time information.");
                  my $service = $m->cloneNode(1);
                  $service->setAttribute("id", $mdKey);
                  $metadatadb->insertIntoContainer(wrapStore($service->toString, "LSStore"), $mdKey, $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;
                  $metadatadb->insertIntoContainer(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;
                }

                # deal with the data
                my $dCount = 0;
                foreach my $d_content ($d->childNodes) {
                  if($d_content->getType != 3 and $d_content->getType != 8) {
                    # only insert 'new' things
                    my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, "") . "]", $dbTr, \$error);
                    $logger->error($error) and $errorFlag = 1 if $error;
                    if($#resultsString == -1) {
                      $metadatadb->insertIntoContainer(createLSData($mdKey."/".$sec."/".$ids{$mdKey}, $mdKey, $d_content->toString), $mdKey."/".$sec."/".$ids{$mdKey}, $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;
                      $logger->debug("Inserting measurement metadata as \"".$mdKey."/".$sec."/".$keys{$mdKey}."\" for key \"".$mdKey."\".");
                      $dCount++;
                      $ids{$mdKey}++;
                    }
                  }
                }

                $metadatadb->commitTransaction($dbTr, \$error);
                $logger->error($error) and $errorFlag = 1 if $error;
                undef $dbTr;
                if(!$errorFlag) {
                  $mdId = "metadata.".genuid();
                  $dId = "data.".genuid();
                  createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($mdKey, "success.ls.register"), undef);
                  createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$mdKey."]\" />\n", undef);
                }
                else {
                  my $msg = "Database Error: \"" . $error . "\".";
                  $logger->error($error);
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                  $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                  undef $dbTr;
                }
              }
              else {
                # Y: Send 'error.ls.key_in_use' error
                my $msg = "AccessPoint \"".$mdKey."\" is in use, please update with key.";
                $logger->error($msg);
                statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.key_in_use", $msg);
                $metadatadb->commitTransaction($dbTr, \$error);
                undef $dbTr;
              }
            }
            else {
              my $msg = "Cound not start database transaction.";
              $logger->error($error) if ($error);
              statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
              $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
              undef $dbTr;
            }

          }
          else {
            # N: Send 'error.ls.registration.access_point_missing' error
            my $msg = "Cannont register data, accessPoint was not supplied.";
            $logger->error($msg);
            statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.access_point_missing", $msg);
          }
        }

      }
      else {
        my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
        $logger->error($msg);
        statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.registration.data_trigger", $msg);
      }
    }
    if(!$counter) {
      my $msg = "No data triggers found in request.";
      $logger->error($msg);
      statusReport($doc, "metadata.".genuid(), "", "data.".genuid(), "error.ls.registration.data_trigger_missing", $msg);
    }
    my $error;
    $metadatadb->closeDB(\$error);
    if($error) {
      $logger->error($error);
    }
  }
  else {
    $logger->error("Database could not be opened.");
  }
  return;
}


sub lsDeregisterRequest {
  my($self, $doc, $request) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $metadatadb = prepareDatabases(\%{$self}, $doc);
  if(defined $metadatadb and $metadatadb ne "") {
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

    my %ids = ();
    my $counter = 0;
    foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
      $counter++;
      my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
      if(defined $m) {

        $mdKey = extract(find($m, "./nmwg:key", 1), 0);
        if($mdKey) {

          $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
          if($mdKey) {

            # Y: Is Key in the DB?
            if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
              $keys{$mdKey} = isValidKey($self, $metadatadb, $mdKey);
              $ids{$mdKey} = 0;
            }

            if($keys{$mdKey} == 1 or $keys{$mdKey} == 2) {
              my $error;

              # surround the following things in a transaction that can be reversed
              my $dbTr = $metadatadb->getTransaction(\$error);
              if($dbTr and !$error) {
                my $errorFlag = 0;
                my $result = $metadatadb->queryByName($mdKey, $dbTr, \$error);
                $logger->error($error) and $errorFlag = 1 if $error;

                my @deregs = $d->getElementsByTagNameNS($ls_namespaces{"nmwg"}, "metadata");
                my @resultsString = ();
                my $msg = "";
                if($#deregs == -1) {
                  @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$result."\"]", $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;
                  for(my $x = 0; $x <= $#resultsString; $x++) {
                    $logger->debug("Removing data \"".$resultsString[$x]."\".");
                    $metadatadb->remove($resultsString[$x], $dbTr, \$error);
                    $logger->error($error) and $errorFlag = 1 if $error;
                  }

                  $logger->debug("Removing control info \"".$result."\".");
                  $metadatadb->remove($result."-control", $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;

                  $logger->debug("Removing service info \"".$result."\".");
                  $metadatadb->remove($result, $dbTr, \$error);
                  $logger->error($error) and $errorFlag = 1 if $error;

                  $msg = "Removed [".($#resultsString+1)."] data elements and service info for key \"".$result."\".";
                }
                else {
                  foreach my $d_md (@deregs) {
                    @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$result."\"]/nmwg:metadata[" . getMetadataXQuery($d_md, "") . "]", $dbTr, \$error);
                    $logger->error($error) and $errorFlag = 1 if $error;
                    for(my $x = 0; $x <= $#resultsString; $x++) {
                      $logger->debug("Removing data \"".$resultsString[$x]."\".");
                      $metadatadb->remove($resultsString[$x], $dbTr, \$error);
                      $logger->error($error) and $errorFlag = 1 if $error;
                    }
                  }
                  $msg = "Removed [".($#resultsString+1)."] data elements for key \"".$result."\".";
                }

                $metadatadb->commitTransaction($dbTr, \$error);
                undef $dbTr;
                $logger->error($error) and $errorFlag = 1 if $error;
                if(!$errorFlag) {
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "success.ls.deregister", $msg);
                }
                else {
                  my $msg = "Database Error: \"" . $error . "\".";
                  $logger->error($error);
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                  $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                  undef $dbTr;
                }
              }
              else {
                my $msg = "Cound not start database transaction.";
                $logger->error($error) if ($error);
                statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                undef $dbTr;
              }
            }
            else {
              # N: Send 'error.ls.deregister.key_not_found' error

              my $msg = "Sent key \"".$mdKey."\" was not registered.";
              $logger->error($msg);
              statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.deregister.key_not_found", $msg);
            }
          }
          else {
            my $msg = "lsKey Attribute not found in message.";
            $logger->error($msg);
            statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.deregister.key_not_found", $msg);
          }
        }
        else {
          my $msg = "Key not found in sent metadata.";
          $logger->error($msg);
          statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.deregister.key_not_found", $msg);
        }
      }
      else {
        my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
        $logger->error($msg);
        statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.deregister.data_trigger", $msg);
      }
    }
    if(!$counter) {
      my $msg = "No data triggers found in request.";
      $logger->error($msg);
      statusReport($doc, "metadata.".genuid(), "", "data.".genuid(), "error.ls.deregister.data_trigger_missing", $msg);
    }

    my $error;
    $metadatadb->closeDB(\$error);
    if($error) {
      $logger->error($error);
    }
  }
  else {
    $logger->error("Database could not be opened.");
  }
  return;
}


sub lsKeepaliveRequest {
  my($self, $doc, $request) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $metadatadb = prepareDatabases(\%{$self}, $doc);
  if(defined $metadatadb and $metadatadb ne "") {
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

    my %ids = ();
    my $counter = 0;
    foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
      $counter++;
      my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
      if(defined $m) {

        $mdKey = extract(find($m, "./nmwg:key", 1), 0);
        if($mdKey) {

          $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
          if($mdKey) {

            # Y: Is Key in the DB?
            if(!$keys{$mdKey} or $keys{$mdKey} eq "") {
              $keys{$mdKey} = isValidKey($self, $metadatadb, $mdKey);
              $ids{$mdKey} = 0;
            }

            if($keys{$mdKey} == 1 or $keys{$mdKey} == 2) {
              my $error;

              # surround the following things in a transaction that can be reversed
              my $dbTr = $metadatadb->getTransaction(\$error);
              if($dbTr and !$error) {
                my $errorFlag = 0;

                $logger->debug("Updating control time information.");
                $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
                $logger->error($error) and $errorFlag = 1 if $error;

                $metadatadb->commitTransaction($dbTr, \$error);
                undef $dbTr;
                $logger->error($error) and $errorFlag = 1 if $error;
                if(!$errorFlag) {
                  my $msg = "Key \"".$mdKey."\" was updated.";
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "success.ls.keepalive", $msg);
                }
                else {
                  my $msg = "Database Error: \"" . $error . "\".";
                  $logger->error($error);
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                  $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                  undef $dbTr;
                }
              }
              else {
                my $msg = "Cound not start database transaction.";
                $logger->error($error) if ($error);
                statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                undef $dbTr;
              }
            }
            else {
              # N: Send 'error.ls.keepalive.key_not_found' error

              my $msg = "Sent key \"".$mdKey."\" was not registered.";
              $logger->error($msg);
              statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.keepalive.key_not_found", $msg);
            }
          }
          else {
            my $msg = "lsKey Attribute not found in message.";
            $logger->error($msg);
            statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.keepalive.key_not_found", $msg);
          }
        }
        else {
          my $msg = "Key not found in sent metadata.";
          $logger->error($msg);
          statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.keepalive.key_not_found", $msg);
        }
      }
      else {
        my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
        $logger->error($msg);
        statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.keepalive.data_trigger", $msg);
      }
    }
    if(!$counter) {
      my $msg = "No data triggers found in request.";
      $logger->error($msg);
      statusReport($doc, "metadata.".genuid(), "", "data.".genuid(), "error.ls.keepalive.data_trigger_missing", $msg);
    }
    my $error;
    $metadatadb->closeDB(\$error);
    if($error) {
      $logger->error($error);
    }
  }
  else {
    $logger->error("Database could not be opened.");
  }
  return;
}


sub lsQueryRequest {
  my($self, $doc, $request) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  my $metadatadb = prepareDatabases(\%{$self}, $doc);
  if(defined $metadatadb and $metadatadb ne "") {

    my $query = "";
    my $queryType = "";
    my $error = "";
    my $mdId = "";
    my $dId = "";
    my($sec, $frac) = Time::HiRes::gettimeofday;

    # LS Query Steps
    # ---------------------
    # Does MD have an xquery:subject (support more later)
    # Y: does it have an eventType?
    #   Y: Supported eventType?
    #     Y: Send query to DB, perpare results
    #     N: Send 'error.ls.querytype_not_suported' error
    #   N: Send 'error.ls.no_querytype' error
    # N: Send 'error.ls.query.query_not_found' error

    my $counter = 0;
    foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
      $counter++;
      my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
      if(defined $m) {
        $query = extractQuery(find($m, "./xquery:subject", 1));
        if($query) {
          $queryType = extract(find($m, "./nmwg:eventType", 1), 0);
          if($queryType) {
            if($queryType eq "service.lookup.xquery" or
               $queryType eq "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0") {
              $query =~ s/\s+\// collection('CHANGEME')\//g;

              my @resultsString = ();
              my $dbTr = $metadatadb->getTransaction(\$error);
              if($dbTr and !$error) {
                @resultsString = $metadatadb->query($query, $dbTr, \$error);
                $metadatadb->commitTransaction($dbTr, \$error) if (!$error);
                undef $dbTr;
                if(!$error) {
                  my $dataString = "";
                  for(my $x = 0; $x <= $#resultsString; $x++) {
                    $dataString = $dataString . $resultsString[$x];
                  }
                  $mdId = "metadata.".genuid();
                  $dId = "data.".genuid();
                  if($dataString) {
                    createMetadata($doc, $mdId, $m->getAttribute("id"), "", undef);
                    my $parameters = "";
                    if(find($m, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1)) {
                      $parameters = extractQuery(find($m, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
                    }
                    else {
                      if(find($m, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1)) {
                        $parameters = extractQuery(find($m, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
                      }
                    }
                    if($parameters eq "native") {
                      createData($doc, $dId, $mdId, "      <psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".$dataString."</psservice:datum>\n", undef);
                    }
                    else {
                      createData($doc, $dId, $mdId, "      <psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".escapeString($dataString)."</psservice:datum>\n", undef);
                    }
                  }
                  else {
                    my $msg = "Nothing returned for search.";
                    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.query.empty_results", $msg);
                  }
                }
                else {
                  my $msg = "Database Error: \"" . $error . "\".";
                  $logger->error($error);
                  statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                  $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                  undef $dbTr;
                }
              }
              else {
                my $msg = "Cound not start database transaction.";
                $logger->error($error) if ($error);
                statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", $msg);
                $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
                undef $dbTr;
              }
            }
            else {
              my $msg = "Given query type is not supported ";
              $logger->error($msg);
              statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.query.type_not_supported", $msg);
            }
          }
          else {
            my $msg = "No query type in message";
            $logger->error($msg);
            statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.query.no_querytype", $msg);
          }
        }
        else {
          my $msg = "Query not found in sent metadata.";
          $logger->error($msg);
          statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.query.query_not_found", $msg);
        }
      }
      else {
        my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
        $logger->error($msg);
        statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.query.data_trigger", $msg);
      }
    }
    if(!$counter) {
      my $msg = "No data triggers found in request.";
      $logger->error($msg);
      statusReport($doc, "metadata.".genuid(), "", "data.".genuid(), "error.ls.query.data_trigger_missing", $msg);
    }
    $metadatadb->closeDB(\$error);
    if($error) {
      $logger->error($error);
    }
  }
  else {
    $logger->error("Database could not be opened.");
  }
  return;
}


1;


__END__

=head1 NAME

perfSONAR_PS::LS::LS - A module that provides methods for the single domain LS (sLS).

=head1 DESCRIPTION

This module provides functionality to accept various forms of message and interact with
an XML Database to store and return various forms of XML based information.

=head1 SYNOPSIS

    use perfSONAR_PS::LS::LS;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/LS/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    $conf{"METADATA_DB_CONTROL_FILE"} = "control.dbxml";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
      select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
      perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
      psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/",
      xquery => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/",
      xpath => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xpath/1.0/"
    );

    my $ls = perfSONAR_PS::LS::LS->new(\%conf, \%ns);

    # or
    # $ls = perfSONAR_PS::LS::LS->new;
    # $ls->setConf(\%conf);
    # $ls->setNamespaces(\%ns);

    $ls->init;
    while(1) {
      $ls->receive;
    }

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an LS.

=head1 API

The offered API is simple, but offers the key functions we need in a lookup service.

=head2 init($self)

Initialize the underlying transportation medium.  This function depends
on certain conf file values.

=head2 receive($self)

Receives messages from the Transport.pm module above and acts upon them.

=head2 handleRequest($self, $request, $doc)

Functions as the 'gatekeeper' the the MA.  Will either reject or accept
requets.  will also 'do nothing' in the event that a request has been
acted on by the lower layer.

=head2 __handleRequest($self, $request, $doc)

Based on the type of message that enters this service, route to the proper handling code.

=head2 handleMessageParameters($self, $msgParams)

Extracts and acts on any message level parameters this service may recognize.  Not to be
used externally.

=head2 prepareDatabases($self, $doc)

Opens the databases, returns errors if applicable.  Not to be used externally.

=head2 isValidKey($self, $metadatadb, $key)

Given a key, check to see if it is in the database yet.

=head2 lsRegisterRequest($self, $doc, $request)

Acts on LSRegisterRequest messages.  Not to be used externally.

=head2 lsDeregisterRequest($self, $doc, $request)

Acts on LSDeregisterRequest messages.  Not to be used externally.

=head2 lsKeepaliveRequest($self, $doc, $request)

Acts on LSKeepaliveRequest messages.  Not to be used externally.

=head2 lsQueryRequest($self, $doc, $request)

Acts on LSQueryRequest messages.  Not to be used externally.

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<File::Temp>, L<Time::HiRes>,
L<perfSONAR_PS::LS::Base>, L<perfSONAR_PS::MA::General>,
L<perfSONAR_PS::LS::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::XMLDB>

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

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut


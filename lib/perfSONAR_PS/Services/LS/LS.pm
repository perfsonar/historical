package perfSONAR_PS::Services::LS::LS;

use base 'perfSONAR_PS::Services::Base';

use fields;

use strict;
use warnings;

our $VERSION = 0.07;

=head1 NAME

perfSONAR_PS::Services::LS::LS - A module that provides methods for the 
perfSONAR-PS Single Domain Lookup Service (LS).

=head1 DESCRIPTION

This module, in conjunction with other parts of the perfSONAR-PS framework,
handles specific messages from interested actors in search of data and services
that are registered with the LS.  There are four major message types that this
service can act upon:

 - LSRegisterRequest   - Given the name of a service and the metadata it
                         contains, register this information into the LS.
                         Special considerations should be given to already
                         registered services that wish to augment already
                         registered data.
 - LSDeregisterRequest - Removes all or selective data about a specific service
                         already registered in the LS.
 - LSKeepaliveRequest  - Given some info about already registered data (i.e. a 
                         'key') update the internal state to reflect that this
                         service and it's data are still alive and valid.
 - LSQueryRequest      - Given a descriptive query (written in the XPath or
                         XQuery langugages) return any relevant data or a 
                         descriptive error message.

The LS in general offers a web services (WS) interface to the Berkeley/Oracle
DB XML, a native XML database.   

=cut

use Log::Log4perl qw(get_logger);
use Time::HiRes qw(gettimeofday);
use Params::Validate qw(:all);
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
  iperf => "http://ggf.org/ns/nmwg/tools/iperf/2.0/",
  bwctl => "http://ggf.org/ns/nmwg/tools/bwctl/2.0/",
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

=head1 API

The offered API is not meant for external use as many of the functions are
relied upon by internal aspects of the perfSONAR-PS framework.

=head2 init($self, $handler)

Called at startup by the daemon when this particular module is loaded into
the perfSONAR-PS deployment.  Checks the configuration file for the necessary
items and fills in others when needed. Initializes the backed metadata storage
(DB XML).  Finally the message handler loads the appropriate message types and
eventTypes for this module.  Any other 'pre-startup' tasks should be placed in
this function.

=cut

sub init {
  my ($self, $handler) = @_;
  $self->{CONF}->{"ls"}->{"logger"} = get_logger("perfSONAR_PS::Services::LS::LS");

  unless(exists $self->{CONF}->{"ls"}->{"metadata_db_name"} and
         $self->{CONF}->{"ls"}->{"metadata_db_name"}) {
    $self->{CONF}->{"ls"}->{"logger"}->error("Value for 'metadata_db_name' is not set.");
    return -1;
  }
  else {
    if(exists $self->{DIRECTORY}) {
      unless($self->{CONF}->{"ls"}->{"metadata_db_name"} =~ "^/") {
        $self->{CONF}->{"ls"}->{"metadata_db_name"} = $self->{DIRECTORY}."/".$self->{CONF}->{"ls"}->{"metadata_db_name"};
      }
    }
  }

  unless(exists $self->{CONF}->{"ls"}->{"metadata_db_file"} and
         $self->{CONF}->{"ls"}->{"metadata_db_file"}) {
    $self->{CONF}->{"ls"}->{"logger"}->warn("Setting 'metadata_db_file' to 'store.dbxml'");
    $self->{CONF}->{"ls"}->{"metadata_db_file"} = "store.dbxml";
  }

  unless(exists $self->{CONF}->{"ls"}->{"ls_ttl"} and $self->{CONF}->{"ls"}->{"ls_ttl"}) {
    $self->{CONF}->{"ls"}->{"logger"}->warn("Setting 'ls_ttl' to '3600'.");
    $self->{CONF}->{"ls"}->{"ls_ttl"} = 3600;
  }

  unless(exists $self->{CONF}->{"ls"}->{"ls_repear_interval"} and 
         $self->{CONF}->{"ls"}->{"ls_repear_interval"}) {
    $self->{CONF}->{"ls"}->{"logger"}->warn("Setting 'ls_repear_interval' to '0'.");
    $self->{CONF}->{"ls"}->{"ls_repear_interval"} = 0;
  }

  $handler->registerFullMessageHandler("LSRegisterRequest", $self);
  $handler->registerFullMessageHandler("LSDeregisterRequest", $self);
  $handler->registerFullMessageHandler("LSKeepaliveRequest", $self);
  $handler->registerFullMessageHandler("LSQueryRequest", $self);
  $handler->registerFullMessageHandler("LSLookupRequest", $self);

  my $error = q{};
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"ls"}->{"metadata_db_name"},
    $self->{CONF}->{"ls"}->{"metadata_db_file"},
    \%ls_namespaces,
  );
  unless($metadatadb->openDB(q{}, \$error) == 0) {
    $self->{CONF}->{"ls"}->{"logger"}->error("There was an error opening \"".$self->{CONF}->{"ls"}->{"metadata_db_name"}."/".$self->{CONF}->{"ls"}->{"metadata_db_file"}."\": ".$error);
    return -1;
  }
  $metadatadb->closeDB(\$error);

  return 0;
}

=head2 needLS($self)

Stub function that would allow the LS to register with another LS.  This is
currently disabled.

=cut

sub needLS {
	my ($self) = @_;

	return 0;
}

=head2 handleMessage($self, $doc, $messageType, $message, $request)

Given a message from the Transport module, this function will route
the message to the appropriate location based on message type.

=cut

sub handleMessage {
  my($self, @parameters) = @_;
	my $args = validate(@parameters, 
			{
				output => { type => ARRAYREF, isa => "perfSONAR_PS::XML::Document_string" },
				messageId => { type => SCALAR | UNDEF },
				messageType => { type => SCALAR },
				message => { type => SCALARREF },
				rawRequest => { type => ARRAYREF },
			});

	my $doc = $args->{"output"};
	my $messageType = $args->{"messageType"};
	my $messageId = $args->{"messageId"};
	my $message = $args->{"message"};
	my $request = $args->{"rawRequest"};

	my $messageIdReturn = "message.".genuid();
	(my $messageTypeReturn = $messageType) =~ s/Request/Response/xm;

	startMessage($doc, $messageIdReturn, $messageId, $messageTypeReturn, q{}, undef);

	my $msgParams = find($request->getRequestDOM()->getDocumentElement, "./nmwg:parameters", 1);
	if($msgParams) {
		$msgParams = $self->handleMessageParameters({ msgParams => $msgParams});
		$doc->addExistingXMLElement($msgParams);
	}

	if($messageType eq "LSRegisterRequest") {
		$self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSRegister request.");
		lsRegisterRequest($self, $doc, $request);
		endMessage($doc);
		return;
	}
	if($messageType eq "LSDeregisterRequest") {
		$self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSDeregister request.");
		lsDeregisterRequest($self, $doc, $request);
		endMessage($doc);
		return;
	}
	if($messageType eq "LSKeepaliveRequest") {
		$self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSKeepalive request.");
		lsKeepaliveRequest($self, $doc, $request);
		endMessage($doc);
		return;
	}
	if($messageType eq "LSQueryRequest" or
			$messageType eq "LSLookupRequest") {
		$self->lsQueryRequest($doc, $request);
		endMessage($doc);
		return;
	}

  # default case?
	$self->{CONF}->{"ls"}->{"logger"}->error("Unrecognized message type");
  statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.messages", q{});
	endMessage($doc);
	
	return;
}

=head2 handleMessageParameters($self, $msgParams)

Looks in the mesage for any parameters and sets appropriate variables if
applicable.

=cut

sub handleMessageParameters {
  my ( $self, @args ) = @_;
  my $parameters = validate(
      @args,
      {
          msgParams             => 1
      }
  );  
  
  foreach my $p ($parameters->{msgParams}->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "parameter")) {
    if($p->getAttribute("name") eq "lsTTL") {
      $self->{CONF}->{"ls"}->{"logger"}->debug("Found TTL parameter.");
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
  return $parameters->{msgParams};
}

=head2 prepareDatabases($self, $doc)

Opens the XMLDB and returns the handle if there was not an error.

=cut

sub prepareDatabases {
  my ( $self, @args ) = @_;
  my $parameters = validate(
      @args,
      {
          doc             => 1
      }
  );
  
  my $error = q{};
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"ls"}->{"metadata_db_name"},
    $self->{CONF}->{"ls"}->{"metadata_db_file"},
    \%ls_namespaces,
  );
  unless($metadatadb->openDB(q{}, \$error) == 0) {
    $self->{CONF}->{"ls"}->{"logger"}->error("There was an error opening \"".$self->{CONF}->{"ls"}->{"metadata_db_name"}."/".$self->{CONF}->{"ls"}->{"metadata_db_file"}."\": ".$error);
    statusReport($parameters->{doc}, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $error);
    return;
  }
  return $metadatadb;
}

=head2 isValidKey($self, $metadatadb, $key)

This function will check to see if a key found in a request message is
a valid key in the datbase.  

=cut

sub isValidKey {
  my ( $self, @args ) = @_;
  my $parameters = validate(
      @args,
      {
          metadatadb      => 1,
          key             => 1
      }
  );
  my $error = q{};
  my $result = $parameters->{metadatadb}->queryByName($parameters->{key}, q{}, \$error);
  if($result) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Key \"".$parameters->{key}."\" found in database.");
    return 1;
  }
  $self->{CONF}->{"ls"}->{"logger"}->debug("Key \"".$parameters->{key}."\" not found in database.");
  return 0;
}

=head2 lsRegisterRequest($self, $doc, $request)

The LSRegisterRequest procedure allows services (both previously registered
and new) the ability to register data with the LS.  In the case of previously
registered services it is possible to augment a data set with new information
by supplying your previously issued key, or change an existing registration
(i.e. if the service info has changed) and subsequently un and re-register
all data.  Responses should indicate success and failure for the datasets that
were registered.  This function is split into sub functions described below.

The following is a brief outline of the procedures:

    Does MD have a key
    Y: Update of registration, Is there a service element?
      Y: Old style 'clobber' update, pass to lsRegisterRequestUpdateNew
      N: New style 'append' update, pass to lsRegisterRequestUpdate
    N: This is a 'new' registration, pass to lsRegisterRequestNew
    
=cut

sub lsRegisterRequest {
  my($self, $doc, $request) = @_;

  my $metadatadb = $self->prepareDatabases({ doc => $doc });
  unless($metadatadb) {
    my $msg = "Database could not be opened.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $msg);   
    return;
  }
  
  my %keys = ();
  my $error = q{};
  my $counter = 0;
  my($sec, $frac) = Time::HiRes::gettimeofday;
  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
    $counter++;

    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    unless($m) {
      my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.keepalive.data_trigger", $msg);
      next;
    }

    my $error = q{};
    my $dbTr = $metadatadb->getTransaction(\$error);
    unless($dbTr) {
      statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      return;
    }

    my $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
    if($mdKey) {
      unless(exists $keys{$mdKey}) {
        $keys{$mdKey} = $self->isValidKey({ metadatadb => $metadatadb, key => $mdKey});
      }

      unless($keys{$mdKey}) {
        my $msg = "Sent key \"".$mdKey."\" was not registered.";
        $self->{CONF}->{"ls"}->{"logger"}->error($msg);
        statusReport($doc, "metadata.".genuid(), $m->getAttribute("id"), "data.".genuid(), "error.ls.register.key_not_found", $msg);
        next;
      }      
      
      my $service = extract(find($m, "./perfsonar:subject/psservice:service", 1), 0);
      if($service) {
        $self->lsRegisterRequestUpdateNew($doc, $request, $metadatadb, $dbTr, $m, $d, $mdKey, $service, $sec);
      }
      else {
        $self->lsRegisterRequestUpdate($doc, $request, $metadatadb, $dbTr, $m, $d, $mdKey, $sec);
      }
    }
    else {
      $self->lsRegisterRequestNew($doc, $request, $metadatadb, $dbTr, $m, $d, $sec);
    }
  }
  
  unless($counter) {
    my $msg = "No data triggers found in request.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.registration.data_trigger_missing", $msg);
  }
  
  $metadatadb->closeDB(\$error);
  return;
}

=head2 lsRegisterRequestUpdateNew($self, $doc, $request, $metadatadb, $m, $d, $mdKey, $service, $sec)

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the 'clobber' update.  Namely there is data for a given key in the
database already (will be verified) and the user wishes to update the service
info and delete all existing data, and replace it with new sent data.  This
essentually amounts to a deregistration, and reregistration.  

The following is a brief outline of the procedures:

    Does service info have an accessPoint
    Y: Remove old info, add new info
    N: Error Out

=cut

sub lsRegisterRequestUpdateNew {
  my($self, $doc, $request, $metadatadb, $dbTr, $m, $d, $mdKey, $service, $sec) = @_;
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();

  my $accessPoint = extract(find($m, "./perfsonar:subject/psservice:service/psservice:accessPoint", 1), 0);
  unless($accessPoint) {
    my $msg = "Cannont register data, accessPoint was not supplied.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.registration.access_point_missing", $msg);
    return;
  }

  my $error = q{};
  my $errorFlag = 0;

  my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]", $dbTr, \$error);
  my $len = $#resultsString;
  $self->{CONF}->{"ls"}->{"logger"}->debug("Removing all info for \"".$mdKey."\".");
  for my $x (0..$len) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Removing data \"".$resultsString[$x]."\".");
    $metadatadb->remove($resultsString[$x], $dbTr, \$error);
  }
  $metadatadb->remove($mdKey."-control", $dbTr, \$error);
  $metadatadb->remove($mdKey, $dbTr, \$error);

  my $mdCopy = $m->cloneNode(1);
  my $deadKey = $mdCopy->removeChild(find($mdCopy, "./nmwg:key", 1));
  my $queryString = "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[\@id=\"".$accessPoint."\" and " . getMetadataXQuery($mdCopy, q{}) . "]";
  my @resultsString = $metadatadb->query($queryString, $dbTr, \$error);
  if($#resultsString == -1) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("New registration info, inserting service metadata and time information.");
    $mdCopy->setAttribute("id", $accessPoint);
    $metadatadb->insertIntoContainer(wrapStore($mdCopy->toString, "LSStore"), $accessPoint, $dbTr, \$error);
    $metadatadb->insertIntoContainer(createControlKey($accessPoint, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $accessPoint."-control", $dbTr, \$error);
  }

  my $dCount = 0;
  foreach my $d_content ($d->childNodes) {
    my($sec2, $frac2) = Time::HiRes::gettimeofday;
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, q{}) . "]", $dbTr, \$error);
      if($#resultsString == -1) {
        $metadatadb->insertIntoContainer(createLSData($accessPoint."/".$sec."/".$sec2.$frac2.$dCount, $accessPoint, $d_content->toString), $accessPoint."/".$sec."/".$sec2.$frac2.$dCount, $dbTr, \$error);
        $errorFlag++ if $error;
        $self->{CONF}->{"ls"}->{"logger"}->debug("Inserting measurement metadata as \"".$accessPoint."/".$sec."/".$sec2.$frac2.$dCount."\" for key \"".$accessPoint."\".");
        $dCount++;
      }
    }
  }

  if($errorFlag) {
    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database errors prevented the transaction from completing.");
    $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
  }
  else {  
    my $status = $metadatadb->commitTransaction($dbTr, \$error);
    if($status == 0) {
      createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($accessPoint, "success.ls.register"), undef);
      createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$accessPoint."]\" />\n", undef);      
    }
    else {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;  
    }   
  }
  undef $dbTr;
  return;
}

=head2 lsRegisterRequestUpdate($self, $doc, $request, $metadatadb, $m, $d, $mdKey, $sec)

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the 'append' update.  Namely there is data for a given key in the
database already (will be verified) and the user wishes to add more data to this
set.  The key will already have been verified in the previous step, so the
control info is simply updated, and the new data is appended.

=cut

sub lsRegisterRequestUpdate {
  my($self, $doc, $request, $metadatadb, $dbTr, $m, $d, $mdKey, $sec) = @_;
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
  
  my $error = q{};
  my $errorFlag = 0;
  
  $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists, updating control time information.");
  $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
  $errorFlag++ if $error;
       
  my $dCount = 0;
  foreach my $d_content ($d->childNodes) {
    my($sec2, $frac2) = Time::HiRes::gettimeofday;
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, q{}) . "]", $dbTr, \$error);
      if($#resultsString == -1) {
        $metadatadb->insertIntoContainer(createLSData($mdKey."/".$sec."/".$sec2.$frac2.$dCount, $mdKey, $d_content->toString), $mdKey."/".$sec."/".$sec2.$frac2.$dCount, $dbTr, \$error);
        $errorFlag++ if $error;
        $self->{CONF}->{"ls"}->{"logger"}->debug("Inserting measurement metadata as \"".$mdKey."/".$sec."/".$sec2.$frac2.$dCount."\" for key \"".$mdKey."\".");
        $dCount++;
      }
    }
  }

  if($errorFlag) {
    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database errors prevented the transaction from completing.");
    $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
  }
  else {  
    my $status = $metadatadb->commitTransaction($dbTr, \$error);
    if($status == 0) {
      createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($mdKey, "success.ls.register"), undef);
      createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been updated with key [".$mdKey."]\" />\n", undef);         
    }
    else {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;  
    }   
  }
  undef $dbTr;

  return;
}

=head2 lsRegisterRequestNew()

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the brand new addition.  We will check to be sure that the data does
not already exist, if it does we treat this as an 'append' update.  

The following is a brief outline of the procedures:

    Does service info have an accessPoint
    Y: Is the key already in the database
      Y: Is the service info exactly the same
        Y: Treat this as an append, add things and update key
        N: Error out (to be safe, ask them to provide a key)
      N: Create a key, add data
    N: Error Out

=cut

sub lsRegisterRequestNew {
  my($self, $doc, $request, $metadatadb, $dbTr, $m, $d, $sec) = @_;
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
  
  my $mdKey = extract(find($m, "./perfsonar:subject/psservice:service/psservice:accessPoint", 1), 0);
  unless($mdKey) {
    my $msg = "Cannont register data, accessPoint was not supplied.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.registration.access_point_missing", $msg);
    return;
  }

  my $error = q{};
  my $errorFlag = 0;
    
  if($self->isValidKey({ metadatadb => $metadatadb, key => $mdKey})) {
    my $queryString = "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[\@id=\"".$mdKey."\" and " . getMetadataXQuery($m, q{}) . "]";
    my @resultsString = $metadatadb->query($queryString, q{}, \$error);
    if($#resultsString == -1) {
      my $msg = "AccessPoint \"".$mdKey."\" is in use by another service, try updating with the lsKey.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.registration.key_in_use", $msg);
      return;            
    }
    $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists, but updating control time information anyway.");
    $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
    $errorFlag++ if $error;
  }
  else {
    $self->{CONF}->{"ls"}->{"logger"}->debug("New registration info, inserting service metadata and time information.");
    my $service = $m->cloneNode(1);
    $service->setAttribute("id", $mdKey);
    $metadatadb->insertIntoContainer(wrapStore($service->toString, "LSStore"), $mdKey, $dbTr, \$error);
    $errorFlag++ if $error;
    $metadatadb->insertIntoContainer(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);
    $errorFlag++ if $error;
  }
  
  my $dCount = 0;
  foreach my $d_content ($d->childNodes) {
    my($sec2, $frac2) = Time::HiRes::gettimeofday;
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/".$d_content->nodeName."[" . getMetadataXQuery($d_content, q{}) . "]", $dbTr, \$error);
      if($#resultsString == -1) {
        $metadatadb->insertIntoContainer(createLSData($mdKey."/".$sec."/".$sec2.$frac2.$dCount, $mdKey, $d_content->toString), $mdKey."/".$sec."/".$sec2.$frac2.$dCount, $dbTr, \$error);
        $errorFlag++ if $error;
        $self->{CONF}->{"ls"}->{"logger"}->debug("Inserting measurement metadata as \"".$mdKey."/".$sec."/".$sec2.$frac2.$dCount."\" for key \"".$mdKey."\".");
        $dCount++;
      }
    }
  }

  if($errorFlag) {
    statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database errors prevented the transaction from completing.");
    $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
  }
  else {  
    my $status = $metadatadb->commitTransaction($dbTr, \$error);
    if($status == 0) {
      createMetadata($doc, $mdId, $m->getAttribute("id"), createLSKey($mdKey, "success.ls.register"), undef);
      createData($doc, $dId, $mdId, "      <nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$mdKey."]\" />\n", undef);      
    }
    else {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;  
    }   
  }
  undef $dbTr;
  return;
}

=head2 lsDeregisterRequest($self, $doc, $request)

The LSDeregisterRequest message should contain a key of an already registered
service, and then optionally any specific data to be removed (absense of data
indicates we want removal of ALL data).  After checking the validity of the key
and if possible any sent data, the items will be removed from the database.  The
response message will indicate success or failure.

The following is a brief outline of the procedures:

    Does MD have a key
    Y: Is Key in the DB?
      Y: Are there metadata blocks in the data section?
        Y: Remove ONLY the data for that service/control
        N: Deregister the service, all data, and remove the control
      N: Send 'error.ls.key_not_found' error
    N: Send 'error.ls.deregister.key_not_found' error

=cut

sub lsDeregisterRequest {
  my($self, $doc, $request) = @_;

  my $metadatadb = $self->prepareDatabases({ doc => $doc });
  unless($metadatadb) {
    my $msg = "Database could not be opened.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $msg);   
    return;
  }
  
  my %keys = ();
  my $error = q{};
  my $counter = 0;
  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
    my $msg = q{};
    my $mdId = "metadata.".genuid();
    my $dId = "data.".genuid();
    $counter++;

    # handle the error conditions first

    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    unless($m) {
      $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.deregister.data_trigger", $msg);
      next;
    }

    my $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
    unless($mdKey) {
      $msg = "Key not found in message.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.deregister.key_not_found", $msg);
      next;
    }

    # see if we verified this key yet (we dont want to run the validator that often)
    unless(exists $keys{$mdKey}) {
      $keys{$mdKey} = $self->isValidKey({ metadatadb => $metadatadb, key => $mdKey});
    }

    # if it's invalid, then we can't do much
    unless($keys{$mdKey}) {
      $msg = "Sent key \"".$mdKey."\" was not registered.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.deregister.key_not_found", $msg);
      next;
    }

    # grab a DB transaction so we can roll back if need be
    my $dbTr = $metadatadb->getTransaction(\$error);
    unless($dbTr) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      next;
    }

    # perform the removal of everything, or just certain data items

    my @resultsString = ();
    my $errorFlag = 0;
    my @deregs = $d->getElementsByTagNameNS($ls_namespaces{"nmwg"}, "metadata");
    if($#deregs == -1) {
      $self->{CONF}->{"ls"}->{"logger"}->debug("Removing all info for \"".$mdKey."\".");
      @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]", q{}, \$error);
      my $len = $#resultsString;
      for my $x (0..$len) {
        $self->{CONF}->{"ls"}->{"logger"}->debug("Removing data \"".$resultsString[$x]."\".");
        $metadatadb->remove($resultsString[$x], $dbTr, \$error);
        $errorFlag++ if $error;
      }
      $metadatadb->remove($mdKey."-control", $dbTr, \$error);
      $errorFlag++ if $error;
      $metadatadb->remove($mdKey, $dbTr, \$error);
      $errorFlag++ if $error;
      $msg = "Removed [".($#resultsString+1)."] data elements and service info for key \"".$mdKey."\".";
    }
    else {
      $self->{CONF}->{"ls"}->{"logger"}->debug("Removing selected info for \"".$mdKey."\", keeping record.");
      foreach my $d_md (@deregs) {
        @resultsString = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/nmwg:metadata[" . getMetadataXQuery($d_md, q{}) . "]", $dbTr, \$error);
        my $len = $#resultsString;
        for my $x (0..$len) {
          $self->{CONF}->{"ls"}->{"logger"}->debug("Removing data \"".$resultsString[$x]."\".");
          $metadatadb->remove($resultsString[$x], $dbTr, \$error);
          $errorFlag++ if $error;
        }
      }
      $msg = "Removed [".($#resultsString+1)."] data elements for key \"".$mdKey."\".";
    }

    # commit the transaction, or error if there are problems
    if($errorFlag) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database errors prevented the transaction from completing.");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
    }
    else {  
      my $status = $metadatadb->commitTransaction($dbTr, \$error);
      if($status == 0) {
        statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "success.ls.deregister", $msg); 
      }
      else {
        statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
        $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;  
      }   
    }
    undef $dbTr;
  }
  
  unless($counter) {
    my $msg = "No data triggers found in request.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.keepalive.data_trigger_missing", $msg);
  }
  
  $metadatadb->closeDB(\$error);
  return;
}

=head2 lsKeepaliveRequest($self, $doc, $request)

The LSKeepaliveRequest message must contain 'key' values identifying an 
already registered LS instance.  If the key for the sent LS is valid the
internal state (i.e. time values) will be advanced so the data set is not
cleaned by the LS Reaper.  Response messages should indicate success or
failure. 

The following is a brief outline of the procedures:

    Does MD have a key
      Y: Is Key in the DB?
        Y: update control info
        N: Send 'error.ls.keepalive.key_not_found' error
      N: Send 'error.ls.keepalive.key_not_found' error

=cut

sub lsKeepaliveRequest {
  my($self, $doc, $request) = @_;

  my $metadatadb = $self->prepareDatabases({ doc => $doc });
  unless($metadatadb) {
    my $msg = "Database could not be opened.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $msg);   
    return;
  }
  
  my %keys = ();
  my $error = q{};
  my $counter = 0;
  my($sec, $frac) = Time::HiRes::gettimeofday;
  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
    my $mdId = "metadata.".genuid();
    my $dId = "data.".genuid();
    $counter++;

    # handle the error conditions first

    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    unless($m) {
      my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.keepalive.data_trigger", $msg);
      next;
    }

    my $mdKey = extract(find($m, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
    unless($mdKey) {
      my $msg = "Key not found in message.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.keepalive.key_not_found", $msg);
      next;
    }

    # see if we verified this key yet (we dont want to run the validator that often)
    unless(exists $keys{$mdKey}) {
      $keys{$mdKey} = $self->isValidKey({ metadatadb => $metadatadb, key => $mdKey});
    }

    # if it's invalid, then we can't do much
    unless($keys{$mdKey}) {
      my $msg = "Sent key \"".$mdKey."\" was not registered.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.keepalive.key_not_found", $msg);
      next;
    }

    # grab a DB transaction so we can roll back if need be
    my $dbTr = $metadatadb->getTransaction(\$error);
    unless($dbTr) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      next;
    }
    
    # update the key
    
    $self->{CONF}->{"ls"}->{"logger"}->debug("Updating control time information.");
    my $status = $metadatadb->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);    
    unless($status == 0) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      next;
    }

    # commit the transaction, or error if there are problems

    my $status = $metadatadb->commitTransaction($dbTr, \$error);
    if($status == 0) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "success.ls.keepalive", "Key \"".$mdKey."\" was updated.");
    }
    else {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;    
    }
    undef $dbTr;
  }
  
  unless($counter) {
    my $msg = "No data triggers found in request.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.keepalive.data_trigger_missing", $msg);
  }
  
  $metadatadb->closeDB(\$error);
  return;
}

=head2 lsQueryRequest($self, $doc, $request)

The LSQueryRequest message contains a query string written in either the XQuery
or XPath languages.  This query string will be extracted and directed to the 
XML Database.  The result (succes being defined as actual XML data, failure
being an error message) will then be packaged and sent in the response message.

The following is a brief outline of the procedures:

    Does MD have a supported subject (xquery: only currently)
    Y: does it have an eventType?
      Y: Supported eventType?
        Y: Send query to DB, perpare results
        N: Send 'error.ls.querytype_not_suported' error
      N: Send 'error.ls.no_querytype' error
    N: Send 'error.ls.query.query_not_found' error

=cut

sub lsQueryRequest {
  my($self, $doc, $request) = @_;

  my $metadatadb = $self->prepareDatabases({ doc => $doc });
  unless($metadatadb) {
    my $msg = "Database could not be opened.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $msg);   
    return;
  }

  my $error = q{};
  my $counter = 0;
  foreach my $d ($request->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
    my $mdId = "metadata.".genuid();
    my $dId = "data.".genuid();
    $counter++;

    # handle the error conditions first
    
    my $m = find($request->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);
    unless($m) {
      my $msg = "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.query.data_trigger", $msg);
      next;
    }

    # support xpath too...      
    my $queryType = extract(find($m, "./nmwg:eventType", 1), 0);    
    unless($queryType eq "service.lookup.xquery" or
           $queryType eq "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0") {
      my $msg = "Given query type is missing or not supported.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.query.eventType", $msg);
    }    

    # support xpath too...
    my $query = extractQuery(find($m, "./xquery:subject", 1));
    unless($query) {
      my $msg = "Query not found in sent metadata.";
      $self->{CONF}->{"ls"}->{"logger"}->error($msg);
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.query.query_not_found", $msg);
      next;
    }      
    $query =~ s/\s+\// collection('CHANGEME')\//gmx;
    
    # the query is legit, send it to the DB

    my @resultsString = $metadatadb->query($query, q{}, \$error);
    if($#resultsString == -1) {
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.xmldb", "Database Error: \"" . $error . "\".");
      next;
    }

    my $dataString = q{};
    my $len = $#resultsString;
    for my $x (0..$len) {
      $dataString = $dataString . $resultsString[$x];
    }
    unless($dataString) {
      my $msg = "Nothing returned for search.";
      statusReport($doc, $mdId, $m->getAttribute("id"), $dId, "error.ls.query.empty_results", $msg);
      next;          
    }
    
    # pass back the results (see if we need to escape the data)
    
    createMetadata($doc, $mdId, $m->getAttribute("id"), q{}, undef);
    my $parameters = q{};
    if(find($m, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1)) {
      $parameters = extractQuery(find($m, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
    }
    if((not $parameters) and find($m, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1)) {
      $parameters = extractQuery(find($m, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
    } 
    if($parameters eq "native") {
      createData($doc, $dId, $mdId, "      <psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".$dataString."</psservice:datum>\n", undef);
    }
    else {
      createData($doc, $dId, $mdId, "      <psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".escapeString($dataString)."</psservice:datum>\n", undef);
    }
  }
  
  unless($counter) {
    my $msg = "No data triggers found in request.";
    $self->{CONF}->{"ls"}->{"logger"}->error($msg);
    statusReport($doc, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.query.data_trigger_missing", $msg);
  }
  
  $metadatadb->closeDB(\$error);
  return;
}

1;

__END__

=head1 SEE ALSO

L<Log::Log4perl>, L<Time::HiRes>, L<perfSONAR_PS::Services::MA::General>, 
L<perfSONAR_PS::Services::LS::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::XMLDB>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut


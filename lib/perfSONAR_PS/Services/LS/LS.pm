package perfSONAR_PS::Services::LS::LS;

use base 'perfSONAR_PS::Services::Base';

use fields 'STATE';

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
use Digest::MD5 qw(md5_hex);
use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Services::LS::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::Error_compat qw/:try/;

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
  average => "http://ggf.org/ns/nmwg/ops/average/2.0/",
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
  transport => "http://ogf.org/schema/network/topology/transport/20070828/",
  pinger => "http://ggf.org/ns/nmwg/tools/pinger/2.0/",
  nmwgr => "http://ggf.org/ns/nmwg/result/2.0/",
  traceroute => "http://ggf.org/ns/nmwg/tools/traceroute/2.0/",
  ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/", 
  owamp => "http://ggf.org/ns/nmwg/tools/owamp/2.0/"
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
  $self->{STATE} = ();
  
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
  my $metadatadb = $self->prepareDatabases;
  unless($metadatadb) {
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

=head2 handleMessageParameters($self, $msgParams)

Looks in the mesage for any parameters and sets appropriate variables if
applicable.

=cut

sub handleMessageParameters {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { msgParams => 1 });  
  
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
  my $parameters = validate(@args, { doc => 0 });
  
  my $error = q{};
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $self->{CONF}->{"ls"}->{"metadata_db_name"},
    $self->{CONF}->{"ls"}->{"metadata_db_file"},
    \%ls_namespaces,
  );
  unless($metadatadb->openDB(q{}, \$error) == 0) {
    $self->{CONF}->{"ls"}->{"logger"}->error("There was an error opening \"".$self->{CONF}->{"ls"}->{"metadata_db_name"}."/".$self->{CONF}->{"ls"}->{"metadata_db_file"}."\": ".$error);
    statusReport($parameters->{doc}, "metadata.".genuid(), q{}, "data.".genuid(), "error.ls.xmldb", $error) if $parameters->{doc};
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
  my $parameters = validate(@args, { metadatadb => 1, key => 1 });
  
  my $error = q{};
  my $result = $parameters->{metadatadb}->queryByName($parameters->{key}, q{}, \$error);
  if($result) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Key \"".$parameters->{key}."\" found in database.");
    return 1;
  }
  $self->{CONF}->{"ls"}->{"logger"}->debug("Key \"".$parameters->{key}."\" not found in database.");
  return 0;
}

=head2 handleMessage($self, $doc, $messageType, $message, $request)

Given a message from the Transport module, this function will route
the message to the appropriate location based on message type.

=cut

sub handleMessage {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { output => { type => ARRAYREF, isa => "perfSONAR_PS::XML::Document_string" }, messageId => { type => SCALAR | UNDEF }, messageType => { type => SCALAR }, message => { type => SCALARREF }, rawRequest => { type => ARRAYREF }});

  my $error = q{};
  my $counter = 0;
  $self->{STATE}->{"messageKeys"} = ();
	my $messageIdReturn = "message.".genuid();
	(my $messageTypeReturn = $parameters->{messageType}) =~ s/Request/Response/xm;

	my $msgParams = find($parameters->{rawRequest}->getRequestDOM()->getDocumentElement, "./nmwg:parameters", 1);
	if($msgParams) {
		$msgParams = $self->handleMessageParameters({ msgParams => $msgParams});
		$parameters->{output}->addExistingXMLElement($msgParams);
	}

	startMessage($parameters->{output}, $messageIdReturn, $parameters->{messageId}, $messageTypeReturn, q{}, undef);

  my $metadatadb = $self->prepareDatabases({ doc => $parameters->{output} });
  unless($metadatadb) {
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database could not be opened.");
    return;
  }
  
  foreach my $d ($parameters->{rawRequest}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS($ls_namespaces{"nmwg"}, "data")) {
    $counter++;

    my $errorEventType = q{};
    my $errorMessage = q{};  
    my $m = find($parameters->{rawRequest}->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"".$d->getAttribute("metadataIdRef")."\"]", 1);  
    try {    
      unless($m) {
        throw perfSONAR_PS::Error_compat("error.ls.data_trigger", "Matching metadata not found for data trigger \"".$d->getAttribute("id")."\"");
      }

	    if($parameters->{messageType} eq "LSRegisterRequest") {
		    $self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSRegister request.");
		    $self->lsRegisterRequest({ doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, d => $d, metadatadb => $metadatadb });
        next;
	    }
	    if($parameters->{messageType} eq "LSDeregisterRequest") {
	    	$self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSDeregister request.");
	    	$self->lsDeregisterRequest({ doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, d => $d, metadatadb => $metadatadb });
        next;
	    }
	    if($parameters->{messageType} eq "LSKeepaliveRequest") {
		    $self->{CONF}->{"ls"}->{"logger"}->debug("Parsing LSKeepalive request.");
		    $self->lsKeepaliveRequest({ doc => $parameters->{output}, request =>$parameters->{rawRequest}, m => $m, metadatadb => $metadatadb });
        next;
	    }
	    if($parameters->{messageType} eq "LSQueryRequest" or
	    	 $parameters->{messageType} eq "LSLookupRequest") {
	    	$self->lsQueryRequest({ doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, metadatadb => $metadatadb });
        next;
	    }
      throw perfSONAR_PS::Error_compat("error.ls.messages", "Unrecognized message type");
    }
    catch perfSONAR_PS::Error_compat with {
      my $ex = shift;
      $errorEventType = $ex->eventType;
      $errorMessage = $ex->errorMessage;
    }
    catch perfSONAR_PS::Error with {
      my $ex = shift;
      $errorEventType = $ex->eventType;
      $errorMessage = $ex->errorMessage;
    }
    catch Error::Simple with {
      my $ex = shift;
      $errorEventType = "error.ls.system";
      $errorMessage = $ex->{"-text"};  
    }
    otherwise {
      my $ex = shift;
      $errorEventType = "error.ls.internal_error";
      $errorMessage = "An internal error occurred.";
    };    
    if($errorEventType) {
      my $mdIdRef = q{};
      if($m and $m->getAttribute("id")) {
        $mdIdRef = $m->getAttribute("id");
      }
      $self->{CONF}->{"ls"}->{"logger"}->error($errorMessage);
      my $mdId = "metadata.".genuid();
      getResultCodeMetadata($parameters->{output}, $mdId, $mdIdRef, $errorEventType);
      getResultCodeData($parameters->{output}, "data.".genuid(), $mdId, $errorMessage, 1); 
    }       
  }

  $metadatadb->closeDB(\$error);
  unless($counter) {
    throw perfSONAR_PS::Error_compat("error.ls.register.data_trigger_missing", "No data triggers found in request.");
  } 
  endMessage($parameters->{output});
  return;
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
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, request => 1, m => 1, d => 1, metadatadb => 1 });

  my $error = q{};
  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $dbTr = $parameters->{metadatadb}->getTransaction(\$error);
  unless($dbTr) {
    $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;
    undef $dbTr;
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
  }

  my $mdKey = extract(find($parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
  if($mdKey) {
    unless(exists $self->{STATE}->{"messageKeys"}->{$mdKey}) {
      $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey({ metadatadb => $parameters->{metadatadb}, key => $mdKey});
    }

    unless($self->{STATE}->{"messageKeys"}->{$mdKey}) {
      throw perfSONAR_PS::Error_compat("error.ls.register.key_not_found", "Sent key \"".$mdKey."\" was not registered.");
    }      
      
    my $service = find($parameters->{m}, "./perfsonar:subject/psservice:service", 1);
    if($service) {
      $self->lsRegisterRequestUpdateNew({ doc => $parameters->{doc}, metadatadb => $parameters->{metadatadb}, dbTr => $dbTr, metadataId => $parameters->{m}->getAttribute("id"), d => $parameters->{d}, mdKey => $mdKey, service => $service, sec => $sec});
    }
    else {
      $self->lsRegisterRequestUpdate({ doc => $parameters->{doc}, metadatadb => $parameters->{metadatadb}, dbTr => $dbTr, metadataId => $parameters->{m}->getAttribute("id"), d => $parameters->{d}, mdKey => $mdKey, sec => $sec});
    }
  }
  else {
    $self->lsRegisterRequestNew({ doc => $parameters->{doc}, metadatadb => $parameters->{metadatadb}, dbTr => $dbTr, m => $parameters->{m}, d => $parameters->{d}, sec => $sec});
  }    
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
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, metadatadb => 1, dbTr => 1, metadataId => 1, d => 1, mdKey => 1, service => 1, sec => 1 });  
  
  my $error = q{};
  my $errorFlag = 0;
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();

  my $accessPoint = extract(find($parameters->{service}, "./psservice:accessPoint", 1), 0);
  unless($accessPoint) {
    throw perfSONAR_PS::Error_compat("error.ls.register.access_point_missing", "Cannont register data, accessPoint was not supplied.");
    return;
  }
  my $mdKeyStorage = md5_hex($accessPoint);

  my @resultsString = $parameters->{metadatadb}->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$parameters->{mdKey}."\"]", q{}, \$error);
  my $len = $#resultsString;
  $self->{CONF}->{"ls"}->{"logger"}->debug("Removing all info for \"".$parameters->{mdKey}."\".");
  for my $x (0..$len) {
    $parameters->{metadatadb}->remove($resultsString[$x], $parameters->{dbTr}, \$error);
  }
  $parameters->{metadatadb}->remove($parameters->{mdKey}."-control", $parameters->{dbTr}, \$error);
  $parameters->{metadatadb}->remove($parameters->{mdKey}, $parameters->{dbTr}, \$error);

  unless($self->{STATE}->{"messageKeys"}->{$mdKeyStorage} == 2) {
    if($self->{STATE}->{"messageKeys"}->{$mdKeyStorage}) {
      $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists, but updating control time information anyway.");
      $parameters->{metadatadb}->updateByName(createControlKey($mdKeyStorage, ($parameters->{sec}+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKeyStorage."-control", $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
    }
    else {
      $self->{CONF}->{"ls"}->{"logger"}->debug("New registration info, inserting service metadata and time information.");
      my $mdCopy = "<nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"".$mdKeyStorage."\">".$parameters->{service}->toString."</nmwg:metadata>\n";
      $parameters->{metadatadb}->insertIntoContainer(wrapStore($mdCopy, "LSStore"), $mdKeyStorage, $parameters->{dbTr}, \$error);
      $parameters->{metadatadb}->insertIntoContainer(createControlKey($mdKeyStorage, ($parameters->{sec}+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKeyStorage."-control", $parameters->{dbTr}, \$error);
    }
    $self->{STATE}->{"messageKeys"}->{$mdKeyStorage} = 2;
  }

  my $dCount = 0;
  foreach my $d_content ($parameters->{d}->childNodes) {
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my $hash = md5_hex($d_content->toString);
      my $insRes = $parameters->{metadatadb}->insertIntoContainer(createLSData($mdKeyStorage."/".$hash, $mdKeyStorage, $d_content->toString), $mdKeyStorage."/".$hash, $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
      $dCount++ if $insRes == 0;
    }
  }
  
  if($errorFlag) {
    $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};
    undef $parameters->{dbTr};
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database errors prevented the transaction from completing.");
  }
  else {  
    my $status = $parameters->{metadatadb}->commitTransaction($parameters->{dbTr}, \$error);
    if($status == 0) {
      createMetadata($parameters->{doc}, $mdId, $parameters->{metadataId}, createLSKey($mdKeyStorage, "success.ls.register"), undef);
      createData($parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$mdKeyStorage."]\" />\n", undef);      
      undef $parameters->{dbTr};
    }
    else {
      $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};  
      undef $parameters->{dbTr};
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }   
  }
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
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, metadatadb => 1, dbTr => 1, metadataId => 1, d => 1, mdKey => 1, sec => 1 }); 

  my $error = q{};
  my $errorFlag = 0;    
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
    
  if($self->{STATE}->{"messageKeys"}->{$parameters->{mdKey}} == 1) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists, but updating control time information anyway.");
    $parameters->{metadatadb}->updateByName(createControlKey($parameters->{mdKey}, ($parameters->{sec}+$self->{CONF}->{"ls"}->{"ls_ttl"})), $parameters->{mdKey}."-control", $parameters->{dbTr}, \$error);
    $errorFlag++ if $error;
    $self->{STATE}->{"messageKeys"}->{$parameters->{mdKey}}++;
  }
  $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists and was already updated in this message, skipping.");
  
  my $dCount = 0;
  foreach my $d_content ($parameters->{d}->childNodes) {
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my $hash = md5_hex($d_content->toString);
      my $insRes = $parameters->{metadatadb}->insertIntoContainer(createLSData($parameters->{mdKey}."/".$hash, $parameters->{mdKey}, $d_content->toString), $parameters->{mdKey}."/".$hash, $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
      $dCount++ if $insRes == 0;
    }
  }

  if($errorFlag) {
    $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};
    undef $parameters->{dbTr};
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database errors prevented the transaction from completing.");
  }
  else {  
    my $status = $parameters->{metadatadb}->commitTransaction($parameters->{dbTr}, \$error);
    if($status == 0) {
      createMetadata($parameters->{doc}, $mdId, $parameters->{metadataId}, createLSKey($parameters->{mdKey}, "success.ls.register"), undef);
      createData($parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[".$dCount."] Data elements have been updated with key [".$parameters->{mdKey}."]\" />\n", undef);         
      undef $parameters->{dbTr};
    }
    else {
      $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};  
      undef $parameters->{dbTr};
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }   
  }
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
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, metadatadb => 1, dbTr => 1, m => 1, d => 1, sec => 1 }); 

  my $error = q{};
  my $errorFlag = 0; 
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid(); 

  my $accessPoint = extract(find($parameters->{m}, "./perfsonar:subject/psservice:service/psservice:accessPoint", 1), 0);
  unless($accessPoint) {
    throw perfSONAR_PS::Error_compat("error.ls.register.access_point_missing", "Cannont register data, accessPoint was not supplied.");
    return;
  }
  my $mdKey = md5_hex($accessPoint);

  unless(exists $self->{STATE}->{"messageKeys"}->{$mdKey}) {
    $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey({ metadatadb => $parameters->{metadatadb}, key => $mdKey});
  }

  unless($self->{STATE}->{"messageKeys"}->{$mdKey} == 2) {
    if($self->{STATE}->{"messageKeys"}->{$mdKey}) {
      $self->{CONF}->{"ls"}->{"logger"}->debug("Key already exists, but updating control time information anyway.");
      $parameters->{metadatadb}->updateByName(createControlKey($mdKey, ($parameters->{sec}+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
    }
    else {
      $self->{CONF}->{"ls"}->{"logger"}->debug("New registration info, inserting service metadata and time information.");
      my $service = $parameters->{m}->cloneNode(1);
      $service->setAttribute("id", $mdKey);
      $parameters->{metadatadb}->insertIntoContainer(wrapStore($service->toString, "LSStore"), $mdKey, $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
      $parameters->{metadatadb}->insertIntoContainer(createControlKey($mdKey, ($parameters->{sec}+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
    }
    $self->{STATE}->{"messageKeys"}->{$mdKey} = 2;
  }    

  my $dCount = 0;
  foreach my $d_content ($parameters->{d}->childNodes) {
    if($d_content->getType != 3 and $d_content->getType != 8) {
      my $hash = md5_hex($d_content->toString);
      my $insRes = $parameters->{metadatadb}->insertIntoContainer(createLSData($mdKey."/".$hash, $mdKey, $d_content->toString), $mdKey."/".$hash, $parameters->{dbTr}, \$error);
      $errorFlag++ if $error;
      $dCount++ if $insRes == 0;
    }
  }

  if($errorFlag) {
    $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database errors prevented the transaction from completing.");
    undef $parameters->{dbTr};
  }
  else {  
    my $status = $parameters->{metadatadb}->commitTransaction($parameters->{dbTr}, \$error);
    if($status == 0) {
      createMetadata($parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), createLSKey($mdKey, "success.ls.register"), undef);
      createData($parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[".$dCount."] Data elements have been registered with key [".$mdKey."]\" />\n", undef);      
      undef $parameters->{dbTr};
    }
    else {
      $parameters->{metadatadb}->abortTransaction($parameters->{dbTr}, \$error) if $parameters->{dbTr};  
      undef $parameters->{dbTr};
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }   
  }
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
      N: Send 'error.deregister.ls.key_not_found' error
    N: Send 'error.ls.deregister.key_not_found' error

=cut

sub lsDeregisterRequest {
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, request => 1, m => 1, d => 1, metadatadb => 1 });
    
  my $msg = q{};
  my $error = q{};
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $mdKey = extract(find($parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
  unless($mdKey) {
    throw perfSONAR_PS::Error_compat("error.ls.deregister.key_not_found", "Key not found in message.");
  }

  unless(exists $self->{STATE}->{"messageKeys"}->{$mdKey}) {
    $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey({ metadatadb => $parameters->{metadatadb}, key => $mdKey});
  }

  unless($self->{STATE}->{"messageKeys"}->{$mdKey}) {
    throw perfSONAR_PS::Error_compat("error.ls.deregister.key_not_found", "Sent key \"".$mdKey."\" was not registered.");
  }

  my $dbTr = $parameters->{metadatadb}->getTransaction(\$error);
  unless($dbTr) {
    $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;
    undef $dbTr;
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
  }

  my @resultsString = ();
  my $errorFlag = 0;
  my @deregs = $parameters->{d}->getElementsByTagNameNS($ls_namespaces{"nmwg"}, "metadata");
  if($#deregs == -1) {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Removing all info for \"".$mdKey."\".");
    @resultsString = $parameters->{metadatadb}->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]", q{}, \$error);
    my $len = $#resultsString;
    for my $x (0..$len) {
      $parameters->{metadatadb}->remove($resultsString[$x], $dbTr, \$error);
      $errorFlag++ if $error;
    }
    $parameters->{metadatadb}->remove($mdKey."-control", $dbTr, \$error);
    $errorFlag++ if $error;
    $parameters->{metadatadb}->remove($mdKey, $dbTr, \$error);
    $errorFlag++ if $error;
    $msg = "Removed [".($#resultsString+1)."] data elements and service info for key \"".$mdKey."\".";
  }
  else {
    $self->{CONF}->{"ls"}->{"logger"}->debug("Removing selected info for \"".$mdKey."\", keeping record.");
    foreach my $d_md (@deregs) {
      @resultsString = $parameters->{metadatadb}->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$mdKey."\"]/nmwg:metadata[" . getMetadataXQuery($d_md, q{}) . "]", q{}, \$error);
      my $len = $#resultsString;
      for my $x (0..$len) {
        $parameters->{metadatadb}->remove($resultsString[$x], $dbTr, \$error);
        $errorFlag++ if $error;
      }
    }
    $msg = "Removed [".($#resultsString+1)."] data elements for key \"".$mdKey."\".";
  }

  if($errorFlag) {
    $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;
    undef $dbTr;
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database errors prevented the transaction from completing.");
  }
  else {  
    my $status = $parameters->{metadatadb}->commitTransaction($dbTr, \$error);
    if($status == 0) {
      statusReport($parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.deregister", $msg); 
      undef $dbTr;
    }
    else {
      $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;  
      undef $dbTr;
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }   
  }      
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
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, request => 1, m => 1, metadatadb => 1 });

  my $error = q{};
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $mdKey = extract(find($parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1), 0);
  unless($mdKey) {
    throw perfSONAR_PS::Error_compat("error.ls.keepalive.key_not_found", "Key not found in message.");
  }

  unless(exists $self->{STATE}->{"messageKeys"}->{$mdKey}) {
    $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey({ metadatadb => $parameters->{metadatadb}, key => $mdKey});
  }

  unless($self->{STATE}->{"messageKeys"}->{$mdKey}) {
    throw perfSONAR_PS::Error_compat("error.ls.keepalive.key_not_found", "Sent key \"".$mdKey."\" was not registered.");
  }

  if($self->{STATE}->{"messageKeys"}->{$mdKey} == 1) {
    my $dbTr = $parameters->{metadatadb}->getTransaction(\$error);
    unless($dbTr) {
      $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Cound not start database transaction, database responded with \"".$error."\".");
    }
    
    $self->{CONF}->{"ls"}->{"logger"}->debug("Updating control time information.");
    my $status = $parameters->{metadatadb}->updateByName(createControlKey($mdKey, ($sec+$self->{CONF}->{"ls"}->{"ls_ttl"})), $mdKey."-control", $dbTr, \$error);    

    unless($status == 0) {
      $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }

    $status = $parameters->{metadatadb}->commitTransaction($dbTr, \$error);
    if($status == 0) {
      statusReport($parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.keepalive", "Key \"".$mdKey."\" was updated.");      
      $self->{STATE}->{"messageKeys"}->{$mdKey}++;
      undef $dbTr;
    }
    else { 
      $parameters->{metadatadb}->abortTransaction($dbTr, \$error) if $dbTr;    
      undef $dbTr;
      throw perfSONAR_PS::Error_compat("error.ls.xmldb", "Database Error: \"" . $error . "\".");
    }
  }
  else {
    statusReport($parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.keepalive", "Key \"".$mdKey."\" was already updated in this exchange, skipping.");
  } 
  return;
}

=head2 lsQueryRequest($self, $doc, $request)

The LSQueryRequest message contains a query string written in either the XQuery
or XPath languages.  This query string will be extracted and directed to the 
XML Database.  The result (succes being defined as actual XML data, failure
being an error message) will then be packaged and sent in the response message.

The following is a brief outline of the procedures:

    Does MD have a supported subject (xquery: only currently)
    Y: does it have an eventType and is it currently supported?
      Y: Send query to DB, prepare results
      N: Send 'error.ls.query.eventType' error
    N: Send 'error.ls.query.query_not_found' error

Any database errors will cause the given metadata/data pair to fail.

=cut

sub lsQueryRequest {
  my ($self, @args) = @_;
  my $parameters = validate(@args, { doc => 1, request => 1, m => 1, metadatadb => 1 });

  my $error = q{};
  my $mdId = "metadata.".genuid();
  my $dId = "data.".genuid();
  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $queryType = extract(find($parameters->{m}, "./nmwg:eventType", 1), 0);    
  unless($queryType eq "service.lookup.xquery" or
         $queryType eq "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0") {
    throw perfSONAR_PS::Error_compat("error.ls.query.eventType", "Given query type is missing or not supported.");
  }    

  my $query = extractQuery(find($parameters->{m}, "./xquery:subject", 1));
  unless($query) {
    throw perfSONAR_PS::Error_compat("error.ls.query.query_not_found", "Query not found in sent metadata.");
  }      
  $query =~ s/\s+\// collection('CHANGEME')\//gmx;

  my @resultsString = $parameters->{metadatadb}->query($query, q{}, \$error);
  if($error) {
    throw perfSONAR_PS::Error_compat("error.ls.xmldb", $error);
  }

  my $dataString = q{};
  my $len = $#resultsString;
  for my $x (0..$len) {
    $dataString = $dataString . $resultsString[$x];
  }
  unless($dataString) {
    throw perfSONAR_PS::Error_compat("error.ls.query.empty_results", "Nothing returned for search.");        
  }   

  createMetadata($parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), q{}, undef);
  my $mdPparameters = q{};
  $mdPparameters = extractQuery(find($parameters->{m}, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
  if(not $mdPparameters) {
    $mdPparameters = extractQuery(find($parameters->{m}, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1));
  } 
  
  if($mdPparameters eq "native") {
    createData($parameters->{doc}, $dId, $mdId, "<psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".$dataString."</psservice:datum>\n", undef);
  }
  else {  
    createData($parameters->{doc}, $dId, $mdId, "<psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">".escapeString($dataString)."</psservice:datum>\n", undef);  
  }
  return;
}

1;

__END__

=head1 SEE ALSO

L<Log::Log4perl>, L<Time::HiRes>, L<Params::Validate>, L<Digest::MD5>,
L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Services::LS::General>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>,
L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::Error_compat qw/:try/>

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

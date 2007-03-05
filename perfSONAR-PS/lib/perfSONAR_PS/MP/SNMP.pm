#!/usr/bin/perl

package perfSONAR_PS::MP::SNMP;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();
our $VERSION = '0.02';

# ================ Internal Package perfSONAR_PS::MP::SNMP::Agent ================

package perfSONAR_PS::MP::SNMP::Agent;
use Net::SNMP;
use perfSONAR_PS::Common;
sub new {
  my ($package, $log, $host, $port, $ver, $comm, $vars) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::SNMP::Agent";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }  
  if(defined $host and $host ne "") {
    $hash{"HOST"} = $host;
  }
  if(defined $port and $port ne "") {
    $hash{"PORT"} = $port;
  }
  else {
    $hash{"PORT"} = 161;
  }
  if(defined $ver and $ver ne "") {
    $hash{"VERSION"} = $ver;
  }
  if(defined $comm and $comm ne "") {
    $hash{"COMMUNITY"} = $comm; 
  }
  if(defined $var and $var ne "") {
    $hash{"VARIABLES"} = \%{$vars};  
  }
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setHost {
  my ($self, $host) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";
  $self->{FUNCTION} = "\"setHost\"";  
  if(defined $host and $host ne "") {
    $self->{HOST} = $host;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";
  $self->{FUNCTION} = "\"setPort\"";  
  if(defined $port and $port ne "") {
    $self->{PORT} = $port;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setVersion {
  my ($self, $ver) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"setVersion\"";  
  if(defined $ver and $ver ne "") {
    $self->{VERSION} = $ver;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setCommunity {
  my ($self, $comm) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"setCommunity\"";  
  if(defined $comm and $comm ne "") {
    $self->{COMMUNITY} = $comm;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setVariables {
  my ($self, $vars) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"setVariables\""; 
  if(defined $var and $var ne "") {
    $hash{"VARIABLES"} = \%{$vars};
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setVariable {
  my ($self, $var) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"setVariable\""; 
  if(defined $var and $var ne "") {
    $self->{VARIABLES}->{$var} = "";
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub getVariableCount {
  my ($self) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"getVariableCount\""; 
  my $num = 0;
  foreach my $oid (keys %{$self->{VARIABLES}}) {
    $num++;
  }
  return $num;
}


sub removeVariables {
  my ($self) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"removeVariables\""; 
  undef $self->{VARIABLES};
  if(defined $self->{VARIABLES}) {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tRemove failure in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");        
  }
  return;
}


sub removeVariable {
  my ($self, $var) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"removeVariable\""; 
  if(defined $var and $var ne "") {
    delete $self->{VARIABLES}->{$var};
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


sub setSession {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"setSession\"";  
  if((defined $self->{COMMUNITY} and $self->{COMMUNITY} ne "") and 
     (defined $self->{VERSION} and $self->{VERSION} ne "") and 
     (defined $self->{HOST} and $self->{HOST} ne "") and 
     (defined $self->{PORT} and $self->{PORT} ne "")) {

    ($self->{SESSION}, $self->{ERROR}) = Net::SNMP->session(
      -community     => $self->{COMMUNITY},
      -version       => $self->{VERSION},
      -hostname      => $self->{HOST},
      -port          => $self->{PORT},
      -translate     => [
                         -timeticks => 0x0
                        ]) or 
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tCouldn't open SNMP session to " . $self->{HOST} . " in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");
	      
    if(!defined($self->{SESSION})) {
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSNMP Error: " . $self->{ERROR} . " in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");
    }
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSession needs 'host', 'version', and 'community' to be set in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");        
  }  
  return;
}


sub closeSession {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"closeSession\"";  
  if(defined $self->{SESSION}) {
    $self->{SESSION}->close;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tCannot close undefined session in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne ""); 
  }
  return;
}


sub collectVariables {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"collectVariables\"";    
  if(defined $self->{SESSION}) {
  
    my @oids = ();
    foreach my $oid (keys %{$self->{VARIABLES}}) {
      push @oids, $oid;
    }
  
    $self->{RESULT} = $self->{SESSION}->get_request(
      -varbindlist => \@oids
    ) or 
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSNMP Error: in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");
    
    if(!defined($self->{RESULT})) {
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSNMP Error: in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");
      return ('error' => -1);
    }    
    else {
      return %{$self->{RESULT}};
    }
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSession to " . $self->{HOST} . " not found in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");          
    return ('error' => -1);
  }      
}


sub collect {
  my ($self, $var) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP::Agent";  
  $self->{FUNCTION} = "\"collect\""; 
  if(defined $var and $var ne "") {   
    undef $self->{RESULT};
    if(defined $self->{SESSION}) {
      
      $self->{RESULT} = $self->{SESSION}->get_request(
        -varbindlist => [$var]
      ) or 
        printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSNMP error: " . $self->{ERROR} . " in ".$self->{FUNCTION}) 
          if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");      
      
      if(!defined($self->{RESULT})) {
        printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSNMP error: " . $self->{ERROR} . " in ".$self->{FUNCTION}) 
          if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");
        return -1;
      }    
      else {
        return $self->{RESULT}->{$var};
      }
    }
    else {
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tSession to " . $self->{HOST} . " not found in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
      return -1;
    }
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


# ================ Main Package perfSONAR_PS::MP::SNMP ================


package perfSONAR_PS::MP::SNMP;
sub new {
  my ($package, $conf, $ns, $metadata, $data) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::SNMP";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }    
  if(defined $metadata and $metadata ne "") {
    $hash{"METADATA"} = \%{$metadata};
  }
  else {
    %{$hash{"METADATA"}} = ();
  }  
  if(defined $data and $data ne "") {
    $hash{"DATA"} = \%{$data};
  }
  else {
    %{$hash{"DATA"}} = ();
  }

  %{$hash{"METADATAMARKS"}} = ();
  %{$hash{"DATADB"}} = ();
  %{$hash{"LOOKUP"}} = ();
  %{$hash{"SNMP"}} = ();
      
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"setHost\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setMetadata {
  my ($self, $metadata) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";    
  $self->{FUNCTION} = "\"setMetadata\"";  
  if(defined $metadata and $metadata ne "") {
    $self->{METADATA} = \%{$metadata};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setData {
  my ($self, $data) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";    
  $self->{FUNCTION} = "\"setData\"";  
  if(defined $data and $data ne "") {
    $self->{DATA} = \%{$data};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub parseMetadata {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";    
  $self->{FUNCTION} = "\"parseMetadata\"";
  
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {  
    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"LOGFILE"},
      $self->{CONF}->{"METADATA_DB_NAME"}, 
      $self->{CONF}->{"METADATA_DB_FILE"},
      \%{$self->{NAMESPACES}}
    );

    $metadatadb->openDB;
    my $query = "//nmwg:metadata";
    my @resultsStringMD = $metadatadb->query($query);   
    if($#resultsStringMD != -1) {    
      for(my $x = 0; $x <= $#resultsStringMD; $x++) {     	
	parse($resultsStringMD[$x], \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, $query);
      }
    }
    else {
      my $msg = $self->{FILENAME} .":\tXMLDB returned 0 results for query '". $query ."' in function " . $self->{FUNCTION};      
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");          
    }  

    $query = "//nmwg:data";
    my @resultsStringD = $metadatadb->query($query);   
    if($#resultsStringD != -1) {    
      for(my $x = 0; $x <= $#resultsStringD; $x++) { 	
        parse($resultsStringD[$x], \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, $query);
      }
    }
    else {
      my $msg = $self->{FILENAME} .":\tXMLDB returned 0 results for query '". $query ."' in function " . $self->{FUNCTION};
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
    }          
    cleanMetadata($self);       
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
    my $xml = readXML($conf{"METADATA_DB_FILE"});
    parse($xml, \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, "//nmwg:metadata");
    parse($xml, \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, "//nmwg:data");	
    cleanMetadata($self);    
  }
  elsif(($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql") or 
        ($self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite")) {
    my $msg = "'METADATA_DB_TYPE' of '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is not yet supported.";
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
  }  
  else {
    my $msg = "'METADATA_DB_TYPE' of '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is invalid.";
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
  }
  return;
}


sub cleanMetadata {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"cleanMetadata\"";
    
  chainMetadata($self->{METADATA}); 

  foreach my $m (keys %{$self->{METADATA}}) {
    my $count = countRefs($m, \%{$self->{DATA}}, "nmwg:data-metadataIdRef");
    if($count == 0) {
      delete $self->{METADATA}->{$m};
    } 
    else {
      $self->{METADATAMARKS}->{$m} = $count;
    }
  }  
  return;
}

sub removeReferences {
  my($self, $id) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"removeReferences\"";      
  my $remove = countRefs($id, $self->{METADATA}, "nmwg:metadata-id");
  if($remove > 0) {
    $self->{METADATAMARKS}->{$id} = $self->{METADATAMARKS}->{$id} - $remove;
    if($self->{METADATAMARKS}->{$id} == 0) {
      delete $self->{METADATAMARKS}->{$id};
      delete $self->{METADATA}->{$id};
    }     
  }
  return;
}

sub prepareData {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"prepareData\"";
      
  foreach my $d (keys %{$self->{DATA}}) {
    if($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
      if(!defined $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}) { 
        $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}} = new perfSONAR_PS::DB::RRD(
          $self->{CONF}->{"LOGFILE"}, 
          $self->{CONF}->{"RRDTOOL"}, 
          $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
          "",
          1
        );
      }
      $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->setVariable($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"});
    }
    elsif(($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") or 
          ($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql")){
      my $msg = "Data DB of type '". $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} ."' is not supported by this MP.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
      removeReferences($self, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }
    else {
      my $msg = "Data DB of type '". $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} ."' is not supported by this MP.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
      removeReferences($self, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }  
  }  
       
  return;
}


sub prepareCollectors {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"prepareCollectors\"";
      
  $self->{LOOKUP}->{"1.3.6.1.2.1.1.3.0"} = "timeticks";
  
  foreach my $m (keys %{$self->{METADATA}}) {
    if($self->{METADATAMARKS}->{$m}) {
    
      my $hostName = "";  
      my $ifIndex = ""; 
      my $snmpVersion = "";
      my $snmpCommunity = "";
      my $OID = "";
      foreach my $m2 (keys %{$self->{METADATA}->{$m}}) {
        if($m2 =~ m/.*hostName$/) {
          $hostName = $m2;
        }
        elsif($m2 =~ m/.*ifIndex$/) {
          $ifIndex = $m2;
        }
        elsif($m2 =~ m/.*nmwg:parameter-OID$/) {
          $OID = $m2;
        }
        elsif($m2 =~ m/.*nmwg:parameter-SNMPVersion$/) {
          $snmpVersion = $m2;
        }
        elsif($m2 =~ m/.*nmwg:parameter-SNMPCommunity$/) {
          $snmpCommunity = $m2;
        }
      }  
  
      if(!defined $self->{SNMP}->{$self->{METADATA}->{$m}->{$hostName}}) {    	  
        $self->{SNMP}->{$self->{METADATA}->{$m}->{$hostName}} = new perfSONAR_PS::MP::SNMP::Agent(
	  $self->{CONF}->{"LOGFILE"},
          $self->{METADATA}->{$m}->{$hostName}, 
          "" ,
          $self->{METADATA}->{$m}->{$snmpVersion},
          $self->{METADATA}->{$m}->{$snmpCommunity},
          "");
      }
      $self->{SNMP}->{$self->{METADATA}->{$m}->{$hostName}}->setVariable($self->{METADATA}->{$m}->{$OID}.".".$self->{METADATA}->{$m}->{$ifIndex});
  
		# map the lookup information
      foreach my $d (keys %{$self->{DATA}}) {
        if($self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"} eq $m) {
          $self->{LOOKUP}->{$self->{METADATA}->{$m}->{$hostName}."-".$self->{METADATA}->{$m}->{$OID}.".".$self->{METADATA}->{$m}->{$ifIndex}} = $d;
          last;
        }
      }
    }
  }

  return;
}


sub prepareTime {
  my($self, $time) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"prepareTime\"";
    
  if(defined $time and $time ne "") {
    %{$self->{HOSTTICKS}} = ();
    %{$self->{REFTIME}} = ();
    foreach my $s (keys %{$self->{SNMP}}) {
      $self->{REFTIME}->{$s} = $time;
      $self->{HOSTTICKS}->{$s} = 0;
      $self->{SNMP}->{$s}->setSession;

      $self->{SNMP}->{$s}->setVariable("1.3.6.1.2.1.1.3.0");
    }  
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }  
  return;
}


sub collectMeasurements {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"collectMeasurements\"";
  
  foreach my $s (keys %{$self->{SNMP}}) {
print "Collecting for '" , $s , "'.\n";
    
    my %results = ();
    %results = $self->{SNMP}->{$s}->collectVariables;

    if(defined $results{"error"} and $results{"error"} == -1) {   
      $self->{SNMP}->{$s}->closeSession;  
      $self->{SNMP}->{$s}->setSession;
    }
    else {     
      my $diff = 0;
      my $newHostTicks = 0;
      foreach my $r (keys %results) {
        if($self->{LOOKUP}->{$r} and $self->{LOOKUP}->{$r} eq "timeticks") {
	  if($self->{HOSTTICKS}->{$s} == 0) {
	    $self->{HOSTTICKS}->{$s} = $results{$r}/100;
	    $newHostTicks = $results{$r}/100;
	  }
	  else {	    
	    $newHostTicks = $results{$r}/100;	    
	  }
	  last;
	}	
      }    

      $diff = $newHostTicks - $self->{HOSTTICKS}->{$s};
      $self->{HOSTTICKS}->{$s} = $newHostTicks;  
      $self->{REFTIME}->{$s} += $diff;

      foreach my $r (keys %results) { 
        if($self->{LOOKUP}->{$s."-".$r} and $self->{LOOKUP}->{$s."-".$r} ne "timeticks") {
	  
	  if($self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
print "inserting: " , $self->{REFTIME}->{$s}  , "," , $self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"} , "," , $results{$r} , "\n";
	      				
            $self->{DATADB}->{$self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->insert($self->{REFTIME}->{$s}, 
	                                                                                                                                         $self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"},
			  				                                                                                         $results{$r});
	  }
	  elsif(($self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") or 
	        ($self->{DATA}->{$self->{LOOKUP}->{$s."-".$r}}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql")) {

	    # do nothing for now
	  }
	  else {

	    # do nothing for now
	  }
	}
      }
    }
  }
		
# NOTE: need a way to make sure we only do this for RRD db's ...
		
  my @result = ();
  foreach my $db (keys %{$self->{DATADB}}) {    
    $self->{DATADB}->{$db}->openDB;
    @result = $self->{DATADB}->{$db}->insertCommit;
    $self->{DATADB}->{$db}->closeDB;
  }

  return;
}


1;


__END__


=head1 NAME

perfSONAR_PS::MP::SNMP - A module that provides methods for creating structures to gather
and store data from SNMP sources.  The submodule, 'perfSONAR_PS::MP::SNMP::Agent', is
responsible for the polling of SNMP data from a resource.

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to poll SNMP data from a specific resource.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use perfSONAR_PS::MP::SNMP;
    use Time::HiRes qw( gettimeofday );
    
    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
    $conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $mp = new perfSONAR_PS::MP::SNMP(\%conf, \%ns, "", "");
    $mp->parseMetadata;
    $mp->prepareData;
    $mp->prepareCollectors;

    my($sec, $frac) = Time::HiRes::gettimeofday;
    $mp->prepareTime($sec.".".$frac);

    $mp->collectMeasurements;

=head1 DETAILS

The Net::SNMP API is rich with features, and does offer lots of functionality we choose not 
to re-package here.  perfSONAR-PS for the most part is not interested in writing SNMP data, 
and currently only supports versions 1 and 2 of the spec.  As such we only provide simple 
methods that accomplish our goals.  We do recognize the importance of these other functions, 
and they may be provided in the future.

This module contains a submodule that is not meant to act as a standalone, but rather as
a specialized structure for use only in this module.  The functions include:


  new($log, $host, $port, $version, $community, \%variables)

    The 'log' argument is the name of the log file where error or warning information may be 
    recorded.  The second argument is a string representing the 'host' from which to collect 
    SNMP data.  The third argument is a numerical 'port' number (will default to 161 if unset).  
    It is also possible to supply the port number via the host name, as in 'hostname:port'.  
    The fourth argument, 'version', is a string that represents the version of snmpd that is 
    running on the target host, currently this module supports versions 1 and 2 only.  The 
    fifth argument is a string representing the 'community' that allows snmp reading on the 
    target host.  The final argument is a hash of oids representing the variables to be 
    polled from the target.  All of these arguments are optional, and may be set or 
    re-set with the other functions.

  setLog($log)

    (Re-)Sets the log file for the SNMP object.

  setHost($host)

    (Re-)Sets the target host for the SNMP object.

  setPort($port)

    (Re-)Sets the port for the target host on the SNMP object.

  setVersion($version)

    (Re-)Sets the version of snmpd running on the target host.

  setCommunity($community)

    (Re-)Sets the community that snmpd is allowing ot be read on the target host.

  setSession()

    Establishes a connection to the target host with the supplied information.  It is 
    necessary to have the host, community, and version set for this to work; port will 
    default to 161 if unset.  If changes are made to any of the above variables, the 
    session will need to be re-set from this function

  setVariables(\%variables)

    Passes a hash of 'oid' encoded variables to the object; these oids will be used 
    when the 'collectVariables' routine is called to gather the proper values.

  setVariable($variable)

    Adds $variable to the hash of oids to be collected when the 'collectVariables' 
    routine is called.

  removeVariables()

    Removes all variables from the hash of oids.

  removeVariable($variable)

    Removes $variable from the hash of oids to be collected when the 'collectVariables' 
    routine is called.

  collectVariables()

    Collects all variables from the target host that are specified in the hash of oids.  The
    results are returned in a hash with keys representing each oid.  Will return -1 
    on error.

  collect($variable)

    Collects the oid represented in $variable, and returns this value.  Will return -1 
    on error.

  closeSession()

    Closes the session to the target host.


A brief description using the API:
   
   
    my %vars = (
      '.1.3.6.1.2.1.2.2.1.10.2' => ""
    );
  
    my $snmp = new perfSONAR_PS::MP::SNMP::Agent(
      "./error.log", "lager", 161, "1", "public",
      \%vars
    );

    # or also:
    # 
    # my $snmp = new perfSONAR_PS::MP::SNMP::Agent;
    # $snmp->setLog("./error.log");
    # $snmp->setHost("lager");
    # $snmp->setPort(161);
    # $snmp->setVersion("1");
    # $snmp->setCommunity("public");
    # $snmp->setVariables(\%vars);

    $snmp->setSession;

    my $single_result = $snmp->collect(".1.3.6.1.2.1.2.2.1.16.2");

    $snmp->setVariable(".1.3.6.1.2.1.2.2.1.16.2");

    my %results = $snmp->collectVariables;
    foreach my $var (sort keys %results) {
      print $var , "\t-\t" , $results{$var} , "\n"; 
    }

    $snmp->removeVariable(".1.3.6.1.2.1.2.2.1.16.2");

    # to remove ALL variables
    # 
    # $snmp->removeVariables;
    
    $snmp->closeSession;


=head1 API

The offered API is simple, but offers the key functions we need in a measurement point. 

=head2 new(\%conf, \%ns, \%metadata, \%data)

The first argument represents the 'conf' hash from the calling MP.  The second argument
is a hash of namespace values.  The final 2 values are structures containing metadata or 
data information.  

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash.  

=head2 setNamespaces(\%ns)

(Re-)Sets the value for the 'namespace' hash. 

=head2 setMetadata(\%metadata) 

(Re-)Sets the value for the 'metadata' object. 

=head2 setData(\%data) 

(Re-)Sets the value for the 'data' object. 

=head2 parseMetadata()

Parses the metadata database (specified in the 'conf' hash) and loads the values for the
data and metadata objects.  

=head2 cleanMetadata()

Chains, and removes unused metadata values from the metadata object.

=head2 removeReferences($id)

Removes a value from the an object (data/metadata) if the value is equal to the supplied
id. 

=head2 prepareData()

Prepares data db objects that relate to each of the valid data values in the data object.  

=head2 prepareCollectors()

Prepares the 'perfSONAR_PS::MP::SNMP::Agent' objects for each of the metadata values in
the metadata object.

=head2 prepareTime($time)

Starts the objects that will keep track of time (in relation to the remote sites).  

=head2 collectMeasurements()

Cycles through each of the 'perfSONAR_PS::MP::SNMP::Agent' objects and gathers the 
necessary values.  

=head1 SEE ALSO

L<Net::SNMP>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

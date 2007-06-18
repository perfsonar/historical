#!/usr/bin/perl -w

package perfSONAR_PS::MP::Status;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MP::Base;
use perfSONAR_PS::MP::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MP::Base);


sub parseMetadata {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status");
  
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
    $self->{STORE} = parseXMLDB($self);
    cleanMetadata(\%{$self});    
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {   
    $self->{STORE} = parseFile($self);
    cleanMetadata(\%{$self});
  }
  else {
    $logger->error($self->{CONF}->{"METADATA_DB_TYPE"}." is not supported."); 
  }
  return;
}


sub prepareData {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status");
  
  cleanData(\%{$self});
  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {    
    my $type = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));
    my $file = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));        

    if($type eq "sqlite"){
      if(!defined $self->{DATADB}->{$file}) {  
        my @dbSchema = ("id", "time", "value", "eventtype", "misc");  
        $self->{DATADB}->{$file} = new perfSONAR_PS::DB::SQL(
          "DBI:SQLite:dbname=".$file, 
          "", 
	        "", 
	        \@dbSchema
        );
        $logger->debug("Connectiong to SQL database \"".$file."\".");
      }
    }
    else {
      $logger->error($type." is not supported.");
      removeReferences(\%{$self}, $d->getAttribute("metadataIdRef"), $d->getAttribute("id"));
    }  
  }  
  return;
}


sub prepareCollectors {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status");
      
  $self->{LOOKUP}->{"1.3.6.1.2.1.1.3.0"} = "timeticks";
  
  
  # add the other status variables here(we won't need to parse the 
  #  metadata to get additional variables)
  
  foreach my $m ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
    if($self->{METADATAMARKS}->{$m->getAttribute("id")}) {
      my $topoPrefix = lookup($self, "http://ggf.org/ns/nmwg/topology/2.0/", "nmwgt");
      my $snmpPrefix = lookup($self, "http://ggf.org/ns/nmwg/tools/snmp/2.0/", "snmp"); 
         
      my $hostName = extract($m->find(".//".$topoPrefix.":hostName")->get_node(1));      
      my $ifIndex = extract($m->find(".//".$topoPrefix.":ifIndex")->get_node(1));
      my $snmpVersion = extract($m->find(".//".$snmpPrefix.":parameters/nmwg:parameter[\@name=\"SNMPVersion\"]")->get_node(1));
      my $snmpCommunity = extract($m->find(".//".$snmpPrefix.":parameters/nmwg:parameter[\@name=\"SNMPCommunity\"]")->get_node(1));
      my $OID = extract($m->find(".//".$snmpPrefix.":parameters/nmwg:parameter[\@name=\"OID\"]")->get_node(1));    
      
      if(!defined $self->{AGENT}->{$hostName}) {    	  
        $self->{AGENT}->{$hostName} = new perfSONAR_PS::MP::Status::Agent(
          $hostName, 
          "" ,
          $snmpVersion,
          $snmpCommunity,
          ""
        );
        $logger->debug("Creating collector for \"".$hostName."\", \"".$snmpVersion."\", \"".$snmpCommunity."\".");
      }
      $self->{AGENT}->{$hostName}->setVariable($OID.".".$ifIndex);
  
      foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
        if($d->getAttribute("metadataIdRef") eq $m->getAttribute("id")) {
          push @{$self->{LOOKUP}->{$hostName."-".$OID.".".$ifIndex}}, $d->getAttribute("id");
        }
      }       
    }    
  }  
  return;
}


sub prepareTime {
  my($self, $time) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status");
    
  if(defined $time and $time ne "") {
    %{$self->{HOSTTICKS}} = ();
    %{$self->{REFTIME}} = ();
    foreach my $s (keys %{$self->{AGENT}}) {
      $self->{REFTIME}->{$s} = $time;
      $self->{HOSTTICKS}->{$s} = 0;
      $self->{AGENT}->{$s}->setSession;
      $self->{AGENT}->{$s}->setVariable("1.3.6.1.2.1.1.3.0");
    }  
  }
  else {
    $logger->error("Missing argument.");      
  }  
  return;
}


sub collectMeasurements {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status");
  
  foreach my $s (keys %{$self->{AGENT}}) {
    $logger->debug("Collecting data for \"".$s."\".");
    my %results = ();
    %results = $self->{AGENT}->{$s}->collectVariables;

    if(defined $results{"error"} and $results{"error"} == -1) {   
      $self->{AGENT}->{$s}->closeSession;  
      $self->{AGENT}->{$s}->setSession;
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
	        foreach $did (@{$self->{LOOKUP}->{$s."-".$r}}) {	    
	          my $d = $self->{STORE}->find("//nmwg:data[\@id=\"".$did."\"]")->get_node(1);
            my $type = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));
	          my $file = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));
    
            if($type eq "sqlite") {
              $logger->debug("inserting (SQLite): ".$d->getAttribute("metadataIdRef").",".$self->{REFTIME}->{$s}.",".$results{$r}.",snmp,''.");
              
              %dbSchemaValues = (
                id => $d->getAttribute("metadataIdRef"), 
                time => $self->{REFTIME}->{$s}, 
                value => $results{$r}, 
                eventtype => "snmp",  
                misc => ""
              );  
              $self->{DATADB}->{$file}->openDB;
              $self->{DATADB}->{$file}->insert(
                extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"table\"]")->get_node(1)),
	              \%dbSchemaValues
	            );
              $self->{DATADB}->{$file}->closeDB;
            }
            else {
              $logger->error("Database \"".$type."\" is not supported.");
            }
	        }
	      }
      }
    }
  }
		  
  return;
}



# ================ Internal Package perfSONAR_PS::MP::Status::Agent ================



package perfSONAR_PS::MP::Status::Agent;

use Net::SNMP;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;

sub new {
  my ($package, $host, $port, $ver, $comm, $vars) = @_; 
  my %hash = ();

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


sub setHost {
  my ($self, $host) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
   
  if(defined $host and $host ne "") {
    $self->{HOST} = $host;
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
    
  if(defined $port and $port ne "") {
    $self->{PORT} = $port;
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setVersion {
  my ($self, $ver) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
   
  if(defined $ver and $ver ne "") {
    $self->{VERSION} = $ver;
  }
  else {
    $logger->error("Missing argument.");     
  }
  return;
}


sub setCommunity {
  my ($self, $comm) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  if(defined $comm and $comm ne "") {
    $self->{COMMUNITY} = $comm;
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setVariables {
  my ($self, $vars) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  if(defined $var and $var ne "") {
    $hash{"VARIABLES"} = \%{$vars};
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setVariable {
  my ($self, $var) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  if(defined $var and $var ne "") {
    $self->{VARIABLES}->{$var} = "";
  }
  else {
    $logger->error("Missing argument.");     
  }
  return;
}


sub getVariableCount {
  my ($self) = @_;  

  my $num = 0;
  foreach my $oid (keys %{$self->{VARIABLES}}) {
    $num++;
  }
  return $num;
}


sub removeVariables {
  my ($self) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  undef $self->{VARIABLES};
  if(defined $self->{VARIABLES}) {
    $logger->error("Remove failure.");       
  }
  return;
}


sub removeVariable {
  my ($self, $var) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  if(defined $var and $var ne "") {
    delete $self->{VARIABLES}->{$var};
  }
  else {
    $logger->error("Missing argument.");      
  }
  return;
}


sub setSession {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
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
                        ]) or $logger->error("Couldn't open SNMP session to \"".$self->{HOST}."\".");
	      
    if(!defined($self->{SESSION})) {
      $logger->error("SNMP error.");
    }
  }
  else {
    $logger->error("Session requires arguments 'host', 'version', and 'community'.");      
  }  
  return;
}


sub closeSession {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
  
  if(defined $self->{SESSION}) {
    $self->{SESSION}->close;
  }
  else {
    $logger->error("Cannont close undefined session.");
  }
  return;
}


sub collectVariables {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
    
  if(defined $self->{SESSION}) {
  
    my @oids = ();
    foreach my $oid (keys %{$self->{VARIABLES}}) {
      push @oids, $oid;
    }

    $self->{RESULT} = $self->{SESSION}->get_request(
      -varbindlist => \@oids
    ) or $logger->error("SNMP error.");
    
    if(!defined($self->{RESULT})) {
      $logger->error("SNMP error.");
      return ('error' => -1);
    }    
    else {
      return %{$self->{RESULT}};
    }
  }
  else {
    $logger->error("Session to \"".$self->{HOST}."\" not found.");     
    return ('error' => -1);
  }      
}


sub collect {
  my ($self, $var) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Status::Agent");
   
  if(defined $var and $var ne "") {   
    undef $self->{RESULT};
    if(defined $self->{SESSION}) {
      
      $self->{RESULT} = $self->{SESSION}->get_request(
        -varbindlist => [$var]
      ) or $logger->error("SNMP error: \"".$self->{ERROR}."\"."); 
      
      if(!defined($self->{RESULT})) {
        $logger->error("SNMP error: \"".$self->{ERROR}."\".");          
        return -1;
      }    
      else {
        return $self->{RESULT}->{$var};
      }
    }
    else {    
      $logger->error("Session to \"".$self->{HOST}."\" not found.");   
      return -1;
    }
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


1;


__END__


=head1 NAME

perfSONAR_PS::MP::Status - A module that provides methods for creating structures to gather
and store data from SNMP sources.  The submodule, 'perfSONAR_PS::MP::Status::Agent', is
responsible for the polling of SNMP data from a resource.

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to poll SNMP data from a specific resource.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use perfSONAR_PS::MP::Status;
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
    
    my $mp = new perfSONAR_PS::MP::Status(\%conf, \%ns, "", "");
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

  error($msg, $line)	

    A 'message' argument is used to print error information to the screen and log files 
    (if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
    Meant to be used internally.

A brief description using the API:
   
   
    my %vars = (
      '.1.3.6.1.2.1.2.2.1.10.2' => ""
    );
  
    my $snmp = new perfSONAR_PS::MP::Status::Agent(
      "./error.log", "lager", 161, "1", "public",
      \%vars
    );

    # or also:
    # 
    # my $snmp = new perfSONAR_PS::MP::Status::Agent;
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

=head2 new(\%conf, \%ns, $store)

The first argument represents the 'conf' hash from the calling MP.  The second argument
is a hash of namespace values.  The final value is an LibXML DOM object representing
a store.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash.  

=head2 setNamespaces(\%ns)

(Re-)Sets the value for the 'namespace' hash. 

=head2 setStore($store) 

(Re-)Sets the value for the 'store' object, which is really just a XML::LibXML::Document

=head2 parseMetadata()

Parses the metadata database (specified in the 'conf' hash) and loads the values for the
data and metadata objects.  

=head2 prepareData()

Prepares data db objects that relate to each of the valid data values in the data object.  

=head2 prepareCollectors()

Prepares the 'perfSONAR_PS::MP::Status::Agent' objects for each of the metadata values in
the metadata object.

=head2 prepareTime($time)

Starts the objects that will keep track of time (in relation to the remote sites).  

=head2 collectMeasurements()

Cycles through each of the 'perfSONAR_PS::MP::Status::Agent' objects and gathers the 
necessary values.  

=head1 SEE ALSO

L<Net::SNMP>, L<perfSONAR_PS::MP::Base>,  L<perfSONAR_PS::MP::General>, 
L<perfSONAR_PS::Common>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>, L<XML::LibXML>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, E<lt>aaron@internet2.eduE<gt>, Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

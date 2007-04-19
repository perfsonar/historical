#!/usr/bin/perl

package perfSONAR_PS::MP::Ping;

use perfSONAR_PS::MP::Base;
use perfSONAR_PS::MP::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::SQL;
use XML::LibXML;

our @ISA = qw(perfSONAR_PS::MP::Base);

sub parseMetadata {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";    
  $self->{FUNCTION} = "\"parseMetadata\"";

  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {  
    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"LOGFILE"},
      $self->{CONF}->{"METADATA_DB_NAME"}, 
      $self->{CONF}->{"METADATA_DB_FILE"},
      \%{$self->{NAMESPACES}},
      $self->{CONF}->{"DEBUG"}
    );

    $metadatadb->openDB;
    
    my $query = "//nmwg:metadata";
    print "DEBUG:\tQuery: \"".$query."\" created.\n" if($self->{CONF}->{"DEBUG"});
    my @resultsStringMD = $metadatadb->query($query);   
    
    my $storeString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<nmwg:store ";
    foreach my $ns (keys %{$self->{NAMESPACES}}) {
      $storeString = $storeString."xmlns:".$ns."=\"".$self->{NAMESPACES}->{$ns}."\" ";
    }
    $storeString = $storeString.">";
    
    if($#resultsStringMD != -1) {   
      for(my $x = 0; $x <= $#resultsStringMD; $x++) {     	
	$storeString = $storeString . $resultsStringMD[$x];
      }    
    }
    else {
      perfSONAR_PS::MP::Base::error($self, $self->{CONF}->{"METADATA_DB_TYPE"}." returned 0 results for query \"".$query."\" ", __LINE__);      
    } 

    $query = "//nmwg:data";
    print "DEBUG:\tQuery: \"".$query."\" created.\n" if($self->{CONF}->{"DEBUG"});
    my @resultsStringD = $metadatadb->query($query);   
    
    if($#resultsStringD != -1) {    
      for(my $x = 0; $x <= $#resultsStringD; $x++) { 	
	$storeString = $storeString . $resultsStringD[$x];
      }
    }
    else {
      perfSONAR_PS::MP::Base::error($self, $self->{CONF}->{"METADATA_DB_TYPE"}." returned 0 results for query \"".$query."\" ", __LINE__); 
    }                 
    $storeString = $storeString."</nmwg:store>";

    my $parser = XML::LibXML->new();
    $self->{STORE} = $parser->parse_string($storeString); 
    cleanMetadata(\%{$self});
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
    my $filedb = new perfSONAR_PS::DB::File(
      $self->{CONF}->{"LOGFILE"},
      $self->{CONF}->{"METADATA_DB_FILE"},
      $self->{CONF}->{"DEBUG"}
    );  
   
    $filedb->openDB;   
    $self->{STORE} = $filedb->getDOM(); 
    cleanMetadata(\%{$self});
  }
  else {
    perfSONAR_PS::MP::Base::error($self, $self->{CONF}->{"METADATA_DB_TYPE"}." is not yet supported", __LINE__);
  }
  return;
}


sub prepareData {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::SNMP";  
  $self->{FUNCTION} = "\"prepareData\"";
  cleanData(\%{$self});
   
  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {    
    my $type = extract(\%{$self}, $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));
    my $file = extract(\%{$self}, $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));
    if($type eq "sqlite"){
      if(!defined $self->{DATADB}->{$file}) {  
        my @dbSchema = ("id", "time", "value", "eventtype", "misc");  
        $self->{DATADB}->{$file} = new perfSONAR_PS::DB::SQL(
          $self->{CONF}->{"LOGFILE"}, 
          "DBI:SQLite:dbname=".$file, 
          "", 
	  "", 
	  \@dbSchema,
	  $self->{CONF}->{"DEBUG"}
        );
      }
    }
    else {
      perfSONAR_PS::MP::Base::error($self, $type." is not supported", __LINE__);
      removeReferences(\%{$self}, $d->getAttribute("metadataIdRef"), $d->getAttribute("id"));
    }  
  }  
  return;
}


sub prepareCollectors {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareCollectors\"";
  foreach my $m ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
    if($self->{METADATAMARKS}->{$m->getAttribute("id")}) {
      my $commandString = $self->{CONF}->{"PING"}." ";
      my $topoPrefix = lookup($self, "http://ggf.org/ns/nmwg/topology/2.0/", "nmwgt");      
      my $pingPrefix = lookup($self, "http://ggf.org/ns/nmwg/tools/ping/2.0/", "ping");    
      my $host = extract(\%{$self}, $m->find(".//".$topoPrefix.":dst")->get_node(1)); 
      my $count = extract(\%{$self}, $m->find(".//".$pingPrefix.":parameters/nmwg:parameter[\@name=\"count\"]")->get_node(1));
             
      if(!defined $host or $host eq "") {
	perfSONAR_PS::MP::Base::error($self, "Destination host not specified", __LINE__);	  
      }
      else {
        $commandString = $commandString . $host;
        if(defined $count) {
          $commandString = $commandString . " -c " . $count;  
        }
	print "DEBUG:\tCommand \"".$commandString."\".\n" if($self->{CONF}->{"DEBUG"});
        $self->{AGENT}->{$m->getAttribute("id")} = new perfSONAR_PS::MP::Ping::Agent(
	  $self->{CONF}->{"LOGFILE"},
          $commandString
	);
      }
    }
  }
  return;
}


sub collectMeasurements {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"collectMeasurements\"";
  
  foreach my $p (keys %{$self->{AGENT}}) {
    print "Collecting for '" , $p , "'.\n";
    $self->{AGENT}->{$p}->collect;
  }
  
  my %dbSchemaValues = ();

  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
    my $type = extract(\%{$self}, $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));  
    my $file = extract(\%{$self}, $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));
    my $table = extract(\%{$self}, $d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"table\"]")->get_node(1));
      
    if($type eq "sqlite") {
      $self->{DATADB}->{$file}->openDB;
      my $results = $self->{AGENT}->{$d->getAttribute("metadataIdRef")}->getResults;
      foreach my $r (sort keys %{$results}) {
        print "DEBUG:\tinserting \"".$d->getAttribute("metadataIdRef").
              "\", \"".$results->{$r}->{"timeValue"}."\", \"".$results->{$r}->{"time"}.
	      "\", \"ping\", \""."numBytes=".$results->{$r}->{"bytes"}.",ttl=".
	      $results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.
	      ",units=".$results->{$r}->{"units"}."\" into table ".
	      $table.".\n" if($self->{CONF}->{"DEBUG"});
             
        %dbSchemaValues = (
          id => $d->getAttribute("metadataIdRef"), 
          time => $results->{$r}->{"timeValue"}, 
          value => $results->{$r}->{"time"}, 
          eventtype => "ping",  
          misc => "numBytes=".$results->{$r}->{"bytes"}.",ttl=".$results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.",units=".$results->{$r}->{"units"}
        );  
      
        $self->{DATADB}->{$file}->insert(
          $table,
	  \%dbSchemaValues
        );
      }
      $self->{DATADB}->{$file}->closeDB;
    }
  }  		
  return;
}





# ================ Internal Package perfSONAR_PS::MP::Ping::Agent ================

package perfSONAR_PS::MP::Ping::Agent;
use perfSONAR_PS::Common;
sub new {
  my ($package, $log, $cmd, $debug) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::Ping::Agent";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }  
  if(defined $cmd and $cmd ne "") {
    $hash{"CMD"} = $cmd;
  }  
  if(defined $debug and $debug ne "") {
    $hash{"DEBUG"} = $debug;  
  }    
  
  %{$hash{"RESULTS"}} = ();
  
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {    
    error($self, "Missing argument", __LINE__);   
  }
  return;
}


sub setCommand {
  my ($self, $cmd) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";
  $self->{FUNCTION} = "\"setCommand\"";  
  if(defined $cmd and $cmd ne "") {
    $self->{CMD} = $cmd;
  }
  else {
    error($self, "Missing argument", __LINE__);       
  }
  return;
}


sub setDebug {
  my ($self, $debug) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";
  $self->{FUNCTION} = "\"setDebug\"";  
  if(defined $debug and $debug ne "") {
    $self->{DEBUG} = $debug;
  }
  else {
    error($self, "Missing argument", __LINE__);         
  }
  return;
}


sub collect {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";  
  $self->{FUNCTION} = "\"collect\""; 
  if(defined $self->{CMD} and $self->{CMD} ne "") {   
    undef $self->{RESULTS};
     
    my($sec, $frac) = Time::HiRes::gettimeofday;
    my $time = eval($sec.".".$frac);
        
    open(CMD, $self->{CMD}." |") or 
      error($self, "Cannot open \"".$self->{CMD}."\"", __LINE__);
    my @results = <CMD>;    
    close(CMD);
    
    for(my $x = 1; $x <= ($#results-4); $x++) { 
      my @resultString = split(/:/,$results[$x]);        
      ($self->{RESULTS}->{$x}->{"bytes"} = $resultString[0]) =~ s/\sbytes.*$//;
      for ($resultString[1]) {
        s/\n//;
        s/^\s*//;
      }
    
      my @tok = split(/ /, $resultString[1]);
      foreach my $t (@tok) {
        if($t =~ m/^.*=.*$/) {
          (my $first = $t) =~ s/=.*$//;
	  (my $second = $t) =~ s/^.*=//;
	  $self->{RESULTS}->{$x}->{$first} = $second;  
        }
        else {
          $self->{RESULTS}->{$x}->{"units"} = $t;
        }
      }
      $self->{RESULTS}->{$x}->{"timeValue"} = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);
      $time = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);
    }
    
  }
  else {
    error($self, "Missing command string", __LINE__);     
  }
  return;
}


sub getResults {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";  
  $self->{FUNCTION} = "\"getResults\""; 
  if(defined $self->{RESULTS} and $self->{RESULTS} ne "") {   
    return $self->{RESULTS};
  }
  else {
    error($self, "Cannot return NULL results", __LINE__);    
  }
  return;
}


sub error {
  my($self, $msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{"DEBUG"});
  perfSONAR_PS::Common::printError($self->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  return;
}



1;


__END__


=head1 NAME

perfSONAR_PS::MP::Ping - A module that performs the tasks of an MP designed for the 
ping measurement.  

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to make ping measurements to various hosts.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use perfSONAR_PS::MP::Ping;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Ping/xmldb";
    $conf{"METADATA_DB_FILE"} = "pingstore.dbxml";
    $conf{"PING"} = "/bin/ping";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";
    $conf{"MP_SAMPLE_RATE"} = 1;
    $conf{"DEBUG"} = 1;
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/"    
    );
    
    my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "");
    
    # or:
    #
    # $mp = new perfSONAR_PS::MP::Ping;
    # $mp->setConf(\%conf);
    # $mp->setNamespaces(\%ns);
    # $mp->setStore();
                
    $mp->parseMetadata;
    $mp->prepareData;
    $mp->prepareCollectors;  
 
    while(1) {
      $mp->collectMeasurements; 
      sleep($conf{"MP_SAMPLE_RATE"});
    }
    
    
=head1 DETAILS

This module contains an 'Agent' submodule that is not meant to act as a standalone, but 
rather as a specialized structure for use only in this module.  The functions include:

  new($log, $cmd)

    The 'log' argument is the name of the log file where error or warning information 
    may be recorded.  The 'cmd' argument is the physical command to execute to gather 
    measurement data.

  setLog($log)

    (Re-)Sets the log file for the ping agent object.

  setCommand($cmd)

    (Re-)Sets the command for the ping agent object.
    
  setDebug($debug)

    (Re-)Sets the debug flag for the ping agent object.  

  collect()

     Executes the command, parses, and stores the results into an object.

  getResults()

     Returns the results object so it may be parsed.  
     
  error($self, $msg, $line)	

    A 'message' argument is used to print error information to the screen and log files 
    (if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
    Meant to be used internally.

A brief description using the API:
   
    my $agent = new perfSONAR_PS::MP::Ping::Agent("./error.log", "/bin/ping -c 1 localhost");

    # or also:
    # 
    # my $agent = new perfSONAR_PS::MP::Ping::Agent;
    # $agent->setLog("./error.log");
    # $agent->setCommand("/bin/ping -c 1 localhost");
    # $agent->setDebug(1);
        
    $agent->collect();

    my $results = $agent->getResults;
    foreach my $r (sort keys %{$results}) {
      foreach my $r2 (keys %{$results->{$r}}) {
        print $r , " - " , $r2 , " - " , $results->{$r}->{$r2} , "\n"; 
      }
      print "\n";
    }
    
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

Prepares the 'perfSONAR_PS::MP::Ping::Agent' objects for each of the metadata values in
the metadata object.

=head2 collectMeasurements()

Cycles through each of the 'perfSONAR_PS::MP::Ping::Agent' objects and gathers the 
necessary values.  

=head2 error($self, $msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<perfSONAR_PS::MP::Base>, L<perfSONAR_PS::MP::General>, L<perfSONAR_PS::Common>, 
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

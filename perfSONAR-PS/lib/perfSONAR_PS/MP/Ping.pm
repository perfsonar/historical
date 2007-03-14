#!/usr/bin/perl

package perfSONAR_PS::MP::Ping;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MP::General;

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();
our $VERSION = '0.02';

# ================ Internal Package perfSONAR_PS::MP::Ping::Agent ================

package perfSONAR_PS::MP::Ping::Agent;
use Carp qw( croak );
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
    error("Missing argument", __LINE__);   
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
    error("Missing argument", __LINE__);       
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
    error("Missing argument", __LINE__);         
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
      error("Cannot open \"".$self->{CMD}."\"", __LINE__);
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
    error("Missing command string", __LINE__);     
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
    error("Cannot return NULL results", __LINE__);    
  }
  return;
}


sub error {
  my($msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{"DEBUG"});
  printError($self->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  return;
}


# ================ Main Package perfSONAR_PS::MP::Ping ================


package perfSONAR_PS::MP::Ping;
sub new {
  my ($package, $conf, $ns, $metadata, $data) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::Ping";
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
  %{$hash{"PING"}} = ();
      
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"setHost\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    error("Missing argument", __LINE__);    
  }
  return;
}


sub setMetadata {
  my ($self, $metadata) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";    
  $self->{FUNCTION} = "\"setMetadata\"";  
  if(defined $metadata and $metadata ne "") {
    $self->{METADATA} = \%{$metadata};
  }
  else {
    error("Missing argument", __LINE__); 
  }
  return;
}


sub setData {
  my ($self, $data) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";    
  $self->{FUNCTION} = "\"setData\"";  
  if(defined $data and $data ne "") {
    $self->{DATA} = \%{$data};
  }
  else {
    error("Missing argument", __LINE__);    
  }
  return;
}


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
    
    if($#resultsStringMD != -1) {    
      for(my $x = 0; $x <= $#resultsStringMD; $x++) {     	
	parse($resultsStringMD[$x], \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, $query);
      }      
    }
    else {	
      error($self->{CONF}->{"METADATA_DB_TYPE"}." returned 0 results for query \"".$query."\" ", __LINE__);      
    }     

    $query = "//nmwg:data";
    print "DEBUG:\tQuery: \"".$query."\" created.\n" if($self->{CONF}->{"DEBUG"});
    my @resultsStringD = $metadatadb->query($query);   
    
    if($#resultsStringD != -1) {    
      for(my $x = 0; $x <= $#resultsStringD; $x++) { 	
        parse($resultsStringD[$x], \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, $query);
      }
    }
    else {
      error($self->{CONF}->{"METADATA_DB_TYPE"}." returned 0 results for query \"".$query."\" ", __LINE__);  
    }          
    cleanMetadata(\%{$self}); 
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
    my $xml = readXML($self->{CONF}->{"METADATA_DB_FILE"});
    print "DEBUG:\tParsing \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" file.\n" if($self->{CONF}->{"DEBUG"});
    parse($xml, \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, "//nmwg:metadata");
    parse($xml, \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, "//nmwg:data");	
    cleanMetadata(\%{$self});  
  }
  elsif(($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql") or 
        ($self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite")) {
    error($self->{CONF}->{"METADATA_DB_TYPE"}." is not yet supported", __LINE__);     
  }  
  else {
    error($self->{CONF}->{"METADATA_DB_TYPE"}." is not yet supported", __LINE__);
  }
  return;
}


sub prepareData {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareData\"";
      
  foreach my $d (keys %{$self->{DATA}}) {
    if($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite"){
      if(!defined $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}) {        
	my @dbSchema = ("id", "time", "value", "eventtype", "misc");
	$self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}} = 
          new perfSONAR_PS::DB::SQL($self->{CONF}->{"LOGFILE"},
	                               "DBI:SQLite:dbname=".$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}, 
                                       "",
                                       "",
				       \@dbSchema,
				       $self->{CONF}->{"DEBUG"});
      }
    }
    elsif(($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") or 
          ($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql")) {
      error($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}." is not yet supported", __LINE__);	  	    
      removeReferences(\%{$self}, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }
    else {
      error($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}." is not yet supported", __LINE__);	
      removeReferences(\%{$self}, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }  
  }  
  return;
}


sub prepareCollectors {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareCollectors\"";
        
  foreach my $m (keys %{$self->{METADATA}}) {
    if($self->{METADATAMARKS}->{$m}) {
      my $commandString = $self->{CONF}->{"PING"}." ";
      my $host = "";
      foreach my $m2 (keys %{$self->{METADATA}->{$m}}) {
        if($m2 =~ m/.*dst-value$/) {
          $host = $self->{METADATA}->{$m}->{$m2};
        }
        elsif($m2 =~ m/.*ping:parameters\/nmwg:parameter-count$/) {
          $commandString = $commandString . "-c " . $self->{METADATA}->{$m}->{$m2} . " ";
        }
      }  
      
      if(!defined $host or $host eq "") {
	error("Destination host not specified", __LINE__);	  
      }
      else {
        $commandString = $commandString . $host;
	print "DEBUG:\tCommand \"".$commandString."\".\n" if($self->{CONF}->{"DEBUG"});
	
        $self->{PING}->{$m} = new perfSONAR_PS::MP::Ping::Agent(
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
  
  foreach my $p (keys %{$self->{PING}}) {
    print "Collecting for '" , $p , "'.\n";
    $self->{PING}->{$p}->collect;
  }
  
  my %dbSchemaValues = ();
  
  foreach my $d (keys %{$self->{DATA}}) {
    $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->openDB;
    my $results = $self->{PING}->{$self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}}->getResults;
    foreach my $r (sort keys %{$results}) {
      
      print "DEBUG:\tinserting \"".$self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}.
            "\", \"".$results->{$r}->{"timeValue"}."\", \"".$results->{$r}->{"time"}.
	    "\", \"ping\", \""."numBytes=".$results->{$r}->{"bytes"}.",ttl=".
	    $results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.
	    ",units=".$results->{$r}->{"units"}."\" into table ".
	    $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"}.
	    ".\n" if($self->{CONF}->{"DEBUG"});
             
      %dbSchemaValues = (
        id => $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}, 
        time => $results->{$r}->{"timeValue"}, 
        value => $results->{$r}->{"time"}, 
        eventtype => "ping",  
        misc => "numBytes=".$results->{$r}->{"bytes"}.",ttl=".$results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.",units=".$results->{$r}->{"units"}
      );  
      
      $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->insert(
        $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"},
	\%dbSchemaValues
      );
      
    }
    $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->closeDB;
  }		
  return;
}


sub error {
  my($msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{CONF}->{"DEBUG"});
  printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
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
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/"    
    );
    
    my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "", "");
    
    # or:
    #
    # $mp = new perfSONAR_PS::MP::Ping;
    # $mp->setConf(\%conf);
    # $mp->setNamespaces(\%ns);
    # $mp->setMetadata("");
    # $mp->setData("");
                
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
     
  error($msg, $line)	

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

=head2 prepareData()

Prepares data db objects that relate to each of the valid data values in the data object.  

=head2 prepareCollectors()

Prepares the 'perfSONAR_PS::MP::Ping::Agent' objects for each of the metadata values in
the metadata object.

=head2 collectMeasurements()

Cycles through each of the 'perfSONAR_PS::MP::Ping::Agent' objects and gathers the 
necessary values.  

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>, 
L<perfSONAR_PS::MA::Ping>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

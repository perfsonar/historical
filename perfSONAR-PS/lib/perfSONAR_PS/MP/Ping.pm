#!/usr/bin/perl

package perfSONAR_PS::MP::Ping;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();
our $VERSION = '0.02';

# ================ Internal Package perfSONAR_PS::MP::Ping::Agent ================

package perfSONAR_PS::MP::Ping::Agent;
use perfSONAR_PS::Common;
sub new {
  my ($package, $log) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::Ping::Agent";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }  
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
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
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
  %{$hash{"LOOKUP"}} = ();
  %{$hash{"AGENT"}} = ();
      
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
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
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
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
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
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
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
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
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
      \%{$self->{NAMESPACES}}
    );

    $metadatadb->openDB;
    my $query = "//nmwg:metadata";
    my @resultsStringMD = $metadatadb->query($query);   
    if($#resultsStringMD != -1) {    
      for(my $x = 0; $x <= $#resultsStringMD; $x++) {     	
	parse($resultsStringMD[$x], \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, $query);
      }      
print "Metadata:\t" , Dumper($self->{METADATA}) , "\n";
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
print "Data:\t" , Dumper($self->{DATA}) , "\n";
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
print "Metadata:\t" , Dumper($self->{METADATA}) , "\n";
print "Data:\t" , Dumper($self->{DATA}) , "\n";
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
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
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


sub prepareData {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareData\"";
      
  foreach my $d (keys %{$self->{DATA}}) {
    if($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite"){
      if(!defined $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}) {
        $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}} = 
          new perfSONAR_PS::DB::SQL($self->{CONF}->{"LOGFILE"},
	                               "DBI:SQLite:dbname=".$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}, 
                                       "",
                                       "");
      }
    }
    elsif(($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") or 
          ($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql")) {
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


sub removeReferences {
  my($self, $id) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
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


sub prepareCollectors {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareCollectors\"";
        
  
  foreach my $m (keys %{$self->{METADATA}}) {
    if($self->{METADATAMARKS}->{$m}) {

      my $commandString = "/bin/ping ";
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
        my $msg = "Destination host not specified.";
        printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
          if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
      }
      else {
        $commandString = $commandString . $host;
        print "CMD: " , $commandString , "\n";
      }
      
    }
  }

  return;
}


1;


__END__


=head1 NAME

perfSONAR_PS::MP::Ping - A module starting point for MP functions...

=head1 DESCRIPTION

...

=head1 SYNOPSIS

    use perfSONAR_PS::MP::Ping;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Ping/xmldb";
    $conf{"METADATA_DB_FILE"} = "Pingstore.dbxml";
    $conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      Ping => "http://ggf.org/ns/nmwg/tools/Ping/2.0/"    
    );
    
    my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "", "");

=head1 DETAILS

This module contains a submodule that is not meant to act as a standalone, but rather as
a specialized structure for use only in this module.  The functions include:


  new($log)

    The 'log' argument is the name of the log file where error or warning information may be 
    recorded.

  setLog($log)

    (Re-)Sets the log file for the Ping object.


A brief description using the API:
   
    my $agent = new perfSONAR_PS::MP::Ping::Agent("./error.log");

    # or also:
    # 
    # my $agent = new perfSONAR_PS::MP::Ping::Agent;
    # $agent->setLog("./error.log");


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

=head1 SEE ALSO

L<Net::SNMP>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::MP::SNMP>, 
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

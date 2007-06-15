#!/usr/bin/perl -w

package skeletonMP;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MP::Base;
use perfSONAR_PS::MP::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::SQL;

our @ISA = qw(perfSONAR_PS::MP::Base);


sub parseMetadata {
  my($self) = @_;
  my $logger = get_logger("skeletonMP");
  
  # Insert handling for other forms of database here, such as the xmldb.
  
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {   
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
  my $logger = get_logger("skeletonMP");
  
  cleanData(\%{$self});
  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {    
    my $type = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));
    my $file = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));        

    # insert other 'back-end' database access methods here.  RRD is a popular choice.

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
  my $logger = get_logger("skeletonMP");
      
  foreach my $m ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
    if($self->{METADATAMARKS}->{$m->getAttribute("id")}) {

      # upgrade this section to the specifics of your tool
 
      my $commandString = $self->{CONF}->{"TOOL"};
	    $logger->debug("Command \"".$commandString."\"");
      $self->{AGENT}->{$m->getAttribute("id")} = new skeletonMP::Agent(
        $commandString
	    );

    }    
  }  
  return;
}


sub collectMeasurements {
  my($self) = @_;
  my $logger = get_logger("skeletonMP");
  
  foreach my $p (keys %{$self->{AGENT}}) {
    $logger->debug("Collecting for '" , $p , "'.");
    $self->{AGENT}->{$p}->collect;
  }
  
  my %dbSchemaValues = ();

  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
    my $type = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));  
    my $file = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));
    
    # add other database access methods here
    
    if($type eq "sqlite") {
      my $table = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"table\"]")->get_node(1));
      $self->{DATADB}->{$file}->openDB;
      my $results = $self->{AGENT}->{$d->getAttribute("metadataIdRef")}->getResults;

      $logger->debug("Inserting \"".$d->getAttribute("metadataIdRef").
        "\", \"".$results->{"timeValue"}."\", \"".$results->{"time"}.
	      "\", \"ping\", \"\" into table ".$table.".");
             
      %dbSchemaValues = (
        id => $d->getAttribute("metadataIdRef"), 
        time => $results->{"timeValue"}, 
        value => $results->{"time"}, 
        eventtype => "skeleton",  
        misc => ""
      );  
      
      $self->{DATADB}->{$file}->insert(
        $table,
	      \%dbSchemaValues
      );
      
      $self->{DATADB}->{$file}->closeDB;
    }
  }  
  
  return;
}





# ================ Internal Package skeletonMP::Agent ================

package skeletonMP::Agent;

use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;



sub new {
  my ($package, $cmd) = @_; 
  my %hash = ();
  if(defined $cmd and $cmd ne "") {
    $hash{"CMD"} = $cmd;
  }    
  %{$hash{"RESULTS"}} = ();
  bless \%hash => $package;
}


sub setCommand {
  my ($self, $cmd) = @_;  
  my $logger = get_logger("skeletonMP::Agent");
  if(defined $cmd and $cmd ne "") {
    $self->{CMD} = $cmd;
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}


sub collect {
  my ($self) = @_;
  my $logger = get_logger("skeletonMP::Agent");
  
  if(defined $self->{CMD} and $self->{CMD} ne "") {   
    undef $self->{RESULTS};
     
    # upgrade thise section with specifics for your tool 
     
    my($sec, $frac) = Time::HiRes::gettimeofday;
    $self->{RESULTS}->{"timeValue"} = eval($sec.".".$frac);
        
    open(CMD, $self->{CMD}." |") or 
      $logger->error("Cannot open \"".$self->{CMD}."\"");
    my @results = <CMD>;    
    close(CMD);
    
    ($self->{RESULTS}->{"time"} = $results[0]) =~ s/\n//;
  }
  else {
    $logger->error("Missing command string.");     
  }
  return;
}


sub getResults {
  my ($self) = @_;
  my $logger = get_logger("skeletonMP::Agent");
  
  if(defined $self->{RESULTS} and $self->{RESULTS} ne "") {   
    return $self->{RESULTS};
  }
  else {
    $logger->error("Cannot return NULL results.");    
  }
  return;
}


1;


__END__


=head1 NAME

skeletonMP - A module that performs the tasks of an MP designed for some form of measurement.  

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to make measurements to various hosts.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use skeletonMP;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "file";
    $conf{"METADATA_DB_NAME"} = "";
    $conf{"METADATA_DB_FILE"} = "/home/jason/perfSONAR-PS/MP/Ping/store.xml";
    $conf{"MP_SAMPLE_RATE"} = 1;
    $conf{"TOOL"} = "perl -e 'print rand(),\"\n;\"'";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
      skeleton => "http://ggf.org/ns/nmwg/tools/skeleton/2.0/"
    );
    
    my $mp = new skeletonMP(\%conf, \%ns, "");
    
    # or:
    #
    # $mp = new skeletonMP;
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

  new($cmd)

    The 'log' argument is the name of the log file where error or warning information 
    may be recorded.  The 'cmd' argument is the physical command to execute to gather 
    measurement data.

  setCommand($cmd)

    (Re-)Sets the command for the ping agent object. 

  collect()

     Executes the command, parses, and stores the results into an object.

  getResults()

     Returns the results object so it may be parsed.  

A brief description using the API:
   
    my $agent = new skeletonMP::Agent("perl -e 'print rand(),\"\n;\"'");

    # or also:
    # 
    # my $agent = new skeletonMP::Agent;
    # $agent->setCommand("perl -e 'print rand(),\"\n;\"'");

        
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

Prepares the 'skeletonMP::Agent' objects for each of the metadata values in
the metadata object.

=head2 collectMeasurements()

Cycles through each of the 'skeletonMP::Agent' objects and gathers the 
necessary values.  

=head1 SEE ALSO

L<perfSONAR_PS::MP::Base>, L<perfSONAR_PS::MP::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::SQL>

To join the 'perfSONAR-PS' mailing list, please visit:

  L<https://mail.internet2.edu/wws/info/i2-perfsonar>

The perfSONAR-PS subversion repository is located at:

  L<https://svn.internet2.edu/svn/perfSONAR-PS >
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

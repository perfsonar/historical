#!/usr/bin/perl -w

package perfSONAR_PS::MP::Traceroute;

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
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute");
  
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
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute");
  
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
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute");
      
  foreach my $m ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "metadata")) {
    if($self->{METADATAMARKS}->{$m->getAttribute("id")}) {

      my $topoPrefix = lookup($self, "http://ggf.org/ns/nmwg/topology/2.0/", "nmwgt");      
      my $traceroutePrefix = lookup($self, "http://ggf.org/ns/nmwg/tools/traceroute/2.0/", "trace");    
      my $source = extract($m->find(".//".$topoPrefix.":src")->get_node(1)); 
      my $destination = extract($m->find(".//".$topoPrefix.":dst")->get_node(1)); 
      my $numQueries = extract($m->find(".//".$traceroutePrefix.":parameters/nmwg:parameter[\@name=\"numQueries\"]")->get_node(1));
             
      if(!defined $destination or $destination eq "") {
        $logger->error("Destination host not specified.");	         
      }
      else {
        $self->{AGENT}->{$m->getAttribute("id")} = new perfSONAR_PS::MP::Traceroute::Agent(
          $source, 
          $destination, 
          $numQueries
        );
      }
    }    
  }  
  return;
}


sub collectMeasurements {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute");
  
  foreach my $p (keys %{$self->{AGENT}}) {
    $logger->debug("Collecting for '" , $p , "'.");
    $self->{AGENT}->{$p}->collect;
  }
  
  my %dbSchemaValues = ();
  foreach my $d ($self->{STORE}->getElementsByTagNameNS($self->{NAMESPACES}->{"nmwg"}, "data")) {
    my $type = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"type\"]")->get_node(1));  
    my $file = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"file\"]")->get_node(1));

    if($type eq "sqlite") {
      my $table = extract($d->find("./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"table\"]")->get_node(1));

      $self->{DATADB}->{$file}->openDB;
      my $results = $self->{AGENT}->{$d->getAttribute("metadataIdRef")}->getResults;

      foreach my $hop (keys %{$results}) {
        $logger->debug("hop = " . $hop);
        foreach my $query (keys %{$results->{$hop}}){
          $logger->debug("query = " . $query);
          my $misc = "hop=".$hop;
          $misc .= ",query=".$query;
          $misc .= ",host=".$results->{$hop}->{$query}->{"host"};
          $misc .= ",status=".$results->{$hop}->{$query}->{"status"};
          $misc .= ",endhost=".$results->{$hop}->{$query}->{"endhost"};
          $misc .= ",source=".$results->{$hop}->{$query}->{"source"};

          $logger->debug("inserting \"".$d->getAttribute("metadataIdRef").
            "\"".$misc."\" with time of day ".$results->{$hop}->{$query}->{"time"}.
            " and time for hop ".$results->{$hop}->{$query}->{"hoptime"}.
            " into table ".$table);
              
          %dbSchemaValues = (
            id => $d->getAttribute("metadataIdRef"), 
            time => $results->{$hop}->{$query}->{"time"}, 
            value => $results->{$hop}->{$query}->{"hoptime"}, 
            eventtype => "traceroute",  
            misc => $misc
          );  
      
          $self->{DATADB}->{$file}->insert(
            $table,
            \%dbSchemaValues
          );
        }
      }
      $self->{DATADB}->{$file}->closeDB;
    }
    else {
      $logger->debug("Database not supported.");
    }
  }  
  
  return;
}





# ================ Internal Package perfSONAR_PS::MP::Traceroute::Agent ================

package perfSONAR_PS::MP::Traceroute::Agent;

use Log::Log4perl qw(get_logger);
use Net::Traceroute;
use perfSONAR_PS::Common;



sub new {
  my ($package, $source, $destination, $numQueries) = @_; 
  my %hash = ();
  if(defined $source and $source ne "") {
    $hash{"SOURCE"} = $source;
  }
  if(defined $destination and $destination ne "") {
    $hash{"DESTINATION"} = $destination;
  }    
  if(defined $numQueries and $numQueries ne "") {
    $hash{"NUMQUERIES"} = $numQueries;
  }    
  %{$hash{"RESULTS"}} = ();
  bless \%hash => $package;
}


sub setSource {
  my ($self, $source) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute::Agent");
  if(defined $source and $source ne "") {
    $self->{SOURCE} = $source;
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}

sub setDestination {
  my ($self, $destination) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute::Agent");
  if(defined $destination and $destination ne "") {
    $self->{DESTINATION} = $destination;
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}

sub setNumQueries {
  my ($self, $numQueries) = @_;  
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute::Agent");
  if(defined $numQueries and $numQueries ne "") {
    $self->{NUMQUERIES} = $numQueries;
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}

sub collect {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute::Agent");
  
  if(defined $self->{DESTINATION} and $self->{DESTINATION} ne "") {   
    undef $self->{RESULTS};
          
    my($sec, $frac) = Time::HiRes::gettimeofday;
    my $time = eval($sec.".".$frac);

    if(!defined $self->{NUMQUERIES} or $self->{NUMQUERIES} eq "") {
      $self->{NUMQUERIES} = 3;
    }
    
    my $obj = Net::Traceroute->new(
      host => $self->{DESTINATION}, 
      queries => $self->{NUMQUERIES}
    );
    
    for(my $hop = 0; $hop < $obj->hops; $hop++) { 
      for (my $query = 0; $query < $obj->hop_queries($hop); $query++){
      
        $logger->debug("Hop ".$hop.", query ".$query.": host=".
          $obj->hop_query_host($hop, $query).", hoptime = ".
          $obj->hop_query_time($hop, $query));
          
        $self->{RESULTS}->{$hop}->{$query}{"status"} = $obj->hop_query_stat($hop, $query);
        $self->{RESULTS}->{$hop}->{$query}{"host"} = $obj->hop_query_host($hop, $query);
        $self->{RESULTS}->{$hop}->{$query}{"hoptime"} = $obj->hop_query_time($hop, $query);
        $self->{RESULTS}->{$hop}->{$query}{"time"} = $time;
        $self->{RESULTS}->{$hop}->{$query}{"endhost"} = $self->{DESTINATION};
        $self->{RESULTS}->{$hop}->{$query}{"source"} = $self->{SOURCE};
      }
    }
  }
  else {
    $logger->error("Missing destination host.");     
  }
  return;
}


sub getResults {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MP::Traceroute::Agent");
  
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

perfSONAR_PS::MP::Traceroute - A module that performs the tasks of an MP designed for the 
traceroute measurement.  

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to make traceroute measurements to various hosts.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use perfSONAR_PS::MP::Traceroute;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/Traceroute/xmldb";
    $conf{"METADATA_DB_FILE"} = "traceroutestore.dbxml";
    $conf{"PING"} = "/usr/sbin/traceroute";
    $conf{"MP_SAMPLE_RATE"} = 1;
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      traceroute => "http://ggf.org/ns/nmwg/tools/traceroute/2.0/"    
    );
    
    my $mp = new perfSONAR_PS::MP::Traceroute(\%conf, \%ns, "");
    
    # or:
    #
    # $mp = new perfSONAR_PS::MP::Traceroute;
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

    (Re-)Sets the command for the traceroute agent object. 

  collect()

     Executes the command, parses, and stores the results into an object.

  getResults()

     Returns the results object so it may be parsed.  

A brief description using the API:
   
    my $agent = new perfSONAR_PS::MP::Traceroute::Agent("/usr/sbin/traceroute localhost");

    # or also:
    # 
    # my $agent = new perfSONAR_PS::MP::Traceroute::Agent;
    # $agent->setCommand("/usr/sbin/traceroute localhost");

        
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

Prepares the 'perfSONAR_PS::MP::Traceroute::Agent' objects for each of the metadata values in
the metadata object.

=head2 collectMeasurements()

Cycles through each of the 'perfSONAR_PS::MP::Traceroute::Agent' objects and gathers the 
necessary values.  

=head1 SEE ALSO

L<perfSONAR_PS::MP::Base>, L<perfSONAR_PS::MP::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::SQL>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Ben Perry <pianoman@UDel.Edu>, Jason Zurawski <zurawski@internet2.edu>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

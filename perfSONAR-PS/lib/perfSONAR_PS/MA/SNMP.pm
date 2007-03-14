#!/usr/bin/perl

package perfSONAR_PS::MA::SNMP;
use Carp qw( croak );
use XML::XPath;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MA::General;

@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $conf, $ns, $metadata, $data) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MA::SNMP";
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

  %{$hash{"RESULTS"}} = ();  
  %{$hash{"TIME"}} = ();
    
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  $self->{FUNCTION} = "\"setConf\"";  
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
  $self->{FUNCTION} = "\"setData\"";  
  if(defined $data and $data ne "") {
    $self->{DATA} = \%{$data};
  }
  else {
    error("Missing argument", __LINE__);  
  }
  return;
}


sub handleRequest {
  my($self, $request) = @_;
  my $response = "";

  my $xp = XML::XPath->new( xml => $request );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  my $nodeset = $xp->find('//nmwg:message');

  if($nodeset->size() < 1) {
    error("Message element not found within request", __LINE__);  
    $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);  
  }
  elsif($nodeset->size() == 1) {
    my @messages = $nodeset->get_nodelist;
    my $messageId = "";
    my $messageType = "";    
    my $messageIdReturn = genuid();    
    foreach my $attr ($messages[0]->getAttributes) {
      if($attr->getLocalName eq "id") {
        $messageId = $attr->getNodeValue;
      }
      elsif($attr->getLocalName eq "type") {
        $messageType = $attr->getNodeValue;
      }
    }
    
    parse($request, \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, "//nmwg:metadata");
    chainMetadata(\%{$self->{METADATA}});
    parse($request, \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, "//nmwg:data");   
            
    foreach my $m (keys %{$self->{METADATA}}) {
      if(countRefs($m, \%{$self->{DATA}}, "nmwg:data-metadataIdRef") == 0) {
        delete $self->{METADATA}->{$m};
      }
    }

    if($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql" or 
       $self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite" or 
       $self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {      
      error("Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not yet supported", __LINE__);  
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    }  
    elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
      my $localContent = "";
      foreach my $d (keys %{$self->{DATA}}) {
        foreach my $m (keys %{$self->{METADATA}}) {  
          if($self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"} eq $m) { 
           
	    my $queryString = "/nmwg:metadata[" . getMetadatXQuery(\%{$self->{METADATA}}, \%{$self->{TIME}}, $m) . "]/\@id";	  

	    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
              $self->{CONF}->{"LOGFILE"},
              $self->{CONF}->{"METADATA_DB_NAME"}, 
              $self->{CONF}->{"METADATA_DB_FILE"},
              \%{$self->{NAMESPACES}}
            );	  
            $metadatadb->openDB;              

            print $self->{FILENAME}.":\tquery \"".$queryString."\" in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});

	    my @resultsString = $metadatadb->query($queryString);   
	    if($#resultsString != -1) {    
              for(my $x = 0; $x <= $#resultsString; $x++) {	
                $resultsString[$x] =~ s/\{\}id=//;
                $resultsString[$x] =~ s/\"//g;
                $resultsString[$x] =~ s/\n//;	    
	        
                $queryString = "/nmwg:data[\@metadataIdRef='".$resultsString[$x]."']";
                my @dataResultsString = $metadatadb->query($queryString);
	        if($#dataResultsString != -1) {    
                  $queryString = "/nmwg:metadata[\@id='".$resultsString[$x]."']";

                  my @metadataResultsString = $metadatadb->query($queryString);		  

                  $localContent = $localContent . $metadataResultsString[0];
                  
		  for(my $y = 0; $y <= $#dataResultsString; $y++) {
		    undef $self->{RESULTS};		    
		    parse($dataResultsString[$x], \%{$self->{RESULTS}}, \%{$self->{NAMESPACES}}, "//nmwg:data");		  
		    @dataIds = keys(%{$self->{RESULTS}});
		    if($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
		      $localContent = $localContent . retrieveRRD($self, $dataIds[0]); 
		      $response = getResultMessage($messageIdReturn, $messageId, "response", $localContent);
		    }
		    elsif(($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql") or 
		          ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") or 
			  ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "xmldb") or 
			  ($self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "file")){
		      error("Database \"".$self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}.
		            "\" is not yet supported", __LINE__);  
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		    else {
		      error("Database \"".$self->{RESULTS}->{$dataIds[0]}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}.
		            "\" is not yet supported", __LINE__);  
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		  }
		}
                else {
		  error("Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search", __LINE__);  
                  $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
                }		    
	      }	  
	    }
            else {
              error("Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search", __LINE__);  
              $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
            }
	  }   
        }
      }
    } 
    else {
      error("Database \"".$self->{CONF}->{"METADATA_DB_TYPE"}."\" is not yet supported", __LINE__);   
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    } 
  }
  else {
    error("Too many message elements found within request", __LINE__); 
    $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
  }
  return $response;
}


sub retrieveRRD {
  my($self, $did) = @_;
  my $responseString = "";

  my $id = genuid();
  my $datadb = new perfSONAR_PS::DB::RRD(
    $self->{CONF}->{"LOGFILE"},
    $self->{CONF}->{"RRDTOOL"}, 
    $self->{RESULTS}->{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
    "",
    1
  );
		      
  $datadb->openDB();
  my %rrd_result = $datadb->query(
    $self->{TIME}->{"CF"}, 
    $self->{TIME}->{"RESOLUTION"}, 
    $self->{TIME}->{"START"}, 
    $self->{TIME}->{"END"}
  );
  
  if($datadb->getErrorMessage()) {
    error("Query error \"".$datadb->getErrorMessage()."\"; query returned \"".$rrd_result{ANSWER}."\"", __LINE__);
    $responseString = $responseString . getResultCodeData($id, $self->{RESULTS}->{$did}->{"nmwg:data-metadataIdRef"}, $msg); 
  }
  else {
    my @keys = keys(%rrd_result);
    $responseString = $responseString . "  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$self->{RESULTS}->{$did}->{"nmwg:data-metadataIdRef"}."\">\n";
    foreach $a (sort(keys(%rrd_result))) {
      foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
	if($b eq $self->{RESULTS}->{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"}) {
	  $responseString = $responseString . "    <nmwg:datum time=\"".$a."\" value=\"".$rrd_result{$a}{$b}."\" valueUnits=\"".$self->{RESULTS}->{$did}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-valueUnits"}."\"/>\n";
        }
      }
    }
    $responseString = $responseString . "  </nmwg:data>\n";
  }
  $datadb->closeDB();	
  return $responseString;
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

perfSONAR_PS::MA::SNMP - A module that provides methods for the SNMP MA.  

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::SNMP;

    my $requestMessage = "some xml request";

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
    
    my $ma = perfSONAR_PS::MA::SNMP->new(\%conf);

    # or
    # $ma = perfSONAR_PS::MA::SNMP->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);    
    
    my $response = $ma->handleRequest($requestMessage, \%ns); 

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf)

The only argument represents the 'conf' hash from the calling MA.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 handleRequest($request, \%ns)

Given a request and a namespace hash, interact with the metadata and data databases 
(information will be collected from the conf hash as well as the backend metadata storage)
and a response will be returned.  This response could be the correct data, or it could be
a descriptive error message if something happened to go wrong. 

=head2 retrieveRRD($sentd, $did, $sentt)	

Given a data and metadata hash, and the time information, the data is extracted from the
backed storage (in this case RRD). 

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MP::Ping>, L<perfSONAR_PS::MA::General>, 
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

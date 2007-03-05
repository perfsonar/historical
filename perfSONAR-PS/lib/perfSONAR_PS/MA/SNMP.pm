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

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $conf) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MA::SNMP";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  $self->{FUNCTION} = "\"setConf\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub handleRequest {
  my($self, $request, $ns) = @_;
  my $response = "";

print "REQUEST: " , $request , "\n";

  my $xp = XML::XPath->new( xml => $request );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  my $nodeset = $xp->find('//nmwg:message');

  if($nodeset->size() < 1) {
    my $msg = "Message elements not found in request; send only one (1) message element.";
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
    $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);  
  }
  elsif($nodeset->size() == 1) {
    @messages = $nodeset->get_nodelist;
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
    
    my %metadata = ();
    my %data = ();      
    parse($request, \%metadata, \%{$ns}, "//nmwg:metadata");;
    chainMetadata(\%metadata);
    parse($request, \%data, \%{$ns}, "//nmwg:data");      
    
print "Metadata: " , Dumper(%metadata) , "\n";    
print "Data: " , Dumper(%data) , "\n";  
    
    foreach my $m (keys %metadata) {
      if(countRefs($m, \%data, "nmwg:data-metadataIdRef") == 0) {
        delete $metadata{$m};
      }
    }
          
    if($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql" or $self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite" or $self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
      my $msg = "The metadata database '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is not yet supported.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    }  
    elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {
      my $localContent = "";
      foreach my $d (keys %data) {
        foreach my $m (keys %metadata) {  
          if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) { 
            
	    my $queryString = "/nmwg:metadata[" . getMetadatXQuery($self, \%metadata, $m);	    
	    my %time = getRange($self, \%metadata, $m);

	    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
              $self->{CONF}->{"LOGFILE"},
              $self->{CONF}->{"METADATA_DB_NAME"}, 
              $self->{CONF}->{"METADATA_DB_FILE"},
              \%{$ns}
            );	  
            $metadatadb->openDB;              

print "Query: " , $queryString , "\n";
	    
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
		    my %dresults = ();
		    parse($dataResultsString[$x], \%dresults, \%{$ns}, "//nmwg:data");		  
    
		    @dataIds = keys(%dresults);
		    if($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
                      $localContent = $localContent . retrieveRRD($self, \%dresults, $dataIds[0], \%time); 
		      $response = getResultMessage($messageIdReturn, $messageId, "response", $localContent);
		    }
		    elsif(($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql") or 
		          ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") or 
			  ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "xmldb") or 
			  ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "file")){
                      my $msg = "The data database '".$dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}."' is not yet supported.";
                      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
                        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		    else {
                      my $msg = "The data database '".$dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}."' is not yet supported.";
                      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
                        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		  }		  	  
		}
                else {
                  my $msg = "The database '".$self->{CONF}->{"METADATA_DB_TYPE"}."' returned 0 results for the data search.";
                  printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
                    if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
                  $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
                }		    
	      }
	    }
            else {
              my $msg = "The database '".$self->{CONF}->{"METADATA_DB_TYPE"}."' returned 0 results for the metadata search.";
              printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
                if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
              $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
            }
	  }   
        }
      }
    } 
    else {
      my $msg = "The metadata database '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is not yet supported.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");  
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    } 
  }
  else {
    my $msg = "Too many message elements found in request; send only one (1) message element.";    
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");        
    $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
  }
  return $response;
}


sub getMetadatXQuery {
  my($self, $sentmd, $id) = @_;
  my %metadata = %{$sentmd};
  my $queryString = "";

  my $ifAddressType = "";
  my $ifAddress = "";
  my $disp = "";  
  foreach my $m (keys %{$metadata{$id}}) {
    if($m =~ m/^.*ifAddress$/) {
      $ifAddress = $metadata{$id}{$m};        
      $disp = $m;
      $disp =~ s/nmwg:metadata\///;  
    }
    elsif($m =~ m/^.*ifAddress-type$/) {
      $ifAddressType = $metadata{$id}{$m};
      $disp = $m;
      $disp =~ s/nmwg:metadata\///; 
      $disp =~ s/-type//; 
    }
  }
    
  if($ifAddress) {
    $queryString = $queryString . $disp . "[text()='" . $ifAddress;
    if($ifAddressType) {
      $queryString = $queryString . "' and \@type='" . $ifAddressType . "']";
    }
    else {
      $queryString = $queryString . "']";
    } 
    $queryCount++;     
  }
  else {
    if($ifAddressType) {
      $queryString = $queryString . $disp . "[\@type='" . $ifAddressType . "']";
      $queryCount++;
    }
  }
    
  foreach my $m (keys %{$metadata{$id}}) {
    if(!($m =~ m/^.*parameter.*$/) and
       !($m =~ m/^.*-id$/) and
       !($m =~ m/^.*-metadataIdRef$/) and
       !($m =~ m/^.*ifAddress.*$/)) {
      $disp = $m;
      $disp =~ s/nmwg:metadata\///;
      if(!($queryCount)) {
        $queryString = $queryString . $disp . "[text()='" . $metadata{$id}{$m} . "']";
        $queryCount++;
      }
      else {
        $queryString = $queryString . " and " . $disp . "[text()='" . $metadata{$id}{$m} . "']";
      }
    }
  }
  $queryString = $queryString . "]/\@id";
  
  return $queryString;  
}


sub getRange {
  my($self, $sentmd, $id) = @_;
  my %metadata = %{$sentmd};
  my %time = ();

  foreach my $m (keys %{$metadata{$id}}) {
    if($m =~ m/^.*select:parameter-time-gte$/) {
      $time{"START"} = $metadata{$id}{$m};
    }
    elsif($m =~ m/^.*select:parameter-time-gt$/) {
      $time{"START"} = $metadata{$id}{$m}+1;
    }
    elsif($m =~ m/^.*select:parameter-time-lte$/) {
      $time{"END"} = $metadata{$id}{$m};
    }
    elsif($m =~ m/^.*select:parameter-time-lt$/) {
      $time{"END"} = $metadata{$id}{$m}+1;
    }
    elsif($m =~ m/^.*select:parameter-time-eq$/) {
      $time{"START"} = $metadata{$id}{$m};
      $time{"END"} = $metadata{$id}{$m};
      last;
    }				
  }	   
    
  return %time;
}


sub retrieveRRD {
  my($self, $sentd, $did, $sentt) = @_;
  my $responseString = "";

  my %data = %{$sentd};
  my %time = %{$sentt};
  my $id = genuid();

  my $datadb = new perfSONAR_PS::DB::RRD(
    $self->{CONF}->{"LOGFILE"},
    $self->{CONF}->{"RRDTOOL"}, 
    $data{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
    "",
    1
  );
		      
  $datadb->openDB();
  my %rrd_result = $datadb->query(
    "AVERAGE", 
    "", 
    $time{START}, 
    $time{END}
  );
  
  if($datadb->getErrorMessage()) {
    my $msg =  "Query Error: " . $datadb->getErrorMessage() . "; query returned: " . $rrd_result{ANSWER};
    $responseString = $responseString . getResultCodeData($id, $data{$did}{"nmwg:data-metadataIdRef"}, $msg); 
  }
  else {
    my @keys = keys(%rrd_result);
    $responseString = $responseString . "  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$data{$did}{"nmwg:data-metadataIdRef"}."\">\n";
    foreach $a (sort(keys(%rrd_result))) {
      foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
	if($b eq $data{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"}) {
	  $responseString = $responseString . "    <nmwg:datum time=\"".$a."\" value=\"".$rrd_result{$a}{$b}."\" valueUnits=\"".$data{$did}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-valueUnits"}."\"/>\n";
        }
      }
    }
    $responseString = $responseString . "  </nmwg:data>\n";
  }
  $datadb->closeDB();	
  return $responseString;
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

  
=head2 getMetadatXQuery($sentmd, $id)

This function is meant to be used internally to form an XQuery statement from a 
metadata object and a specific metadata id.


=head2 getRange($sentmd, $id);
 
Given a metadata object and an id, construct a time hash that contains time related
parameter info from the request.


=head2 retrieveRRD($sentd, $did, $sentt)	

Given a data and metadata hash, and the time information, the data is extracted from the
backed storage (in this case RRD). 


=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MA::General>

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

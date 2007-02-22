#!/usr/bin/perl

package perfSONAR_PS::MA::SNMP;
use Carp;

use XML::XPath;
use Data::Dumper;
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
  my ($package, $dbType, $dbName, $dbFile, $dbUser, $dbPass, $log, $rrd) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MA::SNMP";
  $hash{"FUNCTION"} = "\"new\"";

  if(defined $dbType && $dbType ne "") {
    $hash{"DBTYPE"} = $dbType;
  }
  if(defined $dbName && $dbName ne "") {
    $hash{"DBNAME"} = $dbName;
  }
  if(defined $dbFile && $dbFile ne "") {
    $hash{"DBFILE"} = $dbFile;
  }
  if(defined $dbUser && $dbUser ne "") {
    $hash{"DBUSER"} = $dbUser;
  }
  if(defined $dbPass && $dbPass ne "") {
    $hash{"DBPASS"} = $dbPass;
  }    
  if(defined $log && $log ne "") {
    $hash{"LOG"} = $log;
  }   
  if(defined $rrd && $rrd ne "") {
    $hash{"RRDTOOL"} = $rrd;
  }   
  bless \%hash => $package;
}


sub setDbType {
  my ($self, $dbType) = @_;  
  $self->{FUNCTION} = "\"setDbType\"";  
  if(defined $dbType && $dbType ne "") {
    $self->{DBTYPE} = $dbType;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setDbName {
  my ($self, $dbName) = @_;  
  $self->{FUNCTION} = "\"setDbName\"";  
  if(defined $dbName && $dbName ne "") {
    $self->{DBNAME} = $dbName;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setDbFile {
  my ($self, $dbFile) = @_;  
  $self->{FUNCTION} = "\"setDbFile\"";  
  if(defined $dbFile && $dbFile ne "") {
    $self->{DBFILE} = $dbFile;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setDbUser {
  my ($self, $dbUser) = @_;  
  $self->{FUNCTION} = "\"setDbUser\"";  
  if(defined $dbUser && $dbUser ne "") {
    $self->{DBUSER} = $dbUser;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setDbPass {
  my ($self, $dbPass) = @_;  
  $self->{FUNCTION} = "\"setDbPass\"";  
  if(defined $dbPass && $dbPass ne "") {
    $self->{DBPASS} = $dbPass;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log && $log ne "") {
    $self->{LOG} = $log;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setRRDTool {
  my ($self, $rrd) = @_;  
  $self->{FUNCTION} = "\"setRRDTool\"";  
  if(defined $rrd && $rrd ne "") {
    $self->{RRDTOOL} = $rrd;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub getLog {
  my ($self) = @_;  
  $self->{FUNCTION} = "\"getLog\"";  
  if(defined $self->{LOG} && $self->{LOG} ne "") {
    return 1;
  }
  else {
    return 0;
  }
}


sub handleRequest {
  my($self, $request, $sentns) = @_;
  my $response = "";
  %ns = %{$sentns};  

  my $xp = XML::XPath->new( xml => $request );
  $xp->clear_namespaces();
  $xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  my $nodeset = $xp->find('//nmwg:message');

  if($nodeset->size() < 1) {
    my $msg = "Message elements not found in request; send only one (1) message element.";
    if(getLog($self)) {
      printError($self->{LOG}, $msg);
    }
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
    %metadata = parse($request, \%metadata, \%ns, "//nmwg:metadata");;
    %metadata = chainMetadata(\%metadata);
    %data = parse($request, \%data, \%ns, "//nmwg:data");      
    %metadata = eliminateMetadata(\%metadata, \%data);
     
    if($self->{DBTYPE} eq "mysql" || $self->{DBTYPE} eq "sqlite" || $self->{DBTYPE} eq "file") {
      my $msg = "The metadata database '".$self->{DBTYPE}."' is not yet supported.";
      if(getLog($self)) {
        printError($self->{LOG}, $msg);
      }
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    }  
    elsif($self->{DBTYPE} eq "xmldb") {
      my $localContent = "";
      foreach my $d (keys %data) {
        foreach my $m (keys %metadata) {  
          if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) { 
            
	    my $queryString = "/nmwg:metadata[" . getMetadatXQuery($self, \%metadata, $m);	    
	    my %time = getRange($self, \%metadata, $m);

	    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
              $self->{DBNAME}, 
              $self->{DBFILE},
              \%ns
            );	  
            $metadatadb->openDB;              
	    
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
		    my %dresults = parse($dataResultsString[$x], \%dresults, \%ns, "//nmwg:data");		  
    
		    @dataIds = keys(%dresults);
		    if($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
                      $localContent = $localContent . retrieveRRD($self, \%dresults, $dataIds[0], \%time); 
		      $response = getResultMessage($messageIdReturn, $messageId, "response", $localContent);
		    }
		    elsif(($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql") || 
		          ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") || 
			  ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "xmldb") || 
			  ($dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "file")){
                      my $msg = "The data database '".$dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}."' is not yet supported.";
                      if(getLog($self)) {
                        printError($self->{LOG}, $msg);
                      }
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		    else {
                      my $msg = "The data database '".$dresults{$dataIds[0]}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"}."' is not yet supported.";
                      if(getLog($self)) {
                        printError($self->{LOG}, $msg);
                      }
                      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
		    }
		  }		  	  
		}
                else {
                  my $msg = "The database '".$self->{DBTYPE}."' returned 0 results for the data search.";
                  if(getLog($self)) {
                    printError($self->{LOG}, $msg);
                  }
                  $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
                }		    
	      }
	    }
            else {
              my $msg = "The database '".$self->{DBTYPE}."' returned 0 results for the metadata search.";
              if(getLog($self)) {
                printError($self->{LOG}, $msg);
              }
              $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
            }
	  }   
        }
      }
    } 
    else {
      my $msg = "The metadata database '".$self->{DBTYPE}."' is not yet supported.";
      if(getLog($self)) {
        printError($self->{LOG}, $msg);
      }
      $response = getResultCodeMessage($messageIdReturn, $messageId, "response", "error.mp.snmp", $msg);
    } 
  }
  else {
    my $msg = "Too many message elements found in request; send only one (1) message element.";
    if(getLog($self)) {
      printError($self->{LOG}, $msg);
    }
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
    if(!($m =~ m/^.*parameter.*$/) &&
       !($m =~ m/^.*-id$/) &&
       !($m =~ m/^.*-metadataIdRef$/) &&
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
    "/usr/local/rrdtool/bin/rrdtool", 
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

perfSONAR_PS::MA::SNMP - A module that provides methods for ...

=head1 DESCRIPTION

...

=head1 SYNOPSIS

    use perfSONAR_PS::MA::;
    
    ...

=head1 DETAILS

...

=head1 API

...

=head2 new()

...

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>

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

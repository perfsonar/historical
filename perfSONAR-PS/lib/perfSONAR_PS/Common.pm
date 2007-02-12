#!/usr/bin/perl

package perfSONAR_PS::Common;
use Exporter;
use IO::File;
use XML::XPath;
@ISA = ('Exporter');
@EXPORT = ('readXML','readConfiguration', 'printError' , 'parseMetadata', 
           'parseData', 'chainMetadata', 'genuid');

our $VERSION = '0.02';

sub readXML {
  my ($file)  = @_;
  if(defined $file && $file ne "") {
    my $xmlstring = "";
    my $XML = new IO::File("<$file") || 
      croak("Cannot open 'readXML' $file: $!\n");
    while (<$XML>) {
      if(!($_ =~ m/^<\?xml.*/)) {
        $xmlstring .= $_;
      }
    }          
    $XML->close();
    return $xmlstring;  
  }
  else {
    croak("perfSONAR_PS::Common:\tMissing argument to \"readXML\"");
  }
  return;
}


sub readConfiguration {
  my ($file, $sent)  = @_;
  if((defined $file && $file ne "") && (defined $sent && $sent ne "")) {
    my %hash = %{$sent};
    my $CONF = new IO::File("<$file") or 
      croak("Cannot open 'readDBConf' $file: $!\n");
    while (<$CONF>) {
      if(!($_ =~ m/^#.*$/)) {
        $_ =~ s/\n//;
        @values = split(/\?/,$_);
        $hash{$values[0]} = $values[1];
      }
    }          
    $CONF->close();
    return %hash; 
  }
  else {
    croak("perfSONAR_PS::Common:\tMissing argument(s) to \"readConfiguration\"");
  }
  return;
}


sub printError {
  my($file, $msg) = @_;
  if((defined $file && $file ne "") && (defined $msg && $msg ne "")) {
    open(LOG, "+>>" . $file);
    my ($sec, $micro) = Time::HiRes::gettimeofday;
    print LOG "TIME: " , $sec , "." , $micro , "\t\t";
    print LOG $msg , "\n";
    close(LOG);
  }
  else {
    croak("perfSONAR_PS::Common:\tMissing argument(s) to \"printError\"");
  }
  return;
}


sub parseMetadata {
  my ($xml, $sentmetadata, $sentnamespaces) = @_;
  if((defined $xml && $xml ne "") && 
     (defined $sentmetadata && $sentmetadata ne "") && 
     (defined $sentnamespaces && $sentnamespaces ne "")) {  
    my %metadata = %{$sentmetadata};
    my %ns = %{$sentnamespaces};

    my $xp = XML::XPath->new( xml => $xml );
    $xp->clear_namespaces();
  
    foreach my $prefix (keys %ns) {
      $xp->set_namespace($prefix, $ns{$prefix});
    }
  	  	  	  
    my $nodeset = $xp->find('//nmwg:metadata');
    if($nodeset->size() <= 0) {
      croak("XPath error: either they are not nmwg:metadata, or the namespace could be wrong."); 	
      exit(1);  
    }
    else {
      foreach my $node ($nodeset->get_nodelist) {           
        my %md = ();
        my $id = "";
        my $mid = "";
        foreach my $attr ($node->getAttributes) {
          if($attr->getLocalName eq "id") {
            $id = $attr->getNodeValue;
	    $md{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $id;
          }
          elsif($attr->getLocalName eq "metadataIdRef") {
            $mid = $attr->getNodeValue;
	    $md{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $mid;
          }
        }
        %md = traverse($node, \%md);
        $metadata{$id} = \%md;             	    
      }
    }  
    return %metadata;
  }
  else {
    croak("perfSONAR_PS::Common:\tMissing argument(s) to \"parseMetadata\"");
  }
  return;
}


sub parseData {
  my ($xml, $sentdata, $sentnamespaces) = @_;
  if((defined $xml && $xml ne "") && 
     (defined $sentdata && $sentdata ne "") && 
     (defined $sentnamespaces && $sentnamespaces ne "")) {
    my %data = %{$sentdata};
    my %ns = %{$sentnamespaces};

    my $xp = XML::XPath->new( xml => $xml );
    $xp->clear_namespaces();
  
    foreach my $prefix (keys %ns) {
      $xp->set_namespace($prefix, $ns{$prefix});
    }
  	  	  	  
    my $nodeset = $xp->find('//nmwg:data');
    if($nodeset->size() <= 0) {
      croak("XPath error: either they are not nmwg:data, or the namespace could be wrong."); 	
      exit(1);  
    }
    else {
      foreach my $node ($nodeset->get_nodelist) {           
        my %d = ();
        my $id = "";
        my $mid = "";
        foreach my $attr ($node->getAttributes) {
          if($attr->getLocalName eq "id") {
            $id = $attr->getNodeValue;
	    $d{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $id;
          }
          elsif($attr->getLocalName eq "metadataIdRef") {
            $mid = $attr->getNodeValue;
	    $d{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $mid;
	  }
        }     
        %d = traverse($node, \%d);
        $data{$id} = \%d;             	    
      }
    }  
    return %data;
  }
  else {
    croak("perfSONAR_PS::Common:\tMissing argument(s) to \"parseData\"");
  }
  return;
}


sub traverse {
  my ($set, $sent) = @_;
  my %struct = %{$sent};
  
  foreach my $element ($set->getChildNodes) {          
  
    foreach my $attr ($element->getAttributes) {
      if($attr->getLocalName eq "id" || $attr->getLocalName eq "metadataIdRef") {
        $struct{$element->getPrefix .":" . $element->getLocalName . "-" . $attr->getLocalName} = $attr->getNodeValue;
      }
    }    
        
    if($element->getNodeType == 3) {
      my $value = $element->getValue;
      $value =~ s/\s+//g;
      if($value) {
        $struct{$element->getParentNode->getLocalName} = $value;
      }    
    }
    elsif($element->getLocalName eq "parameter") {    
      my $nm = "";
      my $vl = "";
      my $op = "";      
      foreach my $attr2 ($element->getAttributes) {
        if($attr2->getLocalName eq "name") {
	  $nm = $attr2->getNodeValue;
	}
	elsif($attr2->getLocalName eq "value") {
	  $vl = $attr2->getNodeValue;
	}
	elsif($attr2->getLocalName eq "operator") {
	  $op = $attr2->getNodeValue;
	}	
      }    
      if(!$vl) {
        if($element->getChildNode(1)) {
	  $vl = $element->getChildNode(1)->getValue;
          $vl =~ s/\s+//g;
          $vl =~ s/\n+//g;	  
	}
      }
      if($op) {
        $struct{$element->getLocalName."-".$nm."-".$op} = $vl;
      }
      else {
        $struct{$element->getLocalName."-".$nm} = $vl;      
      }
    }
    else {
      foreach my $attr ($element->getAttributes) {
	if($element->getLocalName eq "ifAddress") {
	  $struct{$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
      }
      %struct = traverse($element, \%struct);
    }
  }	  
  return %struct;
}

sub chainMetadata {
  my ($sentmetadata) = @_;
  my %md = %{$sentmetadata};
    
  my $flag = 1;
  while($flag) {
    $flag = 0;
    foreach my $m (keys %md) {
      foreach $class (keys %{$md{$m}}) {
        my @ns = split(/:/,$class);		
        if($md{$m}{$ns[0].":subject-metadataIdRef"}) {
          foreach my $m2 (keys %{$md{$md{$m}{$ns[0].":subject-metadataIdRef"}}}) {
	    my @mark = split(/-/,$m2);
	    if(!defined $mark[1] || ($mark[1] ne "id" && $mark[1] ne "metadataIdRef")) {
	    
              if((!$md{$m}{$m2} && $m2 ne $ns[0].":subject-metadataIdRef" && 
                 $m2 ne $ns[0].":metadata-metadataIdRef") || 
		 ($md{$m}{$m2} ne $md{$md{$m}{$ns[0].":subject-metadataIdRef"}}{$m2} && 
                 $m2 ne $ns[0].":subject-metadataIdRef" && $m2 ne $ns[0].":metadata-metadataIdRef")) {
		 
	        $md{$m}{$m2} = $md{$md{$m}{$ns[0].":subject-metadataIdRef"}}{$m2};
	        $flag = 1;
	      }
	    }	    
          }
        }
        if($md{$m}{$ns[0].":metadata-metadataIdRef"}) {
          foreach my $m2 (keys %{$md{$md{$m}{$ns[0].":metadata-metadataIdRef"}}}) {
	    my @mark = split(/-/,$m2);    
	    if(!defined $mark[1] || ($mark[1] ne "id" && $mark[1] ne "metadataIdRef")) {		         
	    
	      if((!$md{$m}{$m2} && $m2 ne $ns[0].":subject-metadataIdRef" && 
	         $m2 ne $ns[0].":metadata-metadataIdRef") || 
	         ($md{$m}{$m2} ne $md{$md{$m}{$ns[0].":metadata-metadataIdRef"}}{$m2} &&
	         $m2 ne $ns[0].":subject-metadataIdRef" && $m2 ne $ns[0].":metadata-metadataIdRef")) {
		 
	        $md{$m}{$m2} = $md{$md{$m}{$ns[0].":metadata-metadataIdRef"}}{$m2};
	        $flag = 1;
	      }
	    }
          }
        }
      }
    }
  }
  return %md;
}

sub genuid {
  my ($r) = int( rand( 16777216 ) );
  return ( $r + 1048576 );
}

1;

__END__
=head1 NAME

perfSONAR_PS::Common - A module that provides common methods for performing actions within in the
Netradar framework.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) in the Netradar framework.  As such there
is no 'common thread' that each method shares.  This module IS NOT an object, and the methods
can be invoked directly.  

=head1 SYNOPSIS

    use perfSONAR_PS::Common;

    my $xml = readXML("./store.xml");
    if(!($xml)) {
      printError("./error.log", "XML File is empty."); 
      exit(1);
    }

    my %hash = readConfiguration("./db.conf", \%hash);

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );

    my %metadata = parseMetadata($xml, \%metadata, \%ns);

    my %data = parseData($xml, \%data, \%ns);
       
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and each method does not
have the 'self knowledge' of variables that may travel between functions.  

=head1 API

The API of perfSONAR_PS::Common offers simple calls to common activities in the Netradar 
framework.  

=head2 readXML($file)

Reads the file specified in '$file' and returns the XML contents in string form.

=head2 readConfiguration($file, \%hash)

Reads the file specified in '$file', and loads the hash reference '%hash' with the name/value
paired items from a config file.  Note that the pairs use the '?' symbol as a separator.  For 
example the config file:

  METADATA_DB_TYPE?xmldb
  METADATA_DB_NAME?/home/jason/Netradar/MP/SNMP/xmldb
  METADATA_DB_FILE?snmpstore.dbxml

Would return a hash such as:

  %hash = 
    {
      METADATA_DB_TYPE => "xmldb",
      METADATA_DB_NAME => "/home/jason/Netradar/MP/SNMP/xmldb",
      METADATA_DB_FILE => "snmpstore.dbxml"      
    }

=head2 printError($file, $msg)

Reads the file specified in '$file', and writes the contents of '$msg' (along with a 
timestamp) to this designated log file.

=head2 parseMetadata($xml, \%metadata, \%ns)

The '$xml' argument is an XML string.  The first of the two hash arguments, '%metadata', is 
an object that will contain the contents of each metadata XML tag.  The third argument is 
a hash reference containing a prefix to namespace mapping.  All namespaces that may appear 
in the container should be mapped (there is no harm is sending mappings that will not 
be used).  The metadata object is returned, populated with the appropriate values.  

=head2 parseData($xml, \%data, \%ns)

The '$xml' argument is an XML string.  The first of the two hash arguments, '%data', is 
an object that will contain the contents of each data XML tag.  The third argument is 
a hash reference containing a prefix to namespace mapping.  All namespaces that may appear 
in the container should be mapped (there is no harm is sending mappings that will not 
be used).  The data object is returned, populated with the appropriate values.

=head2 traverse($set, $sentstructure)

This function is not exported, and is meant to be used by parseMetadata($xml, \%metadata, \%ns)
and parseData($xml, \%data, \%ns) to aide in the extraction of XML values.

=head2 chainMetadata($sentmetadata)

TBD

=head2 genuid()

Generates a random number.

=head1 SEE ALSO

L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::MP::SNMP>

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

#!/usr/bin/perl

package Netradar::Common;
use Exporter;
use IO::File;
use XML::XPath;
@ISA = ('Exporter');
@EXPORT = ('readXML','readConfiguration', 'printError' , 'parseMetadata');

our $VERSION = '0.01';

sub readXML {
  my ($file)  = @_;
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


sub readConfiguration {
  my ($file, $sent)  = @_;
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


sub printError {
  my($file, $msg) = @_;
  open(LOG, "+>>" . $file);
  my ($sec, $micro) = Time::HiRes::gettimeofday;
  print LOG "TIME: " , $sec , "." , $micro , "\t\t";
  print LOG $msg , "\n";
  close(LOG);
  return;
}


sub parseMetadata {
  my ($xml, $sentmetadata, $sentnamespaces) = @_;
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
        }
        elsif($attr->getLocalName eq "metadataIdRef") {
          $mid = $attr->getNodeValue;
        }
      }
      %md = loadMetadata($node, \%md);
      $metadata{$id} = \%md;             	    
    }
  }  
  return %metadata;
}


sub loadMetadata {
  my ($set, $sentmetadata) = @_;
  my %md = %{$sentmetadata};
  
  foreach my $element ($set->getChildNodes) {      
     
    if($element->getNodeType == 3) {
      my $value = $element->getValue;
      $value =~ s/\s+//g;
      if($value) {
        $md{$element->getParentNode->getLocalName} = $value;
      }
    }
    elsif($element->getLocalName eq "parameter") {
      my $nm = "";
      my $vl = "";
      foreach my $attr2 ($element->getAttributes) {
        if($attr2->getLocalName eq "name") {
	  $nm = $attr2->getNodeValue;
	}
	elsif($attr2->getLocalName eq "value") {
	  $vl = $attr2->getNodeValue;
	}
      }
      $md{$element->getLocalName."-".$nm} = $vl;   
    }
    else {
      foreach my $attr ($element->getAttributes) {
	if($element->getLocalName eq "ifAddress") {
	  $md{$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
      }
      %md = loadMetadata($element, \%md);
    }
  }	  
  return %md;
}


1;

__END__
=head1 NAME

Netradar::Common - A module that provides common methods for performing actions within in the
Netradar framework.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) in the Netradar framework.  As such there
is no 'common thread' that each method shares.  This module IS NOT an object, and the methods
can be invoked directly.  

=head1 SYNOPSIS

    use Netradar::Common;

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
       
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and each method does not
have the 'self knowledge' of variables that may travel between functions.  

=head1 API

The API of Netradar::Common offers simple calls to common activities in the Netradar 
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

=head2 loadMetadata($set, $sentmetadata)

This function is not exported, and is meant to be used by parseMetadata($xml, \%metadata, \%ns)
to aide in the extraction of metadata values.

=head1 SEE ALSO

L<Netradar::Common>, L<Netradar::DB::XMLDB>, L<Netradar::DB::RRD>, L<Netradar::DB::File>

To join the 'netradar' mailing list, please visit:

  http://moonshine.pc.cis.udel.edu/mailman/listinfo/netradar

The netradar subversion repository is located at:

  https://damsl.cis.udel.edu/svn/netradar/
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

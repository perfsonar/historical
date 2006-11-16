#!/usr/bin/perl

package Netradar::Common;
use Exporter;
@ISA = ('Exporter');
@EXPORT = ('readXML','readConfiguration', 'printError' , 'parseMetadata');


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

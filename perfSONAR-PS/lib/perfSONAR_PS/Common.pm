#!/usr/bin/perl

package perfSONAR_PS::Common;
use Carp qw( carp );
use Exporter;
use IO::File;
use XML::XPath;
use Time::HiRes qw( gettimeofday );

@ISA = ('Exporter');
@EXPORT = ('readXML','readConfiguration', 'printError' , 'parse', 
           'chainMetadata', 'countRefs', 'genuid');

our $VERSION = '0.03';

sub readXML {
  my ($file)  = @_;
  if(defined $file and $file ne "") {
    my $XML = new IO::File("<".$file) or 
      carp("perfSONAR_PS::Common:\tCan't open file \"".$file."\" in \"readXML\" at line ".__LINE__.".");
    if(defined $XML) {
      my $xmlstring = "";
      while (<$XML>) {
        if(!($_ =~ m/^<\?xml.*/)) {
          $xmlstring .= $_;
        }
      }          
      $XML->close();
      return $xmlstring;
    }
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument to \"readXML\" at line ".__LINE__.".");
  }
  return "";
}


sub readConfiguration {
  my ($file, $conf)  = @_;
  if((defined $file and $file ne "") and 
     (defined $conf and $conf ne "")) {
    my $CONF = new IO::File("<".$file) or 
      carp("perfSONAR_PS::Common:\tCan't open configuration file \"".$file."\" in \"readConfiguration\" at line ".__LINE__.".");
    if(defined $CONF) {
      while (<$CONF>) {
        if(!($_ =~ m/^#.*$/)) {
          $_ =~ s/\n//;
          @values = split(/\?/,$_);
          $conf->{$values[0]} = $values[1];
        }
      }          
      $CONF->close();
    }
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument(s) to \"readConfiguration\" at line ".__LINE__.".");
  }
  return;
}


sub printError {
  my($file, $msg) = @_;
  if((defined $file and $file ne "") and 
     (defined $msg and $msg ne "")) {
    my $LOG = new IO::File("+>>".$file) or 
      carp("perfSONAR_PS::Common:\tCan't open log file \"".$file."\" in \"printError\" at line ".__LINE__.".");
    if(defined $LOG) {
      my ($sec, $micro) = Time::HiRes::gettimeofday;
      print $LOG "TIME: " , $sec , "." , $micro , "\t\t";
      print $LOG $msg , "\n";
      $LOG->close();
    }
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument(s) to \"printError\" at line ".__LINE__.".");
  }
  return;
}


sub parse {
  my ($xml, $struct, $ns, $xpath) = @_;
  if((defined $xml and $xml ne "") and 
     (defined $struct and $struct ne "") and 
     (defined $ns and $ns ne "")) {
    
    my $xp = undef;        
    if(UNIVERSAL::can($xml, "isa") ? "1" : "0" == 1
       and $xml->isa('XML::XPath::Node::Element')) {
      $xp = $xml;
    }
    else {
      $xp = XML::XPath->new( xml => $xml );
      $xp->clear_namespaces();        
      foreach my $prefix (keys %{$ns}) {
        $xp->set_namespace($prefix, $ns->{$prefix});
      }
    }
                    
    my $nodeset = $xp->find($xpath);
    if($nodeset->size() <= 0) {
      carp("perfSONAR_PS::Common:\tXPath error in \"parse\" at line ".__LINE__.".");
    }
    else {
      foreach my $node ($nodeset->get_nodelist) {           
        my %s = ();
        my $id = "";
        my $mid = "";
        foreach my $attr ($node->getAttributes) {
          if($attr->getLocalName eq "id") {
            $id = $attr->getNodeValue;
            $s{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $id;
          }
          elsif($attr->getLocalName eq "metadataIdRef") {
            $mid = $attr->getNodeValue;
            $s{$node->getPrefix .":" . $node->getLocalName . "-" . $attr->getLocalName} = $mid;
          }
        }     
        $path = $xpath;
        $path =~ s/\/\///;
        traverse($node, \%s, $path);
        $struct->{$id} = \%s;
      }
    }  
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument(s) to \"parse\" at line ".__LINE__.".");
  }
  return;
}


sub traverse {
  my ($set, $struct, $path) = @_;
  foreach my $element ($set->getChildNodes) {          
  
    foreach my $attr ($element->getAttributes) {
      if($attr->getLocalName eq "id" or $attr->getLocalName eq "metadataIdRef") {
        $struct->{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $attr->getLocalName} = $attr->getNodeValue;
      }
    }    
        
    if($element->getNodeType == 3) {
      my $value = $element->getValue;
      $value =~ s/\s+//g;
      if($value) {
        $struct->{$path} = $value;
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
        $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$nm."-".$op} = $vl;
      }
      else {
        $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$nm} = $vl;      
      }
    }
    else {
      foreach my $attr ($element->getAttributes) {
        if($element->getLocalName eq "ifAddress") {
          $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
        elsif($element->getLocalName eq "ipAddress") {
          $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
        elsif($element->getLocalName eq "src") {
          $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }
        elsif($element->getLocalName eq "dst") {
          $struct->{$path."/".$element->getPrefix.":".$element->getLocalName."-".$attr->getLocalName} = $attr->getNodeValue;
        }	
      }
      traverse($element, \%{$struct}, $path."/".$element->getPrefix .":" . $element->getLocalName);
    }
  }          
  return;
}

sub chainMetadata {
  my ($md) = @_;    
  if((defined $md and $md ne "")) {  
    my $flag = 1;
    while($flag) {
      $flag = 0;
      foreach my $m (keys %{$md}) {
        foreach $class (keys %{$md->{$m}}) {
          $class =~ s/nmwg:metadata\///;
          my @ns = split(/:/,$class);
          if($#ns == 1) {
            if($md->{$m}{"nmwg:metadata/".$ns[0].":subject-metadataIdRef"}) {
              foreach my $m2 (keys %{$md->{$md->{$m}{"nmwg:metadata/".$ns[0].":subject-metadataIdRef"}}}) {
                my @mark = split(/-/,$m2);
                if(!defined $mark[1] or ($mark[1] ne "id" and $mark[1] ne "metadataIdRef")) {
                  if((!$md->{$m}{$m2} and $m2 ne "nmwg:metadata/".$ns[0].":subject-metadataIdRef" and 
                     $m2 ne $ns[0].":metadata-metadataIdRef") or 
                     ($md->{$m}{$m2} ne $md->{$md->{$m}{"nmwg:metadata/".$ns[0].":subject-metadataIdRef"}}{$m2} and 
                     $m2 ne "nmwg:metadata/".$ns[0].":subject-metadataIdRef" and $m2 ne $ns[0].":metadata-metadataIdRef")) {
                 
                    $md->{$m}{$m2} = $md->{$md->{$m}{"nmwg:metadata/".$ns[0].":subject-metadataIdRef"}}{$m2};
                    $flag = 1;
                  }
                }            
              }
            }
            if($md->{$m}{$ns[0].":metadata-metadataIdRef"}) {
              foreach my $m2 (keys %{$md->{$md->{$m}{$ns[0].":metadata-metadataIdRef"}}}) {
                my @mark = split(/-/,$m2);    
                if(!defined $mark[1] or ($mark[1] ne "id" and $mark[1] ne "metadataIdRef")) {                         
                  if((!$md->{$m}{$m2} and $m2 ne "nmwg:metadata/".$ns[0].":subject-metadataIdRef" and 
                     $m2 ne $ns[0].":metadata-metadataIdRef") or 
                     ($md->{$m}{$m2} ne $md->{$md->{$m}{$ns[0].":metadata-metadataIdRef"}}{$m2} and
                     $m2 ne "nmwg:metadata/".$ns[0].":subject-metadataIdRef" and $m2 ne $ns[0].":metadata-metadataIdRef")) {
                 
                    $md->{$m}{$m2} = $md->{$md->{$m}{$ns[0].":metadata-metadataIdRef"}}{$m2};
                    $flag = 1;
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument(s) to \"chainMetadata\" at line ".__LINE__.".");
  }  
  return;
}


sub countRefs {
  my($id, $struct, $value) = @_;
  if((defined $id and $id ne "") and 
     (defined $struct and $struct ne "") and 
     (defined $value and $value ne "")) {  
    my $flag = 0;
    foreach my $s (keys %{$struct}) {
      if($id eq $struct->{$s}->{$value}) {
        $flag++;
      }
    }
    return $flag;
  }
  else {
    carp("perfSONAR_PS::Common:\tMissing argument(s) to \"countRefs\" at line ".__LINE__.".");
  }
  return -1;  
}


sub genuid {
  my ($r) = int( rand( 16777216 ) );
  return ( $r + 1048576 );
}


1;


__END__
=head1 NAME

perfSONAR_PS::Common - A module that provides common methods for performing simple, necessary actions 
within the perfSONAR-PS framework.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) in the perfSONAR-PS framework.  As such there
is no 'common thread' that each method shares.  This module IS NOT an object, and the methods
can be invoked directly (and sparingly).  

=head1 SYNOPSIS

    use perfSONAR_PS::Common;
    
    # NOTE: Individual methods can be extraced:
    # 
    # use perfSONAR_PS::Common qw( readXML readConfiguration )

    my $xml = readXML("./store.xml");
    if(!($xml)) {
      printError("./error.log", "XML File is empty."); 
      exit(1);
    }

    my %conf = ();
    readConfiguration("./db.conf", \%conf);


    # To see the structure of the conf hash:
    # 
    # use Data::Dumper;
    # print Dumper(%conf) , "\n";


    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );

    my %metadata = ();
    
    # NOTE: $xml in the case may ALSO be an already calculated XPath expression
    
    parse($xml, \%metadata, \%ns, "//nmwg:metadata");
    chainMetadata(\%metadata);


    # To see the structure of the metadata hash:
    # 
    # use Data::Dumper;
    # print Dumper(%metadata) , "\n";


    my %data = ();
    parse($xml, \%data, \%ns, "//nmwg:data");


    # To see the structure of the data hash:
    # 
    # use Data::Dumper;
    # print Dumper(%data) , "\n";

    
    foreach my $m (keys %metadata) {
      print "There are '" , countRefs($m, \%data) , "' references to data objects";
      print " for metadata '" , $m , "'\n";
    }
    
    print "A random id would look like this:\t'" , genuid() , "'\n";
       
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The API of perfSONAR_PS::Common offers simple calls to common activities in the 
perfSONAR-PS framework.  

=head2 readXML($file)

Reads the file specified in '$file' and returns the XML contents in string form.  
The <xml> tag will be extracted from the final returned string.  Function will
warn on error, and return an empty string.  

=head2 readConfiguration($file, \%conf)

Reads the file specified in '$file', and loads the hash reference '%conf' with the name/value
paired items from a config file.  Note that the pairs use the '?' symbol as a separator.  For 
example the config file:

  METADATA_DB_TYPE?xmldb
  METADATA_DB_NAME?/home/jason/perfSONAR-PS/MP/SNMP/xmldb
  METADATA_DB_FILE?snmpstore.dbxml

Would return a hash such as:

  %conf = 
    {
      METADATA_DB_TYPE => "xmldb",
      METADATA_DB_NAME => "/home/jason/perfSONAR-PS/MP/SNMP/xmldb",
      METADATA_DB_FILE => "snmpstore.dbxml"      
    }

Function will warn on error.  

=head2 printError($file, $msg)

Writes the contents of '$msg' (along with a timestamp) to this designated log file 
'$file'.  Function will warn on error.  

=head2 parse($xml, \%struct, \%ns, $xpath)

The '$xml' argument is an XML string or XML::XPath expression.  The first of the two hash 
arguments, '%struct', is an object that will contain the contents of each XML tag (this 
could be something like nmwg:metadata, or nmwg:data, etc.).  The third argument is a 
hash reference containing a prefix to namespace mapping.  All namespaces that may appear 
in the container should be mapped (there is no harm is sending mappings that will not 
be used).  The last argument is an XPath expression (such as '//nmwg:metadata') that 
will be evaluated to return the struct object, populated with the appropriate values.  
Function will warn on error (when the XPath returns no results).

=head2 traverse($set, $sentstructure, $path)

This function is not exported, and is meant to be used by parse($xml, \%metadata, \%ns, $xpath) 
to aide in the extraction of XML values.

=head2 chainMetadata(\%metadata)

Given a hash of metadata objects, this function will continuously loop through performing
a 'cahining' operation to share values between metadata objects.  An example would be:

  <nmwg:metadata id="1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="1">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
        <nmwgt:hostName>stout</nmwgt:hostName>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0/</nmwg:eventType>
  </nmwg:metadata>  

  <nmwg:metadata id="2" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" metadataIdRef="1">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="2">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifName>eth1</nmwgt:ifName>
        <nmwgt:ifIndex>3</nmwgt:ifIndex>
        <nmwgt:direction>in</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0/</nmwg:eventType>
  </nmwg:metadata>

  <nmwg:metadata id="3">
    <netutil:subject id="3" metadataIdRef="2"/>
    <nmwg:parameters id="3">
      <select:parameter name="time" operator="gte">
        1172173843
      </select:parameter>
      <select:parameter name="time" operator="lte">
        1172173914
      </select:parameter>      
    </nmwg:parameters>
  </nmwg:metadata>  

Which would then become:

  <nmwg:metadata id="3">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="1">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
        <nmwgt:hostName>stout</nmwgt:hostName>
        <nmwgt:ifName>eth1</nmwgt:ifName>
        <nmwgt:direction>in</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0/</nmwg:eventType>
    <nmwg:parameters id="3">
      <select:parameter name="time" operator="gte">
        1172173843
      </select:parameter>
      <select:parameter name="time" operator="lte">
        1172173914
      </select:parameter>      
    </nmwg:parameters>
  </nmwg:metadata>  

This chaining is useful for 'factoring out' large chunks of XML.

=head2 countRefs($id, \%struct, $value)

Given a ID, and a series of 'struct' objects and a key 'value' to search on, this function 
will return a 'count' of the number of times the id was seen as a reference to the objects.  
This is useful for eliminating 'dead' blocks that may not contain a trigger.  The function
will return -1 on error.  

=head2 genuid()

Generates a random number.

=head1 SEE ALSO

L<Carp>, L<IO::File>, L<XML::XPath>, L<Time::HiRes>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::RRD>, 
L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MP::Ping>, 
L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>, L<perfSONAR_PS::MA::Ping>

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

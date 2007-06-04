#!/usr/bin/perl -w

package perfSONAR_PS::Common;

use warnings;
use Carp qw( carp );
use Exporter;

use IO::File;
use XML::XPath;
use Time::HiRes qw( gettimeofday );
use Log::Log4perl qw(get_logger);

@ISA = ('Exporter');
@EXPORT = ('readXML','readConfiguration', 'printError', 'chainMetadata', 
           'countRefs', 'genuid', 'extract', 'reMap');

sub readXML {
  my ($file)  = @_;  
  my $logger = get_logger("perfSONAR_PS::Common");
  
  if(defined $file and $file ne "") {
    my $XML = new IO::File("<".$file);
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
    else {
      $logger->error("Cannot open file \"".$file."\".");
    }
  }
  else {
    $logger->error("Missing argument.");
  }
  return "";
}


sub readConfiguration {
  my ($file, $conf)  = @_;
  my $logger = get_logger("perfSONAR_PS::Common");
  
  if((defined $file and $file ne "") and 
     (defined $conf and $conf ne "")) {
    my $CONF = new IO::File("<".$file);
    if(defined $CONF) {
      while (<$CONF>) {
        if(!($_ =~ m/^#.*$/) and !($_ =~ m/^\s+/)) {
          $_ =~ s/\n//;
          @values = split(/\?/,$_);
          $conf->{$values[0]} = $values[1];
          $logger->debug("Found ".$values[0]." = \"".$values[1]."\".");
        }
      }          
      $CONF->close();
    }
    else {
      $logger->error("Cannot open file \"".$file."\".");
    }
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return;
}


sub chainMetadata {
  my($dom, $uri) = @_;
  my $logger = get_logger("perfSONAR_PS::Common");

  if(defined $dom and $dom ne "") {
    foreach my $md ($dom->getElementsByTagNameNS($uri, "metadata")) {
      my @subjects = $md->getElementsByLocalName("subject");
      if($subjects[0]) {
        if($subjects[0]->getAttribute("metadataIdRef")) {
          foreach my $md2 ($dom->getElementsByTagNameNS($uri, "metadata")) {
	          if($subjects[0]->getAttribute("metadataIdRef") eq $md2->getAttribute("id")) {
              $logger->debug("Found chain for subject \"".$subjects[0]->getAttribute("id")."\" and metadata \"".$md2->getAttribute("id")."\".");
              
              # XXX jason: [6/1/07]
              # testing... (if we were to remove the unecessary subject)
              $md->removeChild($subjects[0]);
              
              chain($md2, $md, $md2);
	          }
          }
        }
      }
    }
  }
  else {
    $logger->error("Missing argument.");
  }
  return $dom;
}


sub chain {
  my($node, $ref, $ref2) = @_;
  
  if($node->nodeType != 3) {
    my $attrString = "";
    my $counter = 0;
    foreach my $attr ($node->attributes) {
      if($attr->isa('XML::LibXML::Attr')) {
        if($attr->getName ne "id" and !($attr->getName =~ m/.*IdRef$/)) {
          if($counter == 0) {  
            $attrString = $attrString . "@" . $attr->getName . "=\"" . $attr->getValue . "\"";
          }
          else {
            $attrString = $attrString . " and @" . $attr->getName . "=\"" . $attr->getValue . "\"";
          }
          $counter++;
        }
      }
    }
    
    if($node->hasChildNodes()) {
      my @children = $node->childNodes;
      if($#children == 0) {
        if($node->firstChild->nodeType == 3) {        
          (my $value = $node->firstChild->textContent) =~ s/\s*//g;
          if($value) {
            if($counter == 0) {
              $attrString = $attrString . "text()=\"" . $value . "\"";
            }
            else {
              $attrString = $attrString . " and text()=\"" . $value . "\"";
            }      
          }        
        }
      }
    }
    if($attrString) {
      $attrString = "[".$attrString."]";      
    }
    
    my $path = "";
    if($node->nodePath() =~ m/nmwg:store/) {
      ($path = $node->nodePath()) =~ s/\/nmwg:store\/nmwg:metadata//;
      $path =~ s/\[\d\]//g;
      $path =~ s/^\///g;  
    }
    else {
      ($path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
      $path =~ s/\[\d\]//g;
      $path =~ s/^\///g;  
    }

    if($path) {  
      if(!($ref->find($path.$attrString))) {
	      my $name = $node->nodeName;
	      my $path2 = $path;
	      $path2 =~ s/\/$name$//;	  
        if($ref->find($path2)) {
          $ref->find($path2)->get_node(1)->addChild($node->cloneNode(1));	 
        }
        else {
          $ref->addChild($node->cloneNode(1));	 
        } 
      }
    }
  
    if($node->hasChildNodes()) {
      foreach my $c ($node->childNodes) {
        chain($c, $ref, $ref2);
      }
    }
  }
  return;
}


sub countRefs {
  my($id, $dom, $uri, $element, $attr) = @_;
  my $logger = get_logger("perfSONAR_PS::Common");
  
  if((defined $id and $id ne "") and 
     (defined $dom and $dom ne "") and 
     (defined $uri and $uri ne "") and 
     (defined $element and $element ne "") and 
     (defined $attr and $attr ne "")) {
    my $flag = 0;
    foreach my $d ($dom->getElementsByTagNameNS($uri, $element)) {
      if($id eq $d->getAttribute($attr)) {
        $flag++;
      }
    }
    return $flag;
  }
  else {
    $logger->error("Missing argument(s).");
  }
  $logger->debug("0 Refernces Found");
  return -1;  
}


sub genuid {
  my $r = int(rand(16777216))+1048576;
  return $r;
}


sub extract {
  my($node) = @_;
  my $logger = get_logger("perfSONAR_PS::Common");
  
  if(defined $node and $node ne "") {
    if($node->getAttribute("value")) {
      return $node->getAttribute("value");
    }
    else {
      return $node->textContent;
    }  
  }
  else {
    $logger->error("Missing argument.");
  }
  return "";
}


sub reMap {
  my($requestNamespaces, $namespaces, $node) = @_;  
  my $logger = get_logger("perfSONAR_PS::Common");
  
  if($node->prefix and $node->namespaceURI()) {
    if(!$requestNamespaces->{$node->namespaceURI()}) {
      $requestNamespaces->{$node->namespaceURI()} = $node->prefix;
      $logger->debug("Setting namespace \"".$node->namespaceURI()."\" with prefix \"".$node->prefix."\".");
    }
    if(!($namespaces->{$node->prefix})) {
      foreach my $ns (keys %{$namespaces}) {
        if($namespaces->{$ns} eq $node->namespaceURI()) {
          $node->setNamespace($namespaces->{$ns}, $ns, 1);
          $logger->debug("Re-mapping namespace \"".$namespaces->{$ns}."\" to prefix \"".$ns."\".");
          last;
        }
      }    
    }
  }
  if($node->hasChildNodes()) {
    foreach my $c ($node->childNodes) {
      if($node->nodeType != 3) {
        $requestNamespaces = reMap($requestNamespaces, $namespaces, $c);
      }
    }
  }
  return $requestNamespaces;
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
    use XML::LibXML;
    
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

    my $parser = XML::LibXML->new();
    $my $dom = $parser->parse_file($self->{CONF}->{"METADATA_DB_FILE"}); 
    
    $dom = chainMetadata($dom, $ns{"nmwg"});
   
    foreach my $md ($dom->getElementsByTagNameNS($ns{"nmwg"}, "metadata")) {
      my $count = countRefs($md->getAttribute("id"), $dom, $ns{"nmwg"}, "data", "metadataIdRef");
      if($count == 0) {
        print $md->getAttribute("id") , " not found.\n";
      } 
      else {
        print $md->getAttribute("id") , " found " , $count , " times.\n";
      }
    }        

    print "A random id would look like this:\t'" , genuid() , "'\n";

    # consider the elements that could be stored in '$node':
    #
    #  <nmwg:parameter name="something">value</nmwg:parameter>
    #  <nmwg:parameter name="something" value="value" />
    #  <nmwg:parameter name="something" value="value" />value2</nmwg:parameter>
    #
    # 'value' would be returned for each of them
    #
    my $value = extract($node);    
    
    my %rns = ();
    reMap(\%rns, \%ns, $DOM); 
       
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

=head2 chainMetadata($dom, $uri)

Given a dom of objects (and a uri), this function will continuously loop through performing
a 'chaining' operation to share values between metadata objects.  An example would be:

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

=head2 countRefs($id, $dom, $uri, $element, $attr)

Given a ID, and a series of 'struct' objects and a key 'value' to search on, this function 
will return a 'count' of the number of times the id was seen as a reference to the objects.  
This is useful for eliminating 'dead' blocks that may not contain a trigger.  The function
will return -1 on error.  

=head2 genuid()

Generates a random number.

=head2 extract($node)

Returns a 'value' from a xml element, either the value attribute or the 
text field.

=head2 reMap(\%{$rns}, \%{$ns}, $dom_node) 

Re-map the nodes namespace prefixes to known prefixes (to not screw with the 
XPath statements that will occur later).

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<IO::File>, L<XML::XPath>, L<Time::HiRes>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

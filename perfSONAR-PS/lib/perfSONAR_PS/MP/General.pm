#!/usr/bin/perl

package perfSONAR_PS::MP::General;
use Carp qw( carp );
use Exporter;  
use perfSONAR_PS::Common;
use perfSONAR_PS::MP::Base;

@ISA = ('Exporter');
@EXPORT = ( 'cleanMetadata', 'cleanData', 'removeReferences', 'lookup', 'extract' );


sub cleanMetadata {
  my($mp) = @_;  
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"cleanMetadata\"";

  if(defined $mp and $mp ne "") {
    $mp->{STORE} = chainMetadata($mp->{STORE}, $mp->{NAMESPACES}->{"nmwg"});
   
    foreach my $md ($mp->{STORE}->getElementsByTagNameNS($mp->{NAMESPACES}->{"nmwg"}, "metadata")) {
      my $count = countRefs($md->getAttribute("id"), $mp->{STORE}, $mp->{NAMESPACES}->{"nmwg"}, "data", "metadataIdRef");
      if($count == 0) {
        $mp->{STORE}->getDocumentElement->removeChild($md);
      } 
      else {
        $mp->{METADATAMARKS}->{$md->getAttribute("id")} = $count;
      }
    }    
  }
  else {
    perfSONAR_PS::MP::Base::error("Missing argument", __LINE__);
  }
  return;
}


sub cleanData {
  my($mp) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"cleanData\"";
  if(defined $mp and $mp ne "") {
    foreach my $d ($mp->{STORE}->getElementsByTagNameNS($mp->{NAMESPACES}->{"nmwg"}, "data")) {
      my $count = countRefs($d->getAttribute("metadataIdRef"), $mp->{STORE}, $mp->{NAMESPACES}->{"nmwg"}, "metadata", "id");
      if($count == 0) {
        $mp->{STORE}->getDocumentElement->removeChild($d);
      } 
      else {
        $mp->{DATAMARKS}->{$d->getAttribute("id")} = $count;
      }         
    }
  }
  else {
    perfSONAR_PS::MP::Base::error("Missing argument", __LINE__);  
  }
  return;
}


sub lookup {
  my($mp, $uri, $default) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"lookup\"";
  
  if((defined $mp and $mp ne "") and 
     (defined $uri and $uri ne "") and 
     (defined $default and $default ne "")) {
    my $prefix = "";
    foreach my $n (keys %{$mp->{NAMESPACES}}) {
      if($uri eq $mp->{NAMESPACES}->{$n}) {
        $prefix = $n;
        last;
      }
    }
    $prefix = $default if($prefix eq "");
    return $prefix;
  }
  else {
    perfSONAR_PS::MP::Base::error("Missing argument", __LINE__);  
  }
  return "";
}


sub extract {
  my($mp, $node) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"extract\"";    
  if((defined $mp and $mp ne "") and
     (defined $node and $node ne "")) {
    if($node->getAttribute("value")) {
      return $node->getAttribute("value");
    }
    else {
      return $node->textContent;
    }  
  }
  else {
    perfSONAR_PS::MP::Base::error("Missing argument", __LINE__);
  }
  return "";
}


sub removeReferences {
  my($mp, $id, $did) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"removeReferences\"";    
    
  if((defined $mp and $mp ne "") and
     (defined $id and $id ne "") and 
     (defined $did and $did ne "")) {
     
    $mp->{DATAMARKS}->{$did}--;
    $mp->{METADATAMARKS}->{$id}--;
    
    foreach my $dm (sort keys %{$mp->{DATAMARKS}}) {
      if($mp->{DATAMARKS}->{$dm} == 0) {
        delete $mp->{DATAMARKS}->{$dm};
        my $rmD = $mp->{STORE}->find("//nmwg:data[\@id=\"".$dm."\"]")->get_node(1);
        $mp->{STORE}->getDocumentElement->removeChild($rmD);   
      }
    }
    
    foreach my $mm (sort keys %{$mp->{METADATAMARKS}}) {
      if($mp->{METADATAMARKS}->{$mm} == 0) {
        delete $mp->{METADATAMARKS}->{$mm};
        my $rmMD = $mp->{STORE}->find("//nmwg:metadata[\@id=\"".$mm."\"]")->get_node(1);
        $mp->{STORE}->getDocumentElement->removeChild($rmMD);  
      }
    }  
  }
  else {
    perfSONAR_PS::MP::Base::error("Missing argument", __LINE__);
  }
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MP::General - A module that provides methods for general tasks that MPs need to 
perform, such as creating messages or result code structures.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of MPs in the perfSONAR-PS framework.  
As such there is no 'common thread' that each method shares.  This module IS NOT an object, 
and the methods can be invoked directly (and sparingly).  

=head1 SYNOPSIS


    use perfSONAR_PS::MP::General;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $mp = perfSONAR_PS::MP::...;
    
    # do mp stuff ...
    
    cleanMetadata(\%{$mp}); 

    cleanData(\%{$mp}); 
    
    my $prefix = lookup(\%{$mp}, "http://ggf.org/ns/nmwg/base/2.0/", "nmwg");
    
    # consider the elements that could be stored in '$node':
    #
    #  <nmwg:parameter name="something">value</nmwg:parameter>
    #  <nmwg:parameter name="something" value="value" />
    #  <nmwg:parameter name="something" value="value" />value2</nmwg:parameter>
    #
    # 'value' would be returned for each of them
    #
    my $value = extract(\%{$mp}, $node);
    
    removeReferences(\%{$mp}, $id_value);
    
    
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The offered API is basic for now, until more common features to MPs can be identified
and utilized in this module.

=head2 cleanMetadata($mp)

Chains, and removes unused metadata values from the metadata object located in the 
passed 'MP' object.

=head2 cleanData($mp)

Chains, and removes unused data values from the data object located in the 
passed 'MP' object.

=head2 lookup($mp, $uri, $default)

Lookup the prefix value for a given URI in the NS hash.  If not found, supply a 
simple deafult.

=head2 extract($mp, $node)
Returns a 'value' from a xml element, either the 'value' attribute or the 
text field.

=head2 removeReferences($mp, $id, $did)

Removes a value from the an object (data/metadata) located in the passed 'MP' object 
and only if the value is equal to the supplied id values. 

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

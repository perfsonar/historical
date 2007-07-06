#!/usr/bin/perl -w

package perfSONAR_PS::LS::General;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

@ISA = ('Exporter');
@EXPORT = ('createControlKey', 'createKey', 'createData', 'getXQuery');


sub createControlKey {
  my($key, $time) = @_;
  my $keyElement = "  <nmwg:metadata id=\"".$key."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$keyElement = $keyElement . "    <nmwg:parameters id=\"control-parameters\">\n";
	$keyElement = $keyElement . "      <nmwg:parameter name=\"timestamp\">".$time."</nmwg:parameter>\n";
	$keyElement = $keyElement . "    </nmwg:parameters>\n";
	$keyElement = $keyElement . "  </nmwg:metadata>\n";    
  return $keyElement;
}


sub createKey {
  my($id, $metadataIdRef, $key, $eventType) = @_;
  my $keyElement = "  <nmwg:metadata id=\"".$id."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" ";
	if(defined $metadataIdRef and $metadataIdRef ne "") {
	  $keyElement = $keyElement . "metadataIdRef=\"".$metadataIdRef."\" >\n";
	}
	else {
	  $keyElement = $keyElement . ">\n";
	}
	$keyElement = $keyElement . "    <nmwg:parameters id=\"parameters\">\n";
	$keyElement = $keyElement . "      <nmwg:parameter name=\"lsKey\">".$key."</nmwg:parameter>\n";
	$keyElement = $keyElement . "    </nmwg:parameters>\n";
	$keyElement = $keyElement . "    <nmwg:eventType>".$eventType."</nmwg:eventType>\n";
	$keyElement = $keyElement . "  </nmwg:metadata>\n";    
  return $keyElement;
}


sub createData {
  my($dataId, $metadataId, $data) = @_;
  my $dataElement = "  <nmwg:data id=\"".$dataId."\" metadataIdRef=\"".$metadataId."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
	$dataElement = $dataElement . "    " . $data . "\n";
	$dataElement = $dataElement . "  </nmwg:data>\n";
  return $dataElement;
}


sub getXQuery {
  my($node) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::General");
  if(defined $node and $node ne "") {
    $queryString = subjectQuery($node, "");
    return $queryString;  
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub subjectQuery {
  my($node, $queryString) = @_;

  my $queryCount = 0;
  if($node->nodeType != 3) {

    (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:data//;
    $path =~ s/\[\d\]//g;
    $path =~ s/^\///g;  
    
    foreach my $attr ($node->attributes) {
      if($attr->isa('XML::LibXML::Attr')) {
        if($attr->getName ne "id" and !($attr->getName =~ m/.*IdRef$/)) {
          if($queryCount == 0) {
            if($queryString) {
              $queryString = $queryString . " and ";
            }
            $queryString = $queryString . $path . "[";
            $queryString = $queryString . "\@" . $attr->getName . "=\"" . $attr->getValue . "\"";
            $queryCount++;
          }
          else {
            $queryString = $queryString . " and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
          }
        }
      }
    }
   
    if($node->hasChildNodes()) {
      my @children = $node->childNodes;
      if($#children == 0) {
        if($node->firstChild->nodeType == 3) {        
          (my $value = $node->firstChild->textContent) =~ s/\s*//g;
          if($value) {
            if($queryCount == 0) {
              if($queryString) {
                $queryString = $queryString . " and ";
              }
              $queryString = $queryString . $path . "[";
              $queryString = $queryString . "text()=\"" . $value . "\"";
              $queryCount++;
            }
            else {
              $queryString = $queryString . " and text()=\"" . $value . "\"";              
            }
            if($queryCount) {
              $queryString = $queryString . "]"
            }                   
            return $queryString;
          }        
        }
      }
      if($queryCount) {
        $queryString = $queryString . "]"
      }
      foreach my $c ($node->childNodes) {
        $queryString = subjectQuery($c, $queryString);
      }
    }
    
  }
  if($queryCount) {
    $queryString = $queryString . "]"
  }
  return $queryString;
}

1;


__END__
=head1 NAME

perfSONAR_PS::LS::General - ...

=head1 DESCRIPTION

. 

=head1 SYNOPSIS

    ...
    
=head1 DETAILS

... 

=head1 API

...

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, <zurawski@internet2.edu>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

#!/usr/bin/perl

package perfSONAR_PS::MA::General;
use Carp qw( carp );
use Exporter;  
use perfSONAR_PS::Common;

@ISA = ('Exporter');
@EXPORT = ('getResultMessage', 'getResultCodeMessage', 'getResultCodeMetadata', 
           'getResultCodeData', 'getMetadatXQuery', 'extract', 'getTime');

sub getResultMessage {
  my ($id, $messageIdRef, $type, $content) = @_;   
  if(defined $content and $content ne "") {
    my $m = "<nmwg:message xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
    if(defined $id and $id ne "") {
      $m = $m . " id=\"".$id."\"";
    }
    if(defined $messageIdRef and $messageIdRef ne "") {
      $m = $m . " messageIdRef=\"".$messageIdRef."\"";
    }
    if(defined $type and $type ne "") {
      $m = $m . " type=\"".$type."\"";
    }        
    $m = $m . ">\n  ";
    $m = $m . $content;
    $m = $m . "</nmwg:message>\n";
    return $m;
  }
  else {
    carp("perfSONAR_PS::MA::General:\tMissing argument \"content\" to \"getResultMessage\" at line ".__LINE__.".");
  }
  return "";
}


sub getResultCodeMessage {
  my ($id, $messageIdRef, $type, $event, $description) = @_;   
  if((defined $event and $event ne "") and 
     (defined $description and $description ne "")) {
    my $metadataId = genuid();
    my $dataId = genuid();
    return getResultMessage($id, $messageIdRef, $type, getResultCodeMetadata($metadataId, $event).getResultCodeData($dataId, $metadataId, $description));
  }
  else {
    carp("perfSONAR_PS::MA::General:\tMissing argument \"content\" to \"getResultMessage\" at line ".__LINE__.".");
  }
  return "";
}


sub getResultCodeMetadata {
  my ($id, $event) = @_;  
  if((defined $id and $id ne "") and 
     (defined $event and $event ne "")) {
    my $md = "  <nmwg:metadata id=\"".$id."\">\n";
    $md = $md . "    <nmwg:eventType>";
    $md = $md . $event;
    $md = $md . "</nmwg:eventType>\n";
    $md = $md . "  </nmwg:metadata>\n";
    return $md;
  }
  else {
    carp("perfSONAR_PS::MA::General:\tMissing argument(s) to \"getResultMetadata\" at line ".__LINE__.".");
  }
  return "";
}


sub getResultCodeData {
  my ($id, $metadataIdRef, $description) = @_;  
  if((defined $id and $id ne "") and 
     (defined $metadataIdRef and $metadataIdRef ne "") and 
     (defined $description and $description ne "")) {
    my $d = "  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$metadataIdRef."\">\n";
    $d = $d . "    <nmwgr:datum xmlns:nmwgr=\"http://ggf.org/ns/nmwg/result/2.0/\">";
    $d = $d . $description;
    $d = $d . "</nmwgr:datum>\n";  
    $d = $d . "  </nmwg:data>\n";
    return $d;
  }
  else {
    carp("perfSONAR_PS::MA::General:\tMissing argument(s) to \"getResultData\" at line ".__LINE__.".");
  }
  return "";
}


sub getTime {
  my($ma, $id) = @_;
  $ma->{FILENAME} = "perfSONAR_PS::MA::General";  
  $ma->{FUNCTION} = "\"getTime\"";    
  if((defined $ma and $ma ne "") and
     (defined $id and $id ne "")) {

    my $m = $ma->{REQUESTDOM}->find("//nmwg:metadata[\@id=\"".$id."\"]")->get_node(1);

    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
      $ma->{TIME}->{"START"} = extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gte\"]")->get_node(1));
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
      $ma->{TIME}->{"END"} = extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lte\"]")->get_node(1));
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
      $ma->{TIME}->{"START"} = eval(extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gt\"]")->get_node(1))+1);
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
      $ma->{TIME}->{"END"} = eval(extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lt\"]")->get_node(1))+1);
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
      $ma->{TIME}->{"START"} = extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"eq\"]")->get_node(1));
      $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"consolidationFunction\"]")) {
      $ma->{TIME}->{"CF"} = extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"consolidationFunction\"]")->get_node(1));
    }
    if($m->find(".//nmwg:parameters/select:parameter[\@name=\"resolution\"]")) {
      $ma->{TIME}->{"RESOLUTION"} = extract($ma, 
        $m->find(".//nmwg:parameters/select:parameter[\@name=\"resolution\"]")->get_node(1));
    }
       
    foreach $t (keys %{$ma->{TIME}}) {
      $ma->{TIME}->{$t} =~ s/(\n)|(\s+)//g;
    }
    return;  
  }
  else {
    perfSONAR_PS::MA::Base::error($ma, "Missing argument", __LINE__);
  }
  return "";
}


sub getMetadatXQuery {
  my($ma, $id, $data) = @_;
  $ma->{FILENAME} = "perfSONAR_PS::MA::General";  
  $ma->{FUNCTION} = "\"getMetadatXQuery\"";    
  if((defined $ma and $ma ne "") and
     (defined $id and $id ne "")) {

    my $m = $ma->{REQUESTDOM}->find("//nmwg:metadata[\@id=\"".$id."\"]")->get_node(1);

    if($data) {
     
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
        $ma->{TIME}->{"START"} = extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gte\"]")->get_node(1));
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
        $ma->{TIME}->{"END"} = extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lte\"]")->get_node(1));
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
        $ma->{TIME}->{"START"} = eval(extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"gt\"]")->get_node(1))+1);
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
        $ma->{TIME}->{"END"} = eval(extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"lt\"]")->get_node(1))+1);
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
        $ma->{TIME}->{"START"} = extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"time\" and \@operator=\"eq\"]")->get_node(1));
        $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"consolidationFunction\"]")) {
        $ma->{TIME}->{"CF"} = extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"consolidationFunction\"]")->get_node(1));
      }
      if($m->find(".//nmwg:parameters/select:parameter[\@name=\"resolution\"]")) {
        $ma->{TIME}->{"RESOLUTION"} = extract($ma, 
          $m->find(".//nmwg:parameters/select:parameter[\@name=\"resolution\"]")->get_node(1));
      }
       
      foreach $t (keys %{$ma->{TIME}}) {
        $ma->{TIME}->{$t} =~ s/(\n)|(\s+)//g;
      }
    }
    $queryString = subjectQuery($m, "");
    return $queryString;  
  }
  else {
    perfSONAR_PS::MA::Base::error($ma, "Missing argument", __LINE__);
  }
  return "";
}


sub subjectQuery {
  my($node, $queryString) = @_;
  my $queryCount = 0;
  
  if($node->nodeType != 3) {
    if(!($node->nodePath() =~ m/nmwg:parameters\/select:parameter/)) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
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
  }
  if($queryCount) {
    $queryString = $queryString . "]"
  }
  return $queryString;
}


sub extract {
  my($ma, $node) = @_;
  $ma->{FILENAME} = "perfSONAR_PS::MA::General";  
  $ma->{FUNCTION} = "\"extract\"";    
  if((defined $ma and $ma ne "") and
     (defined $node and $node ne "")) {
    if($node->getAttribute("value")) {
      return $node->getAttribute("value");
    }
    else {
      return $node->textContent;
    }  
  }
  else {
    perfSONAR_PS::MA::Base::error($ma, "Missing argument", __LINE__);
  }
  return "";
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::General - A module that provides methods for general tasks that MAs need to 
perform, such as creating messages or result code structures.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of MAs in the perfSONAR-PS framework.  
As such there is no 'common thread' that each method shares.  This module IS NOT an object, 
and the methods can be invoked directly (and sparingly).  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::General;
    use perfSONAR_PS::Common;
        
    my $id = genuid();	
    my $idRef = genuid();

    my $content = "<nmwg:metadata />";
	
    my $msg = getResultMessage($id, $idRef, "response", $content);
    
    $msg = getResultCodeMessage($id, $idRef, "response", "error.ma.transport" , "something...");
    
    $msg = getResultCodeMetadata($id, "error.ma.transport);
    
    $msg = getResultCodeData($id, $idRef, "something...");


    # Consider this metadata:
    # 
    # <nmwg:metadata xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="1">
    #   <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="stout">
    #     <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
    #       <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
    #       <nmwgt:hostName>stout</nmwgt:hostName>
    #       <nmwgt:ifName>eth1</nmwgt:ifName>
    #       <nmwgt:direction>in</nmwgt:direction>
    #     </nmwgt:interface>
    #   </netutil:subject>
    #   <nmwg:parameters xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="2">
    #     <select:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="time" operator="gte">
    #       1176480310
    #     </select:parameter>
    #     <select:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="time" operator="lte">
    #       1176480340
    #     </select:parameter>      
    #     <select:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="consolidationFunction">
    #       AVERAGE
    #     </select:parameter>     
    #   </nmwg:parameters>
    # </nmwg:metadata>

    # note that $ma is an MA object.

    my $queryString = "/nmwg:metadata[".
      getMetadatXQuery($ma, $id).
      "]/\@id";

    # the query after should look like this:
    #
    # /nmwg:metadata[
    #   netutil:subject/nmwgt:interface/nmwgt:ifAddress[
    #     @type="ipv4" and text()="128.4.133.167"
    #   ] and 
    #   netutil:subject/nmwgt:interface/nmwgt:hostName[text()="stout"] and 
    #   netutil:subject/nmwgt:interface/nmwgt:ifName[text()="eth1"] and 
    #   netutil:subject/nmwgt:interface/nmwgt:direction[text()="in"]
    # ]/@id

    # the time structure should look like this:
    #
    #   {
    #     'START' => '1173723350',
    #     'END' => '1173723366'
    #     'CF' => 'AVERAGE'
    #     'RESOLUTION' => ''    
    #   };
    
    # consider the elements that could be stored in '$node':
    #
    #  <nmwg:parameter name="something">value</nmwg:parameter>
    #  <nmwg:parameter name="something" value="value" />
    #  <nmwg:parameter name="something" value="value" />value2</nmwg:parameter>
    #
    # 'value' would be returned for each of them
    #
    my $value = extract($ma, $node);    
    
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The offered API is basic for now, until more common features to MAs can be identified
and utilized in this module.

=head2 getResultMessage($id, $messageIdRef, $type, $content)

The arguments are a message id, a messageIdRef, a messate type, and finally the 'content'
which is understood to be the xml content of the message.  

=head2 getResultCodeMessage($id, $messageIdRef, $type, $event, $description)

The arguments are a message id, a messageIdRef, a messate type, an 'eventType' for the result
code metadata, and a message for the result code data.  

=head2 getResultCodeMetadata($id, $event)

The arguments are a metadata id, and an 'eventType' for the result code metadata.

=head2 getResultCodeData($id, $metadataIdRef, $description)

The arguments are a data id, a metadataIdRef, and a message for the result code data.  

=head2 getMetadatXQuery($ma, $id, $data)

This function is meant to be used to convert a metadata object into an 
XQuery statement.  If the '$data' variable is set to 1, time based values 
are stored in a time object to be used in the subsequent data retrieval 
steps.  

=head2 subjectQuery($node, $queryString)

Helper function to create an xquery string from a metadata object.

=head2 extract($ma, $node)

Returns a 'value' from a xml element, either the 'value' attribute or the 
text field.

=head2 error($ma, $msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

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

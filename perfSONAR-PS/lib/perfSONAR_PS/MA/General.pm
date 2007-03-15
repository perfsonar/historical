#!/usr/bin/perl

package perfSONAR_PS::MA::General;
use Carp qw( carp );
use Exporter;  
use perfSONAR_PS::Common;

@ISA = ('Exporter');
@EXPORT = ('getResultMessage', 'getResultCodeMessage', 'getResultCodeMetadata', 
           'getResultCodeData', 'getMetadatXQuery');

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


sub getMetadatXQuery {
  my($metadata, $time, $id) = @_;
  my $queryString = "";
  my $queryCount = 0;
  
  my %struct = ();
  foreach my $m (keys %{$metadata->{$id}}) {
    my $attribute = "";
    my $element = "";
    if(($m =~ m/^.*-id$/) or 
       ($m =~ m/^.*IdRef$/)) {	  
      # ignore for now
    }
    elsif(($m =~ m/^.*:parameter-time-.*$/) or 
          ($m =~ m/^.*:parameter-consolidationFunction$/) or 
	  ($m =~ m/^.*:parameter-resolution$/)) {
      if($m =~ m/^.*select:parameter-time-gte$/) {
        $time->{"START"} = $metadata->{$id}->{$m};
      }
      elsif($m =~ m/^.*select:parameter-time-gt$/) {
        $time->{"START"} = $metadata->{$id}->{$m}+1;
      }
      elsif($m =~ m/^.*select:parameter-time-lte$/) {
        $time->{"END"} = $metadata->{$id}->{$m};
      }
      elsif($m =~ m/^.*select:parameter-time-lt$/) {
        $time->{"END"} = $metadata->{$id}->{$m}+1;
      }
      elsif($m =~ m/^.*select:parameter-time-eq$/) {
        $time->{"START"} = $metadata->{$id}->{$m};
        $time->{"END"} = $metadata->{$id}->{$m};
      }				
      elsif($m =~ m/^.*select:parameter-resolution$/) {
        $time->{"RESOLUTION"} = $metadata->{$id}->{$m};
      }	
      elsif($m =~ m/^.*select:parameter-consolidationFunction$/) {
        $time->{"CF"} = $metadata->{$id}->{$m};
      }	          
    }    
    elsif(($m =~ m/^.*:dst$/) or ($m =~ m/^.*:src$/) or 
       ($m =~ m/^.*:ifAddress$/) or ($m =~ m/^.*:ipAddress$/)){
      $element = $m;
      $element =~ s/^.*:metadata\///;      
      $struct{$element}{"text"} = $metadata->{$id}->{$m};
    }
    elsif(($m =~ m/^.*:dst-.*$/) or ($m =~ m/^.*:src-.*$/) or 
          ($m =~ m/^.*:ifAddress-.*$/) or ($m =~ m/^.*:ipAddress-.*$/)) {
      $attribute = $m;
      $attribute =~ s/^.*:metadata.*://; 
      $attribute =~ s/^.*-//; 
      $element = $m;
      $element =~ s/^.*:metadata\///;
      $element =~ s/-.*$//;
      $struct{$element}{$attribute} = $metadata->{$id}->{$m};   
    }
    elsif(($m =~ m/^.*:parameter.*$/)) {
      $attribute = $m;
      $attribute =~ s/^.*:metadata.*://; 
      $attribute =~ s/^.*-//; 
      $element = $m;
      $element =~ s/^.*:metadata\///;
      $element =~ s/-.*$//;
      $struct{$element}{$attribute} = $metadata->{$id}->{$m};   
    }
    else {
      $element = $m;
      $element =~ s/^.*:metadata\///;      
      $struct{$element}{"text"} = $metadata->{$id}->{$m};
    }            
  } 

  foreach my $s (sort keys %struct) {
    if(!$queryCount) {
      $queryString = $queryString.$s."[";
      $queryCount++;
    }
    else {
      $queryString = $queryString." and ".$s."[";
    } 
    my $queryCount2 = 0;
    foreach my $s2 (sort keys %{$struct{$s}}) {
      if($s2 eq "text") {
        if(!$queryCount2) {
          $queryString = $queryString."text()='".$struct{$s}{$s2}."'";
          $queryCount2++;
	}
	else {
          $queryString = $queryString." and text()='".$struct{$s}{$s2}."'";
	}
      }
      else {
        if(!$queryCount2) {
          $queryString = $queryString."\@".$s2."='".$struct{$s}{$s2}."'";
          $queryCount2++;
	}
	else {
          $queryString = $queryString." and \@".$s2."='".$struct{$s}{$s2}."'";
	}
      }
    }
    $queryString = $queryString."]";
  }
  
  return $queryString;  
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
    
    my %metadata = {
      'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
      'nmwg:metadata/nmwg:parameters-id' => '3',
      'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-value' => 'lager',
      'nmwg:metadata/nmwg:parameters/select:parameter-time-lte' => '1173723366',
      'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-type' => 'hostname',
      'nmwg:metadata-id' => 'meta1',
      'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-type' => 'hostname',
      'nmwg:metadata/nmwg:parameters/select:parameter-time-gte' => '1173723350',
      'nmwg:metadata/ping:subject-id' => 'sub1'
    };

    my %time = ();
    my $queryString = "/nmwg:metadata[".
      getMetadatXQuery(\%metadata, 
                       \%time, 
		       $m).
      "]/\@id";

    # the query after should look like this:
    #
    # /nmwg:metadata[
    #   ping:subject/nmwgt:endPointPair/nmwgt:dst[@type='hostname' and 
    #     @value='ellis.internet2.edu'] and 
    #   ping:subject/nmwgt:endPointPair/nmwgt:src[@type='hostname' and 
    #     @value='lager']
    # ]/@id

    # the time structure should look like this:
    #
    #   {
    #     'START' => '1173723350',
    #     'END' => '1173723366'
    #   };
    
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

=head2 getMetadatXQuery($sentmd, $sentt, $id)

This function is meant to be used to convert a metadata object into an 
XQuery statement.  Additionally, time based values are stored in a time
object to be used in the subsequent data retrieval steps.  

=head2 error($msg, $line)	

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

$Id:$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

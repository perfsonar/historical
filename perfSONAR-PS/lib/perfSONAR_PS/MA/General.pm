#!/usr/bin/perl

package perfSONAR_PS::MA::General;
use Carp qw( carp );
use Exporter;  
use perfSONAR_PS::Common;
@ISA = ('Exporter');
@EXPORT = ('getResultMessage', 'getResultCodeMessage', 'getResultCodeMetadata', 'getResultCodeData');

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
    my $md = "  <nmwg:metadata id=\"result-code-".$id."\">\n";
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
    my $d = "  <nmwg:data id=\"result-code-description-".$id."\" metadataIdRef=\"result-code-".$metadataIdRef."\">\n";
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

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MA::SNMP>

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

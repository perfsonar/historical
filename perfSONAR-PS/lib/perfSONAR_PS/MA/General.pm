#!/usr/bin/perl

package perfSONAR_PS::MA::General;
use Exporter;  
use perfSONAR_PS::Common;
@ISA = ('Exporter');
@EXPORT = ('getResultMessage','getResultMetadata', 'getResultData');

sub getResultMessage {
  my ($id, $messageIdRef, $type, $content) = @_;   
  if(defined $content && $content ne "") {
    my $m = "<nmwg:message xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
    if(defined $id && $id ne "") {
      $m = $m . " id=\"".$id."\"";
    }
    if(defined $messageIdRef && $messageIdRef ne "") {
      $m = $m . " messageIdRef=\"".$messageIdRef."\"";
    }
    if(defined $type && $type ne "") {
      $m = $m . " type=\"".$type."\"";
    }        
    $m = $m . ">\n  ";
    $m = $m . $content;
    $m = $m . "</nmwg:message>\n";
    return $m;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument \"content\" to \"getResultMessage\".");
  }
  return "";
}


sub getResultCodeMessage {
  my ($id, $messageIdRef, $type, $event, $description) = @_;   
  if((defined $event && $event ne "") && 
     (defined $description && $description ne "")) {
    my $metadataId = genuid();
    my $dataId = genuid();
    return getResultMessage($id, $messageIdRef, $type, getResultCodeMetadata($metadataId, $event), getResultCodeData($dataId, $metadataId, $description));
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument \"content\" to \"getResultMessage\".");
  }
  return "";
}


sub getResultCodeMetadata {
  my ($id, $event) = @_;  
  if((defined $id && $id ne "") && 
     (defined $event && $event ne "")) {
    my $md = "  <nmwg:metadata id=\"result-code-".$id."\">\n";
    $md = $md . "    <nmwg:eventType>";
    $md = $md . $event;
    $md = $md . "</nmwg:eventType>\n";
    $md = $md . "  </nmwg:metadata>\n";
    return $md;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument(s) to \"getResultMetadata\".");
  }
  return "";
}


sub getResultCodeData {
  my ($id, $metadataIdRef, $description) = @_;  
  if((defined $id && $id ne "") && 
     (defined $metadataIdRef && $metadataIdRef ne "") && 
     (defined $description && $description ne "")) {
    my $d = "  <nmwg:data id=\"result-code-description-".$id."\" metadataIdRef=\"result-code-".$metadataIdRef."\">\n";
    $d = $d . "    <nmwgr:datum xmlns:nmwgr=\"http://ggf.org/ns/nmwg/result/2.0/\">";
    $d = $d . $description;
    $d = $d . "</nmwgr:datum>\n";  
    $d = $d . "  </nmwg:data>\n";
    return $d;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument(s) to \"getResultData\".");
  }
  return "";
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::General - A module that provides methods for ...

=head1 DESCRIPTION

...

=head1 SYNOPSIS

    use perfSONAR_PS::MA::;
    
    ...

=head1 DETAILS

...

=head1 API

...

=head2 new()

...

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>

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

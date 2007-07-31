#!/usr/bin/perl -w

package perfSONAR_PS::Messages;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;


@ISA = ('Exporter');
@EXPORT = ('getResultMessage', 'getResultCodeMessage', 'getResultCodeMetadata', 
           'getResultCodeData', 'createMetadata', 'createData');

sub getResultMessage {
  my ($id, $messageIdRef, $type, $content, $namespaces) = @_;  
  my $logger = get_logger("perfSONAR_PS::Messages");
   
  if(defined $content and $content ne "") {
    my $m = "<nmwg:message xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";

    if(defined $namespaces) {
       foreach $ns (keys %{ $namespaces }) {
         next if $namespaces->{$ns} eq "nmwg";
         $m .= " xmlns:".$namespaces->{$ns}."=\"$ns\"";
       }
    }

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
    $logger->debug("Result message created.");
    return $m;
  }
  else {
    $logger->error("Missing argument.");
  }
  return "";
}


sub getResultCodeMessage {
  my ($id, $messageIdRef, $metadataIdRef, $type, $event, $description) = @_;   
  my $logger = get_logger("perfSONAR_PS::Messages");
  
  if((defined $event and $event ne "") and 
     (defined $description and $description ne "")) {
    my $metadataId = "metadata.".genuid();
    my $dataId = "data.".genuid();
    $logger->debug("Result code message created.");
    return getResultMessage($id, $messageIdRef, $type, getResultCodeMetadata($metadataId, $metadataIdRef, $event).getResultCodeData($dataId, $metadataId, $description));
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub getResultCodeMetadata {
  my ($id, $metadataIdRef, $event) = @_; 
  my $logger = get_logger("perfSONAR_PS::Messages");

  if((defined $id and $id ne "") and 
     (defined $event and $event ne "")) {
    my $md = "  <nmwg:metadata id=\"".$id."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" ";
    if(defined $metadataIdRef and $metadataIdRef ne "") {
      $md = $md . " metadataIdRef=\"".$metadataIdRef."\" >\n";
    }
    else {
      $md = $md . ">\n";
    } 
    $md = $md . "    <nmwg:eventType>";
    $md = $md . $event;
    $md = $md . "</nmwg:eventType>\n";
    $md = $md . "  </nmwg:metadata>\n";
    $logger->debug("Result code metadata created.");
    return $md;
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub getResultCodeData {
  my ($id, $metadataIdRef, $description) = @_;  
  my $logger = get_logger("perfSONAR_PS::Messages");

  if((defined $id and $id ne "") and 
     (defined $metadataIdRef and $metadataIdRef ne "") and 
     (defined $description and $description ne "")) {
    my $d = "  <nmwg:data id=\"".$id."\" metadataIdRef=\"".$metadataIdRef."\">\n";
    $d = $d . "    <nmwgr:datum xmlns:nmwgr=\"http://ggf.org/ns/nmwg/result/2.0/\">";
    $d = $d . $description;
    $d = $d . "</nmwgr:datum>\n";  
    $d = $d . "  </nmwg:data>\n";
    $logger->debug("Result code data created.");
    return $d;
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub createMetadata {
  my($id, $metadataIdRef, $content) = @_;
  my $mdElement = "  <nmwg:metadata id=\"".$id."\" ";
  if(defined $metadataIdRef and $metadataIdRef ne "") {
    $mdElement = $mdElement . "metadataIdRef=\"".$metadataIdRef."\" ";
  }
  if(defined $content and $content ne "") {
    $mdElement = $mdElement . "xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";  
	  $mdElement = $mdElement . "    " . $content . "\n";
	  $mdElement = $mdElement . "  </nmwg:metadata>\n";
  }
  else {
    $mdElement = $mdElement . "xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" />\n"; 
  }
  return $mdElement;
}


sub createData {
  my($dataId, $metadataId, $content) = @_;
  my $dataElement = "  <nmwg:data id=\"".$dataId."\" ";
  if(defined $metadataId and $metadataId ne "") {  
    $dataElement = $dataElement . "metadataIdRef=\"".$metadataId."\" ";
	}
  if(defined $content and $content ne "") {
    $dataElement = $dataElement . "xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";  
	  $dataElement = $dataElement . "    " . $content . "\n";
	  $dataElement = $dataElement . "  </nmwg:data>\n";
  }
  else {
    $dataElement = $dataElement . "xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" />\n"; 
  }
  return $dataElement;
}


1;


__END__
=head1 NAME

perfSONAR_PS::Messages - A module that provides common methods for performing actions on message
constructs.

=head1 DESCRIPTION

This module is a catch all for message related methods in the perfSONAR-PS framework.  As such 
there is no 'common thread' that each method shares.  This module IS NOT an object, and the 
methods can be invoked directly (and sparingly).  

=head1 SYNOPSIS

    use perfSONAR_PS::Messages;
    
    # NOTE: Individual methods can be extraced:
    # 
    # use perfSONAR_PS::Messages qw( getResultMessage getResultCodeMessage )

    my $id = genuid();	
    my $idRef = genuid();

    my $content = "<nmwg:metadata />";
	
    my $msg = getResultMessage($id, $idRef, "response", $content);
    
    $msg = getResultCodeMessage($id, $idRef, "response", "error.ma.transport" , "something...");
    
    $msg = getResultCodeMetadata($id, $idRef, "error.ma.transport);
    
    $msg = getResultCodeData($id, $idRef, "something...");
    
    $msg = createMetadata($id, $idRef, $content);

    $msg = createData($id, $idRef, $content);
    
           
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The API of perfSONAR_PS::Messages offers simple calls to create message
constructs.

=head2 getResultMessage($id, $messageIdRef, $type, $content)

Given a messageId, messageIdRef, a type, and some amount of content a 
message element is returned.

=head2 getResultCodeMessage($id, $messageIdRef, $metadataIdRef, $type, $event, $description)

Given a messageId, messageIdRef, metadataIdRef, messageType, event code, and
some sort of description, generate a result code message.  This function uses
the getResultCodeMetadata and getResultCodeData.  

=head2 getResultCodeMetadata($id, $metadataIdRef, $event)

Given an id, metadataIdRef, and some event code retuns the result metadata.

=head2 getResultCodeData($id, $metadataIdRef, $description)

Given an id, metadataIdRef, and some description return the result data.

=head2 createMetadata($id, $metadataIdRef, $content)

Given an id, metadataIdRef and some content, create a metadata.

=head2 createData($dataId, $metadataId, $content)

Given an id, metadataIdRef and some content, create a data.

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: Transport.pm 267 2007-07-06 19:38:45Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

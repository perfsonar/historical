#!/usr/bin/perl -w

package perfSONAR_PS::Messages;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;


@ISA = ('Exporter');
@EXPORT = ('getResultMessage', 'getResultCodeMessage', 'getResultCodeMetadata', 
           'getResultCodeData', 'createMetadata', 'createData', 'createEchoRequest');

sub getResultMessage {
  my ($id, $messageIdRef, $type, $content, $namespaces, $escape_content) = @_;  
  my $logger = get_logger("perfSONAR_PS::Messages");

  my $m = "<nmwg:message xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
  if(defined $namespaces) {
     foreach $ns (keys %{ $namespaces }) {
       next if $ns eq "nmwg";
       $m .= " xmlns:".$ns."=\"".$namespaces->{$ns}."\"";

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
  if(defined $content and $content ne "") {    
    if (defined $escape_content and $escape_content == 1) {
      $content = escapeString($content);
    }

    $m = $m . $content;
  }
  else {
    $logger->error("Missing argument.");
    my $mdID = "metadata.".genuid();
    $m = $m . getResultCodeMetadata($mdID, "", "failure.service");
    $m = $m . getResultCodeData("data.".genuid(), $mdID, "Internal Service Error; content not created for message.");
  }  
  $m = $m . "</nmwg:message>\n";
  $logger->debug("Result message created.");
  return $m;
}



sub getResultCodeMessage {
  my ($id, $messageIdRef, $metadataIdRef, $type, $event, $description, $escape_content) = @_;   
  my $logger = get_logger("perfSONAR_PS::Messages");
  if((defined $event and $event ne "") and 
     (defined $description and $description ne "")) {
    my $metadataId = "metadata.".genuid();
    my $dataId = "data.".genuid();
    $logger->debug("Result code message created.");
    return getResultMessage($id, $messageIdRef, $type, getResultCodeMetadata($metadataId, $metadataIdRef, $event).getResultCodeData($dataId, $metadataId, $description, $escape_content));
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
  my ($id, $metadataIdRef, $description, $escape_content) = @_;  
  my $logger = get_logger("perfSONAR_PS::Messages");

  if((defined $id and $id ne "") and 
     (defined $metadataIdRef and $metadataIdRef ne "") and 
     (defined $description and $description ne "")) {

    if (defined $escape_content and $escape_content == 1) {
      $description = escapeString($description);
    }

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


sub createEchoRequest($) {
  my ($type) = @_;

  if (defined $type and $type eq "ls") {
    $eventType = "http://schemas.perfsonar.net/tools/admin/echo/ls/2.0";
  } else {
    $eventType = "http://schemas.perfsonar.net/tools/admin/echo/2.0";
  }
  my $mdID = "metadata.".genuid();
  my $echo = "<nmwg:message type=\"EchoRequest\" id=\"message.".genuid()."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
  $echo = $echo . "  <nmwg:metadata id=\"".$mdID."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
  $echo = $echo . "    <nmwg:eventType>$eventType</nmwg:eventType>\n";
  $echo = $echo . "  </nmwg:metadata>\n";
  $echo = $echo . "  <nmwg:data id=\"data.".genuid()."\" metadataIdRef=\"".$mdID."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"/>\n";
  $echo = $echo . "</nmwg:message>\n";
  return $echo;
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

=head2 getResultMessage($id, $messageIdRef, $type, $content, $namespaces)

Given a messageId, messageIdRef, a type, and some amount of content a message
element is returned. If $namespaces is specified, it adds the specified
namespaces to the resulting nmwg:message.

=head2 getResultCodeMessage($id, $messageIdRef, $metadataIdRef, $type, $event, $description, $encode_description)

Given a messageId, messageIdRef, metadataIdRef, messageType, event code, and
some sort of description, generate a result code message.  This function uses
the getResultCodeMetadata and getResultCodeData.  If the $escape_description
value is equal to 1, the description is XML escaped.

=head2 getResultCodeMetadata($id, $metadataIdRef, $event)

Given an id, metadataIdRef, and some event code retuns the result metadata.

=head2 getResultCodeData($id, $metadataIdRef, $description, $escape_description)

Given an id, metadataIdRef, and some description return the result data. If the
$escape_description value is equal to 1, the description is XML escaped.

=head2 createMetadata($id, $metadataIdRef, $content)

Given an id, metadataIdRef and some content, create a metadata.

=head2 createData($dataId, $metadataId, $content)

Given an id, metadataIdRef and some content, create a data.

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

package perfSONAR_PS::Messages;

use strict;
use Exporter;
use Log::Log4perl qw(get_logger :nowarn);

our $VERSION = 0.02;
use perfSONAR_PS::Common;


our @ISA = ('Exporter');
our @EXPORT = (
        'startMessage',
        'endMessage',
        'startMetadata',
        'endMetadata',
        'startData',
        'endData',
        'startParameters',
        'endParameters',
        'addParameter',
        'getResultCodeMessage',
        'getResultCodeMetadata',
        'getResultCodeData',
        'statusReport',
        'createMessage',
        'createMetadata',
        'createData',
        );


sub startMessage($$$$$$) {
    my ($output, $id, $messageIdRef, $type, $content, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    my %attrs = ();
    $attrs{"type"} = $type;
    $attrs{"id"} = $id;
    $attrs{"messageIdRef"} = $messageIdRef if (defined $messageIdRef and $messageIdRef ne "");

    return $output->startElement(prefix => "nmwg", tag => "message", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => \%attrs, extra_namespaces => $namespaces, content => $content);
}

sub endMessage($) {
    my ($output) = @_;

    return $output->endElement("message");
}

sub startMetadata($$$$) {
    my ($output, $id, $metadataIdRef, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "") {
        $logger->error("Missing argument(s).");
        return -1;
    }

    my %attrs = ();
    $attrs{"id"} = $id;
    $attrs{"metadataIdRef"} = $metadataIdRef if (defined $metadataIdRef and $metadataIdRef ne "");

    return $output->startElement(prefix => "nmwg", tag => "metadata", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => \%attrs, extra_namespaces => $namespaces);
}

sub endMetadata($) {
    my ($output) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    return $output->endElement("metadata");
}

sub startData($$$$) {
    my ($output, $id, $metadataIdRef, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "" or !defined $metadataIdRef or $metadataIdRef eq "") {
        $logger->debug("createData failed: \"$id\" \"$metadataIdRef\"");
        return -1;
    }

    return $output->startElement(prefix => "nmwg", tag => "data", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id=>$id, metadataIdRef=>$metadataIdRef }, extra_namespaces => $namespaces);
}

sub endData($) {
    my ($output) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    return $output->endElement("data");
}

sub startParameters($$) {
    my ($output, $id) = @_;

    return $output->startElement(prefix => "nmwg", tag => "parameters", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id=>$id });
}

sub endParameters($) {
    my ($output) = @_;

    return $output->endElement("parameters");
}

# XXX this should probably ensure that the parameters are being created inside a parameters block
sub addParameter($$$) {
    my ($output, $name, $value) = @_;
    my $logger = get_logger("perfSONAR_PS::Messages");

    return $output->createElement(prefix => "nmwg", tag => "parameter", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => {name=>$name}, content => $value);
}

sub getResultCodeMessage {
    my ($output, $id, $messageIdRef, $metadataIdRef, $type, $event, $description, $namespaces, $escape_content) = @_;   
    my $logger = get_logger("perfSONAR_PS::Messages");

    my $n;

    my $ret_mdid = "metadata.".genuid();
    my $ret_did = "data.".genuid();

    $n = startMessage($output, $id, $messageIdRef, $type, "", undef);
    return $n if ($n != 0);
    $n = getResultCodeMetadata($output, $ret_mdid, $metadataIdRef, $event);
    return $n if ($n != 0);
    $n = getResultCodeData($output, $ret_did, $ret_mdid, $description, $escape_content);
    return $n if ($n != 0);
    $n = endMessage($output);

    return 0;
}

sub getResultCodeMetadata($$$$) {
    my ($output, $id, $metadataIdRef, $event) = @_; 
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "" or !defined $event or $event eq "") {
        $logger->error("Missing argument(s).");
        return -1;
    }

    my %attrs = ();
    $attrs{"id"} = $id;
    $attrs{"metadataIdRef"} = $metadataIdRef if (defined $metadataIdRef and $metadataIdRef ne "");

    $output->startElement(prefix => "nmwg", tag => "metadata", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => \%attrs);
    $output->startElement(prefix => "nmwg", tag => "eventType", namespace => "http://ggf.org/ns/nmwg/base/2.0/", content => $event);
    $output->endElement("eventType");
    $output->endElement("metadata");

    $logger->debug("Result code metadata created.");

    return 0;
}

# Changes: adds an 'escape_content' parameter at the end
sub getResultCodeData($$$$$) {
    my ($output, $id, $metadataIdRef, $description, $escape_content) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "" or !defined $metadataIdRef or $metadataIdRef eq "" or !defined $description or $description eq "") {
        return -1;
    }

    if (defined $escape_content and $escape_content == 1) {
        $description = escapeString($description);
    }

    $output->startElement(prefix => "nmwg", tag => "data", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id=>$id, metadataIdRef=>$metadataIdRef });
    $output->startElement(prefix => "nmwgr", tag => "datum", namespace => "http://ggf.org/ns/nmwg/result/2.0/", content => $description);
    $output->endElement("datum");
    $output->endElement("data");

    return 0;
}

sub statusReport($$$$$$) {
    my ($output, $mdId, $mdIdRef, $dId, $eventType, $msg) = @_;
    my $logger = get_logger("perfSONAR_PS::Messages");

    my $n = getResultCodeMetadata($output, $mdId, $mdIdRef, $eventType);

    return $n if ($n != 0);

    return getResultCodeData($output, $dId, $mdId, $msg, 1); 
}

sub createMessage($$$$$$) {
    my ($output, $id, $messageIdRef, $type, $content, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    my $n = startMessage($output, $id, $messageIdRef, $type, $content, $namespaces);

    return $n if ($n != 0);

    return endMessage($output);
}

sub createMetadata($$$$$) {
    my ($output, $id, $metadataIdRef, $content, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "") {
        $logger->error("Missing argument(s).");
        return -1;
    }

    my %attrs = ();
    $attrs{"id"} = $id;
    $attrs{"metadataIdRef"} = $metadataIdRef if (defined $metadataIdRef and $metadataIdRef ne "");

    my $n = $output->startElement(prefix => "nmwg", tag => "metadata", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => \%attrs, extra_namespaces => $namespaces, content => $content);
    return $n if ($n != 0);
    return $output->endElement("metadata");
}

sub createData($$$$$) {
    my ($output, $id, $metadataIdRef, $content, $namespaces) = @_;  
    my $logger = get_logger("perfSONAR_PS::Messages");

    if (!defined $id or $id eq "" or !defined $metadataIdRef or $metadataIdRef eq "") {
        $logger->debug("createData failed: \"$id\" \"$metadataIdRef\"");
        return -1;
    }

    $output->startElement(prefix => "nmwg", tag => "data", namespace => "http://ggf.org/ns/nmwg/base/2.0/", attributes => { id=>$id, metadataIdRef=>$metadataIdRef }, extra_namespaces => $namespaces, content => $content);
    $output->endElement("data");

    return 0;
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

=head2 createData($dataId, $metadataIdRef, $content)

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
# vim: expandtab shiftwidth=4 tabstop=4

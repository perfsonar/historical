package perfSONAR_PS::Services::LS::General;

use base 'Exporter';

use strict;
use warnings;

our $VERSION = 0.08;

=head1 NAME

perfSONAR_PS::LS::General - A module that provides methods for general tasks
that LSs need to perform.

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of :Ss in the
perfSONAR-PS framework.  As such there is no 'common thread' that each method
shares.  This module IS NOT an object, and the methods can be invoked directly
(and sparingly). 

=cut

use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Common;

our @EXPORT = ( 'wrapStore', 'createControlKey', 'createLSKey', 'createLSData', 'extractQuery');

=head2 wrapStore($content, $type)

Adds 'store' tags around some content.  This is to mimic the way eXist deals
with storing XML data.  The 'type' argument is used to type the store file.

=cut

sub wrapStore {
    my ( $content, $type ) = @_;
    my $store = "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
    if ( defined $type and $type ) {
        $store = $store . " type=\"" . $type . "\" ";
    }
    if ( defined $content and $content ) {
        $store = $store . ">\n";
        $store = $store . $content;
        $store = $store . "</nmwg:store>\n";
    }
    else {
        $store = $store . "/>\n";
    }
    return $store;
}

=head2 createControlKey($key, $time)

Creates a 'control' key for the control database that keeps track of time.

=cut

sub createControlKey {
    my ( $key, $time ) = @_;
    my $keyElement = "  <nmwg:metadata id=\"" . $key . "-control\" metadataIdRef=\"" . $key . "\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
    $keyElement = $keyElement . "    <nmwg:parameters id=\"control-parameters\">\n";
    $keyElement = $keyElement . "      <nmwg:parameter name=\"timestamp\">\n";
    $keyElement = $keyElement . "        <nmtm:time type=\"unix\" xmlns:nmtm=\"http://ggf.org/ns/nmwg/time/2.0/\">" . $time . "</nmtm:time>\n";
    $keyElement = $keyElement . "      </nmwg:parameter>\n";
    $keyElement = $keyElement . "    </nmwg:parameters>\n";
    $keyElement = $keyElement . "  </nmwg:metadata>\n";
    return wrapStore( $keyElement, "LSStore-control" );
}

=head2 createLSKey($key, $eventType)

Creates the 'internals' of the metadata that will be returned w/ a key.

=cut

sub createLSKey {
    my ( $key, $eventType ) = @_;
    my $keyElement = q{};
    $keyElement = $keyElement . "      <nmwg:key xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"key." . genuid() . "\">\n";
    $keyElement = $keyElement . "          <nmwg:parameters id=\"param." . genuid() . "\">\n";
    $keyElement = $keyElement . "            <nmwg:parameter name=\"lsKey\">" . $key . "</nmwg:parameter>\n";
    $keyElement = $keyElement . "          </nmwg:parameters>\n";
    $keyElement = $keyElement . "        </nmwg:key>\n";
    if ( defined $eventType and $eventType ) {
        $keyElement = $keyElement . "        <nmwg:eventType>" . $eventType . "</nmwg:eventType>\n";
    }
    return $keyElement;
}

=head2 createLSData($dataId, $metadataId, $data)

Creates a 'data' block that is stored in the backend storage. 

=cut

sub createLSData {
    my ( $dataId, $metadataId, $data ) = @_;
    my $dataElement = "    <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"" . $dataId . "\" metadataIdRef=\"" . $metadataId . "\">\n";
    $dataElement = $dataElement . "      " . $data . "\n";
    $dataElement = $dataElement . "    </nmwg:data>\n";
    return wrapStore( $dataElement, "LSStore" );
}

=head2 extractQuery($node)

Pulls out the COMPLETE contents of an XQuery subject, this also includes sub 
elements. 

=cut

sub extractQuery {
    my ($node) = @_;
    my $query = q{};
    if ( $node and $node->hasChildNodes() ) {
        foreach my $c ( $node->childNodes ) {
            if ( $c->nodeType == 3 ) {
                $query = $query . $c->textContent;
            }
            else {
                $query = $query . $c->toString;
            }
        }
    }
    return $query;
}

1;

__END__

=head1 SYNOPSIS

    use perfSONAR_PS::LS::General;
    use Time::HiRes qw(gettimeofday tv_interval);
    
    my $type = "LSStore";
    my $store = wrapStore("<nmwg:data />", $type);

    my $t0 = [Time::HiRes::gettimeofday];  
    my $key = "http://localhost:8080/perfSONAR_PS/services/LS";
    my $controlKey = createControlKey($key, $t0->[0].".".$t0->[1]);

    my $lsKey = createLSKey($key, "success.ls.registration");

    my $lsData = createLSData($dataId, $metadataId, $data);
        
    # Let $node be an XML::LibXML Node:
    #
    #  <xquery:subject id="sub2">
    #    declare namespace nmwg="http://ggf.org/ns/nmwg/base/2.0/";
    #    declare namespace perfsonar="http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/";
    #    declare namespace psservice="http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/";
    #    declare namespace xquery="http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/";
    #    for $metadata in /nmwg:store/nmwg:metadata
    #      let $metadata_id := $metadata/@id
    #      let $data := /nmwg:store/nmwg:data[@metadataIdRef=$metadata_id]
    #      where $metadata//psservice:accessPoint[
    #        text()="http://localhost:8181/axis/services/snmpMA" or
    #        @value="http://localhost:8181/axis/services/snmpMA"]
    #        return <nmwg:stuff>{$metadata} {$data}</nmwg:stuff>
    #  </xquery:subject>
    
    my $query = extractQuery($node);
    
    cleanLS(\%conf, \%ns);

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut


package perfSONAR_PS::Common;

=head1 NAME

perfSONAR_PS::Common - A module that provides common methods for performing simple, necessary actions
within the perfSONAR-PS framework.

=head1 DESCRIPTION

This module is a catch all for common methods (for now) in the perfSONAR-PS framework.  As such there
is no 'common thread' that each method shares.  This module IS NOT an object, and the methods
can be invoked directly (and sparingly).

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and
each method does not have the 'self knowledge' of variables that may travel
between functions.

=head1 API

The API of perfSONAR_PS::Common offers simple calls to common activities in the
perfSONAR-PS framework.
=cut

use strict;
use warnings;
use Exporter;
use IO::File;
use Time::HiRes qw( gettimeofday );
use Log::Log4perl qw(get_logger :nowarn);
use XML::LibXML;

our $VERSION = 0.06;
use base 'Exporter';
our @EXPORT = ('readXML','chainMetadata',
           'countRefs', 'genuid', 'extract', 'reMap', 'consultArchive',
            'find', 'findvalue', 'escapeString', 'unescapeString',
             'makeEnvelope', 'mapNamespaces', 'mergeConfig', 'resolveMetadataChain');


sub find($$$);
sub findvalue($$);
sub makeEnvelope($);
sub readXML($);
sub chainMetadata($);
sub metadataChaining($$);
sub getPath($);
sub elements($$$);
sub attributes($$);
sub exact($$);
sub countRefs($$$$$);
sub genuid();
sub extract($$);
sub mapNamespaces($$);
sub reMap($$$$);
sub consultArchive($$$$);
sub escapeString($);
sub unescapeString($);
sub convertISO($);
sub mergeConfig($$);
sub mergeHash($$$);
sub duplicateHash($$);
sub duplicateArray($$);


=head2 find($node, $query, $return_first)
    This function replicates the libxml "find" function. However, it formats
    the query to work around some oddities in the find implementation. It
    converts the xpath query to get rid of direct references like /nmwg:element
    and replaces them with /*[name()='nmwg:element"] which avoids spurious
    'undefined namespace' errors. It also wraps the find in an eval and returns
    'undef' if ->find throws an errors. If the $return_first is set to one, the
    function returns only the first node from the nodes found.
=cut
sub find($$$) {
    my ($node, $query, $return_first) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");
    my $res;

    $logger->debug("Query(pre-process): $query");
    $query =~ s/\/([a-zA-Z_][a-zA-Z0-9\.\-\_]+:[a-zA-Z_][a-zA-Z0-9\.\-\_]+)\[/\/*[name()='$1' and /g;
    $query =~ s/\/([a-zA-Z_][a-zA-Z0-9\.\-\_]+:[a-zA-Z_][a-zA-Z0-9\.\-\_]+)/\/*[name()='$1']/g;
    $query =~ s/^([a-zA-Z_][a-zA-Z0-9\.\-\_]+:[a-zA-Z_][a-zA-Z0-9\.\-\_]+)\[/*[name()='$1' and /g;
    $query =~ s/^([a-zA-Z_][a-zA-Z0-9\.\-\_]+:[a-zA-Z_][a-zA-Z0-9\.\-\_]+)/*[name()='$1']/g;
    $logger->debug("Query(post-process): $query");

    eval {
        $res = $node->find($query);
    };
    if ($@) {
        $logger->error("Error finding value($query): $@");
        return undef;
    }

    if (defined $return_first and $return_first == 1) {
        return $res->get_node(1);
    }

    return $res;
}

=head2 findvalue($node, $query)
    This function is analogous to the libxml "findvalue" function. However, it
    makes use of the 'find' function documented above. Unlike the libxml
    findvalue function, this function will only return the text contents of the
    first node found.
=cut
sub findvalue($$) {
    my ($node, $xpath) = @_;

    my $found_node;

    $found_node = find($node, $xpath, 1);

    return undef if (!defined $found_node);

    return $found_node->textContent;
}

=head2 makeEnvelope($content)
   Wraps the specified content in a soap envelope and returns it as a string.
=cut
sub makeEnvelope($) {
    my($content) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");
    my $string = "<SOAP-ENV:Envelope xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\"\n";
    $string .= "                   xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"\n";
    $string .= "                   xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n";
    $string .= "                   xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">\n";
    $string .= "  <SOAP-ENV:Header/>\n";
    $string .= "  <SOAP-ENV:Body>\n";
    $string .= $content;
    $string .= "  </SOAP-ENV:Body>\n";
    $string .= "</SOAP-ENV:Envelope>\n";
    return $string;
}

=head2 readXML($file)
    Reads the file specified in '$file' and returns the XML contents in string
    form.  The <xml> tag will be extracted from the final returned string.
    Function will warn on error, and return an empty string.
=cut
sub readXML($) {
    my ($file)  = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    if(defined $file and $file ne "") {
        my $XML = new IO::File("<".$file);
        if(defined $XML) {
            my $xmlstring = "";
            while (<$XML>) {
                if(!($_ =~ m/^<\?xml.*/)) {
                    $xmlstring .= $_;
                }
            }
            $XML->close();
            return $xmlstring;
        } else {
            $logger->error("Cannot open file \"".$file."\".");
        }
    } else {
        $logger->error("Missing argument.");
    }

    return "";
}

=head2 resolveMetadataChain($metadata, $dom)
  Given a metadata and a dom, this function will resolve the metadata chain and
  merge the specified metadata with all its parent elements.
=cut
sub resolveMetadataChain($$) {
    my ($metadata, $dom) = @_;

    if (!defined $metadata->getAttribute("metadataIdRef")) {
        return $metadata;
    }

    my %metadata = ();
    foreach my $md ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
        if ($md->getAttribute("id")) {
            $metadata{$md->getAttribute("id")} = $md;
        }
    }

    my $curr_md = $metadata;
    while($curr_md->getAttribute("metadataIdRef")) {
        if (!defined $metadata{$curr_md->getAttribute("metadataIdRef")}) {
            return undef;
        }

        $curr_md = $metadata{$curr_md->getAttribute("metadataIdRef")};

        metadataChaining($curr_md, $metadata);
    }

    return $metadata;
}

=head2 chainMetadata($dom)
    Given a dom of objects, this function will continuously loop through
    performing a 'chaining' operation to share values between metadata objects.
    An example would be:

  <nmwg:metadata id="1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="1">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
        <nmwgt:hostName>stout</nmwgt:hostName>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:eventType>
  </nmwg:metadata>

  <nmwg:metadata id="2" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" metadataIdRef="1">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="2">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifName>eth1</nmwgt:ifName>
        <nmwgt:ifIndex>3</nmwgt:ifIndex>
        <nmwgt:direction>in</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:eventType>
  </nmwg:metadata>

    Which would then become:

  <nmwg:metadata id="2">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="1">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
        <nmwgt:hostName>stout</nmwgt:hostName>
        <nmwgt:ifName>eth1</nmwgt:ifName>
        <nmwgt:ifIndex>3</nmwgt:ifIndex>
        <nmwgt:direction>in</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0/</nmwg:eventType>
  </nmwg:metadata>

    This chaining is useful for 'factoring out' large chunks of XML.
=cut

sub chainMetadata($) {
    my($dom) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");


    if(defined $dom and $dom ne "") {
        my %mdChains = ();

        my $changes = 1;
        while($changes) {
            $changes = 0;
            foreach my $md ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
                if($md->getAttribute("metadataIdRef")) {
                    if(!$mdChains{$md->getAttribute("metadataIdRef")}) {
                        $mdChains{$md->getAttribute("metadataIdRef")} = 0;
                    }
                    if($mdChains{$md->getAttribute("id")} != $mdChains{$md->getAttribute("metadataIdRef")}+1) {
                        $mdChains{$md->getAttribute("id")} = $mdChains{$md->getAttribute("metadataIdRef")}+1;
                        $changes = 1;
                    }
                }
            }
        }

        my @sorted = sort {$mdChains{$a} <=> $mdChains{$b}} keys %mdChains;
        for(my $x = 0; $x <= $#sorted; $x++) {
            $mdChains{$sorted[$x]} = 0;
            foreach my $md ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
                if($md->getAttribute("id") eq $sorted[$x]){
                    foreach my $md2 ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
                        if($md->getAttribute("metadataIdRef") and
                                $md2->getAttribute("id") eq $md->getAttribute("metadataIdRef")){
                            metadataChaining($md2, $md);
                            $md->removeAttribute("metadataIdRef");
                            last;
                        }
                    }
                    last;
                }
            }
        }
    } else {
        $logger->error("Missing argument.");
    }

    return $dom;
}

sub metadataChaining($$) {
    my($node, $original) = @_;
    if(!($node->getName eq "\#text")) {
        if($node->getName eq "nmwg:parameter") {
            exact($node, $original);
        } else {
            elements($node, $original, "");
            attributes($node, $original);
        }

        if($node->hasChildNodes()) {
            foreach my $c ($node->childNodes) {
                metadataChaining($c, $original);
            }
        }
    }

    return;
}

=head2 getPath($node)
    Cleans up the 'path' (XPath location) of a node by removing positional
    notation, and the root elements.  This path is then returned.  Note this
    function should not be called externally.
=cut 
sub getPath($) {
    my($node) = @_;
    my $path = "";

    if($node->nodePath() =~ m/nmwg:store/) {
        ($path = $node->nodePath()) =~ s/\/nmwg:store\/nmwg:metadata//;
        $path =~ s/\[\d+\]//g;
        $path =~ s/^\///g;
    } elsif($node->nodePath() =~ m/nmwg:message/) {
        ($path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
        $path =~ s/\[\d+\]//g;
        $path =~ s/^\///g;
    }

    return $path;
}

=head2 elements($node, $original, $extra)
    Given a node (and knowing what the original structure looks like) adds
    'missing' elements when needed.  Note this function should not be called
    externally.
=cut 
sub elements($$$) {
    my($node, $original, $extra) = @_;
    my $path = getPath($node);
    if($path) {
        if(!(find($original, $path.$extra, 1))) {
            my $name = $node->nodeName;
            my $path2 = $path;
            $path2 =~ s/\/$name$//;
            if(find($original, $path2, 1)) {
                find($original, $path2, 1)->addChild($node->cloneNode(1));
            } else {
                $original->addChild($node->cloneNode(1));
            }
        }
    }
    return;
}

=head2 attributes($node, $original)
    Given a node (and knowing what the original structure looks like) adds
    'missing' attributes.  Note this function should not be called externally.
=cut 
sub attributes($$) {
    my($node, $original) = @_;
    my $path = getPath($node);
    foreach my $attr ($node->attributes) {
        if($attr->isa('XML::LibXML::Attr')) {
            if($attr->getName ne "id") {
                if($path) {
                    if(!(find($original, $path."[@".$attr->getName."]", 1))) {
                        if(find($original, $path, 1)) {
                            find($original, $path, 1)->setAttribute($attr->getName, $attr->getValue);
                        }
                    }
                }
            }
        }
    }
    return;
}

=head2 exact($node, $original)
    Checks parameter nodes for 'exact' matches.  Note this function should not
    be called externally.
=cut 
sub exact($$) {
    my($node, $original) = @_;
    my $path = getPath($node);

    my $attrString = "";
    my $counter = 0;
    foreach my $attr ($node->attributes) {
        if($attr->isa('XML::LibXML::Attr')) {
            if($attr->getName ne "id") {
                if($counter == 0) {
                    $attrString = $attrString . "@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                } else {
                    $attrString = $attrString . " and @" . $attr->getName . "=\"" . $attr->getValue . "\"";
                }
                $counter++;
            }
        }
    }
    if($attrString) {
        $attrString = "[".$attrString."]";
    }
    elements($node, $original, $attrString);
    return;
}

=head2 countRefs($id, $dom, $uri, $element, $attr)
    Given a ID, and a series of 'struct' objects and a key 'value' to search on, this function
    will return a 'count' of the number of times the id was seen as a reference
    to the objects.  This is useful for eliminating 'dead' blocks that may not
    contain a trigger. The function will return -1 on error.
=cut 
sub countRefs($$$$$) {
    my($id, $dom, $uri, $element, $attr) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    if((defined $id and $id ne "") and
            (defined $dom and $dom ne "") and
            (defined $uri and $uri ne "") and
            (defined $element and $element ne "") and
            (defined $attr and $attr ne "")) {
        my $flag = 0;
        foreach my $d ($dom->getElementsByTagNameNS($uri, $element)) {
            if($id eq $d->getAttribute($attr)) {
                $flag++;
            }
        }
        return $flag;
    } else {
        $logger->error("Missing argument(s).");
    }
    $logger->debug("0 Refernces Found");
    return -1;
}

=head2 genuid()
    Generates a random number.
=cut
sub genuid() {
    my $r = int(rand(16777216))+1048576;
    return $r;
}

=head2 extract($node)
    Returns a 'value' from a xml element, either the value attribute or the
    text field.
=cut
sub extract($$) {
    my($node, $clean) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");
    if(defined $node and $node ne "") {
        if($node->getAttribute("value")) {
            return $node->getAttribute("value");
        } else {
            my $value = $node->textContent;
            if($clean) {
                $value =~ s/\s*//g;
            }
            if($value) {
                return $value;
            }
        }
    }
    return "";
}

=head2 mapNamespaces($node, \%namespaces)
    Fills in a uri -> prefix mapping of the namespaces.
=cut
sub mapNamespaces($$) {
    my ($node, $namespaces) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    my $uri = $node->namespaceURI();
    my $prefix = $node->prefix();
    if(defined $prefix and $prefix ne "" and $uri) {
        if(!defined $namespaces->{$uri}) {
            $namespaces->{$uri} = $prefix;
            $node->ownerDocument->getDocumentElement->setNamespace($uri, $prefix, 0);
        }
    } elsif ((!defined $prefix or $prefix eq "") and defined $uri) {
        if (defined $namespaces->{$uri}) {
            $node->setNamespace($uri, $namespaces->{$uri}, 1);
        }
    }
    if($node->hasChildNodes()) {
        foreach my $c ($node->childNodes) {
            if($node->nodeType != 3) {
                mapNamespaces($c, $namespaces);
            }
        }
    }
}

=head2 reMap(\%{$rns}, \%{$ns}, $dom_node)
    Re-map the nodes namespace prefixes to known prefixes (to not screw with
    the XPath statements that will occur later).
=cut
sub reMap($$$$) {
    my($requestNamespaces, $namespaces, $node, $set_owner_prefix) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    if($node->prefix and $node->namespaceURI()) {
        if(!$requestNamespaces->{$node->namespaceURI()}) {
            $requestNamespaces->{$node->namespaceURI()} = $node->prefix;
            if ($set_owner_prefix) {
                $node->ownerDocument->getDocumentElement->setNamespace($node->namespaceURI(), $node->prefix, 0);
            }
            $logger->debug("Setting namespace \"".$node->namespaceURI()."\" with prefix \"".$node->prefix."\".");
        }
        if(!($namespaces->{$node->prefix})) {
            foreach my $ns (keys %{$namespaces}) {
                if($namespaces->{$ns} eq $node->namespaceURI()) {
                    $node->setNamespace($namespaces->{$ns}, $ns, 1);
                    if ($set_owner_prefix) {
                        $node->ownerDocument->getDocumentElement->setNamespace($namespaces->{$ns}, $ns, 0);
                    }
                    $logger->debug("Re-mapping namespace \"".$namespaces->{$ns}."\" to prefix \"".$ns."\".");
                    last;
                }
            }
        }
    } elsif ((!defined $node->prefix or $node->prefix eq "") and defined $node->namespaceURI()) {
        if (defined $requestNamespaces->{$node->namespaceURI()}) {
            $node->setNamespace($node->namespaceURI(), $requestNamespaces->{$node->namespaceURI()}, 1);
        } else {
            foreach my $ns (keys %{$namespaces}) {
                if($namespaces->{$ns} eq $node->namespaceURI()) {
                    $node->setNamespace($namespaces->{$ns}, $ns, 1);
                    if ($set_owner_prefix) {
                        $node->ownerDocument->getDocumentElement->setNamespace($namespaces->{$ns}, $ns, 0);
                    }
                    $logger->debug("Re-mapping namespace \"".$namespaces->{$ns}."\" to prefix \"".$ns."\".");
                    $requestNamespaces->{$node->namespaceURI()} = $ns;
                    last;
                }
            }
        }
    }
    if($node->hasChildNodes()) {
        foreach my $c ($node->childNodes) {
            if($node->nodeType != 3) {
                $requestNamespaces = reMap($requestNamespaces, $namespaces, $c, $set_owner_prefix);
            }
        }
    }
    return $requestNamespaces;
}

=head2 consultArchive($host, $port, $endpoint, $request)
    This function can be used to easily consult a measurement archive. It's a
    thin wrapper around the sendReceive function in the perfSONAR_PS::Transport
    module.  You specify the host, port and endpoint for the MA you wish to
    consult and the request you wish to send. The function sends the request to
    the MA, parses the response and returns to you the LibXML element
    corresponding to the nmwg:message portion of the response. The return value
    an array of the form ($status, $res) where status is 0 means the function
    was able to send the request and get a properly formed response and -1 on
    failure. $res contains the LibXML element on success and an error message
    on failure.
=cut
sub consultArchive($$$$) {
    my ($host, $port, $endpoint, $request) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    # start a transport agent
    my $sender = new perfSONAR_PS::Transport($host, $port, $endpoint);

    my $envelope = makeEnvelope($request);
    my $error;
    my $start_time = time;
    my $response = $sender->sendReceive($envelope, "", \$error);
    my $end_time = time;

    $logger->debug("Time to make request: ".($end_time - $start_time));

    if ($error ne "") {
        my $msg = "Error while sending request to server: $error";
        $logger->error($msg);
        return (-1, $msg);
    }

    if (!defined $response or $response eq "") {
        my $msg = "No response received from status service";
        $logger->error($msg);
        return (-1, $msg);
    }

    my $doc;
    eval {
        my $parser = XML::LibXML->new();
        $doc = $parser->parse_string($response);
    };
    if ($@) {
        my $msg = "Couldn't parse response: $@";
        $logger->error($msg);
        return (-1, $msg);
    }

    my $nodeset = find($doc, "//nmwg:message", 0);
    if($nodeset->size <= 0) {
        my $msg = "Message element not found in response";
        $logger->error($msg);
        return (-1, $msg);
    } elsif($nodeset->size > 1) {
        my $msg = "Too many message elements found in response";
        $logger->error($msg);
        return (-1, $msg);
    }

    my $nmwg_msg = $nodeset->get_node(1);

    return (0, $nmwg_msg);
}

=head2 escapeString($string)
    This function does some basic XML character escaping. Replacing < with
    &lt;, & with &amp;, etc.
=cut
sub escapeString($) {
    my ($input) = @_;

    $input =~ s/&/&amp;/g;
    $input =~ s/</&lt;/g;
    $input =~ s/>/&gt;/g;
    $input =~ s/'/&apos;/g;
    $input =~ s/"/&quot;/g;

    return $input;
}

=head2 unescapeString($string)
    This function does some basic XML character escaping. Replacing &lt; with
    <, &amp; with &, etc.
=cut
sub unescapeString($) {
    my ($input) = @_;

    $input =~ s/&lt;/</g;
    $input =~ s/&gt;/>/g;
    $input =~ s/&apos;/'/g;
    $input =~ s/&quot;/"/g;
    $input =~ s/&amp;/&/g;

    return $input;
}

=head2 mergeConfig($base, $specific)
    Merges the configurations in $base and $specific.
=cut
sub mergeConfig($$) {
    my ($base, $specific) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");

    my %elements = (
            port => 1,
            endpoint => 1 );

    my $ret_config = mergeHash($base, $specific, \%elements);

    return $ret_config;
}

# mergeHash($base, $specific, $skip_elements)
#   Internal function that merges $base and $specific into a unified hash. The
#   elements from the $specific hash will be used whenever a collision occurs.
#   $skip_elements is a hash containing the set of keys whose values should be
#   ignored.
sub mergeHash($$$) {
	my ($base, $specific, $skip_elements) = @_;
	my $logger = get_logger("perfSONAR_PS::Common");

	my $new = duplicateHash($base, $skip_elements);

	foreach my $key (keys %{ $specific }) {
		if (defined $skip_elements->{$key}) {
			next;
		}

		if (ref $specific->{$key} eq "HASH") {
			if (!defined $new->{$key}) {
				$new->{$key} = duplicateHash($specific->{$key}, $skip_elements);
			} else {
				$new->{$key} = mergeHash($new->{$key}, $specific->{$key}, $skip_elements);
			}
		} else {
			$new->{$key} = $specific->{$key};
		}
	}

	return $new;
}

# duplicateArray($array, $skip_elements)
#   Internal function that duplicates the specified hash. It ignores hash
#   elements with the keys specified in the $skip_elements.
sub duplicateHash($$) {
	my ($hash, $skip_elements) = @_;
	my $logger = get_logger("perfSONAR_PS::Common");

	my %new = ();

	foreach my $key (keys %{ $hash }) {
		if (defined $skip_elements->{$key}) {
			next;
		}

		if (ref $hash->{$key} eq "HASH") {
			$new{$key} = duplicateHash($hash->{$key}, $skip_elements);
		} elsif (ref $hash->{$key} eq "ARRAY") {
			$new{$key} = duplicateArray($hash->{$key}, $skip_elements);
		} else {
			$new{$key} = $hash->{$key};
		}
	}

	return \%new;
}

# duplicateArray($array, $skip_elements)
#   Internal function that duplicates the specified array. When duplicating
#   hash elements in the array, the elements specified in skip_elements will be
#   skipped.
sub duplicateArray($$) {
	my ($array, $skip_elements) = @_;

	my @old_array = @{ $array };
	my @new = ();
	for(my $i = 0; $i <= $#old_array; $i++) {
		if (ref $old_array[$i] eq "ARRAY") {
			$new[$i] = duplicateArray($old_array[$i], $skip_elements);
		} elsif (ref $old_array[$i] eq "HASH") {
			$new[$i] = duplicateHash($old_array[$i], $skip_elements);
		} else {
			$new[$i] = $old_array[$i];
		}
	}

	return \@new;
}

=head2 convertISO($iso)
    Given the time in ISO format, conver to 'unix' epoch seconds.
=cut
sub convertISO($) {
    my($iso) = @_;
    my $logger = get_logger("perfSONAR_PS::Common");
    if(defined $iso and $iso ne "") {
        my($first, $second) = split(/T/, $iso);
        my($year, $mon, $day) = split(/-/, $first);
        my($hour, $min, $sec) = split(/:/, $second);
        my $frac = "";
        ($sec, $frac) = split(/\./, $sec);
        my $zone = $frac;
        $frac =~ s/\D+//g;
        $zone =~ s/\d+//g;
        if($zone eq "Z") {
            return timegm($sec,$min,$hour,$day,$mon-1,$year-1900);
        }
        else {
            return timelocal($sec,$min,$hour,$day,$mon-1,$year-1900);
        }
    } else {
        $logger->error("Missing argument.");
        return "N/A";
    }
}

1;


__END__
=head1 SEE ALSO

L<Exporter>, L<IO::File>, L<XML::XPath>, L<Time::HiRes>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown <aaron@internet2.edu>, Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4

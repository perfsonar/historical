package perfSONAR_PS::MA::Topology::ID;

use Exporter;

@ISA  = ('Exporter');
@EXPORT = ('idConstruct', 'idIsFQ', 'idAddLevel', 'idRemoveLevel', 'idBaseLevel', 'idEncode', 'idDecode');

sub idConstruct {
	my ($domain, $node, $interface, $link) = @_;

	my $id = "";

	return $id if (!defined $domain);

	$id .= "urn:nmtopo:".idEncode($domain);

	return $id if (!defined $node);

	$id .= ":".idEncode($node);

	return $id if (!defined $interface);

	$id .= ":".idEncode($interface);

	return $id if (!defined $link);

	$id .= ":".idEncode($link);

	return $id;
}

sub idIsFQ($) {
	my ($id) = @_;

	return 1 if ($id =~ /^urn:nmtopo:(.*)$/);

	return 0;
}

sub idAddLevel($$) {
	my ($id, $new_level) = @_;

	$new_level = idEncode($new_level);

	if ($id =~ /urn:nmtopo:$/) {
		$id .= $new_level;
	} else {
		$id .= ":".$new_level;
	}

	return $id;
}

sub idRemoveLevel($) {
	my ($id) = @_;

	if ($id =~ /(urn:nmtopo.*):[^:]+$/) {
		return $1;
	} else {
		return $id;
	}
}

sub idBaseLevel($) {
	my ($id) = @_;

	my $ret_id;

	if ($id =~ /urn:nmtopo.*:([^:]+)$/) {
		$ret_id = $1;
	} else {
		$ret_id = $id;
	}

	return idDecode($ret_id);
}

sub idEncode($) {
	my ($id) = @_;

	$id =~ s/:/%3A/g;
	$id =~ s/%/%25/g;
	$id =~ s/#/%23/g;
	$id =~ s/\//%2F/g;
	$id =~ s/\?/%3F/g;

	return $id;
}

sub idDecode($) {
	my ($id) = @_;

	$id =~ s/%3A/:/g;
	$id =~ s/%25/%/g;
	$id =~ s/%23/#/g;
	$id =~ s/%2F/\//g;
	$id =~ s/%3F/?/g;

	return $id;
}

1;

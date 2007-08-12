package perfSONAR_PS::MA::Topology::ID;

use Exporter;

@ISA  = ('Exporter');
@EXPORT = ('idConstruct', 'idIsFQ', 'idAddLevel', 'idRemoveLevel', 'idBaseLevel', 'idEncode', 'idDecode', 'idSplit');

sub idConstruct {
	my ($domain, $node, $interface, $link) = @_;

	my $id = "";

	return $id if (!defined $domain);

	$id .= "urn:ogf:network:".idEncode($domain);

	return $id if (!defined $node);

	$id .= ":".idEncode($node);

	return $id if (!defined $interface);

	$id .= ":".idEncode($interface);

	return $id if (!defined $link);

	$id .= ":".idEncode($link);

	return $id;
}

sub idIsFQ($$) {
	my ($id, $type) = @_;

	return 0 if (!($id =~ /^urn:ogf:network:(.*)$/));

	my @fields = split(':', $id);

	print "ID: $id FIELDS: $#fields\n";

	if ($type eq "domain") {
		return 1 if ($#fields == 3);
		return -1;
	}

	if ($type eq "node") {
		return 1 if ($#fields == 4);
		return -1;
	}

	if ($type eq "port") {
		return 1 if ($#fields == 5);
		return -1;
	}

	if ($type eq "link") {
		return 1 if ($#fields == 6);
		return -1;
	}

	return 1;
}

sub idAddLevel($$) {
	my ($id, $new_level) = @_;

	$new_level = idEncode($new_level);

	if ($id =~ /urn:ogf:network:$/) {
		$id .= $new_level;
	} else {
		$id .= ":".$new_level;
	}

	return $id;
}

sub idRemoveLevel($) {
	my ($id) = @_;

	if ($id =~ /(urn:ogf:network.*):[^:]+$/) {
		return $1;
	} else {
		return $id;
	}
}

sub idBaseLevel($) {
	my ($id) = @_;

	my $ret_id;

	if ($id =~ /urn:ogf:network.*:([^:]+)$/) {
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

sub idSplit($$) {
	my ($id, $fq) = @_;

	if (idIsFQ($id, "") == 0) {
		my $msg = "ID \"$id\" is not fully qualified";
		return (-1, $msg);
	}

	my @fields = split(':', $id);

	if ($#fields > 6 or $#fields < 3) {
		my $msg = "ID \"$id\" has an invalid number of fields: $#fields";
		return (-1, $msg);
	}

	my $domain_id = idDecode($fields[3]) if defined $fields[3];
	my $node_id = idDecode($fields[4]) if defined $fields[4];
	my $port_id = idDecode($fields[5]) if defined $fields[5];
	my $link_id = idDecode($fields[6]) if defined $fields[6];

	if ($fq) {
		$domain_id = idConstruct($domain_id);
		$node_id = idConstruct($domain_id, $node_id) if defined $node_id;
		$port_id = idConstruct($domain_id, $node_id, $port_id) if defined $port_id;
		$link_id = idConstruct($domain_id, $node_id, $port_id, $link_id) if defined $link_id;
	}

	return (0, $domain_id, $node_id, $port_id, $link_id);
}

1;

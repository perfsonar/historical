package perfSONAR_PS::MA::Topology::ID;

use Exporter;

@ISA  = ('Exporter');
@EXPORT = ('idConstruct', 'idIsFQ', 'idAddLevel', 'idRemoveLevel', 'idBaseLevel', 'idEncode', 'idDecode', 'idSplit');

sub idConstruct;
sub idIsFQ($$);
sub idAddLevel($$);
sub idRemoveLevel($);
sub idBaseLevel($);
sub idEncode($);
sub idDecode($);
sub idSplit($$);

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
		$link_id = idConstruct($domain_id, $node_id, $port_id, $link_id) if defined $link_id;
		$port_id = idConstruct($domain_id, $node_id, $port_id) if defined $port_id;
		$node_id = idConstruct($domain_id, $node_id) if defined $node_id;
		$domain_id = idConstruct($domain_id);
	}

	return (0, $domain_id, $node_id, $port_id, $link_id);
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::Topology::ID - A module that provides various utility functions for Topology IDs.

=head1 DESCRIPTION

This module contains a set of utility functions that are used to interact with
Topology IDs.

=head1 SYNOPSIS

=head1 DETAILS

=head1 API

=head2 idConstruct($domain_id, $node_id, $port_id, $link_id)

	Constructs an a fully-qualified id based on the specified elements. The
	only required element is "$domain_id", all others are optional.

=head2 idIsFQ($id, $type)

	Checks if the specified ID is a fully-qualified ID of the specified
	type. If it is not a fully-qualified id, the function returns 0. If it
	is an incorrect fully-qualified id(e.g. too many elements), it returns
	-1. If it is a correctly specified fully-qualified id, it returns 1.

=head2 idAddLevel($id, $new_level)

	Takes a fully-qualified id and adds a new level onto it.

=head2 idRemoveLevel($id)

	Takes a fully-qualified id and returns the parent level for the id.

=head2 idBaseLevel($id)

	Returns the base level of the specified id.

	e.g. urn:ogf:network:hopi:losa would return 'losa'

=head2 idEncode($element)

	Performs any necessary encoding of the specified element for inclusion
	in a fully-qualified id.

=head2 idDecode($element)

	Decodes the specified element from a fully-qualified id.

=head2 idSplit($id, $fq)

	Splits the specified fully-qualified id into its component elements. If
	$fq is 1, the returns components are all fully-qualified. If the id is
	incorrect(e.g. has too many or too few elements), it returns -1 for its
	status otherwise, it returns 0.

=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, E<lt>aaron@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

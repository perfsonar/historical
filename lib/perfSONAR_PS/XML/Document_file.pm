package perfSONAR_PS::XML::Document_string;

use fields 'OPEN_TAGS', 'DEFINED_PREFIXES', 'FILE', 'FILENAME';

use strict;
use File::Temp qw(tempfile);
use Log::Log4perl qw(get_logger :nowarn);
use Params::Validate qw(:all);

our $VERSION = 0.06;

my $pretty_print = 0;

sub new($) {
	my ($package) = @_;

	my $self = fields::new($package);

    my($fileHandle, $fileName) = tempfile();

    $self->{FILE} = $fileHandle;
    $self->{FILENAME} = $fileName;
	$self->{OPEN_TAGS} = ();
	$self->{DEFINED_PREFIXES} = ();

	return $self;
}

sub getNormalizedURI($) {
	my ($uri) = @_;

	# trim whitespace
	$uri =~ s/^\s+//;
	$uri =~ s/\s+$//;

	if ($uri =~ /[^\/]$/) {
		$uri .= "/";
	}

	return $uri;
}

sub startElement {
    my $self = shift;
	my $args = validate(@_, 
			{
				prefix => { type => SCALAR, regex => qr/^[a-z0-9]/ },
				namespace => { type => SCALAR, regex => qr/^http/ },
				tag => { type => SCALAR, regex => qr/^[a-z0-9]/ },
				attributes => { type => HASHREF | UNDEF, optional => 1 },
				extra_namespaces => { type => HASHREF | UNDEF, optional => 1 },
				content => { type => SCALAR | UNDEF, optional => 1}
			});

	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	my $prefix = $args->{"prefix"};
	my $namespace = $args->{"namespace"};
	my $tag = $args->{"tag"};
	my $attributes = $args->{"attributes"};
	my $extra_namespaces = $args->{"extra_namespaces"};
	my $content = $args->{"content"};

	$logger->debug("Starting tag: $tag");

	$namespace = getNormalizedURI($namespace);

	my %namespaces = ();
	$namespaces{$prefix} = $namespace;

	if (defined $extra_namespaces and $extra_namespaces ne "") {
		foreach $prefix (keys %{ $extra_namespaces }) {
			my $new_namespace = getNormalizedURI($extra_namespaces->{$prefix});

			if (defined $namespaces{$prefix} and $namespaces{$prefix} ne $new_namespace) {
				$logger->error("Tried to redefine prefix $prefix from ".$namespaces{$prefix}." to ".$new_namespace);
				return -1;
			}

			$namespaces{$prefix} = $new_namespace;
		}
	}

	my %node_info = ();
	$node_info{"tag"} = $tag;
	$node_info{"prefix"} = $prefix;
	$node_info{"namespace"} = $namespace;
	$node_info{"defined_prefixes"} = ();

	if ($pretty_print) {
		foreach my $node (@{ $self->{OPEN_TAGS} }) {
			print { $self->{FILE} } "  ";
		}
	}

	print { $self->{FILE} } "<$prefix:$tag";

	foreach my $prefix (keys %namespaces) {
		my $require_defintion = 0;

		if (!defined $self->{DEFINED_PREFIXES}->{$prefix}) {
			# it's the first time we've seen a prefix like this
			$self->{DEFINED_PREFIXES}->{$prefix} = ();
			push @{ $self->{DEFINED_PREFIXES}->{$prefix} }, $namespaces{$prefix};
			$require_defintion = 1;
		} else {
			my @namespaces = @{ $self->{DEFINED_PREFIXES}->{$prefix} };

			# if it's a new namespace for an existing prefix, write the definition (though we should probably complain)
			if ($#namespaces == -1 or $namespaces[$#namespaces] ne $namespace) {
				push @{ $self->{DEFINED_PREFIXES}->{$prefix} }, $namespaces{$prefix};

				$require_defintion = 1;
			}
		}

		if ($require_defintion) {
			push @{ $node_info{"defined_prefixes"} }, $prefix;
			print { $self->{FILE} } " xmlns:$prefix=\"".$namespaces{$prefix}."\"";
		}
	}

	if (defined $attributes) {
		for my $attr (keys %{ $attributes }) {
			print { $self->{FILE} } " ".$attr."=\"".$attributes->{$attr}."\"";
		}
	}

	print { $self->{FILE} } ">";

	if ($pretty_print) {
		print { $self->{FILE} } "\n";
	}

	if (defined $content and $content ne "") {
		print { $self->{FILE} }  $content;
		print { $self->{FILE} } "\n" if ($pretty_print);
	}


	push @{ $self->{OPEN_TAGS} }, \%node_info;

	return 0;
}

sub createElement {
	my $self = shift;
	my $args = validate(@_, 
			{
				prefix => { type => SCALAR, regex => qr/^[a-z0-9]/ },
				namespace => { type => SCALAR, regex => qr/^http/ },
				tag => { type => SCALAR, regex => qr/^[a-z0-9]/ },
				attributes => { type => HASHREF | UNDEF, optional => 1 },
				extra_namespaces => { type => HASHREF | UNDEF, optional => 1 },
				content => { type => SCALAR | UNDEF, optional => 1}
			});

	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	my $prefix = $args->{"prefix"};
	my $namespace = $args->{"namespace"};
	my $tag = $args->{"tag"};
	my $attributes = $args->{"attributes"};
	my $extra_namespaces = $args->{"extra_namespaces"};
	my $content = $args->{"content"};

	$namespace = getNormalizedURI($namespace);

	my %namespaces = ();
	$namespaces{$prefix} = $namespace;

	if (defined $extra_namespaces and $extra_namespaces ne "") {
		foreach $prefix (keys %{ $extra_namespaces }) {
			my $new_namespace = getNormalizedURI($extra_namespaces->{$prefix});

			if (defined $namespaces{$prefix} and $namespaces{$prefix} ne $new_namespace) {
				$logger->error("Tried to redefine prefix $prefix from ".$namespaces{$prefix}." to ".$new_namespace);
				return -1;
			}

			$namespaces{$prefix} = $new_namespace;
		}
	}

	if ($pretty_print) {
		foreach my $node (@{ $self->{OPEN_TAGS} }) {
			print { $self->{FILE} } "  ";
		}
	}

	print { $self->{FILE} } "<$prefix:$tag";

	foreach my $prefix (keys %namespaces) {
		my $require_defintion = 0;

		if (!defined $self->{DEFINED_PREFIXES}->{$prefix}) {
			# it's the first time we've seen a prefix like this
			$self->{DEFINED_PREFIXES}->{$prefix} = ();
			$require_defintion = 1;
		} else {
			my @namespaces = @{ $self->{DEFINED_PREFIXES}->{$prefix} };

			# if it's a new namespace for an existing prefix, write the definition (though we should probably complain)
			if ($#namespaces == -1 or $namespaces[$#namespaces] ne $namespace) {
				$require_defintion = 1;
			}
		}

		if ($require_defintion) {
			print { $self->{FILE} } " xmlns:$prefix=\"".$namespaces{$prefix}."\"";
		}
	}

	if (defined $attributes) {
		for my $attr (keys %{ $attributes }) {
			print { $self->{FILE} } " ".$attr."=\"".$attributes->{$attr}."\"";
		}
	}

	if (!defined $content or $content eq "") {
		print { $self->{FILE} } " />";
	} else {
		print { $self->{FILE} } ">";

		if ($pretty_print) {
			print { $self->{FILE} } "\n" if ($content =~ /\n/);
		}

		print { $self->{FILE} }  $content;

		if ($pretty_print) {
			if ($content =~ /\n/) {
				print { $self->{FILE} } "\n";
				foreach my $node (@{ $self->{OPEN_TAGS} }) {
					print { $self->{FILE} } "  ";
				}
			}
		}

		print { $self->{FILE} } "</".$prefix.":".$tag.">";
	}

	if ($pretty_print) {
		print { $self->{FILE} } "\n";
	}

	return 0;
}

sub endElement($$) {
	my ($self, $tag) = @_;
	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	$logger->debug("Ending tag: $tag");

	my @tags = @{ $self->{OPEN_TAGS} };

    if ($#tags == -1) {
        $logger->error("Tried to close tag $tag but no current open tags");
		return -1;
	} elsif ($tags[$#tags]->{"tag"} ne $tag) {
        $logger->error("Tried to close tag $tag, but current open tag is \"".$tags[$#tags]->{"tag"}."\n");
		return -1;
	}

	foreach my $prefix (@{ $tags[$#tags]->{"defined_prefixes"} }) {
		pop @{ $self->{DEFINED_PREFIXES}->{$prefix} };
	}

	pop @{ $self->{OPEN_TAGS} };

	if ($pretty_print) {
		foreach my $node (@{ $self->{OPEN_TAGS} }) {
			print { $self->{FILE} } "  ";
		}
	}

	print { $self->{FILE} } "</".$tags[$#tags]->{"prefix"}.":".$tag.">";

	if ($pretty_print) {
		print { $self->{FILE} } "\n";
	}

	return 0;
}

sub addExistingXMLElement($$) {
	my ($self, $element) = @_;
	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	print { $self->{FILE} }  $element->toString();

	return 0;
}

sub addOpaque($$) {
	my ($self, $data) = @_;
	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	print { $self->{FILE} }  $data;

	return 0;
}

sub getValue($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::XML::Document_string");

	if (defined $self->{OPEN_TAGS}) {
		my @open_tags = @{ $self->{OPEN_TAGS} };

		if (scalar(@open_tags) != 0) {
			my $msg = "Open tags still exist: ";

			for(my $x = $#open_tags; $x >= 0; $x--) {
				$msg .= " -> ".$open_tags[$x];
			}

			$logger->warn($msg);
		}
	}

    my $value;
    seek($self->{FILE}, 0, 0);
    $value = do { local( $/ ); my $file = $self->{FILE}; <$file> };
    seek($self->{FILE}, 0, 2);

	$logger->debug("Construction Results: ".$value);

	return $value;
}

sub DESTROY {
    my $self = shift;

    unlink($self->{FILENAME});

    $self->SUPER::DESTROY  if $self->can("SUPER::DESTROY");
}

1;

# vim: expandtab shiftwidth=4 tabstop=4

#!/usr/bin/perl

my %files = ();
open(MANIFEST, "MANIFEST") or die("Couldn't open MANIFEST file");
while(<MANIFEST>) {
	chomp;
	$files{$_} = 1;
}
close(MANIFEST);

my %dependencies = ();
my %checked = ();

my $files_left = 1;

while ($files_left) {
	foreach my $file (keys %files) {
		$checked{$file} = 1;

		my $type = `file $file`;

		next unless ($file =~ /\.pm$/ or $file =~ /\.pl$/ or $type =~ /Perl/ or $type =~ /perl/);

		open(DEPENDS, "-|", "grep -e '^use .*;' -e 'load [a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*;' $file");
		while(<DEPENDS>) {
			my $module;

			if (/use ([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)/) {
				$module = $1;
			} elsif (/load ([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)/) {
				$module = $2;
			}

			next if (not $module);

			if ($module =~ /^perfSONAR_PS/ or $module =~ /^IEPM/) {
				my $module_name = "lib/".$module.".pm";
				$module_name =~ s/::/\//g;
				$files{$module_name} = 1;
			} else {
				$dependencies{$module} = 1;
			}
		}
		close(DEPENDS);
	}

	$files_left = 0;
	foreach my $file (keys %files) {
		if (not $checked{$file}) {
			$files_left = 1;
		}
	}
}

open(MANIFEST, ">MANIFEST");
foreach my $file (sort keys %files) {
	print MANIFEST $file."\n";
}
close(MANIFEST);

open(DEPENDS, ">dependencies");
foreach my $depend (sort keys %dependencies) {
	print DEPENDS $depend."\n";
}
close(DEPENDS);

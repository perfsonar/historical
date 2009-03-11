#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;

# This is the path relative to the module's directory where the trunk "lib" is located.
my $PATH_TO_PSLIB = "../Shared/lib";

# The module rules listed here allow you to either replace a found dependency
# with a new set of dependencies or append more dependencies when a given one
# is seen. e.g. When you see DBI, auto-include SQLite, for example.
my %module_rules =  (
                            "strict" => { rule => "ignore" },
                            "fields" => { rule => "ignore" },
                            "Error::Simple" => { rule => "replace", new_modules => [ "Error" ] },
                    );


# load the files in the MANIFEST into a hash
my %files = ();
open(MANIFEST, "MANIFEST") or die("Couldn't open MANIFEST file");
while(<MANIFEST>) {
    chomp;
    $files{$_} = 1;
}
close(MANIFEST);

if (open(IGNORED_MODULE, "modules.rules")) {
	my $line = 1;
	while(<IGNORED_MODULE>) {
		next if (/^\S*#/);

		chomp;
		my ($module, $rule, $remainder) = split(',', $_, 3);

		if ($rule ne "ignore" and $rule ne "replace" and $rule ne "add") {
			print "Error: invalid rule on line $line\n";
			next;
		}

		my %rule = ();
		
		$rule{"rule"} = $rule;

		if ($rule eq "replace" or $rule eq "add") {
			my @new_modules = split(",", $remainder);
			$rule{"new_modules"} = \@new_modules;
		}

		$module_rules{$module} = \%rule;
		$line++;
	}
}

my %dependencies = ();
my %checked = ();

my $files_left = 1;

while ($files_left) {
    foreach my $file (keys %files) {
        $checked{$file} = 1;

        my $type = `file $file`;

		# Skip non-Perl files
        next unless ($file =~ /\.pm$/ or $file =~ /\.pl$/ or $type =~ /Perl/ or $type =~ /perl/ or $file =~ /\.cgi/);

		if ($file =~ /\.pm$/ and not -f $file) {
			# auto-link in the library if it's one of ours

			my $orig_path = $PATH_TO_PSLIB.$file;
			$orig_path =~ s/liblib/lib/g;

			if (not -f $orig_path) {
				print "Warning: can't find file $file in $orig_path\n";
				next;
			}

			my $dir_name = dirname($file);
			my $cwd = "";
			foreach my $dir (split("/", $dir_name)) {
				next if ($dir eq "");

				my $new_dir;
				$cwd .= "/" if ($cwd);
				$cwd .= $dir;

				if (! -d $cwd) {
					mkdir($cwd);
				}

				$orig_path = "../".$orig_path;
			}
			system("ln -sf $orig_path $file");
		}

        open(DEPENDS, "-|", "grep -e '^use .*;' -e 'load [a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*;' $file");
        while(<DEPENDS>) {
            my $module;

            if (/use base *['"]([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)['"]/) {
                $module = $1;
				$dependencies{"base"} = 1;
            } elsif (/use *aliased *['"]([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)['"]/) {
                $module = $1;
				$dependencies{"aliased"} = 1;
            } elsif (/use *([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)/) {
                $module = $1;
            } elsif (/load *([a-z_A-Z0-9]*(::[a-z_A-Z0-9]*)*)/) {
				print "Load Module: $1 -- $2\n";
                $module = $1;
            }

            next unless ($module);

			my @modules = ();
			if (not $module_rules{$module}) {
				push @modules, $module;
			} else {
				if ($module_rules{$module}->{"rule"} eq "ignore") {
					next;
				}

				if ($module_rules{$module}->{"rule"} eq "add") {
					push @modules, $module;
				}

				if ($module_rules{$module}->{"new_modules"}) {
					foreach my $new_module (@{ $module_rules{$module}->{"new_modules"} }) {
						push @modules, $new_module;
					}
				}
			}

			foreach my $module (@modules) {
				# auto-link in the library if it's one of ours
				if ($module =~ /^perfSONAR_PS/ or $module =~ /^IEPM/ or $module =~ /^OWP/) {
					my $module_path = "lib/".$module.".pm";
					$module_path =~ s/::/\//g;
					$files{$module_path} = 1;
					my $dir_name = dirname($module_path);
					my $cwd = "";
					my $link_path = $PATH_TO_PSLIB;
					foreach my $dir (split("/", $dir_name)) {
						next if ($dir eq "");

						my $new_dir;
						$cwd .= "/" if ($cwd);
						$cwd .= $dir;

						if (! -d $cwd) {
							mkdir($cwd);
						}

						$link_path = "../".$link_path;
					}
					$link_path .= "/".$module.".pm";
					$link_path =~ s/::/\//g;
					symlink($link_path, $module_path);
				} else {
					$dependencies{$module} = 1;
				}
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

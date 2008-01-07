#!/usr/bin/perl
#
# cpanspec - Generate a spec file for a CPAN module
#
# Copyright (C) 2004-2005 Steven Pritchard <steve@kspei.com>
# This program is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# $Id: cpanspec,v 1.59 2005/09/20 15:07:38 steve Exp $

####
#
# TODO:
#
#   * FIXME - The script should make a pass through README to look for a
#             line that matches /^[^[:alnum:]]*DESCRIPTION[^[:alnum:]]*$/i
#             and use the first paragraph after that, if it exists.
#
#   * It might be a good idea to try to render %description as POD.
#
#   * Add code to get the path to the source from 02packages.details.txt.gz.
#
#   * Planned features (as of 2005-09-19):
#
#     - Find and download dependencies automatically (like CPAN::Unwind).
#     - Download from CPAN automatically when executed as "cpanspec Foo::Bar".
#       + DONE!
#       + Add --download-only or something similar to replace cpanget.
#
# KNOWN BUGS:
#
#   * This script is known to fail on the following:
#
#       - Cache::Cache 1.02 (Tries to do detection magic in Makefile.PL.)
#
####

=head1 NAME

cpanspec - Generate a spec file for a CPAN module

=head1 SYNOPSIS

cpanspec [options] [file [...]]

 Options:
   --help       -h      Help message
   --old        -o      Be more compatible with old RHL/FC releases
   --noprefix   -n      Don't add perl- prefix to package name
   --force      -f      Force overwriting existing spec
   --packager   -p      Name and email address of packager (for changelog)
   --release    -r      Release of package (defaults to 1)
   --disttag    -d      Disttag (defaults to %{?dist})
   --srpm       -s      Build a source rpm
   --build      -b      Build source and binary rpms
   --cpan       -c      CPAN mirror URL
   --verbose    -v      Be more verbose

=head1 DESCRIPTION

B<cpanspec> will generate a spec file to build a rpm from a CPAN-style
Perl module distribution.

=head1 OPTIONS

=over 4

=item B<-h>, B<--help>

Print a brief help message and exit.

=item B<-o>, B<--old>

Be more compatible with old RHL/FC releases.  With this option enabled,
the generated spec file

=over 4

=item *

Defines perl_vendorlib or perl_vendorarch.

=item *

Includes explicit dependencies for core Perl modules.

=item *

Uses C<%check || :> instead of just C<%check>.

=back

=item B<-n>, B<--noprefix>

Don't add I<perl-> prefix to the name of the package.  This is useful
for perl-based applications (such as this one), so that the name of
the rpm is simply B<cpanspec> instead of B<perl-cpanspec>.

=item B<-f>, B<--force>

Force overwriting an existing spec file.  Normally B<cpanspec> will
refuse to overwrite an existing spec file for safety.  This option
removes that safety check.  Please use with caution.

=item B<-p>, B<--packager>

The name and email address of the packager.  Overrides the C<%packager>
macro in C<~/.rpmmacros>.

=item B<-r>, B<--release>

The release number of the package.  Defaults to 1.

=item B<-d>, B<--disttag>

Disttag (a string to append to the release number), used to
differentiate builds for various releases.  Defaults to the
semi-standard (for Fedora Extras) string C<%{?dist}>.

=item B<-s>, B<--srpm>

Build a source rpm from the generated spec file.

=item B<-b>, B<--build>

Build source and binary rpms from the generated spec file.
B<Please be aware that this is likely to fail!>  Even if it succeeds,
the generated rpm will almost certainly need some work to make
rpmlint happy.

=item B<-c>, B<--cpan>

The URL to a CPAN mirror.  If not specified with this option or the
B<CPAN> environment variable, defaults to L<http://www.cpan.org/>.

=item B<-v>, B<--verbose>

Be more verbose.

=back

=head1 AUTHOR

Steven Pritchard <steve@kspei.com>

=head1 SEE ALSO

L<perl(1)>, L<cpan2rpm(1)>, L<cpanflute2(1)>

=cut

use strict;
use warnings;

use FileHandle;
use Archive::Tar;
use Archive::Zip qw(:ERROR_CODES);
use POSIX;
use Text::Autoformat;
use YAML qw(Load);
use Module::CoreList;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use LWP::UserAgent;
use Parse::CPAN::Packages;
# Apparently gets pulled in by another module.
#use Cwd;

our %opt;

our $help=0;
our $compat=0;
our $noprefix=0;
our $force=0;
our $packager;
our $release=1;
our $disttag='%{?dist}';
our $buildsrpm=0;
our $buildrpm=0;
our $verbose=0;
our $include_bin=0;
our $bin_man=0;
our $cpan=$ENV{'CPAN'} || "http://www.cpan.org/";

our $home=$ENV{'HOME'} || (getpwuid($<))[7];
die "Can't locate home directory.  Please define \$HOME.\n"
    if (!defined($home));

our $pkgdetails="$home/.cpan/sources/modules/02packages.details.txt.gz";
our $updated=0;

our $packages;

sub verbose(@) {
    print STDERR @_, "\n" if ($verbose);
}

sub fetch($$) {
    my ($url, $file)=@_;
    my @locations=();

    verbose("Fetching $file from $url...");

    my $ua=LWP::UserAgent->new('env_proxy' => 1)
        or die "LWP::UserAgent->new() failed: $!\n";

    my $request;
    LOOP: $request=HTTP::Request->new('GET' => $url)
        or die "HTTP::Request->new() failed: $!\n";

    my @buf=stat($file);
    $request->if_modified_since($buf[9]) if (@buf);

    # FIXME - Probably should do $ua->request() here and skip loop detection.
    my $response=$ua->simple_request($request)
        or die "LWP::UserAgent->simple_request() failed: $!\n";

    push(@locations, $url);
    if ($response->code eq "301" or $response->code eq "302") {
        $url=$response->header('Location');
        die "Redirect loop detected! " . join("\n ", @locations, $url) . "\n"
            if (grep { $url eq $_ } @locations);
        goto LOOP;
    }

    if ($response->is_success) {
        my $fh=new FileHandle ">$file";
        print $fh $response->content;
        $fh->close();

        my $last_modified=$response->last_modified;
        utime(time, $last_modified, $file) if ($last_modified);
    } elsif ($response->code eq "304") {
        verbose("$file is up to date.");
    } else {
        die "Failed to get $url: " . $response->status_line . "\n";
    }
}

sub mkdir_p($) {
    my $dir=shift;

    my @path=split '/', $dir;

    for (my $n=0;$n<@path;$n++) {
        my $partial="/" . join("/", @path[0..$n]);
        if (!-d $partial) {
            verbose("mkdir($partial)");
            mkdir $partial or die "mkdir($partial) failed: $!\n";
        }
    }
}

sub update_packages() {
    return 1 if ($updated);

    verbose("Updating $pkgdetails...");

    mkdir_p(dirname($pkgdetails)) if (!-d dirname($pkgdetails));

    fetch("$cpan/modules/" . basename($pkgdetails), $pkgdetails);

    $updated=1;
}

sub build_rpm($) {
    my $spec=shift;
    my $dir=getcwd();

    my $rpm=(-x "/usr/bin/rpmbuild" ? "/usr/bin/rpmbuild" : "/usr/bin/rpm");

    verbose("Building " . ($buildrpm ? "rpms" : "source rpm") . " from $spec");

    # From Fedora Extras Makefile.common.
    if (system($rpm, "--define", "_sourcedir $dir",
                     "--define", "_builddir $dir",
                     "--define", "_srcrpmdir $dir",
                     "--define", "_rpmdir $dir",
                     "--nodeps", ($buildrpm ? "-ba" : "-bs"), $spec) != 0) {
        if ($? == -1) {
            die "Failed to execute $rpm: $!\n";
        } elsif (WIFSIGNALED($?)) {
            die "$rpm died with signal " . WTERMSIG($?)
                . (($? & 128) ? ", core dumped\n" : "\n");
        } else {
            die "$rpm exited with value " . WEXITSTATUS($?) . "\n";
        }
    }
}

sub list_files($$) {
    my $archive=$_[0];
    my $type=$_[1];

    if ($type eq 'tar') {
        return $archive->list_files();
    } elsif ($type eq 'zip') {
        return map { $_->fileName(); } $archive->members();
    }
}

sub extract($$$) {
    my $archive=$_[0];
    my $type=$_[1];
    my $filename=$_[2];

    if ($type eq 'tar') {
        return $archive->get_content($filename);
    } elsif ($type eq 'zip') {
        return $archive->contents($filename);
    }
}

GetOptions(
        'help|h'            => \$help,
        'old|o'             => \$compat,
        'noprefix|n'        => \$noprefix,
        'force|f'           => \$force,
        'packager|p=s'      => \$packager,
        'release|r=i'       => \$release,
        'disttag|d=s'       => \$disttag,
        'srpm|s'            => \$buildsrpm,
        'build|b'           => \$buildrpm,
        'includebin'        => \$include_bin,
        'bin_manpage'       => \$bin_man,
        'cpan|c=s'          => \$cpan,
        'verbose|v'         => \$verbose,
    ) or pod2usage({ -exitval => 1, -verbose => 0 });

pod2usage({ -exitval => 0, -verbose => 1 }) if ($help);
pod2usage({ -exitval => 1, -verbose => 0 }) if (!@ARGV);

my $prefix=$noprefix ? "" : "perl-";

$packager=$packager || `rpm --eval '\%packager'`;

chomp $packager;

if (!$packager or $packager eq "\%packager") {
    die "\%packager not defined in ~/.rpmmacros."
        . "  Please add or use --packager option.\n";
}

die "Module::CoreList does not support perl version $]!\n"
    if (!exists($Module::CoreList::version{$]}));

for my $file (@ARGV) {
    my ($name,$version,$type);

    if ($file =~ /^(.*)-([^-]+)\.(tar)\.gz$/) {
        $name=$1;
        $version=$2;
        $type=$3;
    } elsif ($file =~ /^(.*)-([^-]+)\.(zip)$/) {
        $name=$1;
        $version=$2;
        $type=$3;
    } else {
        # Look up $file in 02packages.details.txt.
        update_packages();
        $packages=Parse::CPAN::Packages->new($pkgdetails)
            if (!defined($packages));
        die "Parse::CPAN::Packages->new() failed: $!\n"
            if (!defined($packages));
        my ($m,$d);
        if ($m=$packages->package($file) and $d=$m->distribution()) {
            my $url=$cpan . "/authors/id/" . $d->prefix();
            $file=$d->filename();
            fetch($url, $file);
            $name=$d->dist();
            $version=$d->version();
            if ($file =~ /\.(tar)\.gz$/) {
                $type=$1;
            } elsif ($file =~ /\.(zip)$/) {
                $type=$1;
            } else {
                warn "Failed to parse '$file', skipping...\n";
                next;
            }
        } else {
            warn "Failed to parse '$file' or find a module by that name, skipping...\n";
            next;
        }
    }

    my $module=$name;
    $module=~s/-/::/g;

    my $archive;
    if ($type eq 'tar') {
        $archive=Archive::Tar->new($file, 1)
            or die "Archive::Tar->new() failed: $!\n";
    } elsif ($type eq 'zip') {
        $archive=Archive::Zip->new() or die "Archive::Zip->new() failed: $!\n";
        die "Read error on $file\n" unless ($archive->read($file) == AZ_OK);
    }

    my @files;
    
    my $bogus=0;
    for my $entry (list_files($archive, $type)) {
        print "Looking for \"$name\" - \"$version\"\n";
        if ($entry !~ /^(?:.\/)?$name-$version\//) {
            warn "BOGUS PATH DETECTED: $entry\n";
            $bogus++;
            next;
        }

        $entry=~s,^(?:.\/)?$name-$version/,,;
        next if (!$entry);

        push(@files, $entry);
    }
    if ($bogus) {
        warn "Skipping $file with $bogus path elements!\n";
        next;
    }

    my $url="http://search.cpan.org/dist/$name/";

    my $vfile=$file;
    $vfile=~s/$version/\%{version}/;
    my $source="http://www.cpan.org/modules/by-module/"
        . ($module=~/::/ ? (split "::", $module)[0] : (split "-", $name)[0])
        . "/" . $vfile;

    my $description;
    my $readme=(sort { $a cmp $b } (grep /README/i, @files))[0];
    if ($readme) {
        if (my $content=extract($archive, $type, "$name-$version/$readme")) {
            $content=~s/\r//g; # Why people use DOS text, I'll never understand.
            for my $string (split "\n\n", $content) {
                $string=~s/^\n+//;
                if ((my @tmp=split "\n", $string) > 2
                    and $string !~ /^[#\-=]/) {
                    $description=$string;
                    last;
                }
            }
        } else {
            warn "Failed to read $readme from $file"
                . ($type eq 'tar' ? (": " . $archive->error()) : "") . "\n";
        }
    }

    if (defined($description) and $description) {
        $description=autoformat $description, { "all"     => 1,
                                                "left"    => 1,
                                                "right"   => 75,
                                                "squeeze" => 0,
                                              };
        $description=~s/\n+$//s;
    } else {
        $description="$module Perl module";
    }

    my @doc=sort { $a cmp $b } grep {
                !/\//
            and !/\.(pl|xs|h|c|pm|in|pod)$/i
            and !/^\./
            and $_ ne "MANIFEST"
            and $_ ne "MANIFEST.SKIP"
            and $_ ne "INSTALL"
            and $_ ne "SIGNATURE"
            and $_ ne "META.yml"
            and $_ ne "configure"
            and $_ ne "typemap"
            } @files;

    my $date=strftime("%a %b %d %Y", localtime);

    my $noarch=!grep /\.(c|xs)$/i, @files;
    my $vendorlib=($noarch ? "vendorlib" : "vendorarch");
    my $lib="\%{perl_$vendorlib}";

    my $specfile="$prefix$name.spec";
    my $spec;
    if ($force) {
        rename($specfile, "$specfile~") if (-e $specfile);
        $spec=new FileHandle ">$specfile";
    } else {
        $spec=new FileHandle "$specfile", O_WRONLY|O_CREAT|O_EXCL;
    }

    if (!$spec) {
        warn "Failed to create $specfile: $!\n";
        next;
    }

    print $spec qq[\%{!?perl_$vendorlib: \%define perl_$vendorlib \%(eval "\`\%{__perl} -V:install$vendorlib\`"; echo \$install$vendorlib)}\n\n]
        if ($compat);

    my $license="";

    my $scripts=0;
    my (%build_requires,%requires);
    my ($yml,$meta);
    if (grep /^META\.yml$/, @files
        and $yml=extract($archive, $type, "$name-$version/META.yml")) {
        # Basic idea borrowed from Module::Depends.
        my $meta=Load($yml);

        %build_requires=%{$meta->{build_requires}} if ($meta->{build_requires});
        %requires=%{$meta->{requires}} if ($meta->{requires});
        if ($meta->{recommends}) {
            for my $module (keys(%{$meta->{recommends}})) {
                $requires{$module}=$requires{$module}
                    || $meta->{recommends}->{$module};
            }
        }

        # FIXME - I'm not sure this is sufficient...
        if ($meta->{script_files} or $meta->{scripts}) {
            $scripts=1;
        }

        if ($meta->{license}) {
            if ($meta->{license} eq "perl") {
                $license="GPL or Artistic";
            } elsif ($meta->{license} eq "gpl") {
                $license="GPL";
            } elsif ($meta->{license} eq "lgpl") {
                $license="LGPL";
            } elsif ($meta->{license} eq "artistic") {
                $license="Artistic";
            } elsif ($meta->{license} eq "bsd") {
                $license="BSD";
            } elsif ($meta->{license} eq "open_source") {
                $license="OSI-Approved"; # rpmlint will complain
            } elsif ($meta->{license} eq "unrestricted") {
                $license="distributable"; # rpmlint should complain
            } elsif ($meta->{license} eq "restrictive") {
                $license="Proprietary";
                warn "License is 'restrictive'."
                    . "  This package should not be redistributed.\n";
            } else {
                warn "Unknown license '" . $meta->{license} . "'!\n";
                $license="CHECK(distributable)";
            }
        }
    }

    if (my @licenses=grep /license|copyright|copying/i, @doc) {
        if (!$license) {
            $license="distributable, see @licenses";
        } elsif ($license=~/^(OSI-Approved|distributable|Proprietary)$/) {
            $license.=", see @licenses";
        }
    }
    $license="CHECK(GPL or Artistic)" if (!$license);

    my $usebuildpl=0;
    if (grep /^Build\.PL$/, @files) {
        # FIXME - I need to figure out how to parse Build.PL.
        $build_requires{'Module::Build'}=0;
        $usebuildpl=1 if (!grep /^Makefile\.PL$/, @files);
    }

    if (!$usebuildpl) {
        # This is an ugly hack to parse any PREREQ_PM in Makefile.PL.
        if (open(CHILD, "-|") == 0) {
            eval {
                use subs 'WriteMakefile';

                sub WriteMakefile(@) {
                    my %args=@_;

                    if (!defined($args{'PREREQ_PM'})) {
                        return;
                    }

                    # Versioned BuildRequires aren't reliably honored by
                    # rpmbuild, but we'll include them anyway as a hint to the
                    # packager.
                    for my $module (keys(%{$args{'PREREQ_PM'}})) {
                        print "BuildRequires: $module";
                        print " " . $args{'PREREQ_PM'}->{$module}
                            if ($args{'PREREQ_PM'}->{$module});
                        print "\n";
                    }
                }
            };

            local $/=undef;

            my $makefilepl=extract($archive, $type, "$name-$version/Makefile.PL")
                or warn "Failed to extract $name-$version/Makefile.PL";

            open(STDERR, ">/dev/null");
            eval "no warnings;
                  use subs qw(require die warn eval open close rename);
                  BEGIN { sub require { 1; } }
                  BEGIN { sub die { 1; } }
                  BEGIN { sub warn { 1; } }
                  BEGIN { sub eval { 1; } }
                  BEGIN { sub open { 1; } }
                  BEGIN { sub close { 1; } }
                  BEGIN { sub rename { 1; } }
                  $makefilepl";

            exit 0;
        } else {
            while (<CHILD>) {
                if (/^BuildRequires:\s*(\S+)\s*(\S+)?/) {
                    my $module=$1;
                    my $version=0;
                    $version=$2 if (defined($2));
                    $build_requires{$module}=$version;
                }
            }
        }
    }

    print $spec <<END;
Name:           $prefix$name
Version:        $version
Release:        $release$disttag
Summary:        $module Perl module
License:        $license
Group:          Development/Libraries
URL:            $url
Source0:        $source
BuildRoot:      \%{_tmppath}/\%{name}-\%{version}-\%{release}-root-\%(\%{__id_u} -n)
END

    printf $spec "%-16s%s\n", "BuildArch:", "noarch" if ($noarch);

    if ($requires{perl}) {
        $build_requires{perl}=$build_requires{perl} || $requires{perl};
        delete $requires{perl};
    }

#    if ($build_requires{perl}) {
#        printf $spec "%-16s%s >= %s\n", "BuildRequires:", "perl",
#            (($build_requires{perl} lt "5.6.0" ? "0:" : "1:")
#            . $build_requires{perl});
#        delete $build_requires{perl};
#    }

#    for my $module (keys(%requires)) {
#        $build_requires{$module}=$build_requires{$module} || $requires{$module};
#    }

#    for my $module (sort(keys(%build_requires))) {
#        next if (!$compat and exists($Module::CoreList::version{$]}{$module}));
#        printf $spec "%-16s%s", "BuildRequires:", "perl($module)";
#        print $spec (" >= " . $build_requires{$module})
#            if ($build_requires{$module});
#        print $spec "\n";
#    }

    for my $module (sort(keys(%requires))) {
        next if (!$compat and exists($Module::CoreList::version{$]}{$module}));
        printf $spec "%-16s%s", "Requires:", "perl($module)";
        print $spec (" >= " . $requires{$module}) if ($requires{$module});
        print $spec "\n";
    }

    print $spec <<END;
Requires:       perl(:MODULE_COMPAT_\%(eval "`\%{__perl} -V:version`"; echo \$version))

\%description
$description

\%prep
\%setup -q@{[($noprefix ? "" : " -n $name-\%{version}")]}

\%build
END

    if ($usebuildpl) {
        print $spec <<END;
perl Build.PL installdirs=vendor@{[$noarch ? '' : ' optimize="$RPM_OPT_FLAGS"']}
./Build
END
    } else {
        print $spec <<END;
\%{__perl} Makefile.PL INSTALLDIRS=vendor@{[$noarch ? '' : ' OPTIMIZE="$RPM_OPT_FLAGS"']}
END

        print $spec
            "\%{__perl} -pi -e 's/^\\tLD_RUN_PATH=[^\\s]+\\s*/\\t/' Makefile\n"
            if (!$noarch);

        print $spec <<END;
make \%{?_smp_mflags}
END
    }

    print $spec <<END;

\%install
rm -rf \$RPM_BUILD_ROOT

END

    if ($usebuildpl) {
        print $spec
            "./Build install destdir=\$RPM_BUILD_ROOT create_packlist=0\n";
    } else {
        print $spec <<END;
make pure_install PERL_INSTALL_ROOT=\$RPM_BUILD_ROOT

find \$RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \\;
END
    }

    if (!$noarch) {
        print $spec <<END;
find \$RPM_BUILD_ROOT -type f -name '*.bs' -size 0 -exec rm -f {} \\;
END
}

    print $spec <<END;
find \$RPM_BUILD_ROOT -type d -depth -exec rmdir {} 2>/dev/null \\;

chmod -R u+rwX,go+rX,go-w \$RPM_BUILD_ROOT/*

END

    if (!grep /copying|artistic|copyright|license/i, @doc) {
        print $spec <<END;
perldoc -t perlgpl > COPYING
perldoc -t perlartistic > Artistic

END

        push(@doc, "COPYING", "Artistic");
    }

    print $spec <<END;
\%check@{[($compat ? ' || :' : '')]}
END
    if ($usebuildpl) {
        print $spec "./Build test\n";
    } else {
        print $spec "make test\n";
    }

    print $spec <<END;

\%clean
rm -rf \$RPM_BUILD_ROOT

\%files
\%defattr(-,root,root,-)
\%doc @doc
END

    if ($scripts or $include_bin) {
        print $spec "\%{_bindir}/*\n";
        # FIXME - How do we auto-detect man pages?
    }

    if ($bin_man) {
         print $spec "\%{_mandir}/man1/*\n";
    }

    if ($noarch) {
        print $spec "$lib/*\n";
    } else {
        print $spec "$lib/auto/*\n$lib/" . (split /::/, $module)[0] . "*\n";
    }

    print $spec <<END;
\%{_mandir}/man3/*

\%changelog
* $date $packager $version-$release
- Specfile autogenerated.
END

    $spec->close();

    build_rpm($specfile) if ($buildsrpm or $buildrpm);
}

# vi: set ai et:

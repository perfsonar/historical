#
#      $Id$
#
#	File:		Makefile.PL
#
#	Author:		Jeff W. Boote
#			Internet2
#
#	Date:		Mon Jan 29 16:06:53 MST 2007
#
#	Description:	
#		Build for perfSONAR-PS
#
use ExtUtils::MakeMaker;
use ExtUtils::Manifest;
use Carp;

my $NAME	= 'perfSONAR-PS';
my $VERSION	= '0.0';

my $DOETC = prompt("\nInstall example config files? :" => NO);
$DOETC = 'NO' if(uc $DOETC ne 'YES');

my $ETC_DIR =
    prompt(
        "\nWhere should scripts look for config files? \$(INSTALLETC) :" =>
        '$(PREFIX)/etc');

my $CGI_DIR = '/dev/null';
my $DOCGI = prompt("\nInstall cgi scripts? :" => NO);
if(uc $DOCGI ne 'YES'){
    $DOCGI = 'NO'
}
else{
    $CGI_DIR =
        prompt(
            "\nWhere do you want to install the cgi files? \$(INSTALLCGI) :" =>
            '$(PREFIX)/cgi');
}

#
# New categories for install.
#
my %categories = (
    'etc'	=> {
        'DOIT'      => $DOETC,
        '_SOURCE'   => 'etc',
        'INST_'	    => 'blib/etc',
        'INSTALL'   => $ETC_DIR,
    },
    'cgi'	=> {
        'DOIT'      => $DOCGI,
        '_SOURCE'   => 'cgi',
        'INST_'	    => 'blib/cgi',
        'INSTALL'   => $CGI_DIR,
    },
);

WriteMakefile(
    NAME	=>	$NAME,
    VERSION	=>	$VERSION,
    EXE_FILES	=> [ qw( client/client.pl
                        ) ],
    PMLIBDIRS   =>  [ 'lib', $BASEEXT ],
);

exit 0;

#--------------------------------------------#
package MY;

#--- Add additional constants ---#
sub constants {
    my $inherited = shift->SUPER::constants(@_);

    foreach my $category (sort keys %categories) {
        foreach my $constant (sort keys %{ $categories{$category} }) {
            next if $constant eq '_SOURCE';
            next if $constant eq 'DOIT';

            my $extra_constant = $constant . uc $category;
            my $constant_value = $categories{$category}->{$constant};

            $inherited .= "$extra_constant = $constant_value\n";
        }
    }

    # Call the fixmore hack - jwb
    my $fixmore = q{$(PERLRUN) "-MMakefile" -e '$$Makefile::libdir="$(DESTINSTALLSITELIB)"; $$Makefile::confdir="$(INSTALLETC)";Makefile->fixmore(shift)'};
    $inherited .= "FIXMORE = $fixmore\n";

    # Add Makefile.pm as a dependency for the Makefile
    $inherited =~ s/^(CONFIGDEP\s*=.*)$/$1 Makefile.pm/m;

    return $inherited;
}

sub libscan{
    my ($self, $path) = @_;
    return '' if $path =~ /^Makefile\.pm$/;
    return '' if $path =~ /\/\..+$/;
    $self->SUPER::libscan($path);
}

#--- Add installation targets ---#
sub install {
	my $inherited = shift->SUPER::install(@_);

	foreach my $dep (sort keys %categories) {

		next if($categories{$dep}->{'DOIT'} eq 'NO');
		my $target = lc $dep . '_install';

		#--- add target as install dependency  ---#
		$inherited =~ s/^(\s*install\s+::\s.+)/$1 $target/m or die;

		my $inst_var    = 'INST_' . uc $dep;
		my $install_var = 'INSTALL' . uc $dep;
		
		my $extra = <<END;
# Add code to create the directory under blib/.
\$($inst_var)/.exists :: \$(PERL_INC)/perl.h
	\@\$(MKPATH) \$($inst_var)
	\@\$(EQUALIZE_TIMESTAMP) \$(PERL_INC)/perl.h \$($inst_var)/.exists
	-\@\$(CHMOD) \$(PERM_RWX) \$($inst_var)

# Create a target to install to the final location.
$target ::
	\@echo Installing contents of \$($inst_var) into \$($install_var)
	\@\$(MOD_INSTALL) \\
		\$($inst_var) \$($install_var)

END

		$extra =~ s/ {8}/\t/g;
		$inherited .= $extra;
	}

	#--- remove non-working uninstall target ---#
	$inherited =~ s!^uninstall\s:.*$!!m or die "no uninstall target in: $inherited";

	return $inherited;
}

#--- Create targets for dirs and files in blib ---#
sub installbin {
	my $inherited = shift->SUPER::installbin(@_);


	my %seen_dir;
	foreach my $filetype (sort keys %categories) {
		my $uc = uc $filetype;
		my $src = $categories{$filetype}->{_SOURCE};

		next if($categories{$filetype}->{'DOIT'} eq 'NO');

		$inherited .= "\npure_$filetype :: ";
		$inherited .= "\n\t\@\$(NOOP)\n\n";
		$inherited =~ s/^(\s*pure_all\s+::\s.+)/$1 pure_$filetype/m
			or die "no pure_all in: $inherited";
		
		my $files = ExtUtils::Manifest::maniread();

		foreach my $file (sort keys %$files) {
			next unless($file =~ /^$src/);

			
			my $inst_pos = $file;
			$inst_pos =~ s/^$src\///;

			my @dirs = split m!/!, $inst_pos;
			pop @dirs;
			
			my $extra = '';
			foreach (0 .. $#dirs) {
				my $dir = join('/', @dirs[0 .. $_]);
				my $parent = join('/', @dirs[0 .. $_-1]);
				
				next if $seen_dir{$dir}++;
				die if (length $parent and not $seen_dir{$parent});
				
				my $parent_exists = "\$(INST_$uc)/$parent/.exists";
				$parent_exists =~ tr!/!/!s;

				$extra .= <<END;
\$(INST_$uc)/$dir/.exists :: \$(PERL_INC)/perl.h $parent_exists
        \@\$(MKPATH) \$(INST_$uc)/$dir
        \@\$(EQUALIZE_TIMESTAMP) \$(PERL_INC)/perl.h \$(INST_$uc)/$dir/.exists
        -\@\$(CHMOD) \$(PERM_RWX) \$(INST_$uc)/$dir
        
END
			}

			my $dir_exists = "\$(INST_$uc)/" . join('/', @dirs) . '/.exists';
			$dir_exists =~ tr!/!/!s;

			$extra .= <<END;
\$(INST_$uc)/$inst_pos: $file Makefile $dir_exists
        \@rm -f \$(INST_$uc)/$inst_pos
        cp $file \$(INST_$uc)/$inst_pos
END

			#--- fix #! perl path in CGI's too ---
			if($file =~ /\.cgi$/){
				$extra .= <<END;
	\$(FIXIN) \$(INST_$uc)/$inst_pos
	-\@\$(CHMOD) \$(PERM_RWX) \$(INST_$uc)/$inst_pos

END
			}
			elsif($file =~ /\.sh$/){
				$extra .= <<END;
        -\@\$(CHMOD) \$(PERM_RWX) \$(INST_$uc)/$inst_pos
        
END
			}
			else{
				$extra .= <<END;
        -\@\$(CHMOD) \$(PERM_RW) \$(INST_$uc)/$inst_pos
        
END
			}

			$extra =~ s/ {8}/\t/g;
			$extra =~ tr!/!/!s;

			$inherited .= $extra;

			$inherited =~ s/^(\s*pure_$filetype\s+::\s.*)/$1 \$(INST_$uc)\/$inst_pos/m
				or die "no pure_$filetype in: $inherited";
		}
	}



        # Add to FIXIN - this runs my fixmore hack. -jwb
        $inherited =~ s/^(\s*)(\$\(FIXIN\))(.+)/$1$2$3\n$1\$\(FIXMORE\)$3/mg;

	return $inherited;
}

1;

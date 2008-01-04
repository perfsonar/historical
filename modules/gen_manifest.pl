my @skip_files = (
	'CVS/.*',
	'\.svn/.*', 
	'\.bak$', 
	'\.sw[a-z]$', 
	'\.tar$', 
	'\.tgz$', 
	'\.tar\.gz$', 
	'^mess/', 
	'^tmp/', 
	'^blib/', 
	'^Makefile$', 
	'^Makefile\.[a-z]+$', 
	'^pm_to_blib$', 
	'~$', 
);

my @files = `find -type f`;
my @links = `find -type l`;

unshift(@files, @links);

open(MANIFEST, ">MANIFEST");
foreach my $file (sort @files) {
	$file =~ s/^\.\///;
	foreach my $regex (@skip_files) {
		goto SKIP if ($file =~ /$regex/)
	}

	print MANIFEST $file;
SKIP:
}
close (MANIFEST);

open(MANIFEST_SKIP, ">MANIFEST.SKIP");
foreach my $regex (sort @skip_files) {
	print MANIFEST_SKIP $regex."\n";
}
close(MANIFEST_SKIP);

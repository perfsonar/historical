#!/usr/bin/perl

# script to automate arduous taks of symlinking the files for the libs

my $relativepath = $ARGV[0];

print $relativepath . "\n";

my @list = `tree -if $relativepath`;

my $base = `pwd`;
chomp $base;


foreach my $l ( @list ) {

	chomp ( $l );
	chdir $base;

	my $dir = undef;
	print "===" . $l . "===\n";

	# make directory
	if ( $l =~ m/^(.*)\/(.*).pm$/g ) {
		my $path = $1;
		$path =~ s/^$relativepath//g;
		$path = 'lib' . $path;

		# find out number of levels
		$path =~ s/\/\//\//g;
		$path =~ s/\/$//g;
		my @tmp = split '/', $path;
		my $levels = scalar @tmp;

		my $cmd = "mkdir -p $path";
		`$cmd`;
		print $cmd . "\n";

		$cmd = "cd $path";
		chdir( $path );
		print $cmd . "\n";

		# add relative number of new levels to path
		my $file = '../' x $levels . '/' . $l;

		$cmd = "ln -sf $file .";
		`$cmd`;
		print $cmd . "\n";
	}
}

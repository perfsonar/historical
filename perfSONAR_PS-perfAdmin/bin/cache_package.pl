#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

cache_package.pl - Build a tarball of the gLS cache for distribution

=head1 DESCRIPTION

Examine a checksum to see if cache files have changed and then create a tarball.

=cut
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Archive::Tar;
use Carp;
use Digest;
use File::Copy qw(copy move);
use File::Temp qw(tempdir);

my @directories = ("/var/lib/perfsonar/perfAdmin/cache");
my $archive_file = "/usr/local/www/cache.tgz";
my $heartbeat_file = "/usr/local/www/ls_cache_heartbeat.txt";

#setup logger
use Log::Log4perl qw(:easy);

my $output_level = $INFO;

my %logger_opts = (
    level  => $output_level,
    layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    file   => "/var/log/perfsonar/cache.log",
);

Log::Log4perl->easy_init( \%logger_opts );

my $logger = get_logger( "cache" );

my %digest_map = ();

# read the existing tarball and generate a checksum of each file.
if(-e $archive_file) {
    my $archive = Archive::Tar->new( $archive_file, 1 );
    if ($archive) {
        my @files = $archive->get_files;
        foreach my $file (@files) {
            $logger->info("Found: ".$file->full_path." in cache");
            my $content = $file->get_content;
            next unless ($content);

	    my $digest = Digest->new("MD5");
            $digest->add($content);
            $digest_map{$file->full_path}=$digest->hexdigest;
        }
    }
}

#compare existing digests to calculated
my $do_update = 0;
my $digest = Digest->new("MD5");
foreach my $directory (@directories) {
    opendir DIR, $directory or croak("cannot open directory $directory");
    my @digest_files = readdir(DIR) or croak("cannot read directory $directory");
    closedir DIR;
    my %new_digest_map = ();
    foreach my $digest_file( @digest_files ){
        next if ($digest_file eq "." or $digest_file eq "..");

        $logger->debug("looking for changes in $digest_file");
        open( FILE, "<" . $directory. "/$digest_file") or croak "can't digest $directory/$digest_file.";
        my $tmp_digest = $digest->addfile(*FILE)->hexdigest();
        close FILE;
        if((!defined $digest_map{$digest_file}) || $tmp_digest ne $digest_map{$digest_file}){
            $logger->debug("$digest_file has been updated");
            $do_update = 1;
            last;
        }
    }

    last if ($do_update);
}

if($do_update == 1){
    my $tempdir = tempdir( CLEANUP => 1);

    my %files_to_tar = ();

    # Copy the files to a temp location
    foreach my $directory (@directories) {
        opendir DIR, $directory or croak("cannot open directory $directory");
        my @files = readdir(DIR) or croak("cannot read directory $directory");
        foreach my $file (@files) {
            copy($directory."/".$file, $tempdir."/".$file);
            $files_to_tar{$file} = 1;
        }
    }
 
    #create new tarball
    my @compress_files = ($tempdir);
    chdir $tempdir;
    Archive::Tar->create_archive('/tmp/ps-cache.tgz', "COMPRESS_GZIP", keys %files_to_tar);
    move '/tmp/ps-cache.tgz', $archive_file or croak "can't move file to $archive_file";
    $logger->debug("generated new archive file $archive_file");
}

#touch the heartbeat file so we know this ran
open HEARTBEAT, "> $heartbeat_file" or croak("Unable to open heartbeat file $heartbeat_file");
print HEARTBEAT "1";
close HEARTBEAT;


=head1 SEE ALSO

L<Archive::Tar>, L<Carp>, L<Digest>, L<File::Copy>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: cache.pl 3982 2010-03-30 13:58:42Z alake $

=head1 AUTHOR

Andy Lake, andy@es.net

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2008-2010, Internet2

All rights reserved.

=cut

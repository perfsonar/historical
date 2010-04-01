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
use File::Copy qw(move);


my $base = "/var/lib/perfsonar/perfAdmin/cache";
my $archive_file = "/var/www/html/perfsonar/cache.tgz";

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


# read digest file
my %digest_map = ();
if(-e $base . "/checksum"){
    open( CHKSUM, "<" . $base . "/checksum") or croak "can't open $base/checksum.";
    while( <CHKSUM> ){
        chomp $_;
        if($_ !~ /.+:.+/){
            next;
        }
        my ($chk_key, $chk_val) = split ":", $_;
        $digest_map{$chk_key} = $chk_val;
    }
}

#compare existing digests to calculated
my $do_update = 0;
my $digest = Digest->new("MD5");
opendir DIR, $base or croak("cannot open directory $base");
my @digest_files = readdir(DIR) or croak("cannot read directory $base");
closedir DIR;
my %new_digest_map = ();
foreach my $digest_file( @digest_files ){
    if($digest_file eq 'checksum' || $digest_file =~ '^\.'){
        next;
    }
    $logger->debug("looking for changes in $digest_file");
    open( FILE, "<" . $base . "/$digest_file") or croak "can't digest $base/$digest_file.";
    my $tmp_digest = $digest->addfile(*FILE)->b64digest();
    close FILE;
    if((!defined $digest_map{$digest_file}) || $tmp_digest ne $digest_map{$digest_file}){
        $logger->debug("$digest_file has been updated");
        $do_update = 1;
    }
    $new_digest_map{$digest_file} = $tmp_digest;
}

if($do_update == 1){
    #create new tarball
    my @compress_files = ($base);
    chdir $base;
    Archive::Tar->create_archive('/tmp/ps-cache.tgz', COMPRESS_GZIP, keys %new_digest_map);
    move '/tmp/ps-cache.tgz', $archive_file or croak "can't move file to $archive_file";
    $logger->debug("generated new archive file $archive_file");
    
    #write new checksum file
    open( CHKSUM, ">" . $base . "/checksum") or croak "can't open $base/checksum.";
    foreach my $file_key(keys %new_digest_map){
        print CHKSUM "$file_key:" . $new_digest_map{$file_key} . "\n";
    }
    
    close CHKSUM;
}

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

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008-2010, Internet2

All rights reserved.

=cut
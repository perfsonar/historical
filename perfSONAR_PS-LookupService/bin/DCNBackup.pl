#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

DCNBackup.pl - export DCN content from an hLS

=head1 DESCRIPTION

Exports the DCN specific contents (e.g. node to friendly name mapping) of an hLS

=head1 SYNOPSIS

./DCNBackup.pl OUTPUTFILE
 
=cut

use Carp;

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Client::DCN;

my $file = shift;
croak "Provide output file.\n" unless $file;
open( OUT, ">" . $file );

my $source = new perfSONAR_PS::Client::DCN( { instance => "http://dcn-ls.internet2.edu:8005/perfSONAR_PS/services/hLS" } );

print OUT "name,id,institution,longitude,latitude,keywords\n";

my $map = $source->getMappings;
foreach my $m ( @$map ) {
    print OUT $m->[0] if exists $m->[0] and $m->[0];
    print OUT ",";
    print OUT $m->[1] if exists $m->[0] and $m->[1];
    print OUT ",";
    if ( exists $m->[2] and $m->[2] ) {

       print OUT $m->[2]->{institution} if exists $m->[2]->{institution} and $m->[2]->{institution};
       print OUT ",";
       print OUT $m->[2]->{longitude} if exists $m->[2]->{longitude} and $m->[2]->{longitude};
       print OUT ",";
       print OUT $m->[2]->{latitude} if exists $m->[2]->{latitude} and $m->[2]->{latitude};
       print OUT ",";

        if ( $m->[2]->{keywords} ) {
            my $kwc = 0;
            foreach my $kw ( @{ $m->[2]->{keywords} } ) {
                print OUT ", " if $kwc;
                print OUT $kw;
                $kwc++;
            }
        }
    }
    else {
        print OUT ",,,";
    }
    print OUT "\n";
}

close(OUT);

__END__

=head1 SEE ALSO

L<Carp>, L<perfSONAR_PS::Client::DCN>

To join the 'perfSONAR Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

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

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut



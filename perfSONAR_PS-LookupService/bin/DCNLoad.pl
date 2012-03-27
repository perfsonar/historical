#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

DCNLoad.pl - Load an hLS with DCN content.

=head1 DESCRIPTION

Loads an hLS (specified in URL) with the contents of the file (specified in 
FILENAME).

=head1 SYNOPSIS

./DCNLoad.pl FILENAME URL

=cut

use Carp;

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Client::DCN;

my $file = shift;
my $url = shift;

croak "Provide intput file and LS url.\n" unless $file and $url;

my $dcn = new perfSONAR_PS::Client::DCN( { instance => $url, myAddress => "https://dcn-ls.internet2.edu/dcnAdmin.cgi", myName => "DCN Registration CGI", myType => "dcnmap" } );

open( IN, "<" . $file );
my $counter = 0;
while ( <IN> ) {
    if ( $counter ) {
        my @fields = split( /,/, $_ );

        my @temp = ();
        for( my $x = 5; $x <= $#fields; $x++ ) {
            push @temp, $fields[$x];
        }

        my $code = $dcn->insert( { name => $fields[0], id => $fields[1], institution => $fields[2], longitude => $fields[3], latitude => $fields[4], keywords => \@temp } );
        unless ( $code == 0 ) {
            print "FAIL: " , $_ , "\n";
        }

    }
    $counter++;
}
my @content = <IN>;
close(IN);

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


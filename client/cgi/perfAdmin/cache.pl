#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

cache.pl - Build a cache of information from the global gLS infrastructure

=head1 DESCRIPTION

Contact the gLS's to gain a list of hLS instances (for now double up to be sure
we get things that may not have spun yet).  After this, contact each and get a
list of services.  Store the list in text files where they can be used by other
applications.

=cut

use XML::LibXML;
use Carp;

use lib "/usr/local/perfSONAR-PS/lib";

use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Client::gLS;

my $parser = XML::LibXML->new();
my $hints  = "http://www.perfsonar.net/gls.root.hints";
my $base   = "/var/lib/hLS/cache";

my %hls = ();
my $gls = perfSONAR_PS::Client::gLS->new( { url => $hints } );

croak "roots not found" unless ( $#{ $gls->{ROOTS} } > -1 );

for my $root ( 0 .. 2 ) {
    next unless $gls->{ROOTS}->[$root];
    my $result = $gls->getLSQueryRaw(
        {
            ls => $gls->{ROOTS}->[$root],
            xquery =>
                "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./perfsonar:subject/psservice:service/psservice:serviceType[text()=\"LS\" or text()=\"hLS\" or text()=\"ls\" or text()=\"hls\"]]"
        }
    );
    if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
        my $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};
        my $ap = find( $doc->getDocumentElement, ".//psservice:accessPoint", 0 );
        foreach my $a ( $ap->get_nodelist ) {
            my $value = extract( $a, 0 );
            $hls{$value} = 1 if $value;
        }
    }
}

my %list = ();
open( HLS, ">" . $base . "/list.hls" ) or croak "can't open hls list";
foreach my $h ( keys %hls ) {
    print HLS $h, "\n";

    my $ls = new perfSONAR_PS::Client::LS( { instance => $h } );
    my $result = $ls->queryRequestLS(
        {
            query     => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]\n",
            eventType => "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0",
            format    => 1
        }
    );

    if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
        my $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};

        my $md = find( $doc->getDocumentElement, "./nmwg:store/nmwg:metadata", 0 );
        my $d  = find( $doc->getDocumentElement, "./nmwg:store/nmwg:data",     0 );

        foreach my $m1 ( $md->get_nodelist ) {
            my $id = $m1->getAttribute("id");
            my $contactPoint = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='accessPoint']", 1 ), 0 );
            unless ($contactPoint) {
                $contactPoint = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='address']", 1 ), 0 );
                next unless $contactPoint;
            }
            foreach my $d1 ( $d->get_nodelist ) {
                my $metadataIdRef = $d1->getAttribute("metadataIdRef");
                next unless $id eq $metadataIdRef;

                my $eventTypes = find( $d1, "./nmwg:metadata/nmwg:eventType", 0 );
                foreach my $e ( $eventTypes->get_nodelist ) {
                    my $value = extract( $e, 0 );
                    if ($value) {
                        if ( exists $list{$value} ) {
                            push @{ $list{$value} }, $contactPoint;
                        }
                        else {
                            my @temp = ($contactPoint);
                            $list{$value} = \@temp;
                        }
                    }
                }
                last;
            }
        }
    }
}
close(HLS);

foreach my $et ( keys %list ) {
    my $file = q{};
    if ( $et eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" or $et eq "http://ggf.org/ns/nmwg/tools/snmp/2.0" ) {
        $file = "list.snmpma";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
        $file = "list.pinger";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" or $et eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0" or $et eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" ) {
        $file = "list.psb.bwctl";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" ) {
        $file = "list.psb.owamp";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" ) {
        $file = "list.bwctl";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/traceroute/1.0" ) {
        $file = "list.traceroute";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/npad/1.0" ) {
        $file = "list.npad";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/ndt/1.0" ) {
        $file = "list.ndt";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/owamp/1.0" ) {
        $file = "list.owamp";
    }
    elsif ( $et eq "http://ggf.org/ns/nmwg/tools/ping/1.0" ) {
        $file = "list.ping";
    }
    next unless $file;
    open( OUT, ">" . $base . "/" . $file ) or croak "can't open $base/$file.";
    foreach my $host ( @{ $list{$et} } ) {
        print OUT $host, "\n";
    }
    close(OUT);
}

=head1 SEE ALSO

L<XML::LibXML>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Client::gLS>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.

=cut


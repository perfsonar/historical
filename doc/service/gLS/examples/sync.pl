#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

sync.pl - Utility to syncronize DCN LS deployments.

=head1 DESCRIPTION

The DCN LS manages topology registration as well as host -> linkID mapping.  To
facilitate some demo software it was necessary to move all data from the main
DCN LS to a backup to not affect the live software.

=cut

use Data::Dumper;

use lib "lib";
use perfSONAR_PS::Client::DCN;
use perfSONAR_PS::Client::LS;

# prepare two LS instances (source and destination)
my $origdcn = new perfSONAR_PS::Client::DCN(
  { instance => "http://packrat.internet2.edu:8009/perfSONAR_PS/services/LS" }
);

my $newdcn = new perfSONAR_PS::Client::DCN(
  { instance => "http://dc211.internet2.edu:8090/perfSONAR_PS/services/LS" }
);

# get a full list of host to ID mappings from the source.
my $maporig = $origdcn->getMappings;

# we need to do some juggling here, so use a format that is easy to manage
# (e.g. not an array ref)
my @oa = ();
foreach my $m (@$maporig) {
  my %hash = ();
  $hash{"hostName"} = $m->[0];
  $hash{"linkid"} = $m->[1];  
  push @oa, {%hash};
}

# Do the same for the destination
my $mapnew = $newdcn->getMappings;
my @na = ();
foreach my $m (@$mapnew) {
  my %hash = ();
  $hash{"hostName"} = $m->[0];
  $hash{"linkid"} = $m->[1];  
  push @na, {%hash};
}

# Now loop through each thing on the dest.  If it is not in the source, get
# rid of it.
foreach my $hash1 (@na) {
  my $found = 0;
  foreach my $hash2 (@oa) {
    if(($hash1->{"hostName"} eq $hash2->{"hostName"}) and 
       ($hash1->{"linkid"} eq $hash2->{"linkid"})){
      $found++;
      last;
    }
  }
  if(not $found) {
    my $code = $newdcn->remove({ name => $hash1->{"hostName"}, id => $hash1->{"linkid"} });
    if($code == 0) {
      print "Removal of \"".$hash1->{"hostName"}."\" and \"".$hash1->{"linkid"}."\" passed.\n";
    }
    else {
      print "Removal of \"".$hash1->{"hostName"}."\" and \"".$hash1->{"linkid"}."\" failed.\n";
    }
  }
}

# Loop through each thing on the source, if the dest doesn't have it, add it.
foreach my $hash1 (@oa) {
  my $found = 0;
  foreach my $hash2 (@na) {
    if(($hash1->{"hostName"} eq $hash2->{"hostName"}) and 
       ($hash1->{"linkid"} eq $hash2->{"linkid"})){
      $found++;
      last;
    }
  }
  if(not $found) {
    my $code = $newdcn->insert({ name => $hash1->{"hostName"}, id => $hash1->{"linkid"} });
    if($code == 0) {
      print "Insertion of \"".$hash1->{"hostName"}."\" and \"".$hash1->{"linkid"}."\" passed.\n";
    }
    else {
      print "Insertion of \"".$hash1->{"hostName"}."\" and \"".$hash1->{"linkid"}."\" failed.\n";
    }
  }
}

# now do the same thing with topolgy services...

# Map the source
my @soa = ();
my $services_orig = $origdcn->getTopologyServices;
foreach my $s (sort keys %$services_orig) {
  my %hash = ();
  $hash{"accessPoint"} = $s;
  foreach my $s2 (sort keys %{$services_orig->{$s}}) {
    $hash{$s2} = $services_orig->{$s}->{$s2};  
    my $domains = $origdcn->getDomainService({ accessPoint => $s });
    foreach my $d (@$domains) {
      $hash{"domain"} = $d;
    } 
  }
  push @soa, {%hash};
}

# Map the dest
my @sna = ();
my $services_new = $newdcn->getTopologyServices;
foreach my $s (sort keys %$services_new) {
  my %hash = ();
  $hash{"accessPoint"} = $s;
  foreach my $s2 (sort keys %{$services_new->{$s}}) {
    $hash{$s2} = $services_new->{$s}->{$s2};  
    my $domains = $newdcn->getDomainService({ accessPoint => $s });
    foreach my $d (@$domains) {
      $hash{"domain"} = $d;
    } 
  }
  push @sna, {%hash};
}

# use the LS api (cleaner for non DCN services like the topo)
my $lsn = new perfSONAR_PS::Client::LS(
  { instance => "http://dc211.internet2.edu:8090/perfSONAR_PS/services/LS" }
);

# Loop through and remove from the dest things that are not in the source

foreach my $hash1 (@sna) {
  my $found = 0;
  foreach my $hash2 (@soa) {
    if(($hash1->{"accessPoint"} eq $hash2->{"accessPoint"}) and 
       ($hash1->{"domain"} eq $hash2->{"domain"}) and 
       ($hash1->{"serviceName"} eq $hash2->{"serviceName"}) and 
       ($hash1->{"serviceType"} eq $hash2->{"serviceType"})){
      $found++;
      last;
    }
  }
  if(not $found) {
    $result = $lsn->keyRequestLS( { service => \%{$hash1} } );
    if ( $result->{key} ) {
        my $key = $result->{key};
        print "Key was \"" . $key . "\"\n";
        
        $result = $lsn->deregisterRequestLS( { key => $key } );
        if ( $result->{eventType} eq "success.ls.deregister" ) {    
            print "De-registration worked.\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
        else {
            print "Can't De-register.\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
    }
    else {
        print "Service \"" . $hash1->{"accessPoint"} . "\" is not registered.\n";
    }
  }
}



my $lso = new perfSONAR_PS::Client::LS(
  { instance => "http://packrat.internet2.edu:8009/perfSONAR_PS/services/LS" }
);

# loop through the source and add things to the dest that may be missing

foreach my $hash1 (@soa) {
  my $found = 0;
  foreach my $hash2 (@sna) {
    if(($hash1->{"accessPoint"} eq $hash2->{"accessPoint"}) and 
       ($hash1->{"domain"} eq $hash2->{"domain"}) and 
       ($hash1->{"serviceName"} eq $hash2->{"serviceName"}) and 
       ($hash1->{"serviceType"} eq $hash2->{"serviceType"})){
      $found++;
      last;
    }
  }
  if(not $found) {
    $result = $lso->keyRequestLS( { service => \%{$hash1} } );
    if ( $result->{key} ) {
        my $key = $result->{key};
        print "Key was \"" . $key . "\"\n";
        
        my @rdata = ();
        $rdata[0] .= "    <nmwg:metadata id=\"meta0\">\n";
        $rdata[0] .= "      <nmwg:subject id=\"sub0\">\n";
        $rdata[0] .= "        <nmtb:domain xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"urn:ogf:network:domain=".$hash1->{"domain"}."\"/>\n";
        $rdata[0] .= "      </nmwg:subject>\n";
        $rdata[0] .= "      <nmwg:eventType>topology</nmwg:eventType>\n";
        $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/topology/query/all/20070809</nmwg:eventType>\n";
        $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/topology/query/xquery/20070809</nmwg:eventType>\n";
        $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/add/20070809</nmwg:eventType>\n";
        $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/update/20070809</nmwg:eventType>\n";
        $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/topology/change/replace/20070809</nmwg:eventType>\n";
        $rdata[0] .= "    </nmwg:metadata>\n";

        my $result = $lsn->registerRequestLS( { service => \%{$hash1}, data => \@rdata } );

        if ( $result->{eventType} eq "success.ls.register" ) {
            $key = $result->{key};
            print "Success!  The key is \"" . $key . "\"\n";
            print "Message:\t" . $result->{response} . "\n";
        }    
        else {
            print "Failed to register.\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }
    }
    else {
        print "Service \"" . $hash1->{"accessPoint"} . "\" is not registered.\n";
    }
  }
}

exit(1);

__END__

=head1 SEE ALSO

L<perfSONAR_PS::Client::DCN>, L<perfSONAR_PS::Client::LS>, L<Data::Dumper>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.



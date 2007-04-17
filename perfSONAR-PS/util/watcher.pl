#!/usr/bin/perl

use IO::File;
use Time::HiRes qw( gettimeofday );

$PROGRAM1 = "";
readConf("./watcher.conf");

my $foundit = 0;

open(IN, "ps axw |");
while(<IN>) {
  if (/$PROGRAM1/) {
    $foundit = 1;
    last;
  }
}
close(IN);

unless ($foundit) {
  system("cd /usr/local/perfSONAR-PS/MP/SNMP && ./snmpMP.pl");
}

sub readConf {
  my ($file)  = @_;
  my $CONF = new IO::File("<$file") or die "Cannot open 'readConf' $file: $!\n" ;
  while (<$CONF>) {
    if(!($_ =~ m/^#.*$/)) {
      $_ =~ s/\n//;
      if($_ =~ m/^PROGRAM1=.*$/) {
        $_ =~ s/PROGRAM1=//;
        $PROGRAM1 = $_;
	$PROGRAM1 =~ s/\"//g;
      }
      elsif($_ =~ m/^PROGRAM2=.*$/) {
        $_ =~ s/PROGRAM2=//;
        $PROGRAM2 = $_;
	$PROGRAM2 =~ s/\"//g;
      }
    }
  }          
  $CONF->close();
  return; 
}

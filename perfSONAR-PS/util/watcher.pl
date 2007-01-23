#!/usr/bin/perl -w
# ######################################################## #
#                                                          #
# Name:		watcher.pl                                 #
# Author:	Jason Zurawski                             #
# Contact:	zurawski@eecis.udel.edu                    #
# Args:		N/A                                        #
# Purpose:	Run this in cron to make sure the          #
#               collection script doesnt die:              #
#                                                          #
# In /etc/crontab:                                         #
#                                                          #
# watcher.pl, run it often...                      	   #
# */1 * * * * root   cd $PERFSONAR-PS_HOME && ./watcher.pl #
#                                                          #
# ######################################################## #

use strict;
use IO::File;

my %conf = ();
%conf = readConfiguration("./watcher.conf", \%conf);

open(IN, "ps axw |");
my @ps = <IN>;
close(IN);

my @keys = keys(%conf);

for(my $x = 1; $x <= $#{@keys}; $x += 2) {
  my $foundit = 0;
  my $PROGRAM1 = "PROGRAM".$x;
  my $PROGRAM2 = "PROGRAM".eval($x+1);

  foreach my $process (@ps) {
    $process =~ s/\n//g;
    if ($process =~ m/$conf{$PROGRAM1}/ || $process =~ m/$conf{$PROGRAM2}/) {
      $foundit = 1;
      last;
    }
  }

  unless ($foundit) {
    system("$PROGRAM2");
  }
}



# ################################################ #
# Sub:		readConf                           #
# Args:		$file - Filename to read           #
#               $sent - flattened hash of conf     #
#                       values                     #
# Purpose:	Read and store info.               #
# ################################################ #
sub readConfiguration {
  my ($file, $sent)  = @_;
  my %hash = %{$sent};  
  my $CONF = new IO::File("<$file") || 
    die "Cannot open 'readConf' $file: $!\n" ;
  while (<$CONF>) {
    if(!($_ =~ m/^#.*$/)) {
      $_ =~ s/\n//;
      my @values = split(/=/,$_);
      $hash{$values[0]} = $values[1];
    }
  }          
  $CONF->close();
  return %hash; 
}

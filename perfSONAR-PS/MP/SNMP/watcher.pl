#!/usr/bin/perl
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
# */1 * * * * root       cd $NETRADAR_HOME && ./watcher.pl #
#                                                          #
#                                                          #
#                                                          #
# ######################################################## #

use IO::File;

$PROGRAM1 = "";
$PROGRAM2 = "";
readConf("./watcher.conf");

my $foundit = 0;

open(IN, "ps axw |");
while(<IN>) {
  if (/$PROGRAM1/ || /$PROGRAM2/) {
    $foundit = 1;
    last;
  }
}
close(IN);

unless ($foundit) {
  system("$PROGRAM2");
}

# ################################################ #
# Sub:		readConf                           #
# Args:		$file - Filename to read           #
# Purpose:	Read and store info.               #
# ################################################ #
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

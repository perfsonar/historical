#!/usr/bin/perl
# ##################################################### #
#                                                       #
# Name:		watcher.pl                              #
# Author:	Jason Zurawski                          #
# Contact:	zurawski@eecis.udel.edu                 #
# Args:		N/A                                     #
# Purpose:	Run this in cron to make sure the       #
#               collection script doesnt die:           #
#                                                       #
# In /etc/crontab:                                      #
#                                                       #
# # watcher.pl, run it every 5 minutes                  #
# */5 *  * * *   root    /usr/local/netradar/watcher.pl #
#                                                       #
# ##################################################### #
my $program1 = "/usr/bin/perl ./collect.pl";
my $program2 = "/usr/bin/perl /usr/local/netradar/snmpMP/collect.pl";
my $foundit = 0;

open(IN, "ps axw |");
while(<IN>) {
  if (/$program1/ || /$program2/) {
    $foundit = 1;
    last;
  }
}
close(IN);

unless ($foundit) {
  system("$program2");
}

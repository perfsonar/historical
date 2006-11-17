#!/usr/bin/perl -w
# ################################################ #
#                                                  #
# Name:		configureSNMP.pl                   #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A                                #
# Purpose:	Generating the store.xml can be a  #
#               pain, especially when using deter  #
#               or emulab (where the machine       #
#               config changes each experiment) so #
#               this will automatically generate   #
#               the store file given that the host #
#               machine is running snmp.           #
#                                                  #
# ################################################ #
use strict;

my $CONF = "./SNMP.conf";

		# Remove the old file, and start the
		# new one.  
system("rm -f store.xml");
open(FILE, ">store.xml");

print FILE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print FILE "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
print FILE "            xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
print FILE "            xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n\n";

my $idCounter = 0;
open(CONF, $CONF);
while(<CONF>) {
  if($_ =~ m/^#.*/) {
    # ignore comments
  }
  else {
    $_ =~ s/\n//;
    my @item = split(/\t/,$_);

    open(SNMPWALK, "snmpwalk -v " . $item[1] . " -c " . $item[2] . " " . $item[0] . " ifDescr |");
    while(<SNMPWALK>) {
      $_ =~ s/\n//g;
      $_ =~ s/IF-MIB::ifDescr.//;
      $_ =~ s/\s=\sSTRING:\s/ /;  
      my @pair = split(/ /, $_);
      if($pair[1] =~ m/^eth/) {

        open(SPEED, "snmpget -v " . $item[1] . " -c " . $item[2] . " " . $item[0] . " ifSpeed." . $pair[0] . " |");
        my @speed = <SPEED>;
        $speed[0] =~ s/\n//g;
        $speed[0] =~ s/IF-MIB::ifSpeed\.\d\s=\sGauge32:\s//;            
        close(SPEED);  

        my @pair2 = ();
        open(IP, "snmpwalk -v " . $item[1] . " -c " . $item[2] . " " . $item[0] . " ipAdEntIf |");
	while(<IP>) {
          $_ =~ s/\n//g;
	  $_ =~ s/IP-MIB::ipAdEntIfIndex\.//;            
	  $_ =~ s/\s=\sINTEGER:\s/ /;
	  @pair2 = split(/ /, $_);
	  if($pair2[1] eq $pair[0]) {
	    last;
	  }
        }
	close(IP);  

        print FILE "  <nmwg:metadata id=\"" , $pair2[0] , "-" , $item[4] , "-" , $pair[0] , "\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
        print FILE "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"" , $item[0] , $idCounter , "\">\n";
        print FILE "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
        print FILE "        <nmwgt:ifAddress type=\"ipv4\">" , $pair2[0] , "</nmwgt:ifAddress>\n";
        print FILE "        <nmwgt:hostName>" ,$item[0] , "</nmwgt:hostName>\n";
        print FILE "        <nmwgt:ifName>" , $pair[1] , "</nmwgt:ifName>\n";
        print FILE "        <nmwgt:ifIndex>" , $pair[0] , "</nmwgt:ifIndex>\n";
        print FILE "        <nmwgt:direction>" , $item[3] , "</nmwgt:direction>\n";
        print FILE "        <nmwgt:capacity>" , $speed[0] , "</nmwgt:capacity>\n";
        print FILE "      </nmwgt:interface>\n";
        print FILE "    </netutil:subject>\n";
        print FILE "    <nmwg:eventType>" , $item[4] , "</nmwg:eventType>\n";
        print FILE "    <nmwg:parameters id=\"1\">\n";
        print FILE "      <nmwg:parameter name=\"SNMPVersion\" value=\"" , $item[1] , "\" />\n";
        print FILE "      <nmwg:parameter name=\"SNMPCommunity\" value=\"" , $item[2] , "\" />\n";
        print FILE "      <nmwg:parameter name=\"eventType\" value=\"" , $item[5] , "\" />\n";	
        print FILE "    </nmwg:parameters>\n";
        print FILE "  </nmwg:metadata>\n\n";

	$idCounter++;
      }
    }
    close(SNMPWALK);
  }
}

print FILE "</nmwg:store>\n";
close(FILE);

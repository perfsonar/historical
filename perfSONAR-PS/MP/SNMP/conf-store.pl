#!/usr/bin/perl
# ################################################ #
#                                                  #
# Name:		conf-store.pl                      #
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

$DEBUG = 0;

		# Remove the old file, and start the
		# new one.  
		
system("rm -f store.xml");
open(FILE, ">store.xml");

print FILE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print FILE "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
print FILE "            xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
print FILE "            xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n\n";

		# what is our hostname
open(HOSTNAME, "hostname |");
@results = <HOSTNAME>;
close(HOSTNAME);
$host = $results[0];
$host =~ s/\n//g;

if($DEBUG) {
  print "Host: " , $host , "\n";
}

		# read the if listing, on RH systems 
		# we should get something like this:
		# 
		# eth0      Link encap:Ethernet  HWaddr 00:11:50:70:DA:53
		#           inet addr:192.168.1.101  Bcast:192.168.1.255  Mask:255.255.255.0
		#           inet6 addr: fe80::211:50ff:fe70:da53/64 Scope:Link
		#           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
		#           RX packets:64739 errors:0 dropped:0 overruns:0 frame:0
		#           TX packets:53698 errors:0 dropped:0 overruns:0 carrier:0
		#           collisions:0 txqueuelen:0
		#           RX bytes:61647088 (58.7 MiB)  TX bytes:9393149 (8.9 MiB)
		# 
		# We really only need to know the interface 'eth0', and the 
		# address '192.168.1.101' from this printout; it is important to
		# get information on all '10.*' addresses when in deter (multiple 
		# interfaces)
		
open(IFCFG, "ifconfig |");
my $counter = 0;
my $ip = 0;
my $if = 0;
		# iterate over each line of the output
while(<IFCFG>) {
  $_ =~ s/\n//g;
  		# if we start with an eth, we are interested...
  if($_ =~ m/^eth\d.*$/) {
  		# set the flag to indicate we ONLY want the next line.
    $counter++;      
    		# regex out the bad stuff
    $if = $_;
    $if =~ s/HWaddr.*//;
    $if =~ s/Link.*//;
    $if =~ s/\s+//;            

    if($DEBUG) {
      print "Interface: " , $if , "\n";
    }

  }
  elsif($counter == 1) {
  		# set the flag to indicate that we saw the next line
    $counter--;          
    		# regex out the bad stuff
    $ip = $_;
    $ip =~ s/Bcast.*//;
    $ip =~ s/inet\saddr://;
    $ip =~ s/\s+//g;           
	
    if($DEBUG) {
      print "IP: " , $ip , "\n";
    }	
		
    my $index = 0;
    open(IFCFG, "snmpwalk -v 1 -c public " . $host . " ifDes |");
    while(<IFCFG>) {
      $_ =~ s/\n//g;
      if($_ =~ m/^.*$if$/) {
        $index = $_;
        $index =~ s/IF-MIB::ifDescr.//;
        $index =~ s/\s=\sSTRING.*//;              
      }
    }
    close(IFCFG);  

    if($DEBUG) {
      print "Index: " , $index , "\n";
    }

    open(IFCFG, "snmpget -v 1 -c public " . $host . " ifSpeed." . $index . " |");
    @ifcfg = <IFCFG>;
    $speed = $ifcfg[0];
    $speed =~ s/\n//g;
    $speed =~ s/IF-MIB::ifSpeed\.\d\s=\sGauge32:\s//;            
    close(IFCFG);  
  		
    if($DEBUG) {
      print "Speed: " , $speed , "\n";
    }		
		
		# This file contains all of the SNMP variables we
		# want to include in the store.xml file
    open(CONF, "values.conf");
    while(<CONF>) {
      my $dir = 0;
      my $snmp = 0;
      my $event = 0;
      if($_ =~ m/^#.*/) {
        # ignore comments
      }
      else {
        $_ =~ s/\n//;
        @item = split(/\t/,$_);

        $dir = $item[0];
        $snmp = $item[1];
        $event = $item[2];	  

        if($DEBUG) {
          print "Direction: " , $dir , "\n";
          print "SNMP: " , $snmp , "\n";
          print "Event: " , $event , "\n";	  
        }	
	 
	 	# Print out a complete metadata block for 
		# each line in the conf file
	 
        print FILE "  <nmwg:metadata id=\"" , $ip , "-" , $snmp , "-" , $index , "\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
        print FILE "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"" , $host , $idCounter , "\">\n";
        print FILE "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
        print FILE "        <nmwgt:ifAddress type=\"ipv4\">" , $ip , "</nmwgt:ifAddress>\n";
        print FILE "        <nmwgt:hostName>" ,$host , "</nmwgt:hostName>\n";
        print FILE "        <nmwgt:ifName>" , $if , "</nmwgt:ifName>\n";
        print FILE "        <nmwgt:ifIndex>" , $index , "</nmwgt:ifIndex>\n";
        print FILE "        <nmwgt:direction>" , $dir , "</nmwgt:direction>\n";
        print FILE "        <nmwgt:capacity>" , $speed , "</nmwgt:capacity>\n";
        print FILE "      </nmwgt:interface>\n";
        print FILE "    </netutil:subject>\n";
        print FILE "    <nmwg:eventType>" , $snmp , "</nmwg:eventType>\n";
        print FILE "    <nmwg:parameters id=\"1\">\n";
        print FILE "      <nmwg:parameter name=\"eventType\" value=\"" , $event , "\" />\n";
        print FILE "    </nmwg:parameters>\n";
        print FILE "  </nmwg:metadata>\n";
  
        $idCounter++;
        print FILE "\n";	  
      }
    }
    close(CONF);      
  }
  
}
close(IFCFG);

print FILE "</nmwg:store>\n";

close(FILE);

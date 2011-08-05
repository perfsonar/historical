#!/bin/sh

# Default gateway to the world
DEFAULT_GW=192.17.18.33

# The 10Ge and 1Gb names that would match that given as -B <device FQDN>, -s <src FQDN> and -c <dst FQDN>
TEN_G_FQDN=osgpfsr.hep.uiuc.edu
ONE_G_FQDN=osgx4.hep.uiuc.edu

# The 10Ge and 1Gb devices to be used when setting a route to a host
TEN_G_DEV=eth2
ONE_G_DEV=eth1

# This file has a list of 10Ge hosts as would match that given as by -s [<src FQDN>] or -c [<dst FQDN>]
TEN_G_HOSTS=/usr/local/perfsonar/ten-g-hosts.txt

# Turn logging messages on/off
#LOGGING=0
LOGGING=1



# This script takes a bwctl command line, examines it for a 10Ge source/destination host
# It then modifies the command line to either use the 10Ge or 1Gb network interface
# It also adds a "route" to the source/destination host via the appropriate network interface

# The command line should be of the form
#
# bwctl -T iperf -e local5 -p -B <device FQDN> -rvv -I 14400 -t <time> -d <log> -s <src FQDN> -c [<dst FQDN>]:4823
# bwctl -T iperf -e local5 -p -B <device FQDN> -rvv -I 14400 -t <time> -d <log> -s [ src FQDN ]:4823 -c <dst FQDN>
#
# The script compares the -s [<src FQDN>] or -c [<dst FQDN>] against those listed in the file specified by $TEN_G_HOSTS


# Replace the current bwctl with the following, assuming bwctl.sh is located in /usr/local/perfsonar
#
# mv /usr/bin/bwctl /usr/bin/bwctl.bin
# ln -s /usr/local/perfsonar/bwctl.sh /usr/bin/bwctl
# chmod 755 /usr/local/perfsonar/bwctl.sh

# Change/add the following to /etc/sudoers
#
#       #Defaults    requiretty
#       perfsonar    ALL=(ALL) NOPASSWD: /sbin/route


# It is also useful to add the following to /etc/syslog.conf for logging
#
#       local5.*        /var/log/perfsonar/bwctl.log




# Make it easy for logging
function mylog() {

   if [ $LOGGING -eq 1 ]; then
      logger -t bwctl.sh -p local5.info "$*"
   fi

}



# Get the command line for bwctl
CMD_LINE=$*


# Extract the target host name which should be either -s [<src FQDN>] or -c [<dst FQDN>]
HOST_TARGET=`echo $CMD_LINE | cut -f2 -d "[" | cut -f1 -d "]"`


# Start out assuming the target is a 1Gb host
TEN_G_TARGET=0


# See if any of the listed 10Ge hosts are in the given command line
grep -q -x $HOST_TARGET $TEN_G_HOSTS

if [ $? -eq 0 ]; then
   TEN_G_TARGET=1
fi


# Kill the route to the host if one exists
sudo route del -host $HOST_TARGET 2> /dev/null


# Switch from 1G to 10G or 10G to 1G depending on the target host speed
# Define the route to the host using the appropriate device

if [ $TEN_G_TARGET -eq 0 ]; then
    NEW_LINE=`echo "$CMD_LINE" | sed -e "s/-B $TEN_G_FQDN/-B $ONE_G_FQDN/" -e "s/-s $TEN_G_FQDN/-s $ONE_G_FQDN/" -e "s/-c $TEN_G_FQDN/-c $ONE_G_FQDN/" -`
    sudo route add -host $HOST_TARGET gw $DEFAULT_GW dev $ONE_G_DEV
    mylog "Create  1Gb route ($ONE_G_DEV) for $HOST_TARGET"
else
    NEW_LINE=`echo "$CMD_LINE" | sed -e "s/-B $ONE_G_FQDN/-B $TEN_G_FQDN/" -e "s/-s $ONE_G_FQDN/-s $TEN_G_FQDN/" -e "s/-c $ONE_G_FQDN/-c $TEN_G_FQDN/" -`
    sudo route add -host $HOST_TARGET gw $DEFAULT_GW dev $TEN_G_DEV
    mylog "Create 10Ge route ($TEN_G_DEV) for $HOST_TARGET"
fi


#mylog "Old command: $CMD_LINE"
#mylog "New command: $NEW_LINE"

# Execute the bwctl with the new set of arguments
exec /usr/bin/bwctl.bin $NEW_LINE


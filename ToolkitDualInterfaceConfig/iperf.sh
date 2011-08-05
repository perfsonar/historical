#!/bin/sh

# Default gateway to the world
DEFAULT_GW=192.17.18.33

# The 10Ge and 1Gb names that would match that given as -B <device IP>
TEN_G_IP=192.17.18.43
ONE_G_IP=192.17.18.41

# The 10Ge and 1Gb devices to be used when setting a route to a host
TEN_G_DEV=eth2
ONE_G_DEV=eth1

# Turn logging messages on/off
#LOGGING=0
LOGGING=1



# This script takes a iperf command line, examines to see if this is a client test (iperf -c <client IP>)
# If "-c" is found, the "client IP" is extracted and a "route" is made for this IP via the "device IP" network interface
# If "-c" is not found, the command is executed "as is"
#
# The command line should be of the form
#
# iperf -c <client IP> -B <device IP> -f b -m -p <port> -t <time>
# iperf -B <device IP> -s -f b -m -p <port> -t <time>
# iperf -v
#

# Replace the current iperf with the following, assuming iperf.sh is located in /usr/local/perfsonar
#
# mv /usr/bin/iperf /usr/bin/iperf.bin
# ln -s /usr/local/perfsonar/iperf.sh /usr/bin/iperf
# chmod 755 /usr/local/perfsonar/iperf.sh


# Change/add the following to /etc/sudoers
#
#	#Defaults    requiretty
#	bwctl        ALL=(ALL) NOPASSWD: /sbin/route


# It is also useful to add the following to /etc/syslog.conf for logging
#
#	local6.*	/var/log/perfsonar/iperf.log




# Make it easy for logging
function mylog() {

   if [ $LOGGING -eq 1 ]; then
      logger -t iperf.sh -p local6.info "$*"
   fi

}


# Get the command line for iperf
CMD_LINE=$*


# If this is a client iperf, create a route, otherwise just execute the command
echo $CMD_LINE | grep -q -e "^\-c "

if [ $? -eq 0 ]; then

   mylog "Client: $CMD_LINE"

   # Extract the client and device IP

   CLIENT_IP=`echo $CMD_LINE | cut -f2 -d " "`
   DEVICE_IP=`echo $CMD_LINE | cut -f4 -d " "`

   # Get the time the test will run from -t <time>

   RUN_TIME=`echo $CMD_LINE | cut -f11 -d " "`


   # Assume the route is already defined

   DEL_ROUTE=0


   # See if this route already exists and if not create it

   route -n | grep -q -e "^$CLIENT_IP "
   
   if [ $? -ne 0 ]; then

      if [ $DEVICE_IP = $TEN_G_IP ]; then
         sudo route add -host $CLIENT_IP gw $DEFAULT_GW dev $TEN_G_DEV
         mylog "Create 10Ge route ($TEN_G_DEV) for $CLIENT_IP"
         DEL_ROUTE=1
      fi

      if [ $DEVICE_IP = $ONE_G_IP ]; then
         sudo route add -host $CLIENT_IP gw $DEFAULT_GW dev $ONE_G_DEV
         mylog "Create  1Gb route ($ONE_G_DEV) for $CLIENT_IP"
         DEL_ROUTE=1
      fi
   fi

   # if we created the route, create a script to remove it

   if [ $DEL_ROUTE -eq 1 ]; then

      # Create a file to delete the route
      rm -f /tmp/route-$CLIENT_IP-$DEVICE_IP.sh
      cat <<EOF>>/tmp/route-$CLIENT_IP-$DEVICE_IP.sh
#!/bin/sh
sleep $(($RUN_TIME+10))
sudo route del -host $CLIENT_IP 2> /dev/null
[ $LOGGING -eq 1 ] && logger -t iperf.sh -p local6.info "Delete route for $CLIENT_IP"
rm -f /tmp/route-$CLIENT_IP-$DEVICE_IP.sh
EOF
 
      # Execute it in the background
      sh /tmp/route-$CLIENT_IP-$DEVICE_IP.sh &

   fi

else

   mylog "Server: $CMD_LINE"

fi


#mylog "exec /usr/bin/iperf.bin $CMD_LINE"

# Execute the iperf command as given but exec to keep the pid
exec /usr/bin/iperf.bin $CMD_LINE


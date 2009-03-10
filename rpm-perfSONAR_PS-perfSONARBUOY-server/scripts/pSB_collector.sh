#!/bin/sh
# $Id$
#
# rc.d script to start bwcollector.pl
#
# chkconfig: 2345 60 20
# description: perfSONAR-BUOY Measurement Collector

TOOL="pSB Collector"
PREFIX=/usr/lib/perfsonar/services/perfSONAR-BUOY/server
CONF_PREFIX=/etc/perfSONAR-BUOY
TOOL_EXE=${PREFIX}/bin/bwcollector.pl

cmd="$TOOL_EXE -c $CONF_PREFIX "

case "$1" in
start)
        [ -x $TOOL_EXE ] && $cmd && echo 'perfSONAR-BUOY Measurement Collector Daemon Started'
	if [ $? != 0 ]; then
		echo "Couldn't start perfSONAR-BUOY Measurement Collector Daemon"
	fi
        ;;
stop)
        [ -x $TOOL_EXE ] && $cmd -k && echo 'perfSONAR-BUOY Measurement Collector Daemon Stopped'
	if [ $? != 0 ]; then
		echo "Couldn't stop perfSONAR-BUOY Measurement Collector Daemon"
	fi
        ;;
restart)
	# try a HUP, and then kill/start if not
        [ -x $TOOL_EXE ] && $cmd -h && echo 'perfSONAR-BUOY Measurement Collector Daemon Restarted'
	if [ $? != 0 ]; then
        	[ -x $TOOL_EXE ] && $cmd -k && echo 'perfSONAR-BUOY Measurement Collector Daemon Stopped'
        	[ -x $TOOL_EXE ] && $cmd && echo 'perfSONAR-BUOY Measurement Collector Daemon Started'

		if [ $? != 0 ]; then
			echo "Couldn't start perfSONAR-BUOY Measurement Collector Daemon"
		fi
	fi

        ;;
*)
        echo "Usage: `basename $0` {start|stop}" >&2
        ;;
esac

exit 0

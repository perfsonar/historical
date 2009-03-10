#!/bin/sh
# $Id$
#
# rc.d script to start bwmaster.pl
#
# chkconfig: 2345 60 20
# description: perfSONAR-BUOY Measurement Master

TOOL="pSB Master"
PREFIX=/usr/lib/perfsonar/services/perfSONAR-BUOY/client
CONF_PREFIX=/etc/perfSONAR-BUOY
TOOL_EXE=${PREFIX}/bin/bwmaster.pl

# probably need to add a '-n node' into cmd
# (unless specified by a HOST block in config file)
cmd="$TOOL_EXE -c $CONF_PREFIX "

case "$1" in
start)
        [ -x $TOOL_EXE ] && $cmd && echo 'perfSONAR-BUOY Master Started'
	if [ $? != 0 ]; then
		echo "Couldn't start perfSONAR-BUOY Collection Master"
	fi
        ;;
stop)
        [ -x $TOOL_EXE ] && $cmd -k && echo ' perfSONAR-BUOY Master Stopped'
	if [ $? != 0 ]; then
		echo "Couldn't stop perfSONAR-BUOY Collection Master"
	fi
        ;;
restart)
        [ -x $TOOL_EXE ] && $cmd -h && echo ' perfSONAR-BUOY Master restarted'
	if [ $? != 0 ]; then
        	[ -x $TOOL_EXE ] && $cmd -k && echo ' perfSONAR-BUOY Master Stopped'
        	[ -x $TOOL_EXE ] && $cmd && echo ' perfSONAR-BUOY Master Started'

		if [ $? != 0 ]; then
			echo "Couldn't start perfSONAR-BUOY Master"
		fi
	fi

        ;;
*)
        echo "Usage: `basename $0` {start|stop}" >&2
        ;;
esac

exit 0
	fi
        ;;
*)
        echo "Usage: `basename $0` {start|stop}" >&2
        ;;
esac

exit 0

#!/bin/bash
#
# Init file for perfSONAR-BUOY MA Daemon
#
# chkconfig: 2345 60 20
# description: perfSONAR perfSONAR-BUOY MA Daemon
#

TOOL="pSB"
PREFIX=/usr/lib/perfsonar/services/perfSONAR-BUOY/server
CONF_PREFIX=/etc/perfSONAR-BUOY
TOOL_EXE=${PREFIX}/bin/perfsonar-daemon.pl
TOOL_CONF=${CONF_PREFIX}/pSB_MA.conf
TOOL_LOGGER=${CONF_PREFIX}/pSB_MA_logger.conf
PIDDIR=/var/run
PIDFILE=pSB_MA.pid
USER=perfsonar
GROUP=perfsonar

CMD="${TOOL_EXE} --config ${TOOL_CONF} --logger=${TOOL_LOGGER} --piddir=${PIDDIR} --pidfile=${PIDFILE} --user=${USER} --group=${GROUP}"

# bring in NPT functions for later use
ENV="env -i PATH=/lib/init:/bin:/sbin:/usr/bin"

[ ! -d $PIDDIR ] && mkdir $PIDDIR

ERROR=0
ARGV="$@"
if [ "x$ARGV" = "x" ] ; then 
    ARGS="help"
fi

for ARG in $@ $ARGS
do
    # check for pidfile
    if [ -f $PIDDIR/$PIDFILE ] ; then
	PID=`cat $PIDDIR/$PIDFILE`
	if [ "x$PID" != "x" ] && kill -0 $PID 2>/dev/null ; then
	    STATUS="$TOOL (pid $PID) running"
	    RUNNING=1
	else
	    STATUS="$TOOL (pid $PID?) not running"
	    RUNNING=0
	fi
    else
	STATUS="$TOOL (no pid file) not running"
	RUNNING=0
    fi

    case $ARG in
    start)
	if [ $RUNNING -eq 1 ]; then
	    echo "$0 $ARG: $TOOL (pid $PID) already running"
	    continue
	fi

	echo $CMD

	if $CMD ; then
	    echo "$0 $ARG: $TOOL started"
	else
	    echo "$0 $ARG: $TOOL could not be started"
	    ERROR=3
	fi
	;;
    stop)
	if [ $RUNNING -eq 0 ]; then
	    echo "$0 $ARG: $STATUS"
	    continue
	fi
	if kill $PID ; then
	    echo "$0 $ARG: $TOOL stopped"
	else
	    echo "$0 $ARG: $TOOL could not be stopped"
	    ERROR=4
	fi
	;;
    restart)
    	$0 stop; echo "waiting..."; sleep 10; $0 start;
	;;
    *)
	echo "usage: $0 (start|stop|restart|help)"
	cat <<EOF

start      - start $TOOL
stop       - stop $TOOL
restart    - restart $TOOL if running by sending a SIGHUP or start if 
             not running
help       - this screen

EOF
	ERROR=2
    ;;

    esac

done

exit $ERROR

source /etc/default/ls_registration_daemon

function is_ls_registration_agent_running() {
	if [ -f ${PIDFILE} ]; then
		PID=`cat ${PIDFILE}`
		if [ "x$PID" != "x" ] && kill -0 $PID 2>/dev/null ; then
			return 1;
		fi
	fi

	return 0;
}

function send_ls_agent_msg() {
	if [ is_ls_registration_agent_running -eq 1 ]; then
		echo "$1 $2 $3" > ${NAMEDPIPE}
	fi
}

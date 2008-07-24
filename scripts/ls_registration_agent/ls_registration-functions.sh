source /etc/default/ls_registration_daemon

function is_ls_registration_agent_running() {
	if [ -f ${PIDFILE} ]; then
		PID=`cat ${PIDFILE}`
		if [ "x$PID" != "x" ] && kill -0 $PID 2>/dev/null ; then
			IS_LS_AGENT_RUNNING=1; return;
		fi
	fi

	IS_LS_AGENT_RUNNING=0
}

function send_ls_agent_msg() {
	is_ls_registration_agent_running
	if [ $IS_LS_AGENT_RUNNING -eq 1 ]; then
		echo "$1 $2 $3" > ${NAMEDPIPE}
	fi
}

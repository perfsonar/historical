#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]]; then
    MAKEROOT="sudo "
fi

$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

$MAKEROOT mkdir -p /var/log/perfsonar_status
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar_status

$MAKEROOT mkdir -p /var/lib/perfsonar_status
$MAKEROOT chown perfsonar:perfsonar /var/lib/perfsonar_status

if [ ! -f /var/lib/perfsonar_status/status.db ]; then
	$MAKEROOT sh `$dirname $0`/psCreateStatusDB --type sqlite --file /var/lib/perfsonar_status/status.db
	$MAKEROOT chown perfsonar:perfsonar /var/lib/perfsonar_status/status.db
fi

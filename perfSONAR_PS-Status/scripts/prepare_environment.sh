#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]]; then
    MAKEROOT="sudo "
fi

$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

$MAKEROOT mkdir -p /var/log/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar

$MAKEROOT mkdir -p /var/lib/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/lib/perfsonar

if [ ! -f /var/lib/perfsonar/status.db ];
then
	$MAKEROOT `dirname $0`/psCreateStatusDB --type sqlite --file /var/lib/perfsonar/status.db
	$MAKEROOT chown perfsonar:perfsonar /var/lib/perfsonar/status.db
fi

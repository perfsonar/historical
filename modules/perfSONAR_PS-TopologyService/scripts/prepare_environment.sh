#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]]; then
    MAKEROOT="sudo "
fi

$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

$MAKEROOT mkdir -p /var/log/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar

$MAKEROOT mkdir -p /var/lib/topology_service
$MAKEROOT chown perfsonar:perfsonar /var/lib/topology_service
$MAKEROOT cp `dirname $0`/../doc/DB_CONFIG /var/lib/topology_service

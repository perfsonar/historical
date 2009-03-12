#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]];
then
    MAKEROOT="sudo "
fi

$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

$MAKEROOT mkdir -p /var/log/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar

$MAKEROOT mkdir -p /var/lib/perfsonar/lookup_service/xmldb
if [ ! -f /var/lib/perfsonar/lookup_service/xmldb/DB_CONFIG ];
then
    $MAKEROOT `dirname $0`/../scripts/psCreateLookupDB --directory /var/lib/perfsonar/lookup_service/xmldb
fi

$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar/lookup_service

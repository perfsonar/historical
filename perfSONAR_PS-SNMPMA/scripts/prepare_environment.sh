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


$MAKEROOT mkdir -p /var/lib/perfsonar/snmp_ma
if [ ! -f /var/lib/perfsonar/snmp_ma/store.xml ];
then
    $MAKEROOT `dirname $0`/../scripts/makeStore.pl /var/lib/perfsonar/snmp_ma 1
fi

$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar/snmp_ma

$MAKEROOT ln -s /opt/perfsonar_ps/snmp_ma/scripts/snmp_ma /etc/init.d/snmp_ma

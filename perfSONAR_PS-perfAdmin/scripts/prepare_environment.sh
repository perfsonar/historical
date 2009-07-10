#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]];
then
    MAKEROOT="sudo "
fi

DIRECTORY=`dirname "$0"`

$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

$MAKEROOT mkdir -p /var/log/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar

$MAKEROOT mkdir -p /var/lib/perfsonar/perfAdmin/cache
$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar/perfAdmin

$MAKEROOT mv $DIRECTORY/perfAdmin.cron /etc/cron.d
$MAKEROOT chown root:root /etc/cron.d/perfAdmin.cron
$MAKEROOT chmod 600 /etc/cron.d/perfAdmin.cron

$MAKEROOT mv $DIRECTORY/perfAdmin.conf /etc/httpd/conf.d
$MAKEROOT chown root:root /etc/httpd/conf.d/perfAdmin.conf
$MAKEROOT chmod 644 /etc/httpd/conf.d/perfAdmin.conf

$MAKEROOT mkdir -p /opt/perfsonar_ps/perfAdmin
$MAKEROOT mv $DIRECTORY/../bin /opt/perfsonar_ps/perfAdmin
$MAKEROOT mv $DIRECTORY/../cgi-bin /opt/perfsonar_ps/perfAdmin
$MAKEROOT mv $DIRECTORY/../doc /opt/perfsonar_ps/perfAdmin
$MAKEROOT mv $DIRECTORY/../etc /opt/perfsonar_ps/perfAdmin
$MAKEROOT mv $DIRECTORY/../lib /opt/perfsonar_ps/perfAdmin
$MAKEROOT chown -R perfsonar:perfsonar /opt/perfsonar_ps/perfAdmin
$MAKEROOT chown -R apache:apache /opt/perfsonar_ps/perfAdmin/etc

$MAKEROOT /etc/init.d/crond restart
$MAKEROOT /etc/init.d/httpd restart

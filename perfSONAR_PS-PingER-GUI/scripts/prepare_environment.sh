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

$MAKEROOT mkdir -p /var/lib/perfsonar
$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar

$MAKEROOT mv $DIRECTORY/pinger_cache.cron /etc/cron.d
$MAKEROOT chown root:root /etc/cron.d/pinger_cache.cron
$MAKEROOT chmod 600 /etc/cron.d/pinger_cache.cron

$MAKEROOT mv $DIRECTORY/pinger_gui.conf /etc/httpd/conf.d
$MAKEROOT chown root:root /etc/httpd/conf.d/pinger_gui.conf
$MAKEROOT chmod 644 /etc/httpd/conf.d/pinger_gui.conf

$MAKEROOT mkdir -p /opt/perfsonar_ps/PingER-GUI
$MAKEROOT mv $DIRECTORY/../bin /opt/perfsonar_ps/PingER-GUI
$MAKEROOT mv $DIRECTORY/../doc /opt/perfsonar_ps/PingER-GUI
$MAKEROOT mv $DIRECTORY/../lib /opt/perfsonar_ps/PingER-GUI
$MAKEROOT mv $DIRECTORY/../root /opt/perfsonar_ps/PingER-GUI
$MAKEROOT chown -R perfsonar:perfsonar /opt/perfsonar_ps/PingER-GUI
$MAKEROOT chown -R apache:apache /opt/perfsonar_ps/PingER-GUI/root

$MAKEROOT /etc/init.d/crond restart
$MAKEROOT /etc/init.d/httpd restart

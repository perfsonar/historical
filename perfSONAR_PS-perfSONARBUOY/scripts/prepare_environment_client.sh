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

$MAKEROOT mkdir -p /var/lib/perfsonar/perfsonarbuoy_ma
$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar/perfsonarbuoy_ma

$MAKEROOT ln -s /opt/perfsonar_ps/perfsonarbuoy_ma/scripts/perfsonarbuoy_owp_master /etc/init.d/perfsonarbuoy_owp_master
$MAKEROOT ln -s /opt/perfsonar_ps/perfsonarbuoy_ma/scripts/perfsonarbuoy_bw_master /etc/init.d/perfsonarbuoy_bw_master

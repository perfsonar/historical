#!/bin/bash

MAKEROOT=""
if [[ $EUID -ne 0 ]];
then
    MAKEROOT="sudo "
fi

echo "Adding 'perfsonar' user and group..."
$MAKEROOT /usr/sbin/groupadd perfsonar 2> /dev/null || :
$MAKEROOT /usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

echo "Creating '/var/log/perfsonar'..."
$MAKEROOT mkdir -p /var/log/perfsonar
$MAKEROOT chown perfsonar:perfsonar /var/log/perfsonar

echo "Creating '/var/lib/perfsonar/traceroute_ma'..."
$MAKEROOT mkdir -p /var/lib/perfsonar/traceroute_ma/upload
$MAKEROOT chown -R perfsonar:perfsonar /var/lib/perfsonar/traceroute_ma

echo "Linking init scripts..."
$MAKEROOT ln -s /opt/perfsonar_ps/traceroute_ma/scripts/traceroute_master /etc/init.d/traceroute_master
$MAKEROOT ln -s /opt/perfsonar_ps/traceroute_ma/scripts/traceroute_scheduler /etc/init.d/traceroute_scheduler
$MAKEROOT ln -s /opt/perfsonar_ps/traceroute_ma/scripts/traceroute_ondemand_mp /etc/init.d/traceroute_ondemand_mp

echo "Running chkconfig..."
$MAKEROOT /sbin/chkconfig --add traceroute_master
$MAKEROOT /sbin/chkconfig --add traceroute_scheduler
$MAKEROOT /sbin/chkconfig --add traceroute_ondemand_mp

echo "Removing temporary files..."
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/dependencies
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/modules.rules
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/scripts/install_dependencies.sh
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/scripts/prepare_environment_client.sh

echo "Exiting prepare_environment.sh"

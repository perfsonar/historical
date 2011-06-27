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

echo "Linking init scripts..."
$MAKEROOT ln -s /opt/perfsonar_ps/traceroute_ma/scripts/traceroute_ma /etc/init.d/traceroute_ma
$MAKEROOT ln -s /opt/perfsonar_ps/traceroute_ma/scripts/traceroute_collector /etc/init.d/traceroute_collector

echo "Running chkconfig..."
$MAKEROOT /sbin/chkconfig --add traceroute_ma
$MAKEROOT /sbin/chkconfig --add traceroute_collector

echo "Starting traceroute MA..."
$MAKEROOT /etc/init.d/traceroute_ma start

echo "Starting traceroute Collector..."
$MAKEROOT /etc/init.d/traceroute_collector start

echo "Removing temporary files..."
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/dependencies
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/modules.rules
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/scripts/install_dependencies.sh
$MAKEROOT rm -f /opt/perfsonar_ps/traceroute_ma/scripts/prepare_environment_server.sh

echo "Exiting prepare_environment.sh"


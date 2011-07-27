#!/bin/bash

# Since this script isn't harmful if it's run on an upgraded installation, run
# the commands no matter what version.

# Make sure the log directories are all correct
mkdir -p /var/log/perfsonar
chown -R perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/log/cacti
chown -R apache /var/log/cacti

mkdir -p /var/log/perfsonar/web_admin
chown -R apache:perfsonar /var/log/perfsonar/web_admin

# Make sure that the various /var/lib/perfsonar directories are correct.
mkdir -p /var/lib/perfsonar
chown -R perfsonar:perfsonar /var/lib/perfsonar

mkdir -p /var/lib/perfsonar/snmp_ma
chown -R perfsonar:perfsonar /var/lib/perfsonar/snmp_ma

mkdir -p /var/lib/perfsonar/perfsonarbuoy_ma/bwctl
mkdir -p /var/lib/perfsonar/perfsonarbuoy_ma/owamp
chown -R perfsonar:perfsonar /var/lib/perfsonar/perfsonarbuoy_ma

mkdir -p /var/lib/perfsonar/lookup_service/xmldb
chown -R perfsonar:perfsonar /var/lib/perfsonar/lookup_service

# Make sure that /var/lib/owamp is owned by the owamp user
chown -R owamp:owamp /var/lib/owamp

# Toolkit odds and ends
mkdir -p /var/run/web_admin_sessions
chown -R apache /var/run/web_admin_sessions

chown -R apache /var/lib/cacti/rra

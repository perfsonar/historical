#!/bin/bash
#
# Beginnings of an upgrade script for existing toolkit installations

STORE_LOCATION=
LIVE_LOCATION=
STORE_VERSION=

while getopts  "l:s:v:" flag
do
    case "$flag" in
        l) LIVE_LOCATION=$OPTARG;;
        s) STORE_LOCATION=$OPTARG;;
        v) STORE_VERSION=$OPTARG;;
    esac
done

TOOLKIT_VERSION=`/opt/perfsonar_ps/toolkit/scripts/NPToolkit.version`

# Only upgrade the databases if we're running a different toolkit version
if [ "$STORE_VERSION" != "$TOOLKIT_VERSION" ]; then
    /opt/perfsonar_ps/toolkit/scripts/initialize_databases
fi

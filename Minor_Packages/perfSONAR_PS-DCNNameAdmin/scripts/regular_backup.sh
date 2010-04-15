#!/bin/bash

BASE=`dirname $0`
BACKUP_LOCATION=/var/lib/DCN/
BACKUP_FILE=friendly_names.csv

mkdir -p $BACKUP_LOCATION

$BASE/../bin/dcn_dump > $BACKUP_LOCATION/$BACKUP_FILE 2> /dev/null

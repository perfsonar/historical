#! /bin/sh -x
ADD_DATA_DIR="/home/netadmin/new_pinger/data_MA"
export ADD_DATA_DIR
BINDIR="/home/netadmin/new_pinger/bin" 
export  BINDIR

PING_GATHER_CMD="$BINDIR/pings_gather_fine.pl"
export PING_GATHER_CMD

PING_ADD_CMD="$BINDIR/add_2pinger_MA.pl"
export PING_ADD_CMD

BUILD_MA_CMD="$BINDIR/build_pingerStore.pl"
export BUILD_MA_CMD

GATHER_LIST="/home/netadmin/new_pinger/data/gather_list.txt"

$PING_GATHER_CMD -i $ADD_DATA_DIR -s $GATHER_LIST -t 80

$PING_ADD_CMD -i $ADD_DATA_DIR -m  

$BUILD_MA_CMD

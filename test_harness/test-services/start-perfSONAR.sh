#!/bin/sh

export PSHOME=/usr/local/perfSONAR-PS

#export LD_LIBRARY_PATH=/usr/local/dbxml-2.3.10/lib
#export PATH=$PATH:/usr/local/dbxml-2.3.10/bin

export PERL5LIB=$PSHOME/lib

$PSHOME/perfsonar-daemon.pl --config=perfSONAR.conf --logger=logger.conf &

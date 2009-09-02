#!/bin/bash

BASE=$1
VER=`/bin/uname -m`
echo "Linking for $VER"
if [ -d $BASE ]
then
if [ $VER = 'x86_64' ] 
then
  /bin/ln -s  $BASE/lib/ChartDirector/lib/libchartdirx86_64.so  $BASE/lib/ChartDirector/lib/libchartdir.so
else
  /bin/ln -s  $BASE/lib/ChartDirector/lib/libchartdiri386.so  $BASE/lib/ChartDirector/lib/libchartdir.so
fi
else
echo " $BASE does not exist, failed !!!"
fi

#!/bin/env  bash

 
XMLROOT=$(xml2-config  --prefix)
if [ -z $XMLROOT   ]
then
echo " libxml2 libraries must be installed on building host "
exit
fi  
 
XMLLIB_SO="$XMLROOT/lib/libxml2.so.2"
XMLLIB_A="$XMLROOT/lib/libxml2.a"


MODULE=perfSONARBUOY

EXECNAME=perfsonarbuoy 
echo "Building executable $EXECNAME  for $MODULE MA and MP"
 
COM="pp -I lib/ -M DBD::mysql -M  Sleepycat::DbXml  -M DBD::SQLite -M perfSONAR_PS::Services::LS  \
 -M perfSONAR_PS::Services::Echo -M  perfSONAR_PS::Request \
 -M perfSONAR_PS::RequestHandler  -M perfSONAR_PS::DB::RRD \
 -M perfSONAR_PS::DB::File  -M perfSONAR_PS::DB::XMLDB \
 -M perfSONAR_PS::DB::SQL \
 -M fields \
 -M perfSONAR_PS::Services::MA::$MODULE \
 -l  $XMLLIB_A  \
 -l  $XMLLIB_SO  \
 -o $EXECNAME  perfsonar-daemon.pl"

echo -e " Building ... \n  $COM  \n "
$COM

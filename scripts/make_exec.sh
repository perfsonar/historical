#!/bin/env  bash

 
tolower()
{
local char="$*"

out=$(echo $char | tr [:upper:] [:lower:])
local retval=$?
echo "$out"
unset out
unset char
return $retval
}


XMLLIB=$(xml2-config  --libtool-libs)
if [ -z $XMLLIB  ]
then
echo " libxml2 libraries must be installed on building host "
exit
fi  

MODULE=$1

if ( [ ! -e "../lib/perfSONAR_PS/Services/MA/$MODULE.pm" ] || [ !  -e "../lib/perfSONAR_PS/Services/MP/$MODULE.pm" ] )
then
echo " Usage: make_exec.sh <service module name  - for example PingER> "
echo "        for service XXX it checks  module  ../lib/perfSONAR_PS/Services/M[PA]/XXX.pm "
exit
fi

EXECNAME=$(tolower $MODULE) 
echo "Building executable ps-$EXECNAME  for $MODULE MA and MP"

COM="pp -I ../lib/ -M DBD::mysql  -M perfSONAR_PS::Services::LS  \
 -M perfSONAR_PS::Services::Echo -M  perfSONAR_PS::Request \
 -M perfSONAR_PS::RequestHandler  -M perfSONAR_PS::DB::RRD \
 -M perfSONAR_PS::DB::File  -M perfSONAR_PS::DB::XMLDB \
 -M perfSONAR_PS::DB::SQL -M perfSONAR_PS::DB::SQL::PingER \
 -M fields -M DateTime::Locale::en  \
 -M perfSONAR_PS::Services::MP::$MODULE  \
 -M perfSONAR_PS::Services::MA::$MODULE \
 -l  $XMLLIB  \
 -o ps-$EXECNAME  ../perfsonar-daemon.pl"

echo -e " Building ... \n  $COM  \n "
$COM

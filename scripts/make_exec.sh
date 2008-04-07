#!/bin/env  sh

 
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


MODULE=$1
EXECNAME=$(tolower $MODULE) 
echo "Building executable ps-$EXECNAME  for $MODULE MA and MP"

pp -I ../lib/ -M DBD::mysql  -M perfSONAR_PS::Services::LS  \
 -M perfSONAR_PS::Services::Echo -M  perfSONAR_PS::Request \
 -M  perfSONAR_PS::RequestHandler  -M perfSONAR_PS::DB::RRD \
 -M perfSONAR_PS::DB::File  -M perfSONAR_PS::DB::XMLDB \
 -M perfSONAR_PS::DB::SQL -M perfSONAR_PS::DB::SQL::PingER \
 -M fields -M DateTime::Locale::en  \
 -M perfSONAR_PS::Services::MP::$MODULE  \
 -M perfSONAR_PS::Services::MA::$MODULE \
 -o ps-$EXECNAME  ../perfsonar-daemon.pl



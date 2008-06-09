#!/bin/env  bash

 
XMLROOT=$(xml2-config  --prefix)
if [ -z $XMLROOT   ]
then
echo " libxml2 libraries must be installed on building host "
exit
fi  
 
XMLLIB_SO="$XMLROOT/lib/libxml2.so.2"
XMLLIB_A="$XMLROOT/lib/libxml2.a"

EXECNAME=perfsonar-snmp
echo "Building executable $EXECNAME"

COM="pp -I lib/ \
 -M DBD::mysql \
 -M DBD::SQLite \
 -M fields \
 -M base \
 -M Class::Accessor \
 -M constant \
 -M Cwd \
 -M DBI \
 -M Digest::MD5 \
 -M English \
 -M Error::Simple \
 -M Exporter \
 -M Fcntl \
 -M fields \
 -M File::Basename \
 -M FileHandle \
 -M File::Path \
 -M FindBin \
 -M Getopt::Long \
 -M HTTP::Daemon \
 -M IO::File \
 -M IO::Handle \
 -M Log::Log4perl \
 -M Log::Dispatch::Screen \
 -M Log::Dispatch::FileRotate \
 -M Log::Dispatch::Syslog \
 -M Module::Load \
 -M Params::Validate \
 -M POSIX \
 -M Scalar::Util \
 -M Socket \
 -M strict \
 -M Sys::Hostname \
 -M Sys::Syslog \
 -M Term::ReadKey \
 -M Test::More \
 -M Time::HiRes \
 -M vars \
 -M version \
 -M warnings \
 -M XML::LibXML \
 -M perfSONAR_PS::Client::Echo \
 -M perfSONAR_PS::Client::LS::Remote \
 -M perfSONAR_PS::Common \
 -M perfSONAR_PS::DB::File \
 -M perfSONAR_PS::DB::RRD \
 -M perfSONAR_PS::DB::SQL \
 -M perfSONAR_PS::Error::Authn \
 -M perfSONAR_PS::Error::Common \
 -M perfSONAR_PS::Error_compat \
 -M perfSONAR_PS::Error::LS \
 -M perfSONAR_PS::Error::MA \
 -M perfSONAR_PS::Error::Message \
 -M perfSONAR_PS::Error::MP \
 -M perfSONAR_PS::Error \
 -M perfSONAR_PS::Error::Topology \
 -M perfSONAR_PS::EventTypeEquivalenceHandler \
 -M perfSONAR_PS::Messages \
 -M perfSONAR_PS::NetLogger \
 -M perfSONAR_PS::ParameterValidation \
 -M perfSONAR_PS::RequestHandler \
 -M perfSONAR_PS::Request \
 -M perfSONAR_PS::Services::Base \
 -M perfSONAR_PS::Services::Echo \
 -M perfSONAR_PS::Services::MA::General \
 -M perfSONAR_PS::Services::MA::SNMP \
 -M perfSONAR_PS::Time \
 -M perfSONAR_PS::Transport \
 -M perfSONAR_PS::XML::Document \
 -M perfSONAR_PS::XML::Document_string \
 -l  $XMLLIB_A  \
 -l  $XMLLIB_SO  \
 -o $EXECNAME  perfsonar-daemon.pl"

echo -e " Building ... \n  $COM  \n "
$COM

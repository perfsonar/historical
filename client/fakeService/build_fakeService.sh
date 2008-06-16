#!/bin/sh

XMLROOT=$(xml2-config  --prefix)
if [ -z $XMLROOT   ]
then
    echo " libxml2 libraries must be installed on building host "
    exit
fi  

XMLLIB_SO="$XMLROOT/lib/libxml2.so.2"
XMLLIB_A="$XMLROOT/lib/libxml2.a"

EXECNAME=fakeService
echo "Building executable $EXECNAME"
 
COM="pp -I lib/ -M perfSONAR_PS::Client::LS -M perfSONAR_PS::Common \
 -M perfSONAR_PS::Transport -M perfSONAR_PS::Messages \
 -M perfSONAR_PS::Client::Echo -M perfSONAR_PS::ParameterValidation \
 -M perfSONAR_PS::XML::Document -M HTTP::Daemon -M HTTP::Request \
 -M HTTP::Headers -M LWP::UserAgent -M Exporter -M IO::File -M Time::HiRes \
 -M XML::LibXML -M Log::Log4perl -M Params::Validate -M English \
 -M Config::General -M Data::Random::WordList -M fields -M strict -M warnings \
 -l $XMLLIB_A -l $XMLLIB_SO -o $EXECNAME fakeService.pl"

echo -e " Building ... \n  $COM  \n "
$COM


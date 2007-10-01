#!/bin/sh
# ################################################ #
#                                                  #
# Name:		poll_update.sh                     #
# Author:	Aaron Brown                        #
# Contact:	aaron@internet2.edu                #
# Args:		none                               #
# Purpose:	Downloads and loads the specified  #
#               Toplogy MA with the retreived XML  #
#               file. If no changes have occurred, #
#               it does not update the MA.         #
#                                                  #
# ################################################ #


XML_URL=http://dc-1.grnoc.iu.edu/ndl/nmwg/i2_net.xml
MA_URI=http://packrat.internet2.edu:5800/perfSONAR_PS/services/topology
PREV_FILE=./topo.back.xml
TMP_FILE=./topo.`date +%s`.xml
LOG_FILE=./daily_update.`date "+%Y-%m-%d"`.log

wget -O $TMP_FILE -o /dev/null $XML_URL

if [ ! -f $TMP_FILE ]; then
	exit -1;
fi

if [ -f $PREV_FILE ]; then
OLD_MD5=`md5sum $PREV_FILE | cut -f 1 -d " "`;
else
OLD_MD5="";
fi;

NEW_MD5=`md5sum $TMP_FILE | cut -f 1 -d " "`;

if [ "$OLD_MD5" != "$NEW_MD5" ]; then
	./loadDatabase.pl --uri=$MA_URI --out=out.xml $TMP_FILE &> $LOG_FILE
	if [ $? == 0 ]; then
		mv $TMP_FILE $PREV_FILE;
	else
		rm $TMP_FILE;
		exit -1;
	fi
fi

exit 0;

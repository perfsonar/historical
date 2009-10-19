#!/bin/bash

ModListFile="PerlModuleList"
ModName=`cat $ModListFile`

for PerlMod in $ModName
do
PerlModChk="perl -M$PerlMod -e 1"
#echo $PerlModChk
Result=eval $PerlModChk
#echo $Result

	if [ "x$Result" != "x" ]
	then
	echo "$PerlMod not found, installing"
perl -MCPAN -e 'install $PerlMod'
#	InstallCmd="perl -MCPAN -e 'install $PerlMod'"
#	echo "Install Command = $InstallResult"
#	InstallResult=eval $InstallResult
#	echo "Install Result = $InstallResult"
#	else
#	echo "$PerlMod exists"
	fi 
done

#!/bin/bash
echo "FT MA Service";

if [ "$1" == "--help" ]
then
	echo " PerfSONAR-PS MA for File Transfer Service. "
	echo " Please provide any of the following arguments: "
	echo -e " \t --skip-input \t to skip any user interaction."
	echo -e " \t --help \t to display this help screen."
	exit
fi
if [ "$1" == "--skip-input" ]
then
	NoInput=1
else
	NoInput=0
fi
bindir='../bin'
LibScript="./chkAndInstallPerlModules.sh";
Service="FT"
Conf="$bindir/daemon.conf"
Log="$bindir/daemon_logger.conf"
PidFile='ftp.pid'
PidDir="$bindir"
Pid=`cat $PidDir/$PidFile`

while [ 1 == 1 ]
do

	echo "Install Lib?(y/n)"

	if [ $NoInput == 0 ]
	then
		read InstallLib
	else
		InstallLib="n"
	fi

		if [ $InstallLib == "y" ]
		then
			echo "Running Perl Module Installation Script"
#LibResult=eval $LibScript
#echo $LibResult
			$LibScript
			echo "Installation Compelted"
			break
		elif [ $InstallLib == "n" ]
		then
			echo "Skipping Perl Module Installation"
			break
		else
			echo "wrong input"
			continue
		fi
	done


echo "Stopping Previous Running Instance of FT MA";
if [ "x$Pid" != "x" ] 
then

	if  kill $Pid ; then
            echo "Service $Service($Pid) : Stopped"
            ClrPid=`echo  > $PidDir/$PidFile`
	else
	echo "Error stopping Service $Service ($Pid)"
	fi
fi

echo "Backing up Log File"
LogPath=$( cat $Log | grep 'filename' | cut -d= -f 2 | sed 's/^ *//;s/ *$//')
echo "Log Path = $LogPath"
LogDir=$( echo $LogPath | sed 's|\(.*\)/.*|\1|' )
Timestamp=`date +"%m-%d-%y:%H"`
echo $Timestamp
newDir="$LogDir/Ftp_$Timestamp"
if [ -d $newDir ]
then
	echo "Dir Exists : $newDir"
else
	echo "Creating Dir"
	if mkdir $newDir
	then
	echo "Dir Created : $newDir"
	else
	echo "Unable to create dir : $newDir"
	fi
fi
LogFile=`basename $LogPath`
backupLogPath="$newDir/"
moveCommand="mv $LogPath $backupLogPath"

moveResult=eval $moveCommand
if $moveResult 
then
	echo "Backup complete. Old Log File can be found at $backupLogPath"
else
	echo "Error moving log file $moveResult"
fi

echo "Starting a new instance of FT MA";

ExeCommand="perl $bindir/daemon.pl --config=$Conf --logger=$Log --piddir=$PidDir --pidfile=$PidFile"

echo $ExeCommand

ExeResult=eval $ExeCommand

Pid=`cat $PidDir/$PidFile`
ServiceAccessPoint=`cat $Conf | grep 'service_accesspoint' | cut -f 4 | sed -e 's/service_accesspoint//g' -e 's/^\s*//g'`
if [ "x$Pid" != "x" ] && $ExeResult
then
echo "Service($Pid) : Started at $ServiceAccessPoint"
echo 
else
echo "Error Starting Service $Service ($Pid) : $ExeResult"
fi
StartResult=`tail /var/log/perfsonar/ftp.log`
echo $StartResult

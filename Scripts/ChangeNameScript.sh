#!/bin/sh

/usr/local/jamf/bin/jamf setComputerName -useSerialNumber

###Set New Computer Name
###Change CNU to whatever you want your prefix to be.

CompName=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')

echo $CompName
scutil --set HostName "CNU"$CompName
scutil --set LocalHostName "CNU"$CompName
scutil --set ComputerName "CNU"$CompName


##### recon to update JSS
jamf recon
#!/bin/bash

###############################################################
# Jamf Pro Extension Attribute: Jamf Connect Login Installed  #
#                                                             #
# Checks whether Jamf Connect Login is installed by looking   #
# for the JamfConnectLogin.bundle. Returns the version if     #
# installed, or "Not Installed" if the bundle is not present. #
###############################################################

PLIST="/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle/Contents/Info.plist"
KEY="CFBundleShortVersionString"

if [[ -f "${PLIST}" ]]; then
    echo "<result>Installed</result>"
else
    echo "<result>Not Installed</result>"
fi

exit 0

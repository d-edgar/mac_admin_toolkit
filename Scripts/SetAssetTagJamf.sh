#!/bin/sh
#sets the Asset Tag field in Jamf to "Loaner" to identify loaner MacBooks.
sudo jamf recon -skipApps -skipFonts -skipPlugins -assetTag "Loaner"
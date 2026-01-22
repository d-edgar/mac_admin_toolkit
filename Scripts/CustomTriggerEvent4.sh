#!/bin/bash
#This is clever, but basically call whatever event you want with this, so say you
#		have a script that is called with a custom call. Yet you also want 
#		it to call another custom event, you can use this script to do that.
#
#Example: Prestage config over, custom call install_printer, install_printer also calls this script, which
#         calls the driver for the printer. You can also do this via parameters.
/usr/local/jamf/bin/jamf policy -event $4
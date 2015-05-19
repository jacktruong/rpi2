#!/bin/bash
# X session initialization script; configures and initiates kiosk user's X
# session
#
# Created by Desmond Cox
# Original by David Collie
# Modified Dec. 15, 2008, by SMC to just run Opera, but with two screen savers,
#   one pre-login screensaver and one after user activity detected 
# Modified October 26 by JT to work with Firefox and fix the 'user-wakeup' script. Also to disable screen blanking -- really not needed.

# sleep in case things aren't loaded yet, like networking

if [ -f "/home/kiosk/.location" ]; then
	source /home/kiosk/.location
else
	export LOCATION="test"
fi

/bin/sleep 3

# ping the server to let it know the kiosk is awake
/usr/bin/wget -q -O - --spider http://mmm.eng.uwaterloo.ca/~enginfo/enginfo2/alive.php

# prevent screen blanking
/usr/bin/xset s off
/usr/bin/xset dpms 0
/usr/bin/xset s noblank
/usr/bin/xset -dpms   

# hide the mouse cursor
/usr/bin/unclutter -noevents -idle 1 &

# kill former instances of emerge, if they exist
/usr/bin/killall perl

# load the window manager
/usr/bin/icewmbg-lite &
/usr/bin/icewm-lite &

# runs the emerge client
/usr/bin/perl /home/kiosk/emerge.pl &

# start Chrome here so users automatically see it when they start
# some of these args might not work later, the important one is --no-first-run so the import screen is ignored
chromium-browser --kiosk --bwsi --auto-launch-at-startup --disable-extensions --disable-sync --no-first-run http://mmm.eng.uwaterloo.ca/~enginfo/enginfo2/?loc=${LOCATION}

#script exits after chromium closes and loops back to .bash_profile
#!/bin/bash
if [ -f "/home/kiosk/.location" ]; then
	source /home/kiosk/.location
else
	export LOCATION="test"
fi

/usr/bin/wget -q -O - --spider http://mmm.eng.uwaterloo.ca/~enginfo/enginfo2/heartbeat.php?loc=${LOCATION}

exit
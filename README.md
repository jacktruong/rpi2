# Image builder for Raspberry Pi 2

Needs to be run from armhf Raspberry Pi 2 or similar armhf device (untested) running Debian.

The script is a modified version of ShorTie's script found [here](https://www.raspberrypi.org/forums/viewtopic.php?f=66&t=104981).

I noticed there were problems if the script seems to fail so I added in some fail safes. The modified script generates an image that can be dd'd to a SD card later -- don't want to fiddle with /dev/sdX devices.

#!/bin/bash

##################################################################
# Credit goes to ShorTie:
# https://www.raspberrypi.org/forums/viewtopic.php?f=66&t=104981
# https://www.dropbox.com/s/zp60vi3na7xn3lk/my_pi_os.sh
# the script is pretty much a cleaned up version of my_pi_os.sh
###################################################################

## check for root

echo "Checking for root .. "
if [ `id -u` != 0 ]; then
    echo "Script needs to be run as root."
    exit 1
else
    echo "Root user detected"
fi

## checking for installed applications
checking_apps() {
    echo "Checking for necessary programs..."
    APS=""

    echo "Checking for fuser ... "
    if [ `which fuser` ]; then
        echo "psmisc found"
    else
        echo "psmisc not found"
        APS+="psmisc "
    fi

    echo "Checking for ioctl ... "
    if [ -f /usr/include/linux/ioctl.h ]; then
        echo "libc6-dev found"
    else
        echo "libc6-dev not found"
        APS+="libc6-dev "
    fi

    echo "Checking for kpartx ... "
    if [ `which kpartx` ]; then
        echo "kpartx found"
    else
        echo "kpartx not found"
        APS+="kpartx "
    fi

    echo "Checking for partprobe ... "
    if [ `which partprobe` ]; then
        echo "parted found"
    else
        echo "parted not found"
        APS+="parted "
    fi

    echo "Checking for dosfstools ... "
    if [ `which fsck.vfat` ]; then
        echo "dosfstools found"
    else
        echo "dosfstools not found"
        APS+="dosfstools "
    fi

    echo "Checking for cdebootstrap ... "
    if [ `which cdebootstrap` ]; then
        echo "cdebootstrap found"
    else
        echo "cdebootstrap not found"
        APS+="cdebootstrap "
    fi

    ## installing any needed apps

    if [ "$APS" != "" ]; then
        echo "Getting applications"
        apt-get -qq update
        apt-get -y install $APS
    else
        echo "Everything is good, continuing"
    fi
}

## creating disk image
disk_image() {
    MOUNT=0
    IMAGE="rpi2.img"
    echo "Creating a 3GB image"
    if [ -f "$IMAGE" ]; then
        echo "Conflicting image found, start the script again."
        exit
    fi

    dd if=/dev/zero of="$IMAGE" bs=1M count=3000 iflag=fullblock

    (echo o; echo n; echo p; echo 1; echo; echo +40M; echo a; echo t; echo 6; echo n; echo p; echo 2; echo; echo; echo w) | fdisk "$IMAGE"

    fdisk -l "$IMAGE"

    echo "Setting up kpartx drive mapper for $IMAGE and define loopback devices for boot & root"
    LOOP_DEVICE=$(kpartx -av $IMAGE | grep p2 | cut -d" " -f8 | awk '{print$1}')
    if [ ! -e "$LOOP_DEVICE" ]; then
        echo "Loop device is not found."
        exit
    fi

    # $MOUNT has 3 levels, 1 is kpartx partition discovery, 2 is root is mounted, 3 is everything else
    MOUNT=$((MOUNT+1))
    echo "Loop device is $LOOP_DEVICE"
    partprobe $LOOP_DEVICE

    BOOTPART=$(echo $LOOP_DEVICE | grep dev | cut -d"/" -f3 | awk '{print$1}')p1
    BOOTPART=/dev/mapper/$BOOTPART
    ROOTPART=$(echo $LOOP_DEVICE | grep dev | cut -d"/" -f3 | awk '{print$1}')p2
    ROOTPART=/dev/mapper/$ROOTPART
    if [ ! -e "$BOOTPART" -o ! -e "$ROOTPART" ]; then
        echo "Partitions not found"
        unmounting
        exit
    fi

    echo "Boot partition is $BOOTPART"
    echo "Root partition is $ROOTPART"

    ## formatting the partitions

    echo "Formatting the boot partition"
    mkdosfs -n BOOT $BOOTPART

    echo "Formatting the root partition"
    mkfs.ext4 -O ^has_journal -E stride=0,stripe-width=128 -b 4096 -L rootfs $ROOTPART

    sync
}

## bootstrapping a Debian system now
bootstrap() {
    echo "Bootstrapping Debian"

    BOOTSTRAP=$(mktemp -d)
    INCLUDE="--include=kbd,locales,keyboard-configuration,console-setup"
    MIRROR="http://ftp.us.debian.org/debian"
    RELEASE="stable"
    mount -t ext4 -o sync $ROOTPART $BOOTSTRAP
    if [ $? -gt 0 ]; then
        echo "Troubles mounting the system"
        unmounting
        exit
    fi

    MOUNT=$((MOUNT+1))
    echo "Running: cdebootstrap --arch armhf ${RELEASE} $BOOTSTRAP $MIRROR ${INCLUDE} --allow-unauthenticated"
    cdebootstrap --arch armhf ${RELEASE} $BOOTSTRAP $MIRROR ${INCLUDE} --allow-unauthenticated
    if [ $? -gt 0 ]; then
        echo "Problems bootstrapping the OS"
        unmounting
        exit
    fi
    echo "Successfully bootstrapped"
    sync
}
mounting() {
## mounting stuff
    if [ "$MOUNT" != 2 ]; then
        echo "root partition doesn't seem to be mounted"
        unmounting
        exit
    fi
    mount -t vfat -o sync $BOOTPART $BOOTSTRAP/boot
    mount -t proc proc $BOOTSTRAP/proc
    mount -t sysfs sysfs $BOOTSTRAP/sys
    mount --bind /dev/pts $BOOTSTRAP/dev/pts
    MOUNT=$((MOUNT+1))
}

chrooting() {
    if [ "$MOUNT" != 3 ]; then
        echo "system doesn't seem to be good"
        unmounting
        exit
    fi
    ## root password
    echo "Installing root password"
    echo root:debian | chroot $BOOTSTRAP chpasswd

    ## setting up repositories
    echo "Getting signing keys"

    chroot $BOOTSTRAP sh -c 'wget -q -O - http://archive.raspberrypi.org/debian/raspberrypi.gpg.key | apt-key add -'
    chroot $BOOTSTRAP sh -c 'wget -q -O - http://mirrordirector.raspbian.org/raspbian.public.key | apt-key add -'

    if [ "$echo" -gt 0 ]; then
        chroot $BOOTSTRAP apt-key list
    fi

    sed -i $BOOTSTRAP/etc/apt/sources.list -e "s/main/main contrib non-free/"
    echo "deb http://archive.raspberrypi.org/debian/ wheezy main" >> $BOOTSTRAP/etc/apt/sources.list

    FIRM=$(fgrep "raspb" $BOOTSTRAP/etc/apt/sources.list | cut -f 3 -d ' ')
    echo "Setting up a distro pin for $FIRM"
    echo "# This sets the priority of $FIRM low so ftp.debian files is used" > $BOOTSTRAP/etc/apt/preferences.d/01repo.pref
    echo "Package: *"  >> $BOOTSTRAP/etc/apt/preferences.d/01repo.pref
    echo "Pin: release n=$FIRM"  >> $BOOTSTRAP/etc/apt/preferences.d/01repo.pref
    echo "Pin-Priority: 50"  >> $BOOTSTRAP/etc/apt/preferences.d/01repo.pref

    if [ ! -f "config/etc.apt.apt.conf" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    cp config/etc.apt.apt.conf $BOOTSTRAP/etc/apt/apt.conf

    echo "America/Toronto" > $BOOTSTRAP/etc/timezone

    if [ ! -f "/etc/locale.gen" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    cp /etc/locale.gen $BOOTSTRAP/etc/locale.gen
    DEFAULT_LOCALE="\"en_US.UTF-8\" \"en_US:en\""

    if [ ! -f "/etc/default/keyboard" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    cp /etc/default/keyboard $BOOTSTRAP/etc/default/keyboard

    echo "Creating config.txt/cmdline.txt"

    if [ ! -f "config/boot.config.txt" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    cp config/boot.config.txt $BOOTSTRAP/boot/config.txt

    if [ ! -f "config/boot.cmdline.txt" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    cp config/boot.cmdline.txt $BOOTSTRAP/boot/cmdline.txt

    echo "Tweaking the RPI"
    echo "" >> $BOOTSTRAP/etc/sysctl.conf
    echo "# http://www.raspberrypi.org/forums/viewtopic.php?p=104096#p104096" >> $BOOTSTRAP/etc/sysctl.conf
    echo "# rpi tweaks" >> $BOOTSTRAP/etc/sysctl.conf
    #echo "vm.swappiness = 1" >> $BOOTSTRAP/etc/sysctl.conf
    echo "vm.min_free_kbytes = 8192" >> $BOOTSTRAP/etc/sysctl.conf
    echo "vm.vfs_cache_pressure = 50" >> $BOOTSTRAP/etc/sysctl.conf
    echo "vm.dirty_writeback_centisecs = 1500" >> $BOOTSTRAP/etc/sysctl.conf
    echo "vm.dirty_ratio = 20" >> $BOOTSTRAP/etc/sysctl.conf
    echo "vm.dirty_background_ratio = 10" >> $BOOTSTRAP/etc/sysctl.conf

    if [ ! -f "/etc/hosts" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    echo "Networking"
    cp /etc/hosts $BOOTSTRAP/etc/hosts

    sed -i $BOOTSTRAP/etc/default/rcS -e "s/^#FSCKFIX=no/FSCKFIX=yes/"
    sed -i $BOOTSTRAP/lib/udev/rules.d/75-persistent-net-generator.rules -e 's/KERNEL\!="eth\*|ath\*|wlan\*\[0-9\]/KERNEL\!="ath\*/'
    chroot $BOOTSTRAP dpkg-divert --add --local /lib/udev/rules.d/75-persistent-net-generator.rules

    if [ ! -f "config/etc.fstab" ]; then
        echo "File not found"
        unmounting
        exit
    fi

    echo "fstab"
    cp config/etc.fstab $BOOTSTRAP/etc/fstab

    # configuring system
    chroot $BOOTSTRAP dpkg-reconfigure -f noninteractive locales
    chroot $BOOTSTRAP locale-gen LANG="$DEFAULT_LOCALE"
    chroot $BOOTSTRAP dpkg-reconfigure -f noninteractive tzdata
    chroot $BOOTSTRAP dpkg-reconfigure -f noninteractive keyboard-configuration
    chroot $BOOTSTRAP dpkg-reconfigure -f noninteractive console-setup

    if [ ! -f "config/etc.network.interfaces" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp config/etc.network.interfaces $BOOTSTRAP/etc/network/interfaces

    if [ ! -f "config/etc.modprobe.d.ipv6.conf" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp config/etc.modprobe.d.ipv6.conf $BOOTSTRAP/etc/modprobe.d/ipv6.conf

    #updating system
    echo "updating system"
    chroot $BOOTSTRAP apt-get update
    chroot $BOOTSTRAP apt-get -y upgrade
    chroot $BOOTSTRAP apt-get -y install libraspberrypi-bin libraspberrypi-dev libraspberrypi-doc raspberrypi-bootloader dbus fake-hwclock psmisc ntp raspi-copies-and-fills raspi-config
    chroot $BOOTSTRAP apt-get clean
    chroot $BOOTSTRAP apt-get autoremove -y

    #sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' $BOOTSTRAP/etc/ssh/sshd_config || fail
    sync
    # done
    echo "Done with the image"
}

configuring_system() {
    # adding the ubuntu vivid repo to poke at chromium-browser
    echo "deb http://ports.ubuntu.com/ vivid main universe" >> $BOOTSTRAP/etc/apt/sources.list

    # pinning ubuntu lower so packages don't get mixed up
    echo "Package: *" >> $BOOTSTRAP/etc/apt/preferences.d/02vivid.pref
    echo "Pin: release n=vivid" >> $BOOTSTRAP/etc/apt/preferences.d/02vivid.pref
    echo "Pin-Priority: 200" >> $BOOTSTRAP/etc/apt/preferences.d/02vivid.pref

    # add pubkey for ubuntu repo
    chroot $BOOTSTRAP apt-key adv --keyserver keyserver.ubuntu.com --recv-keys c0b21f32
    chroot $BOOTSTRAP apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 437d05b5
    chroot $BOOTSTRAP apt-get update
    chroot $BOOTSTRAP apt-get -y install icewm-lite unclutter chromium-browser lsb-release libexif12 cpufrequtils xserver-xorg xorg x11-utils

    # create a user just for loading the kiosk page, allow ssh access eventually
    chroot $BOOTSTRAP adduser --disabled-password --gecos "" --quiet kiosk

    sed -i 's/^allowed_users=console$/allowed_users=anybody/' $BOOTSTRAP/etc/X11/Xwrapper.config
    

    if [ ! -f "config/etc.systemd.system.getty.tty1.service.d.override.conf" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    mkdir -p $BOOTSTRAP/etc/systemd/system/getty\@tty1.service.d/
    cp config/etc.systemd.system.getty.tty1.service.d.override.conf $BOOTSTRAP/etc/systemd/system/getty\@tty1.service.d/autologin.conf

    if [ ! -f "config/home.kiosk.xinitrc" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp config/home.kiosk.xinitrc $BOOTSTRAP/home/kiosk/.xinitrc

    if [ ! -f "config/home.kiosk.bash.profile" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp config/home.kiosk.bash.profile $BOOTSTRAP/home/kiosk/.bash_profile

    if [ ! -f "bin/emerge-armhf" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp bin/emerge-armhf $BOOTSTRAP/home/kiosk/.emerge
    chmod +x $BOOTSTRAP/home/kiosk/.emerge

    if [ ! -f "config/home.kiosk.emerge.pl" ]; then
        echo "File not found"
        unmounting
        exit
    fi
    cp config/home.kiosk.emerge.pl $BOOTSTRAP/home/kiosk/.emerge.pl
}

unmounting() {
    if [ "$MOUNT" -gt 0 ]; then
        if [ "$MOUNT" -gt 1 ]; then
            if [ "$MOUNT" -gt 2 ]; then
                fuser -av $BOOTSTRAP
                fuser -kv $BOOTSTRAP
                umount $BOOTSTRAP/proc
                umount $BOOTSTRAP/sys
                umount $BOOTSTRAP/dev/pts
                umount $BOOTSTRAP/boot
                MOUNT=$((MOUNT-1))
                # misc partitions should be done now
            fi
            umount $BOOTSTRAP
            MOUNT=$((MOUNT-1))
        fi
        kpartx -d $IMAGE
        MOUNT=$((MOUNT-1))
        fuser -av $BOOTSTRAP
    fi
    echo "Done"
    exit
}

checking_apps
disk_image
bootstrap
mounting
chrooting
configuring_system
unmounting
#!/bin/sh

 USED_SPACE=`df /tmp/sd/ | grep mmc`
 if [ -z $USED_SPACE ]; then
	USED_SPACE=1
 else
	killall mp4record
	sleep 1
	dev=/dev/mmcblk0p1
	umount -l $dev
	/home/base/tools/mkfs.fat -F 32 $dev
	/home/app/script/mount_sd.sh
 fi

 printf "Content-Type: text/html\r\n\r\n"
 printf "\tfmt\t%s" "Ok"

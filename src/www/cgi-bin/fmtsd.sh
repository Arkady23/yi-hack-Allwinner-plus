#!/bin/sh

 killall mp4record
 dev=/dev/mmcblk0p1
 umount -l $dev
 /home/base/tools/mkfs.fat -F32 $dev
 /home/app/script/mount_sd.sh

 printf "Content-Type: text/html\r\n\r\n"
 printf "\tfmt\t%s" "Ok"

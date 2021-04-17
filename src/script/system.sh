#!/bin/sh

CONF_FILE="etc/system.conf"

YI_HACK_PREFIX="/home/yi-hack"
YI_PREFIX="/home/app"

YI_HACK_VER=$(cat /home/yi-hack/version)
MODEL_SUFFIX=$(cat /home/yi-hack/model_suffix)

get_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2
}

start_buffer()
{
    # Trick to start circular buffer filling
    ./cloud &
    IDX=`hexdump -n 16 /dev/shm/fshare_frame_buf | awk 'NR==1{print $8}'`
    N=0
    while [ "$IDX" -eq "0000" ] && [ $N -lt 60 ]; do
        IDX=`hexdump -n 16 /dev/shm/fshare_frame_buf | awk 'NR==1{print $8}'`
        N=$(($N+1))
        sleep 0.2
    done
    killall cloud
    ipc_cmd -x
}

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/lib:/home/yi-hack/lib:/tmp/sd/yi-hack/lib
export PATH=$PATH:/home/base/tools:/home/yi-hack/bin:/home/yi-hack/sbin:/home/yi-hack/usr/bin:/home/yi-hack/usr/sbin:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin

ulimit -s 1024

# Remove core files, if any
rm -f $YI_HACK_PREFIX/bin/core
rm -f $YI_HACK_PREFIX/www/cgi-bin/core
rm -f $YI_PREFIX/core

if [ ! -L /home/yi-hack-v4 ]; then
    ln -s $YI_HACK_PREFIX /home/yi-hack-v4
fi

touch /tmp/httpd.conf

# Restore configuration after a firmware upgrade
if [ -f $YI_HACK_PREFIX/fw_upgrade_in_progress ]; then
    cp -f /tmp/sd/fw_upgrade/*.conf $YI_HACK_PREFIX/etc/
    chmod 0644 $YI_HACK_PREFIX/etc/*.conf
    if [ -f /tmp/sd/fw_upgrade/hostname ]; then
        cp -f /tmp/sd/fw_upgrade/hostname $YI_HACK_PREFIX/etc/
        chmod 0644 $YI_HACK_PREFIX/etc/hostname
    fi
    rm $YI_HACK_PREFIX/fw_upgrade_in_progress
fi

$YI_HACK_PREFIX/script/check_conf.sh

hostname -F $YI_HACK_PREFIX/etc/hostname
export TZ=$(get_config TIMEZONE)

DISABLE_CLOUD = $(get_config DISABLE_CLOUD)
REC_WITHOUT_CLOUD = $(get_config REC_WITHOUT_CLOUD)

if [[ $(get_config SWAP_FILE) == "yes" ]] ; then
    SD_PRESENT=$(mount | grep mmc | grep -c ^)
    if [[ $SD_PRESENT -eq 1 ]]; then
        if [[ -f /tmp/sd/swapfile ]]; then
            swapon /tmp/sd/swapfile
        else
            dd if=/dev/zero of=/tmp/sd/swapfile bs=1M count=64
            chmod 0600 /tmp/sd/swapfile
            mkswap /tmp/sd/swapfile
            swapon /tmp/sd/swapfile
        fi
    fi
fi

if [[ x$(get_config USERNAME) != "x" ]] ; then
    USERNAME=$(get_config USERNAME)
    PASSWORD=$(get_config PASSWORD)
    ONVIF_USERPWD="--user $USERNAME --password $PASSWORD"
    echo "/:$USERNAME:$PASSWORD" > /tmp/httpd.conf
fi

if [[ x$(get_config SSH_PASSWORD) != "x" ]] ; then
    SSH_PASSWORD=$(get_config SSH_PASSWORD)
    PASSWORD_MD5="$(echo "${SSH_PASSWORD}" | mkpasswd --method=MD5 --stdin)"
    cp -f "/etc/passwd" "/home/yi-hack/etc/passwd"
    sed -i 's|^root::|root:'${PASSWORD_MD5}':|g' "/home/yi-hack/etc/passwd"
    sed -i 's|/root|/home/yi-hack|g' "/home/yi-hack/etc/passwd"
    mount --bind "/home/yi-hack/etc/passwd" "/etc/passwd"
    cp -f "/etc/shadow" "/home/yi-hack/etc/shadow"
    sed -i 's|^root::|root:'${PASSWORD_MD5}':|g' "/home/yi-hack/etc/shadow"
    mount --bind "/home/yi-hack/etc/shadow" "/etc/shadow"
fi

case $(get_config RTSP_PORT) in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$(get_config RTSP_PORT) ;;
esac
case $(get_config ONVIF_PORT) in
    ''|*[!0-9]*) ONVIF_PORT=80 ;;
    *) ONVIF_PORT=$(get_config ONVIF_PORT) ;;
esac
case $(get_config HTTPD_PORT) in
    ''|*[!0-9]*) HTTPD_PORT=8080 ;;
    *) HTTPD_PORT=$(get_config HTTPD_PORT) ;;
esac

if [ ! -f $YI_PREFIX/cloudAPI_real ]; then
    mv $YI_PREFIX/cloudAPI $YI_PREFIX/cloudAPI_real
    cp $YI_HACK_PREFIX/script/cloudAPI $YI_PREFIX/
fi

if [[ $(get_config DISABLE_CLOUD) == "no" ]] ; then
    (
        if [ $(get_config RTSP_AUDIO) != "no" ]; then
            touch /tmp/audio_fifo.requested
        fi
        if [ $(get_config SPEAKER_AUDIO) != "no" ]; then
            touch /tmp/audio_in_fifo.requested
        fi
        cd /home/app
        LD_LIBRARY_PATH="/home/yi-hack/lib:/lib:/usr/lib:/home/lib:/home/qigan/lib:/home/app/locallib" ./rmm &
        sleep 6
        dd if=/tmp/audio_fifo of=/dev/null bs=1 count=8192
#        dd if=/dev/zero of=/tmp/audio_in_fifo bs=1 count=1024
        ./mp4record &
        ./cloud &
        ./p2p_tnp &
        ./oss &
        if [ -f ./oss_fast ]; then
            ./oss_fast &
        fi
        if [ -f ./oss_lapse ]; then
            ./oss_lapse &
        fi
        ./watch_process &
    )
else
    (
        if [ $(get_config RTSP_AUDIO) != "no" ]; then
            touch /tmp/audio_fifo.requested
        fi
        if [ $(get_config SPEAKER_AUDIO) != "no" ]; then
            touch /tmp/audio_in_fifo.requested
        fi
        cd /home/app
        LD_LIBRARY_PATH="/home/yi-hack/lib:/lib:/usr/lib:/home/lib:/home/qigan/lib:/home/app/locallib" ./rmm &
        sleep 6
        dd if=/tmp/audio_fifo of=/dev/null bs=1 count=8192
#        dd if=/dev/zero of=/tmp/audio_in_fifo bs=1 count=1024
        # Trick to start circular buffer filling
        if [[ $(get_config REC_WITHOUT_CLOUD) == "yes" ]] ; then
		./mp4record &
		./cloud &
	else
		start_buffer
        fi
    )
fi

if [[ $(get_config HTTPD) == "yes" ]] ; then
    httpd -p $HTTPD_PORT -h $YI_HACK_PREFIX/www/ -c /tmp/httpd.conf
fi

if [[ $(get_config TELNETD) == "no" ]] ; then
    killall telnetd
fi

if [[ $(get_config FTPD) == "yes" ]] ; then
    if [[ $(get_config BUSYBOX_FTPD) == "yes" ]] ; then
        tcpsvd -vE 0.0.0.0 21 ftpd -w &
    else
        pure-ftpd -B
    fi
fi

if [[ $(get_config SSHD) == "yes" ]] ; then
    mkdir -p $YI_HACK_PREFIX/etc/dropbear
    if [ ! -f /home/base/scp ]; then
        ln -s /home/yi-hack/bin/scp /home/base/scp
    fi
    dropbear -R -B
fi

if [[ $(get_config NTPD) == "yes" ]] ; then
    # Wait until all the other processes have been initialized
    sleep 5 && ntpd -p $(get_config NTP_SERVER) &
fi

ipc_multiplexer &
sleep 1
if [[ $(get_config MQTT) == "yes" ]] ; then
    mqttv4 &
    mqtt-config &
fi

sleep 5

if [[ $RTSP_PORT != "554" ]] ; then
    D_RTSP_PORT=:$RTSP_PORT
fi

if [[ $HTTPD_PORT != "80" ]] ; then
    D_HTTPD_PORT=:$HTTPD_PORT
fi

if [[ $ONVIF_PORT != "80" ]] ; then
    D_ONVIF_PORT=:$ONVIF_PORT
fi

if [[ $(get_config ONVIF_WM_SNAPSHOT) == "yes" ]] ; then
    WATERMARK="&watermark=yes"
fi

if [[ $(get_config RTSP) == "yes" ]] ; then
    RTSP_AUDIO_COMPRESSION=$(get_config RTSP_AUDIO)
    if [[ "$RTSP_AUDIO_COMPRESSION" == "none" ]] ; then
        RTSP_AUDIO_COMPRESSION="no"
    fi

    RRTSP_RES=$(get_config RTSP_STREAM) RRTSP_AUDIO=$RTSP_AUDIO_COMPRESSION RRTSP_PORT=$RTSP_PORT RRTSP_USER=$USERNAME RRTSP_PWD=$PASSWORD rRTSPServer &
    if [[ $(get_config RTSP_STREAM) == "low" ]]; then
        ONVIF_PROFILE_1="--name Profile_1 --width 640 --height 360 --url rtsp://%s$D_RTSP_PORT/ch0_1.h264 --snapurl http://%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK --type H264"
    fi
    if [[ $(get_config RTSP_STREAM) == "high" ]]; then
        ONVIF_PROFILE_0="--name Profile_0 --width 1920 --height 1080 --url rtsp://%s$D_RTSP_PORT/ch0_0.h264 --snapurl http://%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK --type H264"
    fi
    if [[ $(get_config RTSP_STREAM) == "both" ]]; then
        if [[ $(get_config ONVIF_PROFILE) == "low" ]] || [[ $(get_config ONVIF_PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_1="--name Profile_1 --width 640 --height 360 --url rtsp://%s$D_RTSP_PORT/ch0_1.h264 --snapurl http://%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=low$WATERMARK --type H264"
        fi
        if [[ $(get_config ONVIF_PROFILE) == "high" ]] || [[ $(get_config ONVIF_PROFILE) == "both" ]] ; then
            ONVIF_PROFILE_0="--name Profile_0 --width 1920 --height 1080 --url rtsp://%s$D_RTSP_PORT/ch0_0.h264 --snapurl http://%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=high$WATERMARK --type H264"
        fi
    fi
    $YI_HACK_PREFIX/script/wd_rtsp.sh &
fi

SERIAL_NUMBER=$(dd bs=1 count=20 skip=592 if=/tmp/mmap.info 2>/dev/null | cut -c1-20)
HW_ID=$(dd bs=1 count=4 skip=592 if=/tmp/mmap.info 2>/dev/null | cut -c1-4)

if [[ $(get_config ONVIF) == "yes" ]] ; then
    if [[ $MODEL_SUFFIX == "h201c" ]] || [[ $MODEL_SUFFIX == "h305r" ]] ; then
        onvif_srvd --pid_file /var/run/onvif_srvd.pid --model "Yi Hack" --manufacturer "Yi" --firmware_ver "$YI_HACK_VER" --hardware_id $HW_ID --serial_num $SERIAL_NUMBER --ifs wlan0 --port $ONVIF_PORT --scope onvif://www.onvif.org/Profile/S $ONVIF_PROFILE_0 $ONVIF_PROFILE_1 $ONVIF_USERPWD --ptz --move_left "/home/yi-hack/bin/ipc_cmd -m left" --move_right "/home/yi-hack/bin/ipc_cmd -m right" --move_up "/home/yi-hack/bin/ipc_cmd -m up" --move_down "/home/yi-hack/bin/ipc_cmd -m down" --move_stop "/home/yi-hack/bin/ipc_cmd -m stop" --move_preset "/home/yi-hack/bin/ipc_cmd -p %t"
    else
        onvif_srvd --pid_file /var/run/onvif_srvd.pid --model "Yi Hack" --manufacturer "Yi" --firmware_ver "$YI_HACK_VER" --hardware_id $HW_ID --serial_num $SERIAL_NUMBER --ifs wlan0 --port $ONVIF_PORT --scope onvif://www.onvif.org/Profile/S $ONVIF_PROFILE_0 $ONVIF_PROFILE_1 $ONVIF_USERPWD
    fi
    if [[ $(get_config ONVIF_WSDD) == "yes" ]] ; then
        wsdd --pid_file /var/run/wsdd.pid --if_name wlan0 --type tdn:NetworkVideoTransmitter --xaddr http://%s$D_ONVIF_PORT --scope "onvif://www.onvif.org/name/Unknown onvif://www.onvif.org/Profile/Streaming"
    fi
fi

framefinder &

# Add crontab
CRONTAB=$(get_config CRONTAB)
FREE_SPACE=$(get_config FREE_SPACE)
mkdir -p /var/spool/cron/crontabs/
if [ ! -z "$CRONTAB" ]; then
    echo "$CRONTAB" > /var/spool/cron/crontabs/root
fi
if [ "$FREE_SPACE" != "0" ]; then
    echo "0 * * * * /home/yi-hack/script/clean_records.sh $FREE_SPACE" >> /var/spool/cron/crontabs/root
fi
$YI_HACK_PREFIX/usr/sbin/crond -c /var/spool/cron/crontabs/

# Add MQTT Advertise
if [ -f "$YI_HACK_PREFIX/script/mqtt_advertise/startup.sh" ]; then
    $YI_HACK_PREFIX/script/mqtt_advertise/startup.sh
fi

# Remove log files written to SD on boot containing the WiFi password
rm -f "/tmp/sd/log/log_first_login.tar.gz"
rm -f "/tmp/sd/log/log_login.tar.gz"
rm -f "/tmp/sd/log/log_oss_exit.tar.gz"
rm -f "/tmp/sd/log/log_oss_fail_x.tar.gz"
rm -f "/tmp/sd/log/log_oss_fragment_x.tar.gz"
rm -f "/tmp/sd/log/log_oss_success_x.tar.gz"
rm -f "/tmp/sd/log/log_p2p_clr.tar.gz"
rm -f "/tmp/sd/log/log_wifi_connected.tar.gz"

if [[ $(get_config FTP_UPLOAD) == "yes" ]] ; then
    /home/yi-hack/script/ftppush.sh start &
fi

if [ -f "/tmp/sd/yi-hack/startup.sh" ]; then
    /tmp/sd/yi-hack/startup.sh
fi

if [[ $(get_config DISABLE_CLOUD) == "yes" ]]; then
  sleep 20
  if [[ $(get_config REC_WITHOUT_CLOUD) == "yes" ]]; then
	N=0
	while [ $N -lt 60 ]; do
		if [ -f "/tmp/sd/record/tmp.mp4.tmp" ]; then
			N=60
		fi
		sleep 8
		N=$(($N+1))
	done
	killall cloudAPI
	killall cloud
	killall dispatch
  else
	killall dispatch
  fi
fi

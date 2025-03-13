#!/bin/sh
# 
# Copyright (C) 2011 Texas Instruments Incorporated - http://www.ti.com/
#  
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as 
# published by the Free Software Foundation version 2.
# 
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 

# Test video functionality using gstreamer
# Input: File to be downloaded and test file name
# Output: Make the input stream available for running test

source "st_log.sh"
source "common.sh"

############################# Functions #######################################
usage()
{
cat <<-EOF >&2
        usage: ./${0##*/} [-f FILE] [-S file ] [-s] [-p] [-x] [-c v_id] [-a a_id] [-z audiosink] [-v videosink]
        -f absolute path of the stream to be played
        -S absolute path of the subtitles (optionnal)
        -s Enable video and audio sync property
        -x Enable video scaling (Not available on all platforms or with -p)
        -c Video connector id
        -a audio device, i.e hw:0,0
        -z gstreamer audio sink, i.e alsasink, fakesink, etc
        -v gstreamer video sink, i.e waylandsink, fbdevsink. Defaults to
           kmssink/fbdevsink
        -h Help         print this usage
EOF
exit 0
}

SYNC=""
SCALING=""
V_CONN=""
A_DEV=""
A_SINK="alsasink"
case $MACHINE in
	 dra7xx*|am57xx*)
			 VSINK="kmssink";;
         am57*-idk)
			 VSINK="kmssink"
                         A_SINK="fakesink";;
	 *)
			 VSINK="fbdevsink";;
esac
############################ Script Variables ##################################
# Define default valus if possible

############################ CLI Params ###########################################
OPTIND=1
while getopts :spxc:a:f:S:z:v: arg
do case $arg in
        f)
                FILE=$OPTARG ;;
        S)
                SUBTITLES="suburi=file://$OPTARG" ;;
        s)
                SYNC="" ;;
        x)
                SCALING="scale=true" ;;
        c)
                V_CONN="connector-id=$OPTARG" ;;
        a)
                A_DEV="device=$OPTARG" ;;
        z)
                A_SINK=$OPTARG ;;
        v)
                VSINK=$OPTARG ;;
        \?)
		            echo "Invalid Option -$OPTARG ignored." >&2
                usage
                exit 1
                ;;
esac
done

########################### DYNAMICALLY-DEFINED Params #########################
# Try to use /sys and /proc information to determine values dynamically.
# Alternatively you should check if there is an existing script to get the
# value you want

########################### REUSABLE TEST LOGIC ###############################

case $MACHINE in
    dra7*|am57*)
      source ipc_funcs.sh; rm_ipc_mods; ins_ipc_mods rpmsg_rpc; toggle_rprocs stop ; setup_firmware 'dra7-ipu2-fw.xem4.ipumm-fw'; toggle_rprocs start;
      ;;
esac

if [ "$VSINK" == "waylandsink" ]
then
    start_daemon emptty
    stop_daemon matrix-gui-2.0
    V_CONN=""
    SCALING=""
else
    stop_daemon emptty
fi
sleep 3

echo "gst-launch-1.0 playbin uri=file://${FILE} ${SUBTITLES} video-sink=\"${VSINK} ${SCALING} ${SYNC} ${V_CONN}\" audio-sink=\"${A_SINK} ${SYNC} ${A_DEV}\""
gst-launch-1.0 playbin uri=file://${FILE} ${SUBTITLES} video-sink=\"${VSINK} ${SCALING} ${SYNC} ${V_CONN}\" audio-sink=\"${A_SINK} ${SYNC} ${A_DEV}\" || die "Problem occurred while trying to play stream"

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
        usage: ./${0##*/} [-d DOWNLOAD] -c <CODEC> -r <RESOLUTION>
        -d DOWNLOAD	stream to be downloaded from gtopentest-server.gt.design.ti.com
        -c CODEC 	codec h264, mpeg4, mpeg2, mpeg4aac
	-r RESOLUTION	resolution of stream
        -h Help         print this usage
EOF
exit 0
}
############################ Script Variables ##################################
# Define default valus if possible

############################ CLI Params ###########################################
while getopts :d:c:r: arg
do case $arg in
        d)
                DOWNLOAD=$OPTARG ;;
        c)
                CODEC=$OPTARG ;;
        r)
                RESOLUTION=$OPTARG ;;
        \?)
		echo "Invalid Option -$OPTARG ignored." >&2
                usage
                exit 1
                ;;
esac
done

############################ USER-DEFINED Params ###############################
case $CODEC in
   264)
      FILE="/usr/share/ti/video/HistoryOfTI-$RESOLUTION.264";;
   mpeg2)
      FILE="/usr/share/ti/video/HistoryOfTI-$RESOLUTION.m2v";;
   mpeg4)
      FILE="/usr/share/ti/video/HistoryOfTI-$RESOLUTION.m4v";;
   mpeg4aac)
      FILE="/usr/share/ti/video/HistoryOfTIAV-$RESOLUTION.mp4";;
esac

ASINK="alsasink"
case $MACHINE in
   dra7xx*|am57xx*)
       VSINK="kmssink";;
   am572x-idk*)
       VSINK="kmssink"
       ASINK="fakesink";;
   *)
       VSINK="fbdevsink /dev/fb0";;
esac

GSTCMD="gst-launch-1.0 playbin uri=file://${FILE} video-sink=\"${VSINK}\" audio-sink=\"${ASINK}\""

########################### DYNAMICALLY-DEFINED Params #########################
# Try to use /sys and /proc information to determine values dynamically.
# Alternatively you should check if there is an existing script to get the
# value you want

########################### REUSABLE TEST LOGIC ###############################
if [ -e "$FILE" ];then
   echo "Demo file $FILE exists"
else
   echo "Running $FILE"
   if [ ! -s "$FILE" ];then
      echo "Downloading stream $DOWNLOAD from gtopentest-server"
      do_cmd 'Wget http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/Video/$DOWNLOAD -O $FILE'\
 || die "Stream not available!"
   fi
fi
# Stop Weston to avoid conflicts with gst
stop_daemon emptty && sleep 3
do_cmd "$GSTCMD"



#!/bin/bash

#copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#    Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#    Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the
#    distribution.
#
#    Neither the name of Texas Instruments Incorporated nor the names of
#    its contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

setup_imx390(){
    IMX390_CAM_FMT='[fmt:SRGGB12_1X12/1936x1100 field: none]'               

    i=0
    for media_id in {0..1}; do
    # UB953 FORMATS
    UB960_FMT_STR="["
    CSI2RX_FMT_STR="["
    for name in `media-ctl -d $media_id -p | grep entity | grep imx390 | cut -d ' ' -f 5`; do

        CAM_SUBDEV=`media-ctl -d $media_id -p -e "imx390 $name" | grep v4l-subdev | awk '{print $4}'`
#        v4l2-ctl -d $CAM_SUBDEV --set-ctrl wide_dynamic_range=0

        UB953_NAME=`media-ctl -d $media_id -p -e "imx390 $name" | grep ub953 | cut -d "\"" -f 2`
        media-ctl -d $media_id -V "'$UB953_NAME':0 $IMX390_CAM_FMT"

        UB960_NAME=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
        UB960_PAD=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`

        CSI_BRIDGE_NAME=`media-ctl -d $media_id -p -e "$UB960_NAME" | grep csi-bridge | cut -d "\"" -f 2`

        CSI2RX_NAME=`media-ctl -d $media_id -p -e "$CSI_BRIDGE_NAME" | grep "ticsi2rx\"" | cut -d "\"" -f 2`

        CSI2RX_CONTEXT_NAME="$CSI2RX_NAME context $UB960_PAD"

        if [ "$UB960_FMT_STR" != "[" ]; then
                UB960_FMT_STR="${UB960_FMT_STR}, "
                CSI2RX_FMT_STR="${CSI2RX_FMT_STR}, "
        fi
        UB960_FMT_STR="${UB960_FMT_STR}${UB960_PAD}/0 -> 4/${UB960_PAD} [1]"
        CSI2RX_FMT_STR="${CSI2RX_FMT_STR}0/${UB960_PAD} -> $(($UB960_PAD+1))/0 [1]"

        echo "IMX390 Camera $i detected"
        echo "    device = "`media-ctl -d $media_id -p -e "$CSI2RX_CONTEXT_NAME" | grep video | awk '{print $4}'`
        echo "    name = imx390 $name"
        echo "    format = $IMX390_CAM_FMT"
        echo "    subdev_id = $CAM_SUBDEV"
        echo "    isp_required = yes"
        echo "    ldc_required = yes"
	
        ((i++))
    done

    UB960_FMT_STR="${UB960_FMT_STR}]"
    CSI2RX_FMT_STR="${CSI2RX_FMT_STR}]"
    
    media-ctl -d $media_id -p | grep entity | grep imx390 -q
    if [ "$?" == "0" ]; then
    # UB960 ROUTING & FORMATS
    media-ctl -d $media_id -R "'$UB960_NAME' $UB960_FMT_STR"
    for name in `media-ctl -d $media_id -p | grep entity | grep imx390 | cut -d ' ' -f 5`; do
        UB953_NAME=`media-ctl -d $media_id -p -e "imx390 $name" | grep ub953 | cut -d "\"" -f 2`
        UB960_NAME=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d "\"" -f 2`
        UB960_PAD=`media-ctl -d $media_id -p -e "$UB953_NAME" | grep ub960 | cut -d : -f 2 | awk '{print $1}'`
        media-ctl -d $media_id -V "'$UB960_NAME':$UB960_PAD $IMX390_CAM_FMT"
    done

    # CSI2RX ROUTING
    media-ctl -d $media_id -R "'45${media_id}0000.ticsi2rx' $CSI2RX_FMT_STR"
    fi
    done
}


setup_CSI_cameras(){
    #Check for CSI Camera 0
    CSI_CAM_1_SUBDEV_OFFSET=0
    ls /dev/v4l/by-path/platform-4500000.ticsi2rx-video-index0 > /dev/null 2>&1
    if [ "$?" == "0" ]; then
        CSI_CAM_0_DEV=`ls /dev/v4l/by-path/platform-4500000.ticsi2rx-video-index0 | head -1 | xargs readlink -f`
        CSI_CAM_0_SUBDEV_ID=2
        CSI_CAM_0_NAME=`cat /sys/class/video4linux/v4l-subdev$CSI_CAM_0_SUBDEV_ID/name`
        echo $CSI_CAM_0_NAME | grep ov5640 > /dev/null
        if [ "$?" -eq "0" ]; then
            CSI_CAM_0_FMT='[fmt:UYVY8_2X8/640x480@1/30]'
            CSI_CAM_0_NEED_ISP=no
        fi
        echo $CSI_CAM_0_NAME | grep imx219 > /dev/null
        if [ "$?" -eq "0" ]; then
            CSI_CAM_0_FMT='[fmt:SRGGB8_1X8/1920x1080]'
            CSI_CAM_0_NEED_ISP=yes
        fi
        media-ctl -d 0 --set-v4l2 ''"\"$CSI_CAM_0_NAME\""':0 '$CSI_CAM_0_FMT''
        CSI_CAM_1_SUBDEV_OFFSET=3
        #echo "CSI Camera 0 detected"
        #echo "    device = "$CSI_CAM_0_DEV
        #echo "    name = "$CSI_CAM_0_NAME
        #echo "    format = "$CSI_CAM_0_FMT
        #echo "    subdev_id = "$CSI_CAM_0_SUBDEV_ID
        #echo "    isp_required = "$CSI_CAM_0_NEED_ISP
	    echo $CSI_CAM_0_DEV,$CSI_CAM_0_FMT,$CSI_CAM_0_SUBDEV_ID,$CSI_CAM_0_NEED_ISP
    fi

    #Check for CSI Camera 1
    ls /dev/v4l/by-path/platform-4510000.ticsi2rx-video-index0 > /dev/null 2>&1
    if [ "$?" == "0" ]; then
        CSI_CAM_1_DEV=`ls /dev/v4l/by-path/platform-4510000.ticsi2rx-video-index0 | head -1 | xargs readlink -f`
        CSI_CAM_1_SUBDEV_ID=$((2 + $CSI_CAM_1_SUBDEV_OFFSET))
        CSI_CAM_1_NAME=`cat /sys/class/video4linux/v4l-subdev$CSI_CAM_1_SUBDEV_ID/name`
        echo $CSI_CAM_1_NAME | grep imx219 > /dev/null
        if [ "$?" -eq "0" ]; then
            CSI_CAM_1_FMT='[fmt:SRGGB8_1X8/1920x1080]'
            CSI_CAM_1_NEED_ISP=yes
        fi
        media-ctl -d 1 --set-v4l2 ''"\"$CSI_CAM_1_NAME\""':0 '$CSI_CAM_1_FMT''
        # echo "CSI Camera 1 detected"
        # echo "    device = "$CSI_CAM_1_DEV
        # echo "    name = "$CSI_CAM_1_NAME
        # echo "    format = "$CSI_CAM_1_FMT
        # echo "    subdev_id = "$CSI_CAM_1_SUBDEV_ID
        # echo "    isp_required = "$CSI_CAM_1_NEED_ISP
        echo $CSI_CAM_1_DEV,$CSI_CAM_1_FMT,$CSI_CAM_1_SUBDEV_ID,$CSI_CAM_1_NEED_ISP
    fi

}

setup_USB_camera(){
    USB_CAM_DEV=`ls /dev/v4l/by-path/*usb*video-index0 | head -1 | xargs readlink -f`
    echo "USB Camera detected"
    echo "    device = "$USB_CAM_DEV
    echo "    format = jpeg"
}


#Check for USB Camera
ls /dev/v4l/by-path/*usb*video-index0 > /dev/null 2>&1
if [ "$?" == "0" ]; then
    setup_USB_camera
fi

ls /sys/class/video4linux/ | grep v4l-subdev -q
if [ "$?" == "0" ]; then
    cat /sys/class/video4linux/v4l-subdev*/name | grep imx390 -q
    if [ "$?" == "0" ]; then
        setup_imx390
    else
        setup_CSI_cameras
    fi
fi

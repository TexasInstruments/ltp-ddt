#!/bin/bash

CAM_INFO=`setupcamera.sh`
NUM_CAMERA=$(echo "$CAM_INFO" | wc -l)
FORMAT=""

case "$CAM_INFO" in
	*"imx390"*)
		echo "IMX390 camera found"
		FORMAT="video/x-bayer, framerate=30/1, width=1936, height=1100, format=rggb12le"
		;;
	*"imx219"*)
		echo "IMX219 camera found"
		FORMAT="video/x-bayer, framerate=30/1, width=1920, height=1080, format=rggb"
		;;
	*"ov5640"*)
		echo "OV5640 camera found"
		FORMAT="video/x-raw, framerate=30/1, width=640, height=480, format=UYVY"
		;;
	*"ov2312"*)
		echo "OV2312 camera found"
		FORMAT="video/x-bayer, framerate=30/1, width=1600, height=1300, format=bggi10"
		;;
	*"ox05b1s"*)
		echo "OX05B1S camera found"
		FORMAT="video/x-bayer, framerate=30/1, width=2592, height=1944, format=bggi10"
		;;
	*)
		echo "Unknown camera"
		exit -1
		;;
esac

cam_paths=()
while IFS= read -r cam; do
	campath=$(echo $cam | cut -d',' -f1)
	cam_paths+=("$campath")
done <<< "$CAM_INFO"

pipeline=""
for path in "${cam_paths[@]}"
do
pipeline+="v4l2src device=$path ! $FORMAT ! queue ! fakesink "
done
echo $pipeline
timeout 5 gst-launch-1.0 $pipeline

exit_code=$?
if [ $exit_code -eq 124 ]; then
	exit 0
else
	exit $exit_code
fi

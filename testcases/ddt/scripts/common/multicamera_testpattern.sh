#!/bin/bash

CAM_INFO=`setupcamera.sh`
NUM_CAMERA=$(echo "$CAM_INFO" | wc -l)

video_nodes=()
subdev_nodes=()
sensor_names=()

while IFS= read -r cam; do
        video_node=$(echo $cam | cut -d',' -f1)
        video_nodes+=("$video_node")
        subdev_node=$(echo $cam | cut -d',' -f3)
        subdev_nodes+=("$subdev_node")
        sensor_name=$(echo "$video_node" | cut -d'-' -f2)
        sensor_names+=("$sensor_name")
done <<< "$CAM_INFO"

all_success=0

for ((i=0; i<NUM_CAMERA; i++)); do

     echo "Running csi_capture_test with: ${video_nodes[i]} ${subdev_nodes[i]}"
     csi_capture_test -d "${video_nodes[i]}" -s "${subdev_nodes[i]}" -t 1 -n "${sensor_names[i]}"

    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        all_success=$((all_success + 1))
    fi
done

if [ "$all_success" -eq "$NUM_CAMERA" ] && [ "$NUM_CAMERA" -ne 0 ]; then
    echo "All $NUM_CAMERA passed"
    exit 0
else
    if [ "$NUM_CAMERA" -eq 0 ]; then
        echo "No cameras detected!"
    else
        echo "$all_success out of $NUM_CAMERA passed"
    fi
    exit 1
fi

#! /bin/bash
#
# Copyright (C) 2019 Texas Instruments Incorporated - http://www.ti.com/
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

source "common.sh"
source "st_log.sh"
source "functions.sh"

# Load require video modules
insert_video_modules()
{
	local _modules="videobuf2_common videobuf2_memops videobuf2_v4l2 videobuf2_dma_sg videobuf2_dma_contig v4l2_mem2mem vxd_dec vxe_enc"
	for m in $_modules; do
		lsmod | grep $m || modprobe $m
	done
}

# Run TI decoder
run_tidec_decode()
{
	insert_video_modules
	tidec_decode -b $* | grep 'test app completed successfully'
}

# Run TI encoder
run_tienc_encode()
{
	insert_video_modules
	tienc_encode $*
}

# Download Test media if not in fs
get_media()
{
	local __media_url=http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/$1
	local __checksums=/tmp/checksums.txt
	local __media_folder=/usr/share/ti/tidec-decode
	local __video=$2
	local __media

	if [[ "$1" == "encoder" ]]
	then
   		__media_folder=/usr/share/ti/tienc-encode
   		__video=yuv/$2
	fi

	ls ${__media_folder} &>/dev/null || mkdir -p ${__media_folder}
	local __media_checksum=$(md5sum ${__media_folder}/* | awk '{print $1}' | sort -u)
	wget ${__media_url}/media_checksums.txt -O ${__checksums} || return 1
	local __remote_checksum=$(awk '{print $1}' ${__checksums} | sort -u)
	local __remote_media=$(awk '{print $2}' ${__checksums} | sort -u)

	for __media in $__remote_media
	do
	if [[ $__media == $__video ]]
	then
  		wget ${__media_url}/${__media} -O ${__media_folder}/`basename ${__media}` || echo "Could not download  ${__media_url}/${__media}"
	fi
	done
}

# Get the memory consumption of specifc pipepline
get_pipe_mem_consumption()
{
    # Get memory consumption
    local _mem_consumption_before=$(cat /proc/meminfo | grep MemFree | awk '{print $2}')
    gst-launch-1.0 $1 &
    sleep 5
    local _mem_consumption_during=$(cat /proc/meminfo | grep MemFree | awk '{print $2}')
    echo $((_mem_consumption_before - _mem_consumption_during)) > $2
}


# Get the CPU Utilization of specific pipeline
# @param1: the pipeline to execute
# @param2: the output file that holds data
get_pipe_cpu_utilization()
{
    local _data_file=$(mktemp)
    gst-launch-1.0 $1 &
    pid=$(pgrep -f "gst-launch-1.0 $1")
    if [ -z "$pid" ]; then
        echo "Unable to find PID"
        return 1
    fi
    pid_int=$pid
    # Get CPU Utilization
    top -p $pid_int -H -d 1 -b -n 10 | grep v4l2 > $_data_file
    local _cpu_utilization=$( awk '{sum+=$9} END {print sum/NR}' $_data_file )
    echo $_cpu_utilization > $2
}

remove_media()
{
	
	if [[ "$1" == "encoder" ]]
	then
	  rm -rf /usr/share/ti/tienc-encode
	else
	  rm -rf /usr/share/ti/tidec-decode
	fi
	
}

chromium_setup()
{
	WAYLAND_SOCKET="/run/user/1000/wayland-1"

	systemctl restart emptty

	for i in {1..5}; do
		[ -S "$WAYLAND_SOCKET" ] && break
		sleep 1
		systemctl start emptty
	done

	# Check if chromium is already installed
	if ! which chromium > /dev/null; then
		echo "Chromium not found, installing..."
		opkg update
		if ! opkg install chromium-ozone-wayland; then
			echo "ERROR: Failed to install Chromium. Check network connection and package availability." >&2
			exit 1
		fi
	fi

	# Verify Chromium is working properly by checking version
	if ! chromium_version=$(chromium --version 2>/dev/null); then
		echo "ERROR: Chromium installation appears broken. Cannot get version information." >&2
		exit 1
	fi

	echo "$chromium_version is installed and working properly"

	# Check if any display connector is connected
	echo "Checking display connector status..."

	# Run kmsprint, capture output, and display it to terminal
	kmsprint_output=$(kmsprint 2>/dev/null) || {
		echo "ERROR: Failed to run kmsprint command" >&2
		exit 127
	}

	# Display the captured output
	echo "$kmsprint_output"

	# Check if the output contains "connected"
	if ! echo "$kmsprint_output" | grep -iq "(connected)"; then
		echo "ERROR: No connected display connector found" >&2
		exit 3
	fi

	echo "Display connector check passed - found connected display"
}

build_chromium_playback_cmd()
{
	local __media_url
	local __use_proxy=true

	# Determine media URL and proxy settings based on media type
	if [ "$1" = "HTML" ]; then
		if [ "$2" = "TI" ]; then
			__media_url=http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/decoder/CustomerErrorStreams/$3
			__use_proxy=false
		elif [ "$2" = "GOOGLE" ]; then
			__media_url=http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/$3
		else
			echo "ERROR: Invalid HTML source parameter. Must be either 'GOOGLE' or 'TI'." >&2
			exit 2
		fi
	elif [ "$1" = "VIMEO" ]; then
		# Use the provided quality or default to 1080p if not specified
		local __quality=${3:-1080p}
		local __valid_qualities="240p 360p 540p 720p 1080p 2k 4k"
		
		# Check if the quality is valid using pattern matching
		if [[ ! "$__quality" =~ ^(240p|360p|540p|720p|1080p|2k|4k)$ ]]; then
			# Invalid quality value
			echo "ERROR: Invalid quality parameter '$__quality' for VIMEO. Must be one of: $__valid_qualities" >&2
			exit 3
		fi
		# Valid quality value - continue execution
		
		__media_url="https://player.vimeo.com/video/$2?quality=${__quality}&autoplay=1&loop=1"
	elif [ "$1" = "YOUTUBE" ]; then
		__media_url=https://www.youtube.com/embed/$2?autplay=1&loop=1
	else
		echo "ERROR: Invalid media platform parameter. Must be 'HTML', 'VIMEO' or 'YOUTUBE'." >&2
		exit 2
	fi

	# Build the command with appropriate environment variables
	local __cmd="export WAYLAND_DISPLAY=/run/user/1000/wayland-1;"

	# Add proxy settings if needed
	if [ "$__use_proxy" = true ]; then
		__cmd+=" export HTTP_PROXY=http://webproxy.ext.ti.com:80;"
		__cmd+=" export HTTPS_PROXY=http://webproxy.ext.ti.com:80;"
	fi

	# Add the chromium command and display any wayland-related output in terminal
	__cmd+=" chromium \"${__media_url}\" --start-fullscreen --no-first-run 2>&1 | grep -i wayland"

	# Return the command
	echo "$__cmd"
}

chromium_playback()
{
	# Get the command with environment variables setup
	local __cmd

	__cmd=$(build_chromium_playback_cmd "$@")
	
	local __ret=$?
	
	# Check if build_chromium_playback_cmd returned an error
	if [ $__ret -ne 0 ]; then
		exit $__ret
	fi

	# Execute the command
	su -l weston -c "$__cmd" &

	sleep 5

	# Get all Chromium process IDs
	local pids=$(pgrep -f "chromium-bin")
	local retry_count=0
	local max_retries=3

	# Check if we found Chromium processes, retry if not
	while [ -z "$pids" ] && [ $retry_count -lt $max_retries ]; do
		echo "Warning: Failed to detect Chromium processes, retrying (attempt $((retry_count+1))/$max_retries)..."
		
		# Kill any potentially stuck chromium processes
		pkill -f "chromium-bin" 2>/dev/null
		sleep 2
		
		# Re-execute the chromium command
		su -l weston -c "$__cmd" &
		sleep 5
		
		# Check again for processes
		pids=$(pgrep -f "chromium-bin")
		retry_count=$((retry_count+1))
	done

	# If still no processes after retries, then fail
	if [ -z "$pids" ]; then
		echo "ERROR: Failed to detect Chromium processes after $max_retries retries" >&2
		exit 4
	fi

	echo "Found Chromium processes. Sleeping 15 seconds to let chromium stabilize."
	sleep 15
}

get_cpu_threshold()
{
	local device_name=$(uname -n)
	local fhd_high_fps=$1
	local video_source=$2

	# Check for valid video source
	if [ "$video_source" != "VIMEO" ] && [ "$video_source" != "YOUTUBE" ] && [ "$video_source" != "HTML" ]; then
		echo "video source not supported"
		exit 1;
	fi

	# Group am62pxx-evm and j722s-evm together
	if [ "$device_name" = "am62pxx-evm" ] || [ "$device_name" = "j722s-evm" ]; then
		if [ "$video_source" = "VIMEO" ] || [ "$video_source" = "YOUTUBE" ]; then
			# Higher thresholds for streaming sources
			if [ "$fhd_high_fps" = "true" ]; then
				echo 140
			else
				echo 100
			fi
		elif [ "$video_source" = "HTML" ]; then
			# Standard thresholds for HTML sources
			if [ "$fhd_high_fps" = "true" ]; then
				echo 100
			else
				echo 70
			fi
		fi
	# Group j742s2-evm and j784s4-evm together
	elif [ "$device_name" = "j742s2-evm" ] || [ "$device_name" = "j784s4-evm" ]; then
		if [ "$fhd_high_fps" = "true" ]; then
			echo 80
		else
			echo 60
		fi
	else
		# Return error for unsupported platforms
		echo "platform not supported"
	fi
}

get_chromium_cpu_utilization()
{
	# Define sampling parameters based on video length:
	# - SHORT_VIDEO: 2-6 minutes in length, uses more frequent sampling
	# - LONG_VIDEO: >6 minutes in length, uses less frequent sampling with stabilization period
	if [ "$1" = "SHORT_VIDEO" ]; then
		echo "Starting CPU utilization sampling (50 samples, 1 per second)..."
		local total_samples=50
		local sample_interval=1
	elif [ "$1" = "LONG_VIDEO" ]; then
		# Wait 30 seconds before sampling to allow playback to stabilize on long videos
		echo "Waiting another 30 seconds for playback to stabilize..."
		sleep 30
		echo "Starting CPU utilization sampling (100 samples, 1 per 3 seconds)..."
		local total_samples=100
		local sample_interval=3
	else
		echo "Invalid parameter for video length. Use SHORT_VIDEO or LONG_VIDEO."
		exit 2
	fi

	local cumulative_cpu=0

	for ((i=1; i<=$total_samples; i++)); do
		# Get fresh list of Chromium PIDs for each sample
		local pids=$(pgrep -f "chromium-bin")

		if [ -z "$pids" ]; then
			echo "No Chromium processes found in sample $i, failing test"
			exit 6
		fi

		# Get CPU usage for all Chromium processes using ps
		local sample_total_cpu=$(ps -p $(echo $pids | tr ' ' ',') -o %cpu= | awk '{sum+=$1} END {print sum}')
		local process_count=$(echo $pids | wc -w)

		# Add this sample to the cumulative total
		if [ ! -z "$sample_total_cpu" ]; then
			cumulative_cpu=$(echo "$cumulative_cpu + $sample_total_cpu" | bc)
			echo "Sample $i: Total CPU usage across $process_count processes: $sample_total_cpu%"
		else
			echo "Sample $i: Could not calculate CPU usage"
		fi

		# Wait for the next sample
		if [ $i -lt $total_samples ]; then
			sleep $sample_interval
		fi
	done

	local avg_cpu=$(echo "scale=2; $cumulative_cpu / $total_samples" | bc)
	echo "----------------------------------------"
	echo "Average CPU utilization over $total_samples samples: $avg_cpu%"

	# Return the average CPU utilization
	local temp_file=$2
	echo $avg_cpu > $temp_file

	pkill -f "chromium-bin"

	return 0
}

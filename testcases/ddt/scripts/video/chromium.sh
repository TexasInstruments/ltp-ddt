#!/bin/bash
#
# Copyright (C) 2026 Texas Instruments Incorporated - http://www.ti.com/
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

# Chromium return codes
readonly ERR_GENERAL=1                   # general error (e.g. install failure, broken binary)
readonly ERR_INVALID_PARAM=2             # invalid parameter passed to a function
readonly ERR_NO_DISPLAY=3                # no connected display found
readonly ERR_CHROMIUM_NOT_STARTED=4      # Chromium processes not detected after launch
readonly ERR_PLAYBACK_FAILED=5           # video playback verification failed
readonly ERR_COMMAND_NOT_FOUND=127       # command not found

# Chromium constants
readonly CHROMIUM_SCRIPTS_DIR=/opt/ltp/testcases/bin/ddt/chromium
readonly CHROMIUM_LAUNCH_WAIT=15         # seconds to wait after launch for Chromium to load the page
readonly CHROMIUM_SHUTDOWN_TIMEOUT=10    # max seconds to wait for Chromium processes to exit
readonly EMPTTY_START_TIMEOUT=3          # seconds to wait after restarting emptty

readonly HIGH_FPS_THRESHOLD=40           # minimum fps to be considered high fps

# CPU utilization thresholds (%) per platform and source type
readonly CPU_THRESHOLD_A53_HIGH_FPS=45   # am62pxx/j722s, high fps
readonly CPU_THRESHOLD_A53=30            # am62pxx/j722s, normal fps
readonly CPU_THRESHOLD_A72_HIGH_FPS=20   # j742s2, high fps (j784s4 uses half)
readonly CPU_THRESHOLD_A72=15            # j742s2, standard fps (j784s4 uses half)

chromium_setup()
{
	export WAYLAND_DISPLAY=/run/user/1000/wayland-1

	# Check if chromium is already installed
	if ! which chromium > /dev/null; then
		echo "Chromium not found, installing..."
		opkg update
		if ! opkg install chromium-ozone-wayland; then
			echo "ERROR: Failed to install Chromium. Check network connection and package availability." >&2
			return $ERR_GENERAL
		fi
	fi

	# Verify Chromium is working properly by checking version
	if ! chromium --version 2>/dev/null; then
		echo "ERROR: Chromium installation appears broken. Cannot get version information." >&2
		return $ERR_GENERAL
	fi
	echo "Chromium is installed and working properly"

	# Run kmsprint and capture output for display connector check
	local kmsprint_output
	kmsprint_output=$(kmsprint 2>/dev/null) || {
		echo "ERROR: Failed to run kmsprint command" >&2
		return $ERR_COMMAND_NOT_FOUND
	}

	# Check if the output contains "connected"
	if ! echo "$kmsprint_output" | grep -iq "(connected)"; then
		echo "ERROR: No connected display connector found" >&2
		return $ERR_NO_DISPLAY
	fi

	local connector=$(echo "$kmsprint_output" | grep "(connected)" \
		| sed -n 's/.*Connector [0-9]* ([0-9]*) \([^ ]*\) (connected).*/\1/p' | head -1)
	python3 ./weston_setup.py "$connector"

	# Enable debug mode for weston-screenshooter
	# Weston does not support the screen capture protocol, and instead uses an internal helper to fetch and dump active display contents
	if ! grep -q "Exec=.*--debug" /usr/share/wayland-sessions/weston.desktop 2>/dev/null; then
		sed -i 's|Exec=.*|& --debug|' /usr/share/wayland-sessions/weston.desktop
	fi
	systemctl restart emptty
	sleep $EMPTTY_START_TIMEOUT

	systemctl is-active --quiet emptty || { echo "ERROR: emptty service is not active" >&2; return $ERR_NO_DISPLAY; }
	kmsprint
}

close_chromium()
{
	pkill -9 -f "chromium-bin" 2>/dev/null  # SIGKILL prevents deferred shutdown
	for i in $(seq 1 $CHROMIUM_SHUTDOWN_TIMEOUT); do  # wait until all processes have exited
		pgrep -f "chromium-bin" > /dev/null || break
		sleep 1
	done
}

verify_video_playback()
{
	local __cdp_output
	echo "Verifying video playback via CDP..."
	__cdp_output=$(python3 "${CHROMIUM_SCRIPTS_DIR}/chromium_cdp_util.py")
	local __ret=$?
	echo "$__cdp_output"
	if [ $__ret -ne 0 ]; then
		echo "ERROR: Video playback verification failed" >&2
		close_chromium
		return $ERR_PLAYBACK_FAILED
	fi

	# Parse VIDEO_FPS and VIDEO_DURATION from CDP output
	VIDEO_FPS=$(echo "$__cdp_output" | grep -oE 'VIDEO_FPS:[0-9]+(\.[0-9]+)?' | cut -d: -f2)
	VIDEO_DURATION=$(echo "$__cdp_output" | grep -oE 'VIDEO_DURATION:[0-9]+(\.[0-9]+)?' | cut -d: -f2)
}

build_chromium_playback_cmd()
{
	local platform=$1
	local __media_url
	local __use_proxy=true
	local __quality=${3:-1080p}

	if [ "$platform" = "HTML" ]; then
		# Internal server, no proxy needed
		__media_url="http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/decoder/$2"
		__use_proxy=false
	elif [ "$platform" = "VIMEO" ]; then
		if [[ ! "$__quality" =~ ^(240p|360p|540p|720p|1080p|2k|4k)$ ]]; then
			# Invalid quality value
			echo "ERROR: Invalid quality parameter '$__quality' for VIMEO. Must be one of: 240p 360p 540p 720p 1080p 2k 4k" >&2
			return $ERR_INVALID_PARAM
		fi
		__media_url="https://player.vimeo.com/video/$2?quality=${__quality}&autoplay=1&loop=1"
	elif [ "$platform" = "YOUTUBE" ]; then
		__media_url="https://www.youtube.com/embed/$2?autoplay=1&loop=1"
	else
		echo "ERROR: Invalid media platform parameter. Must be 'HTML', 'VIMEO' or 'YOUTUBE'." >&2
		return $ERR_INVALID_PARAM
	fi

	# Build the command with appropriate environment variables
	local __cmd="export WAYLAND_DISPLAY=/run/user/1000/wayland-1;"

	# Add proxy settings if needed
	if [ "$__use_proxy" = true ]; then
		__cmd+=" export HTTPS_PROXY='http://webproxy.ext.ti.com:80';"
		__cmd+=" export HTTP_PROXY='http://webproxy.ext.ti.com:80';"
	fi
	__cmd+=" chromium \"${__media_url}\""
	__cmd+=" --start-fullscreen"
	__cmd+=" --no-first-run"
	__cmd+=" --hide-crash-restore-bubble"
	__cmd+=" --enable-logging=stderr"
	__cmd+=" --mute-audio"
	__cmd+=" --remote-debugging-port=9222"  # enables CDP for video playback verification
	__cmd+=" --remote-allow-origins=*"

	echo "$__cmd"
}

chromium_playback()
{
	# Get the command with environment variables setup
	local __cmd
	__cmd=$(build_chromium_playback_cmd "$@")
	local __ret=$?
	if [ $__ret -ne 0 ]; then
		return $__ret
	fi

	# Execute chromium command, suppressing all output
	su -l weston -c "$__cmd" &
	sleep $CHROMIUM_LAUNCH_WAIT  # allow Chromium to fully launch before checking for processes

	# Verify Chromium processes are running
	if ! pgrep -f "chromium-bin" > /dev/null; then
		echo "ERROR: Failed to detect Chromium processes" >&2
		return $ERR_CHROMIUM_NOT_STARTED
	fi

	verify_video_playback
	__ret=$?
	if [ $__ret -ne 0 ]; then
		return $__ret
	fi
	echo "Video playback verified successfully"
	echo "CPU_THRESHOLD:$(get_cpu_threshold)"
}

get_cpu_threshold()
{
	local device_name
	device_name=$(uname -n)
	local high_fps
	if [ $(echo "${VIDEO_FPS:-0} > $HIGH_FPS_THRESHOLD" | bc -l) -eq 1 ]; then high_fps=true; else high_fps=false; fi

	# Group am62pxx-evm and j722s-evm together
	if [ "$device_name" = "am62pxx-evm" ] || [ "$device_name" = "j722s-evm" ]; then
		if [ "$high_fps" = "true" ]; then
			echo $CPU_THRESHOLD_A53_HIGH_FPS
		else
			echo $CPU_THRESHOLD_A53
		fi
	elif [ "$device_name" = "j742s2-evm" ]; then
		if [ "$high_fps" = "true" ]; then
			echo $CPU_THRESHOLD_A72_HIGH_FPS
		else
			echo $CPU_THRESHOLD_A72
		fi
	elif [ "$device_name" = "j784s4-evm" ]; then
		if [ "$high_fps" = "true" ]; then
			echo $((CPU_THRESHOLD_A72_HIGH_FPS / 2))
		else
			echo $((CPU_THRESHOLD_A72 / 2))
		fi
	else
		# Return error for unsupported platforms
		echo "platform not supported"
		return $ERR_GENERAL
	fi
}

get_video_reference_url()
{
	local platform=$1
	local video_file=$2
	local base_url=""

	if [ "$platform" = "VIMEO" ]; then
		base_url="http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/decoder/chromium/vimeo"
	elif [ "$platform" = "HTML" ]; then
		base_url="http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/decoder/"
	fi

	# Return full URL if base_url exists, otherwise return video_file as-is
	if [ -n "$base_url" ]; then
		echo "$base_url/$video_file"
	else
		echo "$video_file"
	fi
}

download_reference_video()
{
	local url=$1
	local dest="/tmp/$(basename "${url%%\?*}")"

	if [[ ! "$url" =~ ^https?:// ]]; then
		echo "$url"
		return 0
	fi

	echo "Downloading reference video to $dest..." >&2
	if ! wget -q -O "$dest" "$url"; then
		rm -f "$dest"
		echo "ERROR: Failed to download $url" >&2
		return $ERR_GENERAL
	fi
	local size_mb=$(( $(stat -c%s "$dest") / 1048576 ))
	echo "Download complete (${size_mb} MB)" >&2
	echo "$dest"
}

run_chromium_playback_compare_as_weston()
{
	local video_file=$1
	local max_frames=${2:-20}
	local output_dir=${3:-playback_comparison}
	echo "Starting playback comparison test..."

	# Check if Chromium is running
	if ! pgrep -f "chromium-bin" > /dev/null; then
		echo "ERROR: Chromium is not running. Start it first with chromium_playback()" >&2
		return 1
	fi

	cd "${CHROMIUM_SCRIPTS_DIR}" && python3 chromium_playback_compare.py \
		--video "$video_file" --output-dir "$output_dir" --max-frames "$max_frames"
}

chromium_playback_with_comparison()
{
	local platform=$1
	local video_file_for_comparison
	local max_frames=20
	local media_id quality video_file

	# Parse args first so we can download the reference video before Chromium playback
	if [ "$platform" = "HTML" ]; then
		video_file=$2
		max_frames=${3:-$max_frames}
		video_file_for_comparison="$video_file"
	elif [ "$platform" = "VIMEO" ]; then
		media_id=$2
		quality=$3
		local golden_video_file=$4
		max_frames=${5:-$max_frames}
		video_file_for_comparison="$golden_video_file"
	else
		echo "ERROR: Unsupported platform: $platform" >&2
		return 1
	fi

	local video_reference
	video_reference=$(get_video_reference_url "$platform" "$video_file_for_comparison")

	local local_video
	local_video=$(download_reference_video "$video_reference")
	[ $? -ne 0 ] && return $ERR_GENERAL

	echo "Starting Chromium playback..."
	if [ "$platform" = "HTML" ]; then
		chromium_playback "$platform" "$video_file"
	elif [ "$platform" = "VIMEO" ]; then
		chromium_playback "$platform" "$media_id" "$quality"
	fi
	local ret=$?
	if [ $ret -ne 0 ]; then
		rm -f "$local_video"
		return $ret
	fi

	# Run playback comparison test (interval is calculated automatically from video duration)
	run_chromium_playback_compare_as_weston "$local_video" "$max_frames"
	local compare_ret=$?

	# Stop Chromium
	close_chromium
	rm -f "$local_video"

	if [ $compare_ret -eq 0 ]; then
		echo "Test PASSED: Video quality meets thresholds (SSIM > 0.85, PSNR > 25 dB)"
		return 0
	else
		echo "Test FAILED: Video quality below thresholds" >&2
		return 1
	fi
}


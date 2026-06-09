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
readonly CHROMIUM_LAUNCH_WAIT=15         # seconds to wait after launch for Chromium to load the page
readonly CHROMIUM_SHUTDOWN_TIMEOUT=10    # max seconds to wait for Chromium processes to exit
readonly EMPTTY_START_TIMEOUT=3          # max seconds to wait for emptty to reach active

readonly HIGH_FPS_THRESHOLD=40           # minimum fps to be considered high fps

# CPU utilization thresholds (%) per platform and source type
readonly CPU_THRESHOLD_A53_HIGH_FPS=45   # am62pxx/j722s, high fps
readonly CPU_THRESHOLD_A53=30            # am62pxx/j722s, normal fps
readonly CPU_THRESHOLD_A72_HIGH_FPS=20   # j742s2, high fps (j784s4 uses half)
readonly CPU_THRESHOLD_A72=15            # j742s2, standard fps (j784s4 uses half)

chromium_setup()
{
	export WAYLAND_DISPLAY="/run/user/1000/wayland-1"

	systemctl restart emptty
	sleep $EMPTTY_START_TIMEOUT

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

	echo "Display connector check passed - found connected display"
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
	__cdp_output=$(python3 "/opt/ltp/testcases/bin/ddt/chromium/chromium_cdp_util.py")
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
	__cmd+=" --enable-logging=stderr"
	__cmd+=" --vmodule=*media/gpu*=2"
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

	# Execute chromium command, filtering noisy dbus/ALSA errors from stderr
	su -l weston -c "$__cmd" 2>&1 | grep -v -e "dbus" -e "ALSA" >&2 &
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

#! /bin/sh
#
# Copyright (C) 2026 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS for A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# @desc Tests McASP runtime PM: verifies the audio controller enters
#       runtime suspend when idle and resumes when audio is requested.
#       Three phases (run all or individually):
#         idle - checks the suspended_time counter advances at
#                        >= THRESHOLD % of real elapsed time while idle
#         wake         - device becomes "active" within 3s of audio open
#         sleep        - device sleeps after audio closes (full cycle:
#                        suspended -> active during play -> suspended after)
# @params w) Timeout secs : Failure timeout for wake/sleep phases (default: 5)
#         t) Threshold    : Min % of idle window the counter must advance (default: 90)
#         s) Phase        : all|idle|wake|sleep (default: all)
#         r) Sample rate  : Rate for wake/sleep playback (default: 48000)
#         f) Sample format: Format for wake/sleep playback (default: S16_LE)
#         c) Channels     : Channels for wake/sleep playback (default: 2)
# @history 2026-06-06: First version

source "alsa_funcs.sh"

TIMEOUT=5
THRESHOLD=90
PHASE="all"
RATE=48000
FMT="S16_LE"
CH=2

usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/} [-w WAIT_SECS] [-t THRESHOLD_PCT] [-s PHASE] [-r RATE] [-f FMT] [-c CH]
	-w WAIT_SECS      Grace window (secs) added on top of pmdown_time for suspend deadline (default: $TIMEOUT)
	-t THRESHOLD_PCT  Min %% of idle window the suspended_time counter must advance (default: $THRESHOLD)
	-s PHASE          Test phase: all|idle|wake|sleep or comma-separated (default: $PHASE)
	-r RATE           Sample rate for wake/sleep test (default: $RATE)
	-f FMT            Sample format for wake/sleep test (default: $FMT)
	-c CH             Channel count for wake/sleep test (default: $CH)
	EOF
	exit 0
}

while getopts :w:t:s:r:f:c:h arg
do case $arg in
	w)	TIMEOUT="$OPTARG";;
	t)	THRESHOLD="$OPTARG";;
	s)	PHASE="$OPTARG";;
	r)	RATE="$OPTARG";;
	f)	FMT="$OPTARG";;
	c)	CH="$OPTARG";;
	h)	usage;;
	:)	die "$0: Must supply an argument to -$OPTARG.";;
	\?)	die "Invalid Option -$OPTARG";;
esac
done

[ "$TIMEOUT" -ge 1 ] 2>/dev/null || die "-w TIMEOUT must be a positive integer (got: ${TIMEOUT})"

phase_enabled() { [ "$PHASE" = "all" ] || echo ",$PHASE," | grep -q ",$1,"; }

############################ Helper Functions ##################################

# Return the power/ sysfs path for the McASP hardware device.
# Searches /sys/devices for a path component matching *.audio-controller or *.mcasp.
find_mcasp_power()
{
	local paths active count
	paths=$(find /sys/devices -maxdepth 7 -name power 2>/dev/null \
		| grep -E '/[0-9a-f]+\.(audio-controller|mcasp)/')
	count=$(echo "$paths" | grep -c . 2>/dev/null || echo 0)
	[ "$count" -gt 1 ] && \
		test_print_trc "find_mcasp_power: $count instances found, selecting active" >&2
	# Prefer an instance where runtime PM is supported (status != unsupported).
	# Some SoCs enumerate multiple McASP nodes; only the one bound to the sound
	# card has a meaningful runtime_status.
	active=$(echo "$paths" | while IFS= read -r p; do
		[ -n "$p" ] && [ "$(cat "$p/runtime_status" 2>/dev/null)" != "unsupported" ] && echo "$p"
	done | head -1)
	echo "${active:-$(echo "$paths" | head -1)}"
}

# Poll runtime_status until it equals $2, or TIMEOUT $3 seconds expires.
# Returns 0 on match, 1 on timeout.
wait_for_status()
{
	local power_path="$1" expected="$2" timeout_secs="$3"
	local i=0 limit
	limit=$((timeout_secs * 2))
	while [ "$i" -lt "$limit" ]; do
		[ "$(cat "$power_path/runtime_status" 2>/dev/null)" = "$expected" ] && return 0
		sleep 0.5
		i=$((i + 1))
	done
	return 1
}

# Measure time from $3 (ms, date +%s%3N) to when the device enters suspended state.
# Uses runtime_suspended_time counter back-computation: when C > C0 is first detected,
# the device has been suspended for (C - C0) ms, so the actual suspend wall time is
# T_detect - (C - C0). This gives ms accuracy independent of poll interval.
# Prints elapsed ms on success, returns 1 on timeout.
time_to_suspend()
{
	local power_path="$1" timeout_secs="$2" t_ref="$3"
	local c0 c t i=0 limit result
	limit=$((timeout_secs * 100))
	c0=$(cat "$power_path/runtime_suspended_time" 2>/dev/null)
	[ -z "$c0" ] && return 1
	while [ "$i" -lt "$limit" ]; do
		c=$(cat "$power_path/runtime_suspended_time" 2>/dev/null)
		t=$(date +%s%3N)
		if [ -n "$c" ] && [ "$c" -gt "$c0" ]; then
			result=$(( t - (c - c0) - t_ref ))
			[ "$result" -lt 0 ] && result=0
			echo "$result"
			return 0
		fi
		sleep 0.01
		i=$((i + 1))
	done
	return 1
}

# Poll at 10ms intervals; print elapsed ms to stdout on success, return 1 on timeout.
# $4 t_start (optional): external start time from date +%s%3N — use to anchor the
# measurement to an earlier event (e.g. stream open) rather than poll-loop entry.
# Resolution ~10ms (one poll interval); accuracy ±10ms worst-case.
time_to_status()
{
	local power_path="$1" expected="$2" timeout_secs="$3" t_start="${4:-}"
	local t0 t1 i=0 limit
	limit=$((timeout_secs * 100))
	[ -n "$t_start" ] && t0="$t_start" || t0=$(date +%s%3N)
	while [ "$i" -lt "$limit" ]; do
		if [ "$(cat "$power_path/runtime_status" 2>/dev/null)" = "$expected" ]; then
			t1=$(date +%s%3N)
			echo $((t1 - t0))
			return 0
		fi
		sleep 0.01
		i=$((i + 1))
	done
	return 1
}

# Return an ALSA hw:X,Y playback device (first card found).
find_play_dev()
{
	aplay -l 2>/dev/null \
		| awk '/^card [0-9]+:/{
			match($0, /card ([0-9]+):.*device ([0-9]+):/, a)
			if (a[1] != "") { print "hw:" a[1] "," a[2]; exit }
		  }' \
		|| echo "hw:0,0"
}

# Probe the first sample format supported by $1 (hw:X,Y) at 48000Hz stereo.
# Uses --dump-hw-params to inspect device capabilities without blocking.
# Falls back to S16_LE if detection fails.
find_play_fmt()
{
	local dev="$1"
	local formats raw
	# --dump-hw-params prints hw params then exits immediately with error;
	# the FORMAT: line lists supported formats in order.
	raw=$(aplay -D "$dev" -r 48000 -c 2 --dump-hw-params /dev/zero 2>&1 | \
		grep '^FORMAT:' | head -1)
	for fmt in S16_LE S32_LE S24_LE S24_3LE; do
		echo "$raw" | grep -qw "$fmt" && echo "$fmt" && return 0
	done
	echo "S16_LE"
}

############################ Setup #############################################

POWER_PATH=$(find_mcasp_power)
[ -z "$POWER_PATH" ] && skip_test "No McASP/audio-controller device found under /sys/devices"
[ -f "$POWER_PATH/runtime_status" ] \
	|| skip_test "runtime_status sysfs absent (CONFIG_PM_RUNTIME not enabled?)"
[ "$(cat "$POWER_PATH/control" 2>/dev/null)" = "auto" ] \
	|| skip_test "Runtime PM not enabled for McASP (power/control != auto)"

PLAY_DEV_GLOBAL=$(find_play_dev)
DETECTED_FMT=$(find_play_fmt "$PLAY_DEV_GLOBAL")
# If the user-specified format differs from what the device supports, auto-correct.
if [ "$DETECTED_FMT" != "$FMT" ]; then
	test_print_trc "Format auto-corrected: $FMT -> $DETECTED_FMT (device: $PLAY_DEV_GLOBAL)"
	FMT="$DETECTED_FMT"
fi

test_print_trc "ENV board=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0') kernel=$(uname -r)"
test_print_trc "audio modules: $(lsmod | grep -E 'snd_soc|davinci|tlv|pcm624|tac5|sii9' | awk '{print $1}' | tr '\n' ' ')"
test_print_trc "card: $(aplay -l 2>/dev/null | grep -i mcasp | head -1 | sed 's/^card [0-9]*: //')"
test_print_trc "McASP power path : $POWER_PATH  runtime_status=$(cat "$POWER_PATH/runtime_status" 2>/dev/null)  control=$(cat "$POWER_PATH/control" 2>/dev/null)"
test_print_trc "Playback device  : $PLAY_DEV_GLOBAL  Format: $FMT"
PMDOWN_MS=$(find /sys/devices/platform/sound -maxdepth 2 -name pmdown_time 2>/dev/null \
	| head -1 | xargs cat 2>/dev/null)
[ -z "$PMDOWN_MS" ] && PMDOWN_MS=5000
SLEEP_DEADLINE=$(( PMDOWN_MS / 1000 + TIMEOUT ))

test_print_trc "Phase            : $PHASE  Grace: ${TIMEOUT}s  pmdown_time: ${PMDOWN_MS}ms  suspend_deadline: ${SLEEP_DEADLINE}s  Threshold: ${THRESHOLD}%"

############################ Phase: idle ################################
# Verifies:
#   1. Device reaches "suspended" state within TIMEOUT seconds of being idle.
#   2. The runtime_suspended_time counter advances at >= THRESHOLD% of real
#      elapsed time during the idle window — confirming the device is spending
#      most of the idle period in the suspended power state.

if phase_enabled idle; then
	test_print_trc "--- phase: idle ---"

	PLAY_DEV="$PLAY_DEV_GLOBAL"

	# Ensure device is idle (not held open by a prior phase or stray process).
	# A 1-second aplay followed by a close gives a clean baseline.
	# Use a fixed 15s settle window here — this is setup, not a pass/fail gate;
	# TIMEOUT is the failure threshold for the actual wake/sleep assertions below.
	aplay -q -d 1 -D "$PLAY_DEV" -f "$FMT" -r "$RATE" -c "$CH" /dev/zero || true
	_idle_status=$(cat "$POWER_PATH/runtime_status" 2>/dev/null)
	wait_for_status "$POWER_PATH" "suspended" 15 \
		|| die "McASP did not re-suspend within 15s after baseline aplay (status=$_idle_status)"

	# Calibrate counter units: measure advance over 1 wall-clock second.
	C_CAL1=$(cat "$POWER_PATH/runtime_suspended_time")
	T_CAL1=$(date +%s%3N)
	sleep 1
	C_CAL2=$(cat "$POWER_PATH/runtime_suspended_time")
	T_CAL2=$(date +%s%3N)
	CAL_DELTA=$((C_CAL2 - C_CAL1))
	CAL_MS=$((T_CAL2 - T_CAL1))
	[ "$CAL_DELTA" -gt 0 ] || die "suspended_time counter not advancing (device may not be truly suspended)"
	[ "$CAL_MS"    -gt 0 ] || die "calibration wall-clock elapsed zero"
	test_print_trc "counter rate: ${CAL_DELTA} units / ${CAL_MS}ms"

	# Idle window: anchor expected advance to actual wall-clock elapsed time.
	C1=$(cat "$POWER_PATH/runtime_suspended_time")
	T1=$(date +%s%3N)
	sleep "$TIMEOUT"
	C2=$(cat "$POWER_PATH/runtime_suspended_time")
	T2=$(date +%s%3N)
	STATUS=$(cat "$POWER_PATH/runtime_status")

	DELTA=$((C2 - C1))
	ELAPSED_MS=$((T2 - T1))
	EXPECTED=$((CAL_DELTA * ELAPSED_MS / CAL_MS))
	[ "$EXPECTED" -gt 0 ] || die "expected counter advance is zero"
	RATIO=$((DELTA * 100 / EXPECTED))

	test_print_trc "idle window: delta=${DELTA} elapsed=${ELAPSED_MS}ms expected=${EXPECTED} ratio=${RATIO}% status=$STATUS"

	[ "$STATUS" = "suspended" ] \
		|| die "McASP not suspended at end of ${TIMEOUT}s idle window (status=$STATUS)"
	[ "$RATIO" -ge "$THRESHOLD" ] \
		|| die "Suspend ratio ${RATIO}% below threshold ${THRESHOLD}%"

	test_print_trc "PASS: mcasp_idle_ratio = ${RATIO}%  (threshold ${THRESHOLD}%)"
fi

############################ Phase: wake on use #################################

if phase_enabled wake; then
	test_print_trc "--- phase: wake ---"

	PLAY_DEV="$PLAY_DEV_GLOBAL"
	test_print_trc "playback device: $PLAY_DEV"

	PRE_STATUS=$(cat "$POWER_PATH/runtime_status")
	test_print_trc "status before open: $PRE_STATUS"
	[ "$PRE_STATUS" = "suspended" ] \
		|| skip_test "McASP not suspended before wake test (status=$PRE_STATUS)"

	T_OPEN=$(date +%s%3N)
	aplay -q -D "$PLAY_DEV" -f "$FMT" -r "$RATE" -c "$CH" /dev/zero &
	APLAY_PID=$!

	WAKE_MS=$(time_to_status "$POWER_PATH" "active" 3 "$T_OPEN")
	if [ $? -ne 0 ]; then
		kill "$APLAY_PID" 2>/dev/null; wait "$APLAY_PID" 2>/dev/null
		die "McASP did not wake within 3s of aplay start (status=$(cat "$POWER_PATH/runtime_status"))"
	fi

	test_print_trc "PASS: mcasp_wake = ${WAKE_MS}ms (includes aplay startup)"
	kill "$APLAY_PID" 2>/dev/null; wait "$APLAY_PID" 2>/dev/null
fi

############################ Phase: sleep after use ###########################

if phase_enabled sleep; then
	test_print_trc "--- phase: sleep ---"

	PLAY_DEV="$PLAY_DEV_GLOBAL"

	# 15s fixed window — setup, not a pass/fail gate. TIMEOUT=5 is too tight here
	# because ASoC pmdown_time alone is 5000ms; TIMEOUT is the post-close assertion.
	wait_for_status "$POWER_PATH" "suspended" 15 \
		|| die "McASP not suspended before sleep test (status=$(cat "$POWER_PATH/runtime_status"))"
	test_print_trc "status before playback: suspended"

	aplay -q -D "$PLAY_DEV" -f "$FMT" -r "$RATE" -c "$CH" /dev/zero &
	APLAY_PID=$!

	if ! wait_for_status "$POWER_PATH" "active" 3; then
		kill "$APLAY_PID" 2>/dev/null; wait "$APLAY_PID" 2>/dev/null
		die "McASP did not become active during playback (status=$(cat "$POWER_PATH/runtime_status"))"
	fi
	test_print_trc "status during playback: active"

	sleep 2
	kill "$APLAY_PID" 2>/dev/null; wait "$APLAY_PID" 2>/dev/null
	T_CLOSE=$(date +%s%3N)
	test_print_trc "stream closed — polling for re-suspend (deadline: ${SLEEP_DEADLINE}s)"

	SLEEP_MS=$(time_to_suspend "$POWER_PATH" "$SLEEP_DEADLINE" "$T_CLOSE")
	if [ $? -ne 0 ]; then
		die "McASP not suspended within ${SLEEP_DEADLINE}s of stream close (status=$(cat "$POWER_PATH/runtime_status"))"
	fi

	test_print_trc "PASS: mcasp_suspend = ${SLEEP_MS}ms after stream close"
fi

test_print_trc "All phases passed"

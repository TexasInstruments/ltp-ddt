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
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# @desc Tests McASP audio across system S3 suspend-to-RAM and resume.
#       Suspend is triggered via rtcwake -m mem on /dev/rtc0 with mem_sleep
#       explicitly set to deep. Skips on platforms where deep sleep is
#       unavailable. The system enters S3 and wakes after the specified
#       interval. Two scenarios (run all or individually):
#         midstream - McASP playback active when S2RAM suspend is triggered;
#                     verifies the stream survives resume with at most one xrun
#                     at the suspend boundary and no driver errors in dmesg.
#         newstream  - system enters S2RAM with no open McASP streams; verifies
#                     a fresh playback and capture stream can be opened cleanly
#                     after resume.
# @params s) Scenario      : all|midstream|newstream (default: all)
#         t) Suspend secs  : seconds to stay suspended (default: 10)
#         r) Sample rate   : (default: 48000)
#         f) Sample format : (default: S16_LE)
#         c) Channels      : (default: 2)
# @history 2026-06-07: First version

source "alsa_funcs.sh"
source "functions.sh"

SCENARIO="all"
SUSPEND_SECS=10
RATE=48000
FMT="S16_LE"
CH=2

usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/} [-s SCENARIO] [-t SUSPEND_SECS] [-r RATE] [-f FMT] [-c CH]
	-s SCENARIO      Test scenario: all|midstream|newstream (default: all)
	-t SUSPEND_SECS  Seconds to stay suspended (default: 10)
	-r RATE          Sample rate (default: 48000)
	-f FMT           Sample format (default: S16_LE)
	-c CH            Channel count (default: 2)
	EOF
	exit 0
}

while getopts :s:t:r:f:c:h arg
do case $arg in
	s)	SCENARIO="$OPTARG";;
	t)	SUSPEND_SECS="$OPTARG";;
	r)	RATE="$OPTARG";;
	f)	FMT="$OPTARG";;
	c)	CH="$OPTARG";;
	h)	usage;;
	:)	die "$0: Must supply an argument to -$OPTARG.";;
	\?)	die "Invalid Option -$OPTARG";;
esac
done

[ "$SUSPEND_SECS" -ge 1 ] 2>/dev/null \
	|| die "-t SUSPEND_SECS must be a positive integer (got: ${SUSPEND_SECS})"

############################ Helper Functions ##################################

# Return hw:X,Y for the first McASP playback or capture device.
# Falls back to the first available device if no McASP name is found.
find_mcasp_dev()
{
	local type="$1"  # play | record
	local cmd dev
	[ "$type" = "play" ] && cmd="aplay" || cmd="arecord"
	dev=$($cmd -l 2>/dev/null | grep -i mcasp \
		| awk '/^card [0-9]+:/{
			match($0, /card ([0-9]+):.*device ([0-9]+):/, a)
			if (a[1] != "") { print "hw:" a[1] "," a[2]; exit }
		  }')
	[ -n "$dev" ] || dev=$($cmd -l 2>/dev/null \
		| awk '/^card [0-9]+:/{
			match($0, /card ([0-9]+):.*device ([0-9]+):/, a)
			if (a[1] != "") { print "hw:" a[1] "," a[2]; exit }
		  }')
	echo "${dev:-hw:0,0}"
}

check_dmesg_mcasp_errors()
{
	local errs
	errs=$(dmesg 2>/dev/null | grep -i mcasp \
		| grep -iE "error|fail|timeout|BUG" | tail -5)
	[ -z "$errs" ] && return 0
	test_print_err "McASP errors in dmesg after resume:"
	echo "$errs" | while read -r line; do test_print_err "  $line"; done
	return 1
}

############################ Setup #############################################

PLAY_DEV=$(find_mcasp_dev play)
REC_DEV=$(find_mcasp_dev record)

aplay   -l 2>/dev/null | grep -qi mcasp \
	|| skip_test "No McASP playback device found"
arecord -l 2>/dev/null | grep -qi mcasp \
	|| skip_test "No McASP capture device found"
ls /dev/rtc[0-9]* >/dev/null 2>&1 \
	|| skip_test "no RTC device found — no wakeup source for suspend"
command -v rtcwake >/dev/null 2>&1 \
	|| skip_test "rtcwake not available"

power_states=$(cat /sys/power/state 2>/dev/null)
mem_sleep_val=$(cat /sys/power/mem_sleep 2>/dev/null || echo "absent")
[ -n "$power_states" ] \
	|| skip_test "System suspend unavailable — /sys/power/state is empty (CONFIG_SUSPEND not set)"
echo "$power_states" | grep -qw mem \
	|| skip_test "Suspend state 'mem' not listed — available: '$power_states'"
grep -q '\[deep\]' /sys/power/mem_sleep 2>/dev/null \
	|| skip_test "S3 deep not active — mem_sleep='$mem_sleep_val'"

test_print_trc "ENV board=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0') kernel=$(uname -r) power_states='$(cat /sys/power/state 2>/dev/null)' mem_sleep='$(cat /sys/power/mem_sleep 2>/dev/null)'"
test_print_trc "audio modules: $(lsmod | grep -E 'snd_soc|davinci|tlv|pcm624|tac5|sii9' | awk '{print $1}' | tr '\n' ' ')"
test_print_trc "card: $(aplay -l 2>/dev/null | grep -i mcasp | head -1 | sed 's/^card [0-9]*: //')"
test_print_trc "Playback device : $PLAY_DEV"
test_print_trc "Capture device  : $REC_DEV"
test_print_trc "Scenario        : $SCENARIO  Suspend: ${SUSPEND_SECS}s"
test_print_trc "Format          : $FMT  Rate: $RATE  Channels: $CH"

XRUN_LOG=$(mktemp /tmp/alsa_xrun_XXXXXX.log)
CAP_FILE=$(mktemp /tmp/alsa_cap_XXXXXX.wav)
trap 'rm -f "$XRUN_LOG" "$CAP_FILE"; kill "$PLAY_PID" 2>/dev/null' EXIT

############################ Scenario: midstream ################################
# Start playback before suspend. After resume the stream should continue
# with at most one xrun (at the suspend boundary) and no driver errors.

if [ "$SCENARIO" = "all" ] || [ "$SCENARIO" = "midstream" ]; then
	test_print_trc "--- scenario: midstream ---"

	aplay -D "$PLAY_DEV" -f "$FMT" -r "$RATE" -c "$CH" /dev/zero \
		2>"$XRUN_LOG" &
	PLAY_PID=$!
	sleep 1

	kill -0 "$PLAY_PID" 2>/dev/null \
		|| die "aplay failed to start before suspend ($(cat "$XRUN_LOG"))"
	test_print_trc "aplay running (PID $PLAY_PID)"

	suspend -p mem -t "$SUSPEND_SECS" -i 1

	kill -0 "$PLAY_PID" 2>/dev/null \
		|| die "aplay terminated during suspend/resume — McASP stream not restored"
	test_print_trc "aplay alive after resume"

	XRUNS=$(grep -c "underrun\|xrun\|XRUN" "$XRUN_LOG" 2>/dev/null || echo 0)
	test_print_trc "xrun count: $XRUNS"
	[ "$XRUNS" -le 1 ] \
		|| die "McASP DMA produced $XRUNS xruns after resume (threshold: 1)"

	kill "$PLAY_PID" 2>/dev/null
	wait "$PLAY_PID" 2>/dev/null
	PLAY_PID=""

	check_dmesg_mcasp_errors \
		|| die "McASP driver errors after midstream suspend/resume"

	test_print_trc "PASS: midstream — stream survived, xruns=$XRUNS"
fi

############################ Scenario: newstream ################################
# No open streams at suspend time. After resume, a fresh playback stream and
# a fresh capture stream must both open and transfer data without error.

if [ "$SCENARIO" = "all" ] || [ "$SCENARIO" = "newstream" ]; then
	test_print_trc "--- scenario: newstream ---"

	sleep 1
	suspend -p mem -t "$SUSPEND_SECS" -i 1

	aplay -D "$PLAY_DEV" -f "$FMT" -r "$RATE" -c "$CH" -d 3 /dev/zero \
		2>"$XRUN_LOG"
	PLAY_RC=$?
	[ "$PLAY_RC" -eq 0 ] \
		|| die "aplay failed after resume (exit $PLAY_RC: $(cat "$XRUN_LOG"))"
	test_print_trc "new playback stream: OK"

	arecord -D "$REC_DEV" -f "$FMT" -r "$RATE" -c "$CH" -d 3 -t wav \
		"$CAP_FILE" 2>/dev/null
	REC_RC=$?
	[ "$REC_RC" -eq 0 ] \
		|| die "arecord failed after resume (exit $REC_RC)"
	CAP_SIZE=$(stat -c %s "$CAP_FILE" 2>/dev/null || echo 0)
	[ "$CAP_SIZE" -gt 0 ] \
		|| die "capture file empty after resume — McASP RX DMA not working"

	# Verify captured PCM is not all zeros. Skip the 44-byte WAV header and
	# count non-zero bytes in the audio data. A live ADC always produces at
	# least thermal/ambient noise; all-zero data means DMA or clocks are stuck.
	NONZERO=$(dd if="$CAP_FILE" bs=1 skip=44 2>/dev/null | tr -d '\000' | wc -c)
	[ "$NONZERO" -gt 0 ] \
		|| die "capture data is all zeros after resume — McASP RX clocks or DMA not restored"
	test_print_trc "new capture stream: OK (${CAP_SIZE} bytes, ${NONZERO} non-zero bytes)"

	check_dmesg_mcasp_errors \
		|| die "McASP driver errors after newstream suspend/resume"

	test_print_trc "PASS: newstream — play OK, capture ${CAP_SIZE}B"
fi

test_print_trc "All scenarios passed"
exit 0


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
# @desc Tests McASP async mode by running simultaneous playback and
#       capture. In async mode the playback and capture serializers
#       use independent clocks, so this test validates that both
#       directions can operate concurrently without errors.
# @params R) Record Device   : Audio Record Device (e.g. hw:0,0)
#         P) Playback Device : Audio Playback Device (e.g. hw:0,0)
#         r) Sample rate     : Playback Sample rate (44100,48000 etc)
#         s) Rec Sample rate : Capture Sample rate (44100,48000 etc)
#         f) Sample Format   : Sample Format for both directions (S16_LE,S32_LE etc)
#         d) Duration        : Duration in Secs.
#         c) Channel         : Channel count for both directions.
#         l) Capture Log     : Whether to retain captured file (1) or delete (0).
# @history 2026-02-13: First version

source "alsa_funcs.sh"  # Import do_cmd(), die() and other functions

usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/} [-R REC_DEVICE] [-P PLAY_DEVICE] [-r SAMPLE_RATE] [-s REC_SAMPLERATE] [-f SAMPLE_FORMAT] [-c CHANNEL] [-d DURATION] [-l CAPTURELOG_FLAG]
	-R REC_DEVICE       Record Device Name like hw:0,0.
	-P PLAY_DEVICE      Playback Device Name like hw:0,0.
	-r SAMPLE_RATE      Playback Sample Rate like 44100,48000 etc.
	-s REC_SAMPLERATE   Capture Sample Rate like 44100,48000 etc.
	-f SAMPLE_FORMAT    Sample Format for both directions like S16_LE,S32_LE.
	-c CHANNEL          Channel count for both directions like 2,4.
	-d DURATION         Duration In Secs like 5,10 etc.
	-l CAPTURELOG_FLAG  Whether to retain captured file or delete.( 1 -> To retain, 0 -> delete )
	EOF
	exit 0
}

################################ CLI Params ####################################
while getopts  :R:P:r:s:f:d:c:l:h arg
do case $arg in
        R)      REC_DEVICE="$OPTARG";;
        P)      PLAY_DEVICE="$OPTARG";;
        r)      SAMPLERATE="$OPTARG";;
        s)      REC_SAMPLERATE="$OPTARG";;
        f)      SAMPLEFORMAT="$OPTARG";;
        d)      DURATION="$OPTARG";;
        c)      CHANNEL="$OPTARG";;
        l)      CAPTURELOGFLAG="$OPTARG";;
        h)      usage;;
        :)      die "$0: Must supply an argument to -$OPTARG.";;
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

############################ Default Values for Params ###############################
# Auto-select devices if not specified. Use the first apture device for RX,
# and prefers a playback-only device (not in capture list) for TX.
if [ -z "$PLAY_DEVICE" ] || [ -z "$REC_DEVICE" ]; then
	PLAY_DEVS=$(aplay -l 2>/dev/null | grep '^card' | \
		sed 's/card \([0-9]*\):.*device \([0-9]*\):.*/hw:\1,\2/')
	REC_DEVS=$(arecord -l 2>/dev/null | grep '^card' | \
		sed 's/card \([0-9]*\):.*device \([0-9]*\):.*/hw:\1,\2/')
	[ -z "$REC_DEVICE" ] && REC_DEVICE=$(echo "$REC_DEVS" | head -1)
	if [ -z "$PLAY_DEVICE" ]; then
		for dev in $PLAY_DEVS; do
			echo "$REC_DEVS" | grep -qF "$dev" || { PLAY_DEVICE="$dev"; break; }
		done
		[ -z "$PLAY_DEVICE" ] && PLAY_DEVICE=$(echo "$PLAY_DEVS" | head -1)
	fi
fi
[ -z "$PLAY_DEVICE" ] && die "No playback device found"
[ -z "$REC_DEVICE" ]  && die "No capture device found"

PLAY_CAP_STRING=$(dump_hw_params play "$PLAY_DEVICE" | \
	grep -Ev "^(Playing |aplay:|Available formats:|- )|^[[:space:]]")
REC_CAP_STRING=$(dump_hw_params record "$REC_DEVICE" | \
	grep -Ev "^(Recording |Warning:|arecord:|Available formats:|- )|^[[:space:]]")

: ${SAMPLERATE:=$(get_default_val "$PLAY_CAP_STRING" "RATE")}
: ${REC_SAMPLERATE:=$(get_default_val "$REC_CAP_STRING" "RATE")}
# Use per-device format, period, buffer, and channel — devices may differ
PLAY_SAMPLEFORMAT=${SAMPLEFORMAT:-$(get_default_val "$PLAY_CAP_STRING" "FORMAT")}
REC_SAMPLEFORMAT=${SAMPLEFORMAT:-$(get_default_val "$REC_CAP_STRING" "FORMAT")}
PLAY_PERIODSIZE=$(get_default_val "$PLAY_CAP_STRING" "PERIOD_SIZE" 1)
REC_PERIODSIZE=$(get_default_val "$REC_CAP_STRING" "PERIOD_SIZE" 1)
PLAY_BUFFERSIZE=$(get_default_val "$PLAY_CAP_STRING" "BUFFER_SIZE" 1)
REC_BUFFERSIZE=$(get_default_val "$REC_CAP_STRING" "BUFFER_SIZE" 1)
: ${DURATION:='10'}
PLAY_CHANNELS=${CHANNEL:-$(get_default_val "$PLAY_CAP_STRING" "CHANNELS" 1)}
REC_CHANNELS=${CHANNEL:-$(get_default_val "$REC_CAP_STRING" "CHANNELS" 1)}
: ${CAPTURELOGFLAG:='0'}

[ -z "$SAMPLERATE" ]      && die "Could not determine playback sample rate for $PLAY_DEVICE"
[ -z "$REC_SAMPLERATE" ]  && die "Could not determine capture sample rate for $REC_DEVICE"
[ -z "$PLAY_SAMPLEFORMAT" ] && die "Could not determine playback format for $PLAY_DEVICE"
[ -z "$REC_SAMPLEFORMAT" ]  && die "Could not determine capture format for $REC_DEVICE"
[ -z "$PLAY_CHANNELS" ]   && die "Could not determine playback channels for $PLAY_DEVICE"
[ -z "$REC_CHANNELS" ]    && die "Could not determine capture channels for $REC_DEVICE"
[ -z "$PLAY_PERIODSIZE" ] && die "Could not determine playback period size for $PLAY_DEVICE"
[ -z "$REC_PERIODSIZE" ]  && die "Could not determine capture period size for $REC_DEVICE"

PLAY_FILE="/tmp/async_play_${SAMPLERATE}hz_${PLAY_SAMPLEFORMAT}_${PLAY_CHANNELS}ch_$$.wav"
CAPTURE_FILE="/tmp/async_capture_${REC_SAMPLERATE}hz_${REC_SAMPLEFORMAT}_${REC_CHANNELS}ch_$$.wav"
trap 'rm -f "$PLAY_FILE"' EXIT

test_print_trc " ****************** TEST PARAMETERS ******************"
test_print_trc " REC_DEVICE       : $REC_DEVICE"
test_print_trc " PLAY_DEVICE      : $PLAY_DEVICE"
test_print_trc " DURATION         : $DURATION"
test_print_trc " PLAY SAMPLERATE  : $SAMPLERATE"
test_print_trc " PLAY FORMAT      : $PLAY_SAMPLEFORMAT"
test_print_trc " PLAY CHANNELS    : $PLAY_CHANNELS"
test_print_trc " PLAY PERIOD SIZE : $PLAY_PERIODSIZE"
test_print_trc " PLAY BUFFER SIZE : $PLAY_BUFFERSIZE"
test_print_trc " REC SAMPLERATE   : $REC_SAMPLERATE"
test_print_trc " REC FORMAT       : $REC_SAMPLEFORMAT"
test_print_trc " REC CHANNELS     : $REC_CHANNELS"
test_print_trc " REC PERIOD SIZE  : $REC_PERIODSIZE"
test_print_trc " REC BUFFER SIZE  : $REC_BUFFERSIZE"
test_print_trc " PLAY_FILE        : $PLAY_FILE"
test_print_trc " CAPTURE_FILE     : $CAPTURE_FILE"
test_print_trc " *************** END OF TEST PARAMETERS ***************"

test_print_trc " ****************** AUDIO DEV INFO ******************"
aplay -l
arecord -l
echo "Playback HW Params:"
echo "$PLAY_CAP_STRING"
echo "Record HW Params:"
echo "$REC_CAP_STRING"
test_print_trc " *************** END OF AUDIO DEV INFO ***************"

# Generate playback audio at exact format/rate/channels for the playback device.
# Ceiling division ensures the file covers the full duration.
GST_FORMAT=$(echo "$PLAY_SAMPLEFORMAT" | tr -d '_')
NUM_BUFFERS=$(( (SAMPLERATE * DURATION + 1023) / 1024 ))
test_print_trc "Generating playback audio: gst-launch-1.0 audiotestsrc num-buffers=$NUM_BUFFERS ! audio/x-raw,format=$GST_FORMAT,rate=$SAMPLERATE,channels=$PLAY_CHANNELS ! wavenc ! filesink location=$PLAY_FILE"
gst-launch-1.0 audiotestsrc num-buffers="$NUM_BUFFERS" ! \
	"audio/x-raw,format=$GST_FORMAT,rate=$SAMPLERATE,channels=$PLAY_CHANNELS" ! \
	wavenc ! filesink location="$PLAY_FILE" || die "Failed to generate playback audio"

# Start playback using hw: directly
test_print_trc "Starting async playback: aplay -D $PLAY_DEVICE -f $PLAY_SAMPLEFORMAT -r $SAMPLERATE -c $PLAY_CHANNELS --buffer-size=$PLAY_BUFFERSIZE --period-size $PLAY_PERIODSIZE -d $DURATION $PLAY_FILE"
aplay -D "$PLAY_DEVICE" -f "$PLAY_SAMPLEFORMAT" -r "$SAMPLERATE" -c "$PLAY_CHANNELS" \
	--buffer-size="$PLAY_BUFFERSIZE" --period-size "$PLAY_PERIODSIZE" -d "$DURATION" "$PLAY_FILE" &
PLAY_PID=$!

# Start capture simultaneously using per-device params
test_print_trc "Starting async capture: arecord -D $REC_DEVICE -f $REC_SAMPLEFORMAT -r $REC_SAMPLERATE -c $REC_CHANNELS --buffer-size=$REC_BUFFERSIZE --period-size $REC_PERIODSIZE -d $DURATION -t wav $CAPTURE_FILE"
arecord -D "$REC_DEVICE" -f "$REC_SAMPLEFORMAT" -r "$REC_SAMPLERATE" -c "$REC_CHANNELS" \
	--buffer-size="$REC_BUFFERSIZE" --period-size "$REC_PERIODSIZE" -d "$DURATION" -t wav "$CAPTURE_FILE" &
REC_PID=$!

test_print_trc "Playback PID: $PLAY_PID, Capture PID: $REC_PID"

RESULT=0

# Wait for playback to complete
wait $PLAY_PID
PLAY_RC=$?
if [ $PLAY_RC -ne 0 ] ; then
	test_print_err "Async playback failed with return code $PLAY_RC"
	kill $REC_PID 2>/dev/null
	RESULT=$(( $RESULT + 1 ))
else
	test_print_trc "Async playback completed successfully"
fi

# Wait for capture to complete
wait $REC_PID
REC_RC=$?
if [ $REC_RC -ne 0 ] ; then
	test_print_err "Async capture failed with return code $REC_RC"
	kill $PLAY_PID 2>/dev/null
	RESULT=$(( $RESULT + 1 ))
else
	test_print_trc "Async capture completed successfully"
fi

# Verify captured file has content
if [ -f "$CAPTURE_FILE" ] ; then
	CAP_SIZE=$(stat -c %s "$CAPTURE_FILE" 2>/dev/null || echo 0)
	test_print_trc "Captured file size: $CAP_SIZE bytes"
	if [ "$CAP_SIZE" -eq 0 ] ; then
		test_print_err "Captured file is empty"
		RESULT=$(( $RESULT + 1 ))
	fi
else
	test_print_err "Captured file $CAPTURE_FILE does not exist"
	RESULT=$(( $RESULT + 1 ))
fi

# Cleanup generated playback file
rm -f "$PLAY_FILE"

# Cleanup captured file unless user wants to retain it
if [ "$CAPTURELOGFLAG" -eq 0 ] ; then
	rm -f "$CAPTURE_FILE"
fi

if [ $RESULT -ne 0 ] ; then
	test_print_err "McASP async mode test FAILED with $RESULT error(s)"
	exit 1
fi

test_print_trc "McASP async mode test PASSED - simultaneous playback and capture completed successfully"

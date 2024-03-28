#! /bin/sh
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
# @desc Toggles the switch by playing the audio in backgroung using amixer interface.
# @params  l) TEST_LOOP    test loop for switch toggling. default is 1.
# @history 2011-04-07: First version
# @history 2011-05-13: Removed st_log.sh
source "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/} [-l TEST_LOOP]  [-D <device> ]
  -D audio device to use during the test, i.e hw:1,0, defaults to hw:0,0
	EOF
	exit 0
}

################################ CLI Params ####################################
# Please use getopts
while getopts  :l:D:h arg
do case $arg in  
        l)      TEST_LOOP="$OPTARG";;
        D)      DEVICE="$OPTARG";;
        h)      usage;;
        :)      die "$0: Must supply an argument to -$OPTARG.";; 
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

# Define default values if possible
: ${TEST_LOOP:=3}
: ${REC_DEVICE:=$((get_audio_devnodes.sh -d pcm3168 -t record -e JAMR || get_audio_devnodes.sh -d aic -t record -e JAMR) | grep 'hw:[0-9]' || echo 'hw:0,0')}
: ${PLAY_DEVICE:=$((get_audio_devnodes.sh -d pcm3168 -t play -e JAMR || get_audio_devnodes.sh -d aic -t play -e JAMR) | grep 'hw:[0-9]' || echo 'hw:0,0')}
PLAY_CARD=$(echo "${PLAY_DEVICE}" | cut -c 4)
REC_CARD=$(echo "${REC_DEVICE}" | cut -c 4)
PLAY_SW_STATE=1
REC_SW_STATE=1
############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are 
# initilized and exported by runltp script based on platform option (-P)
case $ARCH in
esac
case $DRIVER in

esac
case $SOC in
esac
case $MACHINE in
*dra7xx-evm|am57xx-evm|k2g-evm|am654x-evm)
	CAPTURE_SWITCH_NAME=("PGA Capture Switch")
	PLAYBACK_SWITCH_NAME=("Line Playback Switch" "HP Playback Switch")
	;;
am180x-evm|dm355-evm|dm365-evm|dm6446-evm|dm6467-evm|dm368-evm)
	CAPTURE_SWITCH_NAME=("PGA Capture Switch")
	PLAYBACK_SWITCH_NAME=("LineL Playback Switch"	"LineR Playback Switch")
	;;
omap3evm)	
	CAPTURE_SWITCH_NAME=("Analog Right AUXR Capture Switch" "Analog Left AUXL Capture Switch")	
	PLAYBACK_SWITCH_NAME=("DAC2 Analog Playback Switch")
	amixer cset numid=25 1,1
	amixer cset numid=28 1,1	
	;;
am37x-evm|beagleboard)
	CAPTURE_SWITCH_NAME=("Analog Right AUXR Capture Switch" "Analog Left AUXL Capture Switch")	
	PLAYBACK_SWITCH_NAME=("DAC2 Analog Playback Switch")
	;;
am3517-evm)
	CAPTURE_SWITCH_NAME=("Digital Capture Switch")
	PLAYBACK_SWITCH_NAME=("Digital Playback Switch")
	;;	
da850-omapl138-evm)
	CAPTURE_SWITCH_NAME=("PGA Capture Switch")
	PLAYBACK_SWITCH_NAME=("Line Playback Switch")
	;;	
am387x-evm|am389x-evm|am335x-evm|dm385-evm|am43xx-gpevm)
        CAPTURE_SWITCH_NAME=("PGA Capture Switch")
        PLAYBACK_SWITCH_NAME=("HP Playback Switch")
        ;;
am43xx-epos)
        CAPTURE_SWITCH_NAME=("ADC Capture Switch")
        PLAYBACK_SWITCH_NAME=("HP Driver Playback Switch" "Speaker Driver Playback Switch")
        ;;
j721*|j72s*|j784*|j742*)
        CAPTURE_SWITCH_NAME=("ADC1 Mute Switch" "ADC2 Mute Switch" "ADC3 Mute Switch")
        PLAYBACK_SWITCH_NAME=("DAC1 Invert Switch" "DAC2 Invert Switch" "DAC3 Invert Switch" "DAC4 Invert Switch")
        PLAY_SW_STATE=0
        REC_SW_STATE=0
        ;;
esac

########################### REUSABLE TEST LOGIC ###############################

amixer -c ${PLAY_CARD} controls
amixer -c ${PLAY_CARD} contents
amixer -c ${REC_CARD} controls
amixer -c ${REC_CARD} contents
arecord -D ${REC_DEVICE} -f dat -d 300 | aplay -D ${PLAY_DEVICE} -f dat -d 300 &

i=0
capture_max=$((${#CAPTURE_SWITCH_NAME[@]} - 1))
playback_max=$((${#PLAYBACK_SWITCH_NAME[@]} - 1))
while [[ $i -lt $TEST_LOOP ]]
do
  
  for cidx in `seq 0 $capture_max`
  do
	  do_cmd amixer -c ${REC_CARD} cset name=\'${CAPTURE_SWITCH_NAME[$cidx]}\' $(((REC_SW_STATE + 1) % 2))
  done
	sleep 8

  for cidx in `seq 0 $capture_max`
  do
	  do_cmd amixer -c ${REC_CARD} cset name=\'${CAPTURE_SWITCH_NAME[$cidx]}\' $REC_SW_STATE
	done
	sleep 8
	
  for pidx in `seq 0 $playback_max`
  do
	  do_cmd amixer -c ${PLAY_CARD} cset name=\'${PLAYBACK_SWITCH_NAME[$pidx]}\' $(((PLAY_SW_STATE + 1) % 2))
	done
	sleep 8

  for pidx in `seq 0 $playback_max`
  do
	  do_cmd amixer -c ${PLAY_CARD} cset name=\'${PLAYBACK_SWITCH_NAME[$pidx]}\' $PLAY_SW_STATE
	done
	sleep 8

	let "i += 1"	
done


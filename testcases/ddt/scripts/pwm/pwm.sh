#! /bin/bash
###############################################################################
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
###############################################################################
# @history 2012-01-02: First version
# @desc Verification of PWM funtionality
# Following modules can be tested with this script
#	a. ecap
#	b. ehrpwm
#	c. Haptics motor controlled by eHRPWM
#	d. Backlight controlled by eCap
# Results must be validated based on
#	a. Output waveform shown on CRO in case of eCap and eHRPWM
#	b. LCD display brightness variation in case of backlight
#	c. Vibrator noise in case of Haptics

source "common.sh"  # Import do_cmd(), die() and other functions
PWMPATH="/sys/class/pwm/";

############################# Functions #######################################

usage()
{
	cat <<-EOF >&2
		usage: ./${0##*/} [-t device_type] [-d duty][-D duty_type] [-p period] [-P period_type] [-r polarity] [-T time_delay] [-v bright_val]
		-t device_type		Type of device. ehrpwm,ecap,backlight
		-d duty				Duty cycle value. e.g. 0.02 for Seconds
		-p period			Period value. e.g. 0.05 for seconds
		-r polarity			Polarity of duty second. e.g. normal or inversed
		-T time_delay		Duration for which driver is run. e.g. 3 for seconds
		-v bright_val		Value to be set for device_type backlight
	EOF
	exit 0
}

################################ CLI Params ####################################
# Please use getopts
while getopts  :h:d:p:r:t:T:v:e: arg
do case $arg in
		h)		usage; exit 1;;
		d)		duty="$OPTARG";;
		p)		period="$OPTARG";;
		r)		polarity="$OPTARG";;
		t)		device_type="$OPTARG";;
		T)		time_delay="$OPTARG";;
		v)		bright_val="$OPTARG";;
		e)		pwms="$OPTARG";;
		:)		die "$0: Must supply an argument to -$OPTARG.";;
		\?)		die "Invalid Option -$OPTARG ";;
esac
done
# Define default values if possible
############################ Default Values for Params ###############################

: "${period:=".05"}"
: "${duty:=".02"}"
: "${polarity="normal"}"
: "${time_delay="3"}"
: "${bright_val="5"}"

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are
# initilized and exported by runltp script based on platform option (-P)
case $MACHINE in
	am62*)
		ecap_instance=0
		ehrpwm_instance=0
	;;
	am64*)
		ecap_instance=0
		ehrpwm_instance=0
	;;
esac
# Define default values for variables being overriden

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

get_pwmchip()
{
	pwm=$1
	for subfolder in "$PWMPATH"*; do
		ueventfile="$subfolder/device/uevent";
		dev_path=$(grep "$pwm" "$ueventfile")
		if [ -n "$dev_path" ]; then pwmchip="${subfolder:15:8}"; fi
	done
	echo "$pwmchip"
}

case $device_type in
	ecap|ehrpwm)
		count=0
		for pwm in ${pwms//|/ }; do
			if [ $count -lt 1 ]; then pwmchip=$(get_pwmchip "$pwm"); fi
			((count+=1))
		done
	;;
	backlight)
		"Running backlight test"
	;;
	*)
		usage
esac

#Set brightness value in case device is backlight
if [ "$device_type" = "backlight" ];
then
	backlight_device=$(find_pwm_backlight_device.sh)
	do_cmd "echo $bright_val > /sys/devices/platform/$backlight_device/backlight/$backlight_device/brightness" || die "setting brightness failed"
	sleep $time_delay
	exit 0
fi

pwm_instance="-1"
if [ "$device_type" == "ehrpwm" ]; then pwm_instance=$ehrpwm_instance;
elif [ "$device_type" == "ecap" ]; then pwm_instance=$ecap_instance;
else die "Device type not supported yet"
fi

if [ "$pwm_instance" == "-1" ]; then echo "Nothing to test"; exit 1; fi

pwm_device=$pwmchip

# Export PWM line for use with sysfs
do_cmd "echo $pwm_instance > /sys/class/pwm/$pwm_device/export" || die "Export PWM line failed"
pwm_device="${pwm_device}/pwm${pwm_instance}"

# Configure the device ecap or eHRPWM
if [ "$device_type" == "ehrpwm" ]; then
do_cmd "echo $polarity > /sys/class/pwm/$pwm_device/polarity" || die "Setting polarity failed"
fi

period_ns=$(echo "$period * 1000000000" | bc -l)
period_ns=${period_ns%.*}
do_cmd "echo $period_ns > /sys/class/pwm/$pwm_device/period" || die "setting period failed"
do_cmd "cat /sys/class/pwm/$pwm_device/period" || die "print period failed"

duty_ns=$(echo "$duty * 1000000000" | bc -l)
duty_ns=${duty_ns%.*}
do_cmd "echo $duty_ns > /sys/class/pwm/$pwm_device/duty_cycle" || die "setting duty_cycle failed"
do_cmd "cat /sys/class/pwm/$pwm_device/duty_cycle" || die "print duty_cycle failed"

test_print_trc "Starting device $pwm_device"
do_cmd "echo 1 > /sys/class/pwm/$pwm_device/enable" || die "Run failed"
sleep $time_delay
test_print_trc "Stopping device $pwm_device"
do_cmd "echo 0 > /sys/class/pwm/$pwm_device/enable" || die "Stop failed"

# Unexport PWM line
test_print_trc "Unexport PWM line for: $pwm_device"
do_cmd "echo $pwm_instance > /sys/class/pwm/$pwmchip/unexport" || die "Export PWM line failed"

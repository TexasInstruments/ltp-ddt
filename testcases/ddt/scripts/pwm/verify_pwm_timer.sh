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
source "common.sh" # Import do_cmd(), die() and other functions

SYSFS_PWMS="";
ENU_PWMS="";
PWMPATH="/sys/class/pwm/";

DEF_TYPE="dmtimer"
DEF_ALLPWMS="F"

############################# Functions #######################################

usage()
{
	cat <<-EOF >&2
		usage: ./${0##*/}	[-t device_type]
		-t device_type		Type of device, can be any of timer
		-a all_pwms			Verify all PWM instances for dmtimer
	EOF
	exit 1
}

get_enumerated_pwms_sysfs()
{
	for subfolder in "$PWMPATH"*; do
		ueventfile="$subfolder/device/uevent";
		pwmtimer=$(grep "OF_NAME" "$ueventfile")
		SYSFS_PWMS+=$pwmtimer
		SYSFS_PWMS+="|"
	done
}

check_for_enumeration()
{
	npwms=0
	pwms=""
	for pwmtimer in ${SYSFS_PWMS//|/ }; do
		pwmtimer=$(echo "$pwmtimer" | sed 's/^.*dmtimer/dmtimer/');
		pwms+=$pwmtimer
		pwms+="|"
		npwms=$((npwms+1))
	done

	echo "$pwms"
	return $npwms
}

################################ CLI Params ####################################
# Please use getopts

while [ $# -gt 0 ]
do
	case $1 in
	-t|--device_type)
		type="$2" ; shift;;
	-a|--all_pwms)
		allpwms="T" ;;
	(--)
	  shift; break;;
	(-*)
	  echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
	(*)
	  break;;
	esac
	shift
done

# Define default values if possible
############################ Default Values for Params ###############################

type="${type:=$DEF_TYPE}"
allpwms="${allpwms:=$DEF_ALLPWMS}"

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are
# initilized and exported by runltp script based on platform option (-P)

case $MACHINE in
	am62xx*)
		pwmtimer_inst=3
		;;
esac

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

get_enumerated_pwms_sysfs

echo "Running verify_pwm_timer test for: $type, test all PWMs..."
ENU_PWMS=$(check_for_enumeration)
npwms=$?

if [ "$npwms" != "$pwmtimer_inst" ]
then
	die "For |$type| did not find expected |$pwmtimer_inst| PWMs, found |$npwms| PWMs";
else
	echo "Found the expected |$npwms| |$type| instances: |$ENU_PWMS|";
fi

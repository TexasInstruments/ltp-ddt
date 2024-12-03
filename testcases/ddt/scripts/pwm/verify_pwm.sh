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
SYM_PWMS="";
ENU_PWMS="";
PWMPATH="/sys/class/pwm/";
SYMPATH="/sys/firmware/devicetree/base/__symbols__/";

DEF_CMD="verify"
DEF_TYPE="ecap"
DEF_ALLPWMS="F"
DEF_TESTPWM="ecap0"

############################# Functions #######################################

usage()
{
	cat <<-EOF >&2
		usage: ./${0##*/}	[-t device_type]
		-c command			Command to run, can be any of verify,get
		-t device_type		Type of device, can be any of ehrpwm,ecap
		-a all_pwms			Verify all PWM instances for any of ehrpwm,ecap
		-p pwms				Verify existance of specific PWM, can be any of ehrpwm,ecap type
	EOF
	exit 1
}

get_pwm_name()
{
	ppath=$1
	cpwm=$(tr -d '\0' < "$ppath" | sed 's/^.*pwm/pwm/')
	echo "$cpwm"
}

get_pwm_sysfs()
{
	pwm=$1
	ppath=$(find /sys/ -iname "$pwm")
	cpwm=$(get_pwm_name "$ppath")
	echo "$cpwm"
}

find_pwms_from_symbols()
{
	type=$1
	pwms="|"
	for file in "$SYMPATH"*; do
		ppath=$(find "$file" -iname "${type}[0-9]")
		if [ -n "$ppath" ] && [ "$ppath" != " "  ]; then
			cpwm=$(get_pwm_name "$ppath")
			pwms+=$cpwm
			pwms+="|"
		fi
	done

	echo "$pwms"
}

get_enumerated_pwms_sysfs()
{
	pwm=""
	for subfolder in "$PWMPATH"*; do
		ueventfile="$subfolder/device/uevent";
		pwm=$(grep "pwm@" "$ueventfile")
		SYSFS_PWMS+=$pwm
	done
}

check_for_enumeration()
{
	npwms=0
	pwms=""
	for pwm in ${SYM_PWMS//|/ }; do
		if echo "$SYSFS_PWMS" | grep -q "$pwm"; then
			pwms+=$pwm
			pwms+="|"
			npwms=$((npwms+1))
		fi
	done

	echo "$pwms"
	return $npwms
}

################################ CLI Params ####################################
# Please use getopts

while [ $# -gt 0 ]
do
	case $1 in
	-c|--cmd)
		cmd="$2" ; shift;;
	-t|--device_type)
		type="$2" ; shift;;
	-a|--all_pwms)
		allpwms="T" ;;
	-p|--pwm)
		testpwm="$2" ; shift;;
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

cmd="${cmd:=$DEF_CMD}"
type="${type:=$DEF_TYPE}"
allpwms="${allpwms:=$DEF_ALLPWMS}"
testpwm="${testpwm:=$DEF_TESTPWM}"

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are
# initilized and exported by runltp script based on platform option (-P)

case $MACHINE in
	am62axx*)
		ecap_inst=3
		ehrpwm_inst=2
		;;
	am62lxx*)
		ecap_inst=3
		ehrpwm_inst=3
		;;
	am62xx*)
		ecap_inst=3
		ehrpwm_inst=2
		;;
	am62pxx*)
		ecap_inst=2
		ehrpwm_inst=2
		;;
	am64xx*)
		ecap_inst=3
		ehrpwm_inst=5
		;;
esac

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

get_enumerated_pwms_sysfs

case $cmd in
	verify)
		case $allpwms in
			F)
				echo "Running verify_pwm test for: $type, test PWM=|$testpwm|..."
				pwm=$(get_pwm_sysfs $testpwm)
				pwmresult=$(echo "$SYSFS_PWMS" | grep -o "$pwm")
				if [ -n "$pwmresult" ] && [ "$pwmresult" != " " ]; then echo "Found PWM: |$pwmresult|"; else die "Did not find PWM: |$testpwm|"; fi
				;;
			T)
				echo "Running verify_pwm test for: $type, test all PWMs..."
				SYM_PWMS=$(find_pwms_from_symbols $type)
				ENU_PWMS=$(check_for_enumeration)
				npwms=$?
				case $type in
					ecap)
						if [ "$npwms" != "$ecap_inst" ]; then die "For |$type| did not find expected |$ecap_inst| PWMs, found |$npwms| PWMs"; else echo "Found the expected |$npwms| |$type| instances: |$ENU_PWMS|"; fi ;;
					epwm)
						if [ "$npwms" != "$ehrpwm_inst" ]; then die "For |$type| did not find expected |$ehrpwm_inst| PWMs, found |$npwms| PWMs"; else echo "Found the expected |$npwms| |$type| instances: |$ENU_PWMS|"; fi ;;
					*)
						usage
				esac
				;;
			*)
				usage
		esac
		;;
	get_ehrpwms)
		SYM_PWMS=$(find_pwms_from_symbols epwm)
		ENU_PWMS=$(check_for_enumeration)
		if [ -n "$ENU_PWMS" ] && [ "$ENU_PWMS" != " " ]; then echo "$ENU_PWMS"; else die "Did not find ePWMs, exit"; fi
		;;
	get_ecappwms)
		SYM_PWMS=$(find_pwms_from_symbols ecap)
		ENU_PWMS=$(check_for_enumeration)
		if [ -n "$ENU_PWMS" ] && [ "$ENU_PWMS" != " " ]; then echo "$ENU_PWMS"; else die "Did not find ECAP PWMs, exit"; fi
		;;
	*)
		usage
esac

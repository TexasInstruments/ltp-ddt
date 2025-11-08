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
. "common.sh" # Import do_cmd(), die() and other functions

SYSFS_COUNTERS="";
SYM_COUNTERS="";
ENU_COUNTERS="";
CPATH="/sys/bus/counter/devices/";
SYMPATH="/sys/firmware/devicetree/base/__symbols__/";

DEF_TYPE="eqep"
DEF_ACOUNTERS="F"
DEF_TCOUNTER="eqep0"

############################# Functions #######################################

usage()
{
	cat <<-EOF >&2
		usage: ./${0##*/}	[-t device_type]
		-t device_type			Type of device, can be any of eqep, counters
		-a all_counters			Verify all counter instances for any of eqep, counters
		-c counter				Verify existance of a specific counter, can be any of eqep, counter types
	EOF
	exit 1
}

get_counter_name()
{
	cpath=$1
	ccounter=$(tr -d '\0' < "$cpath" |sed 's/^.*counter/counter/')
	echo "$ccounter"
}

get_counter_sym_sysfs()
{
	counter=$1
	cpath=$(find /sys/ -iname "$counter" | grep "symbols")
	ccounter=$(get_counter_name "$cpath")
	echo "$ccounter"
}

find_counters_from_symbols()
{
	type=$1
	counters="|"
	for file in "$SYMPATH"*; do
		file=${file%*/};
		cpath=$(find "$file" -iname "${type}[0-9]")
		if [ -n "$cpath" ] && [ "$cpath" != " "  ]; then
			ccounter=$(get_counter_name "$cpath")
			counters+=$ccounter
			counters+="|"
		fi
	done

	echo "$counters"
}

get_enumerated_counters_sysfs()
{
	counter=""
	for subfolder in "$CPATH"*; do
		ueventfile="$subfolder/uevent";
		counter=$(grep "counter@" "$ueventfile")
		SYSFS_COUNTERS+=$counter
	done
}

check_for_enumeration()
{
	ncounters=0
	counters=""
	for counter in ${SYM_COUNTERS//|/ }; do
		if echo "$SYSFS_COUNTERS" | grep -q "$counter"; then
			counters+=$counter
			counters+="|"
			ncounters=$((ncounters+1))
		fi
	done

	echo "$counters"
	return $ncounters
}

################################ CLI Params ####################################
# Please use getopts

while [ $# -gt 0 ]
do
	case $1 in
	-t|--device_type)
		type="$2" ; shift;;
	-a|--all_counters)
		acounters="T" ;;
	-c|--counter)
		tcounter="$2" ; shift;;
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
acounters="${acounters:=$DEF_ACOUNTERS}"
tcounter="${tcounter:=$DEF_TCOUNTER}"

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are
# initilized and exported by runltp script based on platform option (-P)

case $MACHINE in
	am62axx*)
		eqep_inst=1
		;;
	am62dxx*)
		eqep_inst=1
		;;
	am62lxx*)
		eqep_inst=2
		;;
	am62pxx*)
		eqep_inst=1
		;;
	am62xx*)
		eqep_inst=1
		;;
	am64xx*)
		eqep_inst=1
		;;
	beagleplay*)
		die "No EQEP counter enabled for beagleplay."
		;;
esac

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

get_enumerated_counters_sysfs

case $acounters in
	F)
		echo "Running verify_counter test for: $type, test counter=|$tcounter|..."
		counter=$(get_counter_sym_sysfs $tcounter)
		cresult=$(echo "$SYSFS_COUNTERS" | grep -o "$counter")
		if [ -n "$cresult" ] && [ "$cresult" != " " ]; then echo "Found counter: |$cresult|"; else die "Did not find counter: |$tcounter|"; fi
		;;
	T)
		echo "Running verify_counter test for: $type, test all counters..."
		SYM_COUNTERS=$(find_counters_from_symbols $type)
		ENU_COUNTERS=$(check_for_enumeration)
		ncounters=$?
		case $type in
			eqep)
				if [ "$ncounters" != "$eqep_inst" ]; then die "For |$type| did not find expected |$eqep_inst| counters, found |$ncounters| counters"; else echo "Found the expected |$ncounters| |$type| instances: |$ENU_COUNTERS|"; fi
			;;
			*)
				usage
		esac
		;;
	*)
		usage
esac

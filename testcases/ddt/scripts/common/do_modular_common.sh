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
# Perform modprobe, then optional driver sanity test like dd read write test
# or rtc readtime time
# Input see usage below

source "common.sh"
source "st_log.sh"

############################# Functions #######################################
usage()
{
	cat <<-EOF >&2
		usage: ./${0##*/} [-d DEVICE_TYPE] [-a ACTION] [-l TEST_LOOP]
		-d DEVICE_TYPE	device type like 'nand', 'mmc', 'usb' etc
		-l TEST_LOOP	test loop for insmod/rmmod. default is 1
		-a ACTION	optional; the test to be run after module is inserted
		-m MODULE_NAME	optional; to provide module name for out-of-tree modules
		-p PARAMETER	optional; parameters to provide for module
		-h Help		print this usage
	EOF
	exit 0
}

############################### CLI Params ###################################
while getopts  :d:l:a:m:p:h arg
	do case $arg in
		d) DEVICE_TYPE="$OPTARG";;
		l) TEST_LOOP="$OPTARG";;
		a) ACTION="$OPTARG";;
		m) MOD_NAME="$OPTARG";;
		p) PARAMETER="$OPTARG";;
		h) usage;;
		:) test_print_trc "$0: Must supply an argument to -$OPTARG." >&2; exit 1;;

		\?) test_print_trc "Invalid Option -$OPTARG ignored." >&2; usage;;
	esac
done

############################ DEFAULT Params #######################
: ${TEST_LOOP:='1'}
test_print_trc "ACTION: $ACTION"

############# Do the work ###########################################
test_print_trc "Doing modprobe test for $TEST_LOOP times"
if [ ! -z "$DEVICE_TYPE" ]; then
	MOD_NAME=`get_modular_name.sh "$DEVICE_TYPE"` || die "error getting modular name"
fi
x=0
while [ $x -lt $TEST_LOOP ]
do
	echo "============Modular Test LOOP: $x============"
	do_cmd insmod.sh "$MOD_NAME" "$PARAMETER"

	if [ -n "$ACTION" ]; then do_cmd "$ACTION"; fi

	# before doing modprobe remove, need make sure device is not mounted
	if [ ! -z "$DEVICE_TYPE" ] && [ "$DEVICE_TYPE" != "net" ] && [ "$DEVICE_TYPE" != "rtc" ]; then
		DEV_NODE=`get_blk_device_node.sh "$DEVICE_TYPE"` || die "error getting device node for $DEVICE_TYPE: $DEV_NODE"
		echo "dev_node: $DEV_NODE"

		if [[ $DEV_NODE = *mmcblk* ]]; then
			echo "umount /dev/mmcblk*"
			umount /dev/mmcblk*
		else
			dev_node_base=`echo $DEV_NODE |sed 's/[0-9]\+$//' `
			nodes=`ls ${dev_node_base}*`

		for node in $nodes; do
			do_cmd "mount" | grep "${node} " && do_cmd "umount $node"
		done
		fi
	fi
	do_cmd rmmod.sh "$MOD_NAME"

	x=$((x+1))
done

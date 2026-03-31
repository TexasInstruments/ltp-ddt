#! /bin/bash
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

source "common.sh"
source "blk_device_common.sh"

############################# Functions #######################################

# Perform a direct (non-cached) block I/O on the given MMC device.
#   $1 - device type: "emmc" or "sd"/"mmc"
#   $2 - direction: "r" for read, "w" for write
mmc_do_io() {
	local dev=$1
	local direction=$2
	local blk_node

	if [[ "$dev" = "emmc" ]]; then
		blk_node=$(find_emmc_basenode)
	else
		blk_node=$(find_mmc_basenode)
	fi

	[ -n "$blk_node" ] || die "Could not find block device node for $dev"

	if [[ "$direction" = "w" ]]; then
		do_cmd "dd if=/dev/zero of=$blk_node bs=512 count=1 oflag=direct"
	else
		do_cmd "dd if=$blk_node of=/dev/null bs=512 count=1 iflag=direct"
	fi
}

############# Do the work ###########################################

while [ $# -gt 0 ]
do
	case $1 in
		-e|--exec_cmd)
			exec_cmd="$2"; shift;;
		-c|--cmd)
			cmd="$2"; shift;;
		-d|--dev)
			dev="$2"; shift;;
		(--)
			shift; break;;
		(-*)
			echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
		(*)
			break;;
	esac
	shift
done

# Pre-discover device node before starting the suspend timer to avoid slow partition probing
if [[ "$cmd" != "cs" ]]; then
	dev_node=$(get_blk_device_node.sh "$dev") || die "Could not find device node for $dev: $dev_node"
else
	dev_node=""
fi

case $cmd in
	rw)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1M' -c '200' -n '$dev_node' -d $dev";;
	cp)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1M' -c '200' -i 'cp' -n '$dev_node' -d $dev";;
	wbg)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1M' -c '200' -i 'write_in_bg' -n '$dev_node' -d $dev";;
	cs)
		if [[ "$dev" = "mmc" ]]; then dev="sd"; fi
		command="check_mmc_speed.sh $dev"
		;;
	*)
		die "Unrecognized or missing command: '$cmd'. Valid commands: rw, cp, wbg, cs"
		;;
esac


if [[ "$exec_cmd" = "a" ]]; then
	do_cmd  rtcwake -s 5 -m mem;
	if [[ "$cmd" = "cs" ]]; then mmc_do_io "$dev" "r"; fi;
	do_cmd "$command"
elif [[ "$exec_cmd" = "d" ]]; then
	(sleep 35; rtcwake -s 5 -m mem)&
	do_cmd "$command"
fi

dmesg | grep "PM: suspend entry (deep)" || die "Did not enter deep sleep"
dmesg | grep "Restarting tasks ... done" || die "Did not resume from deep sleep"
dmesg | grep "PM: suspend exit" || die "Did not exit deep sleep"

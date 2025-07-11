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

############# Do the work ###########################################

case $cmd in
	rw)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1K' -c '10' -d $dev";;
	cp)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1K' -c '10' -i 'cp' -d $dev";;
	wbg)
		command="blk_device_dd_readwrite_test.sh -f 'ext4' -b '1K' -c '10' -i 'write_in_bg' -d $dev";;
	cs)
		if [[ "$dev" = "mmc" ]]; then dev="sd"; fi
		command="check_mmc_speed.sh $dev"
		;;
	*)
		if [[ "$dev" = "mmc" ]]; then dev="sd"; fi
		command="check_mmc_speed.sh $dev"
		;;
esac


if [[ "$exec_cmd" = "a" ]]; then
	do_cmd  rtcwake -s 5 -m mem;
	do_cmd "$command"
elif [[ "$exec_cmd" = "d" ]]; then
	(sleep 25; rtcwake -s 5 -m mem)&
	do_cmd "$command"
fi

dmesg | grep "PM: suspend entry (deep)" || die "Did not enter deep sleep"
dmesg | grep "Restarting tasks ... done" || die "Did not resume from deep sleep"
dmesg | grep "PM: suspend exit" || die "Did not exit deep sleep"

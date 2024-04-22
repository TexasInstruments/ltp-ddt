#! /bin/bash
###############################################################################
# Copyright (C) 2011 Texas Instruments Incorporated -
# http://www.ti.com/ # # This program is free software; you can
# redistribute it and/or # modify it under the terms of the GNU General
# Public License as # published by the Free Software Foundation version 2
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
###############################################################################
. "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	echo "config_can_interface.sh <interface such as can0> <bitrate such as 100000, 250000...>"
	exit 1
}

################################ CLI Params ####################################
interface='can0'
config='canconfig'
bitrate=1000000
dbitrate=1000000
loopback=n
fd=n

while getopts ":hi:c:b:d:lf" arg
do case $arg in
	h)  usage;;
	i)	interface=$OPTARG;;
	c)	config=$OPTARG;;
	b)	bitrate=$OPTARG;;
	d)	dbitrate=$OPTARG;;
	l)	loopback="y";;
	f)	fd="y";;
	\?)	die "Invalid Option -$OPTARG ";;
esac
done

if [[ "$config" == 'canconfig' ]]; then
	do_cmd "canconfig $interface bitrate $bitrate ctrlmode triple-sampling on loopback on";
else
	if [[ "$loopback" == "y" ]]; then do_cmd "ip link set $interface type can loopback on"; fi;
	if [[ "$fd" == "y" ]]; then
		do_cmd "ip link set $interface type can bitrate $bitrate dbitrate $dbitrate fd on"
	else
		do_cmd "ip link set $interface type can bitrate $bitrate";
	fi
fi

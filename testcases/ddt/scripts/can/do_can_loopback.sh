#! /bin/sh
#####################################################################
########## # Copyright (C) 2011 Texas Instruments Incorporated - 
# http://www.ti.com/ # # This program is free software; you can 
#redistribute it and/or # modify it under the terms of the GNU General 
#Public License as # published by the Free Software Foundation version 2
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any 
# kind, whether express or implied; without even the implied warranty 
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
# GNU General Public License for more details.
#####################################################################
########## 
. "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	echo "do_can_loopback.sh <interface such as can0 or can1> <bitrate such as 100000, 250000, ..., 1000000>"
	exit 1
}

################################ CLI Params ####################################
p_interface="can0"
p_bitrate=1000000
while getopts  ":h:i:b:" arg
do case $arg in
	h)	usage;;
	i)	p_interface=$OPTARG;;
	b)	p_bitrate=$OPTARG;;
	\?)	die "Invalid Option -$OPTARG ";;
esac
done

do_cmd "ip link set $p_interface down"
do_cmd "canconfig $p_interface bitrate $p_bitrate ctrlmode triple-sampling on loopback on"
do_cmd "ip link set $p_interface up"

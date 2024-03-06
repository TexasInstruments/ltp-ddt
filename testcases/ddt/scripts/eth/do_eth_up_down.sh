#! /bin/sh
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
source "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	echo "do_eth_up_down.sh <direction such as up/down> <interface_name such as eth0, eth1>"
	exit 1
}

################################ CLI Params ####################################
p_interface="eth0"
p_direction="up"
p_timeout=45
while getopts  ":h:d:i:" arg
do case $arg in
        h)      usage;;
	i)	p_interface=$OPTARG;;
	d)	p_direction=$OPTARG;;
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

if [ $p_direction == "up" ]
then
	do_cmd "ifconfig $p_interface up"
	sleep 1

	operstate=`cat /sys/class/net/$p_interface/operstate`

	count=0
	while [ "$operstate" == "down" -a "$count" -lt "$p_timeout" ];
	do
		sleep 1
		operstate=`cat /sys/class/net/$p_interface/operstate`
		let count++
	done

	do_cmd "udhcpc -n -i $p_interface"
	operstate=`cat /sys/class/net/$p_interface/operstate`
	if [ "$operstate" == "down" ]
	then
		die "$p_interface might not be connected to a switch. Please check"
	fi
else
	ifconfig $p_interface down	
fi

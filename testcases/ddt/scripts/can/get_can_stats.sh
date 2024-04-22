#! /bin/bash
###############################################################################
# Copyright (C) 2011 Texas Instruments Incorporated - http://www.ti.com/
# # This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
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
	echo "get_can_stats.sh <type of statistic - TXF or RXF>"
	exit 1
}

################################ CLI Params ####################################
p_stats='TXF'

while getopts  ":hs:" arg
do case $arg in
	h)	usage;;
	s)	p_stats=$OPTARG;;
	\?)	die "Invalid Option -$OPTARG ";;
esac
done

data=$(grep "$p_stats" /proc/net/can/stats | grep -o -E '[0-9]+');
echo "$data";

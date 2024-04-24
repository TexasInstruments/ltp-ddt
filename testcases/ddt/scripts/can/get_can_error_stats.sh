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
	echo "get_can_error_stats.sh <interface such as can0, main_mcan0> <type of statistic - tx or rx>"
	exit 1
}

################################ CLI Params ####################################
interface='can0'
stats='tx'

while getopts  ":hi:s:" arg
do case $arg in
	h)	usage;;
	i)	interface=$OPTARG;;
	s)	stats=$OPTARG;;
	\?)	die "Invalid Option -$OPTARG ";;
esac
done

nestats=$stats;
nestats="${nestats}_[b,p]*";
stats="${stats}*";
spath=/sys/class/net/$interface/statistics;

data="$(
find "$spath" -type f -name "$stats" ! -name "$nestats" | \
	while read -r variable; do
		printf "%s" "$( < "$variable" )"
	done
)"

data=${data//$'\n'/};
echo "$data";

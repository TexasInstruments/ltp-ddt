#!/bin/sh 
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

# Get devnode for rtc type
# Input: RTC device type like mcp, palmas, omap_rtc
# Output: One rtc node which is of type specified in input like /dev/rtc0 

source "common.sh"

########################### DYNAMICALLY-DEFINED Params #########################
# Try to use /sys and /proc information to determine values dynamically.        
# Alternatively you should check if there is an existing script to get the      
# value you want                                                                

if [ $# -lt 1 ]; then
	echo "Error Invalid Argument Count"
	echo "Syntax: $0 <rtc_device_type>"
	exit 1
fi

: ${DEV_NODE:=`ls /dev/rtc*|grep "rtc[0-9]"`}               
                                                                                
for rtc_node in  ${DEV_NODE[@]};
do
	udev_output=`udevadm info --attribute-walk --name=$rtc_node | grep $1`
	if [ ! -z "$udev_output" ]; then
		echo $rtc_node 
		exit 0
	fi
done
exit 1 
	


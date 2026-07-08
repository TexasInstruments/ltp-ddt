#! /bin/sh
#
# Copyright (C) 2025 Texas Instruments Incorporated - http://www.ti.com/
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

# Check if MMC/SD controller properly enumerates ADMA (Advanced DMA) capability
# ADMA allows efficient memory-based descriptors for data transfers

source "common.sh"
source "blk_device_common.sh"

############################# Functions #######################################

get_adma_capability() {
	device_type=$1

	dmesg_adma=$(dmesg | grep "$device_type" | grep -i "using ADMA")
	if [ -n "$dmesg_adma" ]; then
		echo "$dmesg_adma"
	fi
}

############# Do the work ###########################################
device_type=$1

if [ -z "$device_type" ] || ! echo "$device_type" | grep -qE "^mmc[0-9]+$"; then
	die "device_type must be MMC device (e.g., 'mmc0', 'mmc1'), got: $device_type"
fi

test_print_trc "Checking ADMA enumeration for $device_type"

test_print_trc "MMC IOS information:"
printout_mmc_ios

# Check ADMA capability via kernel dmesg
test_print_trc "Checking for ADMA enumeration in kernel log..."

adma_msg=$(get_adma_capability "$device_type")
[ -z "$adma_msg" ] && die "ADMA not enumerated for $device_type"

echo "Test passed: $device_type controller properly enumerates ADMA:"
echo "$adma_msg"

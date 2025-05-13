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

# Check SD or emmc speed to see if it is expected speed like HS200
# For now, it only works for emmc

source "common.sh"
source "blk_device_common.sh"

############################# Functions #######################################

mmc_get_id(){
	mode=$1
	case $mode in
		LEGACY)
			id=0;;
		HS)
			id=1;;
		SDR12 | SDR25 | SDR50 | DDR50 | SDR104)
			id=2;;
		DDR52 | HS200 | HS400)
			id=3;;
		*)
			id=2;;
	esac
	echo "$id"
}

mmc_get_timespec(){
	mode=$1
	dev=$2
	id=$(mmc_get_id "${mode}")

	case $id in
		0)
			timespec="(legacy";;
		1)
			if [ "$dev" = "emmc" ]; then timespec="(mmc high-speed"; else timespec="(sd high-speed"; fi ;;
		2)
			timespec="(sd uhs ${mode}";;
		3)
			timespec="(mmc ${mode}";;
	esac
	echo "$timespec"
}

############# Do the work ###########################################
device_type=$1
expected_mode=$2

if [ "$expected_mode" = "" ]; then
	if [ "$device_type" = "emmc" ]; then
		# Get emmc expected speed based on platform
		case $MACHINE in
			am57xx-evm |am572x-idk |am574x-idk)
				expected_mode="DDR52";;
			dra7xx-evm | dra72x-evm )
				expected_mode="HS200";;
			 # Set expected eMMC bus mode to HS200 for am62px/j722s due to silicon errata i2458
			am654x-evm | am654x-idk | j721e* | am62lxx* | am62xxsip* | am62xx* | am62axx* | am62dxx* | am64xx-evm | am64xx-hsevm | am62pxx* | j722s*)
				expected_mode="HS200";;
			j7200* | j721s* | j784* | j742* | am69*)
				expected_mode="HS400";;
			*)
				die "No expected eMMC mode is specified for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_mmc_speed.sh";;
		esac
	fi
	if [ "$device_type" = "sd" ]; then
		# Get sd expected speed based on platform
		case $MACHINE in
			am62lxx* | am62xxsip* | am62xx* | am62axx* | am62dxx* | am64xx-evm | am64xx-hsevm | am62pxx* | j7200* | j721s* | j722s* | j784* | j742* | am69*| am68*)
				expected_mode="SDR104";;
			j721e)
				expected_mode="DDR50";;
			*)
				die "No expected sd mode is specified for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_mmc_speed.sh";;
		esac
	fi
fi

if [ "$expected_mode" = "" ]; then
	die "There is no expected speed mode specified for $device_type"
fi

if [ "$device_type" = "emmc" ] || [ "$device_type" = "sd" ]; then
	expected_timespec=$(mmc_get_timespec "${expected_mode}" "${device_type}")
else
	die "There is no support for this device_type : $device_type"
fi

mmcios=$(printout_mmc_ios)
echo "$mmcios"
echo "$mmcios" | grep -i "$expected_timespec" || die "${device_type} is not running at expected mode: ${expected_mode}"
echo "The test passed and mmc ios shows ${device_type} is running at ${expected_mode} mode"

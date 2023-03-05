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

############# Do the work ###########################################
device_type=$1
expected_mode=$2

if [[ "$expected_mode" = "" ]]; then
  if [[ "$device_type" = "emmc" ]]; then
    # Get emmc expected speed based on platform
    case $MACHINE in
      am57xx-evm |am572x-idk |am574x-idk)
        expected_mode="DDR52";;
      dra7xx-evm | dra72x-evm )
        expected_mode="HS200";;
      am654x-evm | am654x-idk | j721e* | am62xx* | am62axx*)
        expected_mode="HS200";;
      am64xx-evm | am64xx-hsevm | j7200* | j721s* | j784* | am69*)
        expected_mode="HS400";;
      *)
        die "No expected eMMC mode is specified for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_mmc_speed.sh";;
    esac
  fi

fi

if [[ "$expected_mode" = "" ]]; then
  die "There is no expected speed mode is specified for $device_type"
fi

if [[ "$device_type" = "emmc" ]]; then
  expected_timespec="(mmc ${expected_mode}"
elif [[ "$device_type" = "mmc" ]]; then
  expected_timespec="(sd uhs ${expected_mode}"
else
  die "Not support this device_type"
fi

mmcios=`printout_mmc_ios` 
echo "$mmcios"
echo "$mmcios" |grep -i "$expected_timespec" && echo "The test pass and mmc ios shows it is running at ${expected_mode} mode" || die "MMC is not running at expected mode: ${expected_mode}"



















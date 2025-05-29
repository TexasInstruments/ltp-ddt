#! /bin/sh
# 
# Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
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

# Check standard supported by the mmc controller

source "common.sh"
source "blk_device_common.sh"

############################# Functions #######################################
usage()
{
cat <<-EOF >&2
  usage: ./${0##*/} [-d DEVICE_TYPE] [-S STD_MATCH]
  -d DEVICE_TYPE  device type like 'emmc' or 'mmc'
  -S STD_MATCH  Standard to Match 
  -h Help         print this usage
EOF
exit 0
}

############################### CLI Params ###################################

while getopts  :d:S:h arg
do case $arg in
        d)      DEVICE_TYPE="$OPTARG";;
        S)      STD_MATCH="$OPTARG";;
        h)      usage;;
        :)      test_print_trc "$0: Must supply an argument to -$OPTARG." >&2
                exit 1
                ;;

        \?)     test_print_trc "Invalid Option -$OPTARG ignored." >&2
                usage
                exit 1
                ;;
esac
done

############# Do the work ###########################################

do_cmd "df -h"

# Emmc Standard Test
if [[ "$DEVICE_TYPE" = "emmc" ]]; then
  test_print_trc "Performing operations for emmc"
  EMMC_BASENODE=$(find_emmc_basenode) || die "error getting device node for $DEVICE_TYPE: $EMMC_BASENODE"
  test_print_trc "Emmc Basenode returned is: $EMMC_BASENODE"

  # printout mmc ios for mmc test
  if [[ "$EMMC_BASENODE" =~ "mmc" ]]; then
    do_cmd printout_mmc_ios
  fi

  #start emmc version test
  emmcver=`mmc extcsd read $EMMC_BASENODE`
  echo 
  echo "$emmcver" | head -4
  echo "$emmcver" | grep -i "$STD_MATCH" && echo "The test pass and emmc standard is JESD JEDEC ${STD_MATCH}" || die " emmc standard is not JESD JEDEC ${STD_MATCH}"
fi


# MMC Standard Test
if [[ "$DEVICE_TYPE" = "mmc" ]]; then
  test_print_trc "Performing operations for mmc"
  MMC_BASENODE=$(find_mmc_basenode) || die "error getting device node for $DEVICE_TYPE: $MMC_BASENODE"
  test_print_trc "MMC Basenode returned is: $MMC_BASENODE"
  regaddr="";
  expected_val="";

  # printout mmc ios for mmc test
  if [[ "$MMC_BASENODE" =~ "mmc" ]]; then
    do_cmd printout_mmc_ios
  fi

  ### start mmc version test

  # Get address of MMCSD1_HOST_CONTROLLER_VER
  case $MACHINE in
    j721* | j7200* | j784s4* | am69* | am68* | j742s2* | tda54*)
      regaddr="0x04FB00FE";;
    am62* | beagleplay* | am64xx* | j722* )
      regaddr="0x0FA000FE";;
    *)
      die "No MMCSD1_HOST_CONTROLLER_VER register address for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_standard.sh";;
  esac


  if [[ "$regaddr" = "" ]]; then
    die "No MMCSD1_HOST_CONTROLLER_VER register address for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_standard.sh";
  fi

  # Get Expected Register Value
  case $MACHINE in
    j7* | am62* | am64xx*)
      expected_val="4";;
    *)
      die "No expected value specified for MMCSD1_HOST_CONTROLLER_VER register for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_standard.sh";;
  esac

  if [[ "$expected_val" = "" ]]; then
    die "No expected value specified for MMCSD1_HOST_CONTROLLER_VER register for this platform in ltp-ddt/testcases/ddt/scripts/blk/check_standard.sh";
  fi

  echo "MMCSD1_HOST_CONTROLLER_VER Register Address : ${regaddr}";
  echo "Expected Value for MMCSD1_HOST_CONTROLLER_VER Register [0:7] : ${expected_val}";

  # Run Test 
  mmcver=$(devmem2 ${regaddr} b | grep "Read" | cut -d " " -f 7);
  mmcver=$((mmcver & 7))
  echo 
  echo "MMC Version Value in MMCSD1_HOST_CONTROLLER_VER Register is ${mmcver}"
  echo "$mmcver" | grep -i "$expected_val" && echo "The test pass and mmc standard is SD ${STD_MATCH}" || die " mmc standard is not SD ${STD_MATCH}"
fi

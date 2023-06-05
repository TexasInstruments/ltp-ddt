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

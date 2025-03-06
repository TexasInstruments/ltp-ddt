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

MTD_BLK="mtdblock"
MTD_CHAR="mtd"
MTD_BLK_DEV="/dev/$MTD_BLK"
MTD_CHAR_DEV="/dev/$MTD_CHAR"

source "common.sh"
############################# Functions #######################################
# Assume the type is always nand for nand device
# this function is to check if the device /dev/mtd$partition is nand based on /sys entry
# if this /sys/ entry doesn't exist, don't do any check.

find_part_type() {
  PART=$1
  MTD_DEV="mtdblock$PART"
  if [[ -e /sys/class/mtd/mtd$PART/type ]]; then
    TYPE=`cat /sys/class/mtd/mtd$PART/type`
    if [[ $TYPE == 'nand' ]]; then
      PART_TYPE='nand'
      if [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'spi'` ]];then
        if [[ `cat /proc/mtd |grep -E "mtd$PART |mtd${PART}: "|grep -i qspi ` ]];then
          PART_TYPE="qspi"
        elif [[ `cat /proc/mtd |grep -E "mtd$PART |mtd${PART}: "|grep -i ospi ` ]];then
          PART_TYPE="ospi"
        else
          PART_TYPE="spi"
        fi
      fi
    else
      if [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'flash'` ]]; then
        PART_TYPE="nor"
      elif [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'hyperbus'` ]];then
        PART_TYPE="hflash"
      elif [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'qspi'` ]];then
        PART_TYPE="qspi"
      elif [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'ospi'` ]];then
        PART_TYPE="ospi"
      elif [[ `ls /sys/class/mtd/mtd$PART/device/driver/ | grep 'spi'` ]];then
        if [[ `cat /proc/mtd |grep -E "mtd$PART |mtd${PART}: "|grep -i qspi ` ]];then
          PART_TYPE="qspi"
        elif [[ `cat /proc/mtd |grep -E "mtd$PART |mtd${PART}: "|grep -i ospi ` ]];then
          PART_TYPE="ospi"
        else
          PART_TYPE="spi"
        fi
      else
        die "/sys/class/mtd/mtd$PART/device/driver doesn't exist"
      fi
    fi
  else
    die "/sys/class/mtd/mtd$PART/type doesn't exist"
  fi
  echo $PART_TYPE
}

# search through Lo to Hi to find out which partition has the biggest size
find_mtdpart_with_biggest_size() {
  local LO=$1
  local HI=$2
  # search through Lo to Hi to find out which one has the biggest size
  local MAX=0
  local PART=$LO
  while [ $PART -le $HI ]; do
    SIZE=`get_mtd_size.sh $PART` || die "error getting mtd$PART size: $SIZE"
    if [ $SIZE -gt $MAX ]; then
      PART_MAX=$PART
      MAX=$SIZE
    fi
    PART=`expr $PART + 1`
  done
  echo $PART_MAX
}


find_mtd_part_range() {
  DEVICE_TYPE=$1
  # Assume maximum number of mtd partition is less than 15
  local CNT=30
  local PART=0  # starting searching from partition 0.
  local PART_RANGE=''
  while [ $PART -le $CNT ]; do
    if [ -e /dev/mtd$PART ]; then
      TYPE=`find_part_type $PART`
      if [ "$TYPE" == "$DEVICE_TYPE" ]; then
        # find out part range; put them in string like ":1:2:3:4"
        PART_RANGE="$PART_RANGE:$PART"
      fi
    fi
    PART=`expr $PART + 1`
  done
  if [ -z $PART_RANGE ]; then
    die "$0: none of mtd partitions are for $DEVICE_TYPE "
  else
    echo $PART_RANGE
  fi
}

get_fs_part() {
  DEVICE_TYPE=$1
  PART_RANGE=`find_mtd_part_range "$DEVICE_TYPE"` || die "Error when trying to find mtd part range"
  # by now, the part_range like ":1:2" should be found.
  LO=`echo $PART_RANGE | cut -d":" -f2`
  HI=`echo $PART_RANGE | rev| cut -d':' -f1 | rev`

  # search through Lo to Hi to find out which one is fs part
  local MAX=0
  local PART=$LO
  while [ $PART -le $HI ]; do
    if [ -e /sys/class/mtd/mtd$PART/name ]; then
      PART_NAME=`cat /sys/class/mtd/mtd$PART/name`
      MTD_FS_NAME=`get_mtd_fs_name.sh $DEVICE_TYPE` || die "error get_mtd_fs_name"
      if [ "$PART_NAME" == "$MTD_FS_NAME" ]; then
        FS_PART=$PART
        break
      fi
    else
      die "/sys/class/mtd/mtd$PART/name doesn't exist"
    fi
    PART=`expr $PART + 1`
  done
  echo $FS_PART

}


# search all partitions and find the Nand partition with the biggest size
get_mtd_biggest_part() {
  DEVICE_TYPE=$1
  PART_RANGE=`find_mtd_part_range "$DEVICE_TYPE"` || die "Error when trying to find mtd part range"
  # by now, the part_range like ":1:2" should be found.
  LO=`echo $PART_RANGE | cut -d":" -f2`
  HI=`echo $PART_RANGE | rev| cut -d':' -f1 | rev`
  TEST_PART=`find_mtdpart_with_biggest_size $LO $HI`
  if [ -n "$TEST_PART" ]; then
    echo $TEST_PART
  else
    test_print_wrg "WARNING!!!:Failed to get mtd partition number dynamically through sys entry, \
          so taking user defined partition number!"
  fi
}

# get subpage size using mtdinfo
# input: devnode like /dev/mtd6
# output: subpage size in bytes
get_subpagesize() {
  DEV_NODE=$1
  SSIZE=`mtdinfo "$DEV_NODE" |grep 'Sub-page size' |awk '{print $3}'`
  echo "$SSIZE"
}

# get page size using mtdinfo
# input: devnode like /dev/mtd6
# output: page size in bytes
get_pagesize() {
  DEV_NODE=$1
  PSIZE=`mtdinfo "$DEV_NODE" |grep 'Minimum input/output unit size' |awk '{print $5}'`
  echo "$PSIZE"
}

# get mtd partition number for part_name like 'kernel', 'file-system'
# $1: device_type like 'nand', 'spi'
# $2: part_name like 'kernel', 'u-boot-spl-os', 'file-system'
# output:
#   partition number for part_name; either empty or number
#   caller script should check the validity of the return
get_partnum_from_name() {
  device_type=$1
  part_name=$2
  test_part=''
  parts=`cat /proc/mtd |grep -i "$part_name" |grep -oE "mtd[[:digit:]]+" |sed 's/mtd//' `
  for part in $parts
  do
    type=`find_part_type $part`
    if [ $type = $device_type ]; then
      test_part=$part
    fi
  done
  echo "$test_part"
}

# Find last ubi device attached
find_ubi_device() {
  ubi_dev=`ubinfo | grep -i 'present ubi devices:' |cut -d ":" -f2 |xargs |awk -F, '{print $NF}' |xargs `
  echo $ubi_dev
}

# DEV_NODE: ex: /dev/mtdblock9
printout_mtdinfo(){
  DEV_NODE=$1
  CHAR_NODE=`echo "$DEV_NODE" |sed "s/block//" `
  do_cmd mtdinfo "$CHAR_NODE"
}


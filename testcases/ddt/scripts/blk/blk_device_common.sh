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

# Functions related to block device partition and its size 

source "common.sh"

############################ Functions ################################

# Create three partitions on blk device like emmc, usbhost, msata/sata etc if there
#   is no partition in it. 
# And mark the first partition as boot partition so the test won't touch it in case 
#   user use it as boot partition later on;
# And also make initial filesystem on these three partitions
# 3rd partition size is whatever left on the card
# Input:
#       basenode like /dev/mmcblk0, /dev/sda etc
#       1st partition size in MB
#       2nd partition size in MB
create_three_partitions() {
    if [ $# -ne 3 ]; then
      die "Usage: $0 <dev_base_node ex. /dev/mmcblk0, /dev/sda>, /dev/nvme0n1 <1st partition size> <2nd partition size>"
    fi

    basenode=$1
    partsize_1st=$2
    partsize_2nd=$3
    check_basenode_regex="\/dev\/([a-z])+([0-9]?)+"
    if [[ ! "$basenode" =~ $check_basenode_regex ]]; then
      die "$0: $basenode is not valid basenode!"
    fi

    have_partition=$(have_partition "$basenode")
    if [ "$have_partition" = 'no' ]; then
      # check if the device size is big enough
      #input_size=`echo ${partsize_1st}*1024*1024+${partsize_2nd}*1024*1024 |bc`
      bnode=$(echo "$basenode" |sed s'/\/dev\///')
      actual_size=$(cat /sys/block/"${bnode}"/size)
      actual_size=$(echo "${actual_size}"*1024 |bc)
      #if [[ $input_size -ge $actual_size ]]; then
      #  die "Device size is too small or Input size (1st+2nd) is too big!"
      #fi

      sector_size=$(get_sector_size "$basenode")
      end_of_1st_partition=$(echo "${partsize_1st}"*1024*1024/"${sector_size}" |bc)
      end_of_2nd_partition=$(echo "${partsize_2nd}"*1024*1024/"${sector_size}"+"${end_of_1st_partition}" |bc)
      echo "Making three partitions..."
      printf "%s\n" "p" \
        "n" "p" "1" "" "${end_of_1st_partition}" \
        "n" "p" "2" "" "${end_of_2nd_partition}" \
        "n" "p" "3" "" "" \
        "a" "1" "t" "1" "c" "p" "w" | fdisk "$basenode"
      # making initial fs
      ls "${basenode}"* | grep "${basenode}"p1 && (mkfs.vfat -F32 "${basenode}"p1; mkfs.vfat -F32 "${basenode}"p2; mkfs.vfat -F32 "${basenode}"p3)
      ls "${basenode}"* | grep "${basenode}"1 && (mkfs.vfat -F32 "${basenode}"1; mkfs.vfat -F32 "${basenode}"2; mkfs.vfat -F32 "${basenode}"3)
    else
      # There are existing partitions so create test partition if there are only 2 partitions
      echo "Found partitions in $basenode"
      partitions=$(get_num_partitions "$basenode")
      if [ "$partitions" = "2" ]; then
        disk_sectors=$(fdisk -l "$basenode" 2>/dev/null | awk -v dev="$basenode" '$0 ~ "^Disk " dev ":" {print $7}')
        last_used_sector=$(fdisk -l "$basenode" 2>/dev/null | grep "^${basenode}" | awk '{end=($2=="*")?$4:$3; if(end>max) max=end} END{print max}')
        if [ -n "$disk_sectors" ] && [ -n "$last_used_sector" ] && [ "$((disk_sectors - last_used_sector - 1))" -gt 2048 ]; then
          echo "Found two partitions in $basenode, create third partition"
          printf "%s\n" "p" "n" "p" "3" "" "" "p" "w" | fdisk "$basenode"
          sleep 2
          [ -b "${basenode}p3" ] && mkfs.vfat -F32 "${basenode}p3" || echo "Failed to create ${basenode}p3"
        else
          echo "Skipping creating a third partition since $basenode has no free space"
        fi
      else
          echo "Skipping creating a third partition since there are $partitions partitions in $basenode"
      fi
    fi
}

# This function is to count the number of partitions
get_num_partitions() {
    basenode=$1
    num_partitions=0
    MATCH=$(fdisk -l "$basenode" |grep -E "${basenode}p|${basenode}[1-9]+")
    for item in $MATCH
    do
      DEVNODE=$(echo "$item" | grep "mmcblk")
      if [ -n "$DEVNODE"  ]; then num_partitions="$((num_partitions+1))"; fi;
    done
    echo "$num_partitions"
}

# This function is to check if blk device has at least on partition in it
have_partition() {
    basenode=$1
    match=$(fdisk -l "$basenode" |grep -E "${basenode}p|${basenode}[1-9]+")
    if [ "$match" = "" ]; then
      have_partition="no"
    else
      have_partition="yes"
    fi
    #ls ${basenode}* |grep -E "${basenode}1|${basenode}p1" > /dev/null && have_partition='yes' || have_partition='no'
    echo "$have_partition"
}

# This function is to get the sector size of blk device
get_sector_size() {
    basenode=$1
    bnode=$(echo "$basenode" |sed s'/\/dev\///')
    sector_size=$(cat /sys/block/"${bnode}"/queue/hw_sector_size)
    echo "$sector_size"
}

get_part_util_to_use()
{
  DEV_BASE_NODE=$1

  # check if fdisk works for this dev
  fdisk -l "$DEV_BASE_NODE" > fdisklog_$$ 2>&1 
  cat fdisklog_$$ |grep -i "fdisk doesn't support" > /dev/null
  if [ $? -ne 0 ]; then
    disklabel_type=$(cat fdisklog_$$ |grep 'Disklabel type' |cut -d":" -f2 |sed 's/^ *//' |sed 's/ *$//' )
    if [ "gpt" == "$disklabel_type" ]; then
      parted -v > /dev/null && UTIL_TO_USE='parted' || (gdisk -v > /dev/null && UTIL_TO_USE='gdisk' || die "Do not know which util to check partition")
    else
      UTIL_TO_USE='fdisk'
    fi
  else
    # use parted or gdisk etc
    parted -v > /dev/null && UTIL_TO_USE='parted' || (gdisk -v > /dev/null && UTIL_TO_USE='gdisk' || die "Do not know which util to check partition")
  fi

  echo "$UTIL_TO_USE"
}


# This function return DEVNODE with the biggest size.
#   If the partition is boot or rootfs partition, it will be skipped.
# Input: DEV_BASE_NODE: like /dev/mmcblk0, /dev/sda, /dev/nvme0n1 etc
#        DEVICE_TYPE: like 'mmc', 'usb'
# Output: test partition which is biggest partition; but not boot or rootfs partition

find_part_with_biggest_size() {
  if [ $# -ne 2 ]; then
    die "Usage: $0 <dev_base_node like /dev/mmcblk0, /dev/sda> <device_type like mmc, usb>"
  fi

  DEV_BASE_NODE=$1
  DEVICE_TYPE=$2

  UTIL_TO_USE=$(get_part_util_to_use "$DEV_BASE_NODE") || die "Failed to get the partition utils for $DEV_BASE_NODE : $UTIL_TO_USE "

  SIZE_BIGGEST=0
  TMP_IFS=$IFS
  IFS=$'\n'

  case "$UTIL_TO_USE" in

  fdisk)
    MATCH=$(fdisk -l "$DEV_BASE_NODE" |grep -E "${DEV_BASE_NODE}p|${DEV_BASE_NODE}[1-9]+")
    if [ -z "$MATCH" ]; then
      die "fdisk does not show any partitions! Please check if the partitions really exist!"
    fi

    for i in $MATCH
    do
      LINE=$i
      FIELD_2ND=$(echo "$LINE" | awk -F " " '{print $2}')
      DEVNODE=$(echo "$LINE" | awk -F " " '{print $1}')
      SIZE=$(echo "$LINE" | awk -F " " '{print $4}' | sed s/+$//)

      # skip boot partition with u-boot* in it and rootfs partition with rootfs in it
      IS_ROOTFS_OR_BOOT=$(is_part_boot_or_rootfs "$DEVICE_TYPE" "$DEVNODE") || die "Error when calling is_part_boot_or_rootfs: |$IS_ROOTFS_OR_BOOT|"
      if [ "$IS_ROOTFS_OR_BOOT" == "no" ]; then
        if [ "$SIZE" -gt "$SIZE_BIGGEST" ]; then SIZE_BIGGEST=$SIZE; PART_DEVNODE="$DEVNODE"; fi;
      fi
    done
  ;;

  parted)
    case "$DEVICE_TYPE" in
    usb*|sata)
      PART_BASE_NODE="${DEV_BASE_NODE}"
    ;;
    *mmc)
      PART_BASE_NODE="${DEV_BASE_NODE}p"
    ;;
    *)
      die "device_type $DEVICE_TYPE is not supported"
    ;;
    esac
   
    MATCH=$(ls "${PART_BASE_NODE}"* |grep -Eo [[:digit:]]+$)
    for i in $MATCH
    do
      PART_NUM=$i
      DEVNODE="${PART_BASE_NODE}${PART_NUM}"

      LINE=$(echo -e "print\nquit\n" |parted "${DEV_BASE_NODE}" |grep -E "^\s*${PART_NUM} ")
      #SIZE=$(echo "$LINE" |awk -F " " '{print $4}' |sed s'/[a-zA-Z].$//' )
      partsize=$(echo "$LINE" |awk -F " " '{print $4}' )
      # Convert all size to KB
      shopt -s nocasematch
      case "$partsize" in
        *KB) SIZE=$(echo "${partsize}" |sed s'/[a-zA-Z].$//' );;
        *MB) 
          partsize=$(echo "${partsize}" |sed s'/[a-zA-Z].$//' )
          SIZE=$(echo "${partsize}"*1024 |bc) ;;
        *GB) 
          partsize=$(echo "${partsize}" |sed s'/[a-zA-Z].$//' )
          SIZE=$(echo "${partsize}"*1024*1024 |bc) ;;
        *) die "Don't know the unit for the partition size";;
      esac
      shopt -u nocasematch
       
      # if size is too small, do not use it as test partition
      minsize=$(echo 100*1024 |bc) #100M in KB
      if (( $(echo "$SIZE < $minsize" |bc -l) ));then
        continue
      fi

      FLAG=$(echo "$LINE" |awk -F " " '{print $7}')
      PART_NAME=$(echo "$LINE" |awk -F " " '{print $5}')

      IS_ROOTFS_OR_BOOT=$(is_part_boot_or_rootfs "$DEVICE_TYPE" "$DEVNODE") || die "error when calling is_part_boot_or_rootfs: |$IS_ROOTFS_OR_BOOT|"
      if [ "$IS_ROOTFS_OR_BOOT" == "no" ]; then
        if [ $(echo "$SIZE > $SIZE_BIGGEST" |bc -l) -ne 0 ]; then SIZE_BIGGEST=$SIZE; PART_DEVNODE="${DEVNODE}"; fi
      fi
    done
  ;;

  gdisk)
    die "Do not support gdisk yet"
  ;;
  
  *)
    die "Do not know which util to use"
  ;;

  esac

  IFS=$TMP_IFS
  if [ -z "$PART_DEVNODE" ]; then
    die "Could not find the partition to test! Maybe all the existing partitions are either boot (contains file u-boot*) or rootfs partition (contains etc or dev directory). Please check the contents of the partitions; if needed, please reformat the device to leave at least one partition for testing!"
  fi  
  echo "$PART_DEVNODE"
}

# get size of the partition with PART_DEVNODE
# return size is in 'MBytes'
get_part_size_of_devnode() {
  PART_DEVNODE=$1
  PARTBYTES=$(fdisk -l "$PART_DEVNODE" | grep "Disk ""$PART_DEVNODE"":" | awk '{print $5 }' )
  if [ "$PARTBYTES" -le 0 ]; then
    die "Could not get partition size from $PART_DEVNODE"
  fi

  PARTSIZE=$((${PARTBYTES}/MB))
  echo $PARTSIZE
}

# Get the partition is used for current rootfs
# Input: None
get_fs_root() {
  BOOTARGS=$(cat /proc/cmdline)
  ROOT=$(get_value_for_key "root" "$BOOTARGS" "=") || die "error getting root from proc cmdline: $ROOT"
  echo "$ROOT"
}

# Check if the partition is holding the root fs
# Input: partition devnode: like /dev/mmcblk0p1
#        device_type: to decide which fs to try to mount
is_part_boot_or_rootfs(){
  if [ $# -ne 2 ]; then
    die "Usage: $0 <device_type like 'mmc', 'usb'> <device_node like /dev/mmcblk0p1, /dev/sda1>"
  fi
  DEVICE_TYPE=$1
  DEV_NODE=$2
  IS_MOUNTED="no"
  RTN="no"

  mount |grep "$DEV_NODE" > /dev/null && IS_MOUNTED="yes"
  if [ "$IS_MOUNTED" == "yes" ];then
    MNT_POINT=$(mount |grep "$DEV_NODE" |cut -d" " -f3)
  else
    # if not mounted yet, try to mount
    MNT_POINT="/mnt/partition_$( echo "$DEV_NODE" |sed s'/\/dev\///' )_$$"
    do_cmd blk_device_do_mount.sh -n "$DEV_NODE" -d "$DEVICE_TYPE" -m "$MNT_POINT" > /dev/null 2>/dev/null
    mount |grep "$DEV_NODE" > /dev/null
    if [ $? -ne 0 ]; then
      do_cmd mkfs.vfat -F32 "${DEV_NODE}" > /dev/null 2>/dev/null
      do_cmd blk_device_do_mount.sh -n "$DEV_NODE" -d "$DEVICE_TYPE" -m "$MNT_POINT" > /dev/null 2>/dev/null
      mount |grep "$DEV_NODE" > /dev/null || die "Failed to mount $DEV_NODE when checking if it is rootfs/boot partition"
    fi
    NEED_UMOUNT="yes" #flag to tell if umount is needed at the end.
  fi

  if [ -e "$MNT_POINT/etc" ] || [ -e "$MNT_POINT/dev" ] || ls "$MNT_POINT"/u-boot* 1>/dev/null 2>&1 ; then
    RTN="yes"
  fi
  #If it is mounted by me, umount it.
  if [ "$NEED_UMOUNT" == "yes" ]; then
    do_cmd blk_device_umount.sh -m "$MNT_POINT" > /dev/null 2>/dev/null
  fi
  echo "$RTN"
}

printout_model(){
  DEV_NODE=$1
  DEV_TYPE=$2
  case "$DEV_NODE" in
    *sd*)
      BASE_SD=$(echo "$DEV_NODE" |sed "s/\/dev\///" |sed "s/[0-9]$//")
      do_cmd "cat /sys/block/$BASE_SD/device/model"
      ;;
    *nvme*)
      # /dev/nvme0n1p1
      BASE_SD=$(echo "$DEV_NODE" |sed "s/\/dev\///" |sed "s/p[0-9]$//")
      do_cmd "cat /sys/block/$BASE_SD/device/model"
      ;;
    *)
      test_print_trc "model info is not available for non scsi devices."
      ;;
  esac
}

printout_mmc_ios() {
  test_print_trc "===== printout of mmc ios ====="
  mmcd=$(for d in "${DEBUGFS_LOCATION}"/mmc*/; do echo "$d"; done)
  for i in $mmcd; do
    do_cmd cat "${i}"ios
  done
  test_print_trc "===== end of mmc ios ====="
}

# find all available scsi drives
# Input: "usb" or "sata"
# Output: drives_found
find_all_scsi_drives() {
  SCSI_DEVICE=$1
  DRIVES_FOUND=""
  DRIVES=$(fdisk -l |grep "Disk /dev/sd" | cut -b 13)
  for DRIVE in $DRIVES; do
    if [ -e /sys/block/sd"$DRIVE"/device/vendor ]; then
      VENDOR=$(cat /sys/block/sd"$DRIVE"/device/vendor)
      RESULT=$(echo "$VENDOR" | grep -i "ATA")
      case $SCSI_DEVICE in
        sata)
          if [ -n "$RESULT" ]; then
            DRIVES_FOUND="${DRIVES_FOUND} $DRIVE"
          fi
        ;;
        usb)
          if [ -z "$RESULT" ]; then
            DRIVES_FOUND="${DRIVES_FOUND} $DRIVE"
          fi
        ;;
        all)
          DRIVES_FOUND="${DRIVES_FOUND} $DRIVE"
        ;;
      esac
    fi
  done
  if [ -n "$DRIVES_FOUND" ]; then
    echo "$DRIVES_FOUND"
  else
    # if could not find match, let user know
    echo "Could not find any device node for SCSI device!"
    exit 1
  fi
}

# return: /dev/mmcblk0 etc
find_emmc_basenode() {
    emmc_node=$(ls /dev/mmcblk* |grep boot |head -1 |sed s'/boot[0-9]*//' )
    echo "$emmc_node"
}

find_mmc_basenode() {
    emmc_node=$(find_emmc_basenode)
    if [ -n "$emmc_node" ]; then
      mmc_node=$(ls /dev/mmcblk* |sed s",$emmc_node.*$,,g" |grep -E ".*blk[[:digit:]]+$" |head -1)
    else
      mmc_node=$(ls /dev/mmcblk* |grep -E ".*blk[[:digit:]]+$" |head -1)
    fi  
    echo "$mmc_node"
}

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

# Get devnode for non mtd device like 'mmc', 'usb', 'usbxhci', 'usbotg', 'sata'
# Input: DEVICE_TYPE like 'mmc', 'usb', 'usbxhci', 'usbotg', 'sata'
# Optional Input: DEVICE PROPERTIES like 'superspeed'
# Output: DEV_NODE like /dev/mmcblk0p1

source "common.sh"
source "mtd_common.sh"
source "blk_device_common.sh"

if [ $# -lt 1 ]; then
	echo "Error: Invalid Argument Count"
	echo "Syntax: $0 <device_type> <optional_param>"
	exit 1
fi

DEVICE_TYPE=$1
EXTRA_PARAM=$2
############################ Functions ################################
# this function is to get SCSI device usb or sata node based on by-id
# input is either 'sata' or 'usb' or 'usbxhci'

find_scsi_basenode() {
	SCSI_DEVICE=$1
	case $SCSI_DEVICE in
		sata)
			# remove DVD
			files=$(ls /dev/disk/by-id/* |grep -v "DRW" |grep -i ata )
			if [ -n "$files" ]; then
				for file in $files; do
					basenode="/dev/""$(basename "$(readlink "$file")")"
					udevadm info -a -n "$basenode" |grep -i 'pci' > /dev/null && continue
					echo "$basenode"
					exit 0
				done
			fi
		;;
		usb|usbxhci|usbotg)
			sleep 30 # give usb some time to get enumerated
			usb_cnt_interface=$(get_usb_controller_name.sh "$SCSI_DEVICE")
			usb_speed_found=1
			# in USB case, extra param is used to indicate usb speed
			DEVICE_SPEED=$EXTRA_PARAM

			for file in $(ls /dev/disk/by-path/* |grep -i "$usb_cnt_interface" |head -1)
			do
				if [ -n "$file" ]; then
					basenode="/dev/""$(basename "$(readlink "$file")")"
					if [ -n "$DEVICE_SPEED" ]; then
						usb_speed=$(find_usbhost_speed.sh "$DEVICE_SPEED")
						speed=$(udevadm info -a -n "$DEV_NODE"|grep speed)
						for speed in $(udevadm info -a -n "$DEV_NODE"|grep speed)
						do
							if [ "${speed}" == *"$usb_speed"* ]; then
								echo "$basenode"
								exit 0
							else
								usb_speed_found=0
							fi
						done
					fi
				fi
			done

			if [ -n "$usb_speed_found" ]; then
				echo "$basenode"
				exit 0
			else
				echo "Could not find USB device or USB device with specified speed"
				exit 1
			fi
		;;
		pci)
			file=$(ls /dev/disk/by-path/* |grep -i 'pci'|head -1)
			if [ -n "$file" ]; then
				basenode="/dev/""$(basename "$(readlink "$file")")"
				echo "$basenode"
				exit 0
			fi
		;;
		ufs)
			file=$(ls /dev/disk/by-path/* |grep -i 'ufs-scsi-0:0:0:1'|head -1)
			if [ -n "$file" ]; then
				#this_node=$(basename "$(readlink "$file")"")
				#ls -l /dev/disk/by-path/platform-*ufs-scsi* > /dev/null |grep ${this_node} || (echo "${this_node} is not ufs-scsi node"; exit 1)
				basenode="/dev/""$(basename "$(readlink "$file")")"
				echo "$basenode"
				exit 0
			fi
		;;
	esac
	# if could not find match, let user know
	echo "Could not find device node for SCSI device!"
	exit 1
}

############################ Default Params ##############################
DEV_TYPE=$(get_device_type_map.sh "$DEVICE_TYPE") || die "error getting device type: $DEV_TYPE"
case $DEV_TYPE in
	mtd)
		PART=$(get_mtd_partition_number.sh "$DEVICE_TYPE") || die "error getting mtd partition number: $PART"
		DEV_NODE="$MTD_BLK_DEV$PART"
		;;
	mmc)
		mmc_basenode=$(find_mmc_basenode)
		if [ -z "$mmc_basenode" ]; then die "Could not find mmc basenode"; fi
		# Create two partitions if mmc doesn't have any partition on it OR create test partition if boot/rootfs partitions exist
		create_three_partitions "$mmc_basenode" 80 1024 1>&2
		DEV_NODE=$(find_part_with_biggest_size "$mmc_basenode" "mmc") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	emmc)
		emmc_basenode=$(find_emmc_basenode)
		if [ -z "$emmc_basenode" ]; then die "Could not find emmc basenode"; fi
		# Create two partitions if mmc doesn't have any partition on it OR create test partition if boot/rootfs partitions exist
		create_three_partitions "$emmc_basenode" 80 1024 1>&2
		DEV_NODE=$(find_part_with_biggest_size "$emmc_basenode" "emmc") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	usb|usbxhci|usbotg)
		basenode=$(find_scsi_basenode "$DEV_TYPE") || die "error getting usb base node: $basenode"
		# create 3 partitions with the size 80M, 2048M, and remaining if there is no partition
		create_three_partitions "$basenode" 80 1024 > /dev/null
		DEV_NODE=$(find_part_with_biggest_size "$basenode" "usb") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	pci)
		basenode=$(find_scsi_basenode "pci") || die "error getting pci basenode: $basenode"
		create_three_partitions "$basenode" 80 2048 > /dev/null
		DEV_NODE=$(find_part_with_biggest_size "$basenode" "pci") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	ata)
		DEV_NODE="/dev/hda1"
		;;
	sata)
		basenode=$(find_scsi_basenode "sata") || die "error getting sata basenode: $basenode"
		# Typically, sata harddisk is big, so create 16G (16384) to be able to run 10G filesize test
		create_three_partitions "$basenode" 80 16384 > /dev/null
		DEV_NODE=$(find_part_with_biggest_size "$basenode" "sata") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	ufs)
		basenode=$(find_scsi_basenode "ufs") || die "error getting sata basenode: $basenode"
		# Typically, sata harddisk is big, so create 16G (16384) to be able to run 10G filesize test
		create_three_partitions "$basenode" 80 16384 > /dev/null
		DEV_NODE=$(find_part_with_biggest_size "$basenode" "ufs") || die "error getting partition with biggest size: $DEV_NODE"
		;;
	*)
		die "Invalid device type in $0 script"
		;;
esac

############################ USER-DEFINED Params ##############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically
case $ARCH in
esac
case $DRIVER in
esac
case $SOC in
esac
case $MACHINE in
esac

######################### Logic here ###########################################
if [ -n "$DEV_NODE" ]; then
	echo "$DEV_NODE"
else
	die "Was not able to get devnode to test. Backtrace:: $DEV_NODE ::"
fi

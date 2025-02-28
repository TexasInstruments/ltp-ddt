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

# search for USB Ethernet devices

source "common.sh"
#
# Search for a USB Ethernet device
#


usb_interface=$1
usb_cnt_interface=`get_usb_controller_name.sh "$usb_interface"` 
ethdev=none

devices=`ls /sys/class/net`
for device in $devices
  do
    usb_interface=`udevadm info --attribute-walk --path=/sys/class/net/$device|grep -m 1 -i "$usb_cnt_interface"`
#    usb_eth_adapter=`udevadm info --attribute-walk --path=/sys/class/net/$device|grep -m 1 -i "adapter"`
    if [ -n "$usb_interface" ];
    then
        echo $device
        ethdev=$device
    fi
done

if test "$ethdev" = "none";
then
  test_print_trc " ::"
  test_print_trc " :: No USB Ethernet Adapter found. Exiting USB Ethernet tests..."
  test_print_trc " ::"
  exit 2	
fi

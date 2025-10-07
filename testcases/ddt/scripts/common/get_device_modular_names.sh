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
# @desc Get module config option and module name for a driver.
# @params
#        Input: device type like "nand", "mmc", "spi", "sound", "graphics" , wlc
# @returns Top-level .ko file (Module) name to modprobe for
#          this driver

source "common.sh"  # Import do_cmd(), die() and other functions
############################# Functions #######################################

################################ CLI Params ####################################
if [ $# -ne 1 ]; then
  echo "Error: Invalid Argument Count"
  echo "Syntax: $0 <device_type like 'nand', 'mmc', 'spi', 'rtc', 'graphics'>"
  exit 1
fi
DEVICE_TYPE=$1
IFS_ORIG=$IFS
IFS=","
for DRIVER in $DRIVERS
do
  case $DRIVER in
    *wlcore_sdio)
        wlcore_sdio="wlcore_sdio";;
    *wl18xx)
        wl18xx="wl18xx";;
    *cc33xx_sdio)
        cc33xx_sdio="cc33xx_sdio";;
    *usbslave_ether)
        usbslave_ether="g_ether";;
    *usbslave_zero)
        usbslave_zero="g_zero";;
    *usbslave_ncm)
        usbslave_ncm="g_ncm";;
    *usbslave_mass_storage)
        usbslave_mass_storage="g_mass_storage";;
    *usbslave_multi)
        usbslave_multi="g_multi";;
    *usbslave_cdc)
        usbslave_cdc="g_cdc";;
  esac
done
IFS=$IFS_ORIG
# Use do_cmd() (imported from common.sh) to execute your test steps.
# do_cmd() will check return code and fail the test is return code is non-zero.
eval MOD_NAME=\$$DEVICE_TYPE
if [ -z "$MOD_NAME" ]; then
        die 'Module name not found'
fi
echo "$MOD_NAME"

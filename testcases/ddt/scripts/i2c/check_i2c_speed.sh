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

# Check i2c speed for each bus and check if the bus works fine 

# Input: 
# Output:

source "common.sh"


for i2cbus_num in `dmesg | grep omap_i2c | sed -rn "s#.*bus ([[:digit:]]+).*#\1#p"`
do
  # check the speed
  speed=`dmesg |grep -i i2c |grep "i2c: bus ${i2cbus_num}" |grep -Eo '[[:digit:]]+\s+kHz' `
  if [ -z "$speed" ]; then
    die "I2C bus ${i2cbus_num} speed could not get from booting log. Please rerun this test after reboot"
  else
    echo "=====For I2C bus ${i2cbus_num}, the speed is ${speed}====="
  fi

  # check if the speed ok for this bus
  i2cdetect -y -r ${i2cbus_num} || die "For I2C bus ${i2cbus_num} with speed ${speed}, the bus has problems"
  
done

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




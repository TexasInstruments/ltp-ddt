#! /bin/sh
#######################################################################
######## # Copyright (C) 2011 Texas Instruments Incorporated - 
# http://www.ti.com/ # # This program is free software; you can 
# redistribute it and/or # modify it under the terms of the GNU General 
# Public License as # published by the Free Software Foundation version 
# 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any 
# kind, whether express or implied; without even the implied warranty 
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU 
# General Public License for more details.
#######################################################################

# @desc Function to return blocked dmtimers (those that are not available
# to be tested) based on platform type  
# @params none # @returns array of dmtimers supported source "common.sh"  
# Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
        echo "get_dmtimer_blocked_list.sh"
        echo "Returns dmtimers not available for request"
        exit 1
}

############################ USER-DEFINED Params ############################### 
# Try to avoid defining values here, instead see if possible # to determine the value dynamically. ARCH, 
# DRIVER, SOC and MACHINE are initilized and exported by runltp script based on platform option (-P)

case $ARCH in
esac
case $DRIVER in
esac
case $SOC in
esac
case $MACHINE in
        dra7xx-evm|am43xx-gpevm|am43xx-epos|am57xx-evm|am335x-evm|am335x-sk|beaglebone|beaglebone-black|beaglebone_green_eco-gp)
                  dmtimer_num=(1);;
esac 
echo "${dmtimer_num[@]}"

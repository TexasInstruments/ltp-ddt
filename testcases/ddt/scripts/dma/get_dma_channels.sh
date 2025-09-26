#! /bin/sh
############################################################################### 
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
###############################################################################

# @desc Function to get array of dma channels
# @params none
# @returns array of dma channels
source "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	echo "get_dma_channels.sh"
	echo "Returns DMA channels"
	exit 1
}

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are 
# initilized and exported by runltp script based on platform option (-P)

case $ARCH in
esac
case $DRIVER in
esac
case $SOC in
        dra7xx|j6eco)
                  dma_channels=(dma0chan0 dma0chan4 dma0chan7 dma0chan8 dma0chan9 dma0chan10 dma0chan11 dma0chan12 dma0chan13 dma0chan16 dma0chan17 dma0chan18 dma0chan19 dma0chan20 dma0chan21 dma0chan30 dma0chan31 dma0chan32 dma0chan33 dma0chan58 dma0chan59);;
esac
case $MACHINE in
        am335x-evm|am335x-sk|beaglebone|beaglebone-black|beaglebone_green_eco-gp)
                  dma_channels=(dma0chan12 dma0chan13 dma0chan20 dma0chan21 dma0chan32 dma0chan33 dma0chan34 dma0chan35 dma0chan37 dma0chan54 dma0chan55);;
        am43xx-gpevm|am43xx-epos)
                  dma_channels=(dma0chan4 dma0chan7 dma0chan32 dma0chan35);;
esac
echo "${dma_channels[@]}"

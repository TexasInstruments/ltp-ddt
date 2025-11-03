#! /bin/sh
############################################################################### 
# Copyright (C) 2013 Texas Instruments Incorporated - http://www.ti.com/
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

# @desc returns total number of udma interrupts raised for each udma irq on a given cpu
# @params  
#         -c cpu number
# @history 2013-04-22: First version

source "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
	echo "$0 -c <0-based cpu number>."
	exit 1
}

############################ Script Variables ##################################
# Define default valus if possible
IRQ_NUM=''
CPU_NUM=''

################################ CLI Params ####################################
# Please use getopts
while getopts  :c:h arg
do case $arg in
	c)	CPU_NUM="$OPTARG";;
        h)      usage;;
        :)      die "$0: Must supply an argument to -$OPTARG.";; 
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.
if [ "x$CPU_NUM" == "x" ]; then
	die "Must supply -c <cpu number> argument"
fi
INT_NUM=0
TOTAL_INT_NUM=0
INT_CHAN=`cat /proc/interrupts | grep -i "Level" | grep -c "dma-controller"`
for i in $(seq 1 $INT_CHAN)
do
   IRQ_NUM=`cat /proc/interrupts | grep -i "Level" | grep -i "dma-controller" | head -n $i | tail -n 1| cut -d':' -f 1`
   if [ $IRQ_NUM ]
   then
     interrupts=`cat /proc/interrupts | grep "${IRQ_NUM}:" | cut -d':' -f 2`
     INT_NUM=`echo $interrupts | cut -d' ' -f 1`
     TOTAL_INT_NUM=`expr $TOTAL_INT_NUM + $INT_NUM`
   fi
done
## Return number of interrupts
echo $TOTAL_INT_NUM

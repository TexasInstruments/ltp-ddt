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

# Check the bus width of mmc or sdio 
# Input  

source "common.sh"
source "st_log.sh"

############################# Functions #######################################
usage()
{
cat <<-EOF >&2
	usage: ./${0##*/} [ -m max_buswidth]
  -m max_buswidth    max_buswidth the sdio card support
	-h Help         print this usage
EOF
exit 0
}
############################### CLI Params ###################################

while getopts  :m:h arg
do case $arg in
        m)      max_buswidth="$OPTARG";;
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

############################ DEFAULT Params #######################
: "${max_buswidth:="4"}"

############# Do the work ###########################################
debugfs_mnt=$(mount |grep 'type debugfs' |cut -d' ' -f3)
if [ -z "$debugfs_mnt" ]; then
  debugfs_mnt='/debugfs'
  mount -t debugfs debugfs $debugfs_mnt 
fi
 
# get mmc instance for sdio
#    1.616760] mmc0: new SDIO card at address 0001
sdio_instance=$(dmesg |grep 'SDIO card' |cut -d':' -f1 |awk '{print $NF}')

if [ -z "$sdio_instance" ]; then
  die "Could not find mmc instance for sdio"
fi

buswidth_str=$(cat ${debugfs_mnt}/"${sdio_instance}"/ios |grep -i 'bus width')
buswidth=$(echo "$buswidth_str" |grep -o '[1-9] bits' | grep -o '[1-9]')

if [ "$buswidth" -ge  "$max_buswidth" ]; then
  echo "This test pass and mmc is operating at maximum bus width = |$max_buswidth|"
else
  die "SDIO is not operating at maximum bus width: |$max_buswidth|"
fi


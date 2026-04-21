#! /bin/bash
#
# Copyright (C) 2019 Texas Instruments Incorporated - http://www.ti.com/
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

source "common.sh"
source "st_log.sh"
source "functions.sh"

# Load require video modules
insert_video_modules()
{
	local _modules="videobuf2_common videobuf2_memops videobuf2_v4l2 videobuf2_dma_sg videobuf2_dma_contig v4l2_mem2mem vxd_dec vxe_enc"
	for m in $_modules; do
		lsmod | grep $m || modprobe $m
	done
}

# Run TI decoder
run_tidec_decode()
{
	insert_video_modules
	tidec_decode -b $* | grep 'test app completed successfully'
}

# Run TI encoder
run_tienc_encode()
{
	insert_video_modules
	tienc_encode $*
}

# Download Test media if not in fs
get_media()
{
	local __media_url=http://gtopentest-server.gt.design.ti.com/anonymous/common/Multimedia/ti-img-encode-decode-testvecs/$1
	local __checksums=/tmp/checksums.txt
	local __media_folder=/usr/share/ti/tidec-decode
	local __video=$2
	local __media

	if [[ "$1" == "encoder" ]]
	then
   		__media_folder=/usr/share/ti/tienc-encode
   		__video=yuv/$2
	fi

	ls ${__media_folder} &>/dev/null || mkdir -p ${__media_folder}
	local __media_checksum=$(md5sum ${__media_folder}/* | awk '{print $1}' | sort -u)
	wget ${__media_url}/media_checksums.txt -O ${__checksums} || return 1
	local __remote_checksum=$(awk '{print $1}' ${__checksums} | sort -u)
	local __remote_media=$(awk '{print $2}' ${__checksums} | sort -u)

	for __media in $__remote_media
	do
	if [[ $__media == $__video ]]
	then
  		wget ${__media_url}/${__media} -O ${__media_folder}/`basename ${__media}` || echo "Could not download  ${__media_url}/${__media}"
	fi
	done
}

# Get the memory consumption of specifc pipepline
get_pipe_mem_consumption()
{
    # Get memory consumption
    local _mem_consumption_before=$(cat /proc/meminfo | grep MemFree | awk '{print $2}')
    gst-launch-1.0 $1 &
    sleep 5
    local _mem_consumption_during=$(cat /proc/meminfo | grep MemFree | awk '{print $2}')
    echo $((_mem_consumption_before - _mem_consumption_during)) > $2
}


# Get the CPU Utilization of specific pipeline
# @param1: the pipeline to execute
# @param2: the output file that holds data
get_pipe_cpu_utilization()
{
    local _data_file=$(mktemp)
    gst-launch-1.0 $1 &
    pid=$(pgrep -f "gst-launch-1.0 $1")
    if [ -z "$pid" ]; then
        echo "Unable to find PID"
        return 1
    fi
    pid_int=$pid
    # Get CPU Utilization
    top -p $pid_int -H -d 1 -b -n 10 | grep v4l2 > $_data_file
    local _cpu_utilization=$( awk '{sum+=$9} END {print sum/NR}' $_data_file )
    echo $_cpu_utilization > $2
}

remove_media()
{
	
	if [[ "$1" == "encoder" ]]
	then
	  rm -rf /usr/share/ti/tienc-encode
	else
	  rm -rf /usr/share/ti/tidec-decode
	fi
	
}

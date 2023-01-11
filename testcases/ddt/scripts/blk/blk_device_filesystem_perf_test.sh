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
# @desc Helper for file system read/write performance 
#	This script does: mount->write->umount->mount->read for different buffer size.
# @params d) device type: nand, nor, spi 
#         f) Filesystem type (i.e. jffs2)
#	  e) extra parameters such as speed for usb nodes
# @history 2011-03-05: First version

source "st_log.sh"
source "common.sh"
source "blk_device_common.sh"

############################# Functions #######################################
usage()
{
cat <<-EOF >&2
  usage: ./${0##*/} [-f FS_TYPE] [-n DEV_NODE] [-m MOUNT POINT] [-B BUFFER SIZES] [-s FILE SIZE] [-d DEVICE TYPE] [-o SYNC or ASYNC] [-t TIME_OUT] [-p PERF_METHOD] [-w FIO_W_RUNTIME] [-r FIO_R_RUNTIME]
  -f FS_TYPE	filesystem type like jffs2, ext2, etc
  -n DEV_NODE	optional param, block device node like /dev/mtdblock4, /dev/sda1
  -m MNT_POINT	optional param, mount point like /mnt/mmc
  -B BUFFER_SIZES	optional param, buffer sizes for perf test like '102400 262144 524288 1048576 5242880'
  -s FILE SIZE 	optional param, file size in MB for perf test
  -e EXTRA_PARAM      optional param, example superspeed for usb
  -c SRCFILE SIZE 	optional param, srcfile size in MB for writing to device
  -d DEVICE_TYPE	device type like 'nand', 'mmc', 'usb' etc
  -o MNT_MODE     mount mode: sync or async. default is async
  -t TIME_OUT  time out duratiopn for copying
  -p PERF_METHOD the method used to measure perf; like 'fio'
  -w FIO_W_RUNTIME run time duration for FIO write in seconds; default is 60s 
  -r FIO_R_RUNTIME run time duration for FIO read in seconds; default is 60s 
  -h Help 	print this usage
EOF
exit 0
}

do_fio()
{
  IO_OP=$1
  RUNTIME=$2
  do_cmd "fio --name ${DEVICE_TYPE}_TEST --directory=$MNT_POINT --size=$FILE_SIZE --rw=$IO_OP --blocksize=$BUFFER_SIZE --ioengine=$FIO_IOENGINE --iodepth=$FIO_IODEPTH --numjobs=${FIO_NUMJOBS} --direct=1 --group_reporting --runtime=${RUNTIME} --time_based --eta=never &"
  do_cmd sleep 5
  do_cmd mpstat -P ALL $(( $RUNTIME - 5 )) 1 2>&1 > mpstat.out
  do_cmd wait
  cat mpstat.out
  iowait=`cat mpstat.out|grep -i 'average:\s*all\s*'|awk '{print $6}' `
  idle=`cat mpstat.out|grep -i 'average:\s*all\s*'|awk '{print $11}' `
  cpuload=`echo "100 - $iowait - $idle" |bc -l`
  echo "CPUload for rw:$IO_OP with blocksize:$BUFFER_SIZE is: ${cpuload}%"
  rm mpstat.out
}

############################### CLI Params ###################################
if [ $# == 0 ]; then
	echo "Please provide options; see usage"
	usage
	exit 1
fi

while getopts  :f:n:m:B:s:c:d:o:t:e:p:r:w:h arg
do case $arg in
  f)  FS_TYPE="$OPTARG";;
  n)  DEV_NODE="$OPTARG";;
  m)  MNT_POINT="$OPTARG";;
  B)  BUFFER_SIZES="$OPTARG";;
  s)  FILE_SIZE="$OPTARG";;
  c)  SRCFILE_SIZE="$OPTARG";;
  d)  DEVICE_TYPE="$OPTARG";;
  o)  MNT_MODE="$OPTARG";;
  t)  TIME_OUT="$OPTARG";;
  e)  EXTRA_PARAM="$OPTARG";;
  p)  PERF_METHOD="$OPTARG";;
  w)  FIO_W_RUNTIME="$OPTARG";;
  r)  FIO_R_RUNTIME="$OPTARG";;
  h)  usage;;
  :)  test_print_trc "$0: Must supply an argument to -$OPTARG." >&2
  exit 1 
  ;;

  \?)  test_print_trc "Invalid Option -$OPTARG ignored." >&2
  usage 
  exit 1
  ;;
esac
done

########################### DYNAMICALLY-DEFINED Params ########################
: ${BUFFER_SIZES:='102400 262144 524288 1048576 5242880'}
: ${FILE_SIZE:='100'}
: ${SRCFILE_SIZE:='10'}
: ${MNT_MODE:='async'}
: ${TIME_OUT:='30'}
: ${MNT_POINT:=/mnt/partition_$DEVICE_TYPE}
: ${FIO_IOENGINE:='libaio'}
: ${FIO_IODEPTH:=4}
: ${FIO_NUMJOBS:=1}
: ${FIO_W_RUNTIME:=60}
: ${FIO_R_RUNTIME:=60}

echo "ls -al /dev/disk/by-id"
ls -al /dev/disk/by-id
echo "ls -al /dev/disk/by-path"
ls -al /dev/disk/by-path

if [ -z $DEV_NODE ]; then
        DEV_NODE=`get_blk_device_node.sh "$DEVICE_TYPE" "$EXTRA_PARAM"` || die "error while getting device node: $DEV_NODE"
        test_print_trc "DEV_NODE return from get_blk_device_node is: $DEV_NODE" 
fi

# translate DEVICE_TYPE to DEV_TYPE (mtd or not)
DEV_TYPE=`get_device_type_map.sh $DEVICE_TYPE` || die "error while translating device type"
# erase mtd device so the test start with a good mtd device
if [ $DEV_TYPE = 'mtd' ]; then
  mtd_part=`get_mtd_partnum_from_devnode.sh $DEV_NODE` || die "error getting mtd part number"
  do_cmd flash_eraseall -q "/dev/mtd${mtd_part}"
  do_cmd modprobe mtdblock
  do_cmd modprobe ubi
  do_cmd modprobe ubifs
fi

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use user-defined Params section above.
test_print_trc "STARTING FILE SYSTEM PERFORMANCE Test for $DEVICE_TYPE"
test_print_trc "FS_TYPE:${FS_TYPE}"
test_print_trc "DEV_NODE:${DEV_NODE}"
test_print_trc "MOUNT POINT:${MNT_POINT}"
test_print_trc "BUFFER SIZES:${BUFFER_SIZES}"
test_print_trc "FILE SIZE:${FILE_SIZE}MB"
test_print_trc "SRCFILE SIZE:${SRCFILE_SIZE}MB"
test_print_trc "DEVICE_TYPE:${DEVICE_TYPE}"

# print out the model number if possible
do_cmd printout_model "$DEV_NODE" "$DEVICE_TYPE"

# printout mmc ios for mmc test
if [[ "$DEV_NODE" =~ "mmc" ]]; then
  do_cmd printout_mmc_ios
fi

# check if input are valid for this machine
DEVICE_PART_SIZE=`get_blk_device_part_size.sh -d $DEVICE_TYPE -n $DEV_NODE` || die "error while getting device partition size: $DEVICE_PART_SIZE"
test_print_trc "Device Partition Size is $DEVICE_PART_SIZE MB"
#[ $(( $FILE_SIZE * $MB )) -gt $DEVICE_PART_SIZE ] && die "File Size: $FILE_SIZE MB is not less than or equal to Device Partition Size: $DEVICE_PART_SIZE"
[ $FILE_SIZE -gt $DEVICE_PART_SIZE ] && die "File Size: $FILE_SIZE MB is not less than or equal to Device Partition Size: $DEVICE_PART_SIZE MB"

# run filesystem perf test
do_cmd "mkdir -p $MNT_POINT"
if [ -n "$FS_TYPE" ]; then
  do_cmd blk_device_prepare_format.sh -d "$DEVICE_TYPE" -n "$DEV_NODE" -f "$FS_TYPE" -m "$MNT_POINT" -o "$MNT_MODE"
else
  do_cmd blk_device_prepare_format.sh -d "$DEVICE_TYPE" -n "$DEV_NODE" -m "$MNT_POINT" -o "$MNT_MODE"
fi
for BUFFER_SIZE in $BUFFER_SIZES; do
	test_print_trc "BUFFER SIZE = $BUFFER_SIZE"

	# find out what is FS in the device
	if [ -z "$FS_TYPE" ]; then
		FS_TYPE=`mount | grep $DEV_NODE | cut -d' ' -f5 |head -1`
		test_print_trc "existing FS_TYPE: ${FS_TYPE}"
	fi

  case $PERF_METHOD in
    fio)
      # call fio
      # fio --name TEST --directory=/run/media/nvme0n1p3/ --size=10g --rw=write --blocksize=4m --ioengine=libaio --iodepth=4 --direct=1 --group_reporting --runtime=30 --time_base --eta=never
      do_fio 'write' $FIO_W_RUNTIME 
      sleep 1
      do_fio 'read' $FIO_R_RUNTIME 
      ;;
    *) 
      test_print_trc "Checking if Buffer Size is valid"
      [ $BUFFER_SIZE -gt $(( $FILE_SIZE * $MB )) ] && die "Buffer size provided: $BUFFER_SIZE is not less than or equal to File size $FILE_SIZE MB"
      test_print_trc "Creating src test file..."
      TMP_FILE="/dev/shm/srctest_file_${DEVICE_TYPE}_$$"
      do_cmd "dd if=/dev/urandom of=$TMP_FILE bs=1M count=$SRCFILE_SIZE"

      TEST_FILE="${MNT_POINT}/test_file_$$"

      for i in {1..5};do
        do_cmd filesystem_tests -write -src_file $TMP_FILE -srcfile_size $SRCFILE_SIZE -file ${TEST_FILE} -buffer_size $BUFFER_SIZE -file_size $FILE_SIZE -performance 
      done
      do_cmd "rm -f $TMP_FILE"
      do_cmd "sync"
      # should do umount and mount before read to force to write to device
      #do_cmd "umount $DEV_NODE"
      #do_cmd blk_device_umount.sh -n "$DEV_NODE" -d "$DEVICE_TYPE" -f "$FS_TYPE" 
      do_cmd blk_device_umount.sh -m "$MNT_POINT" 
      do_cmd "echo 3 > /proc/sys/vm/drop_caches"

      #do_cmd "mount -t $FS_TYPE -o $MNT_MODE $DEV_NODE $MNT_POINT"
      do_cmd blk_device_do_mount.sh -n "$DEV_NODE" -f "$FS_TYPE" -d "$DEVICE_TYPE" -o "$MNT_MODE" -m "$MNT_POINT"
      do_cmd filesystem_tests -read -file ${TEST_FILE} -buffer_size $BUFFER_SIZE -file_size $FILE_SIZE -performance 
      do_cmd "sync"
      do_cmd "echo 3 > /proc/sys/vm/drop_caches"

      # For copy test, only do half of file size to avoid out of space problem.
      test_print_trc "Creating file which is half size of $FILE_SIZE on $MNT_POINT to test copyfile"
      # TMP_FILE='/test_file'
      #HALF_FILE_SIZE=`expr $FILE_SIZE / 2`
      HALF_FILE_SIZE=$(echo "scale=2; $FILE_SIZE/2" | bc)
      TEST_FILE="${MNT_POINT}/test_file_$$"
      DST_TEST_FILE="${MNT_POINT}/dst_test_file_$$"
      do_cmd "dd if=/dev/urandom of=${TEST_FILE} bs=512K count=$FILE_SIZE"
      do_cmd filesystem_tests -copy -src_file ${TEST_FILE} -dst_file ${DST_TEST_FILE} -duration ${TIME_OUT} -buffer_size $BUFFER_SIZE -file_size $HALF_FILE_SIZE -performance 
      do_cmd "rm -f ${TEST_FILE}"
      do_cmd "rm -f ${DST_TEST_FILE}"
      test_print_trc "Unmount the device"
      #do_cmd "umount $DEV_NODE"
      ;;
  esac

done
do_cmd blk_device_unprepare.sh -n "$DEV_NODE" -d "$DEVICE_TYPE" -f "$FS_TYPE" -m "$MNT_POINT"



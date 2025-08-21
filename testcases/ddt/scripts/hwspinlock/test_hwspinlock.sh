#! /bin/sh
###############################################################################
# Copyright (C) 2018 Texas Instruments Incorporated - http://www.ti.com/
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

source "common.sh"  # Import do_cmd(), die() and other functions

############################# Functions #######################################
usage()
{
cat <<-EOF >&1
        usage: ./${0##*/} [-n TRIALS]
        -n TRIALS    Number of times to run the test
        -h Help      print this usage
EOF
exit 0
}

load_test_module()
{
  modprobe -r omap_hwspinlock_test
  dmesg -c
  modprobe omap_hwspinlock_test
  log=$(dmesg -c)
  lsmod | grep "omap_hwspinlock_test"
  if [ $? -ne 0 ]; then die "Missing omap_hwspinlock_test out of tree module"; fi;
  lock_tests=$(echo "$log" | grep -i -o 'Testing [0-9]\+ locks' | grep -o '[0-9]\+')
  if [[ $? -ne 0 ]]
  then
    echo "No lock tests detected, exiting ...."
  else
    echo "Checking ${lock_tests} lock tests"
  fi
  lock_attempts=$((lock_tests*2))
  rc0_locks=$(echo "$log" | grep -i 'trylock #1 status\[[0-9]\+\] = 0' | wc -l)
  rc16_locks=$(echo "$log" | grep -i 'trylock #2 status\[[0-9]\+\] = -16' | wc -l)
  unlock_status=$(echo "$log" | grep -i 'trylock after unlock status\[[0-9]\+\] = 0' | wc -l)
  if [[ $rc0_locks -ne $lock_attempts ]]
  then
    die "Unexpected number of succesful locks ${rc0_locks} != ${lock_attempts}"
  else
    echo "${rc0_locks} good lock attempts passed"
  fi
  if [[ $rc16_locks -ne $lock_attempts ]]
  then
    die "Unexpected number of failed lock attempts ${rc16_locks} != ${lock_attempts}"
  else
    echo "${rc16_locks} rc 16 locks attempts passed"
  fi
  if [[ $unlock_status -ne $lock_attempts ]]
  then
    die "Unexpected number try after lock tests ${unlock_status} != ${lock_attempts}"
  else
    echo "${unlock_status} try after unlock attempts passed"
  fi
  echo "$log" | grep -i -e 'hwspinlock tests failed on lock' -e 'hwspin_lock_free failed on lock' -e 'hwspinlock test failed on DT lock' && die "Lock test error message reported"
}

############################ Script Variables ##################################

TRIALS=-1
################################ CLI Params ####################################
while getopts  :n:h arg
do case $arg in
        n)      TRIALS="$OPTARG";;
        h)      usage;;
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

if [[ $TRIALS -le 0 ]]
then
  usage
fi

for i in seq 1 $TRIALS
do
  load_test_module
done

exit 0

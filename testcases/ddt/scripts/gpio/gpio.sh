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
# @desc Script to run gpio test 

#source "common.sh"
source "super-pm-tests.sh"

############################# Functions #######################################
usage()
{
cat <<-EOF >&2
  usage: ./${0##*/}  [-l TEST_LOOP] [-t SYSFS_TESTCASE] [-i TEST_INTERRUPT]
  -l TEST_LOOP  test loop
  -t SYSFS_TESTCASE testcase like 'out', 'in'
  -i TEST_INTERRUPT if test interrupt, default is 0.
  -h Help   print this usage
EOF
exit 0
}

gpio_sysentry_get_item()  {
  GPIO_NUM=$1
  ITEM=$2

  VAL=`cat /sys/class/gpio/gpio${GPIO_NUM}/${ITEM}`
  echo "$VAL"
}

gpio_sysentry_set_item() {
  if [ $# -lt 3 ]; then
    echo "Error: Invalid Argument Count"
    echo "Syntax: $0 <gpio_num> <item like 'direction', 'value', 'edge'> <item value>"
    exit 1
  fi

  GPIO_NUM=$1
  ITEM=$2
  ITEM_VALUE=$3

  ORIG_VAL=`gpio_sysentry_get_item ${GPIO_NUM} ${ITEM}`
  test_print_trc "The value was ${ORIG_VAL} before setting ${ITEM}" 

  do_cmd "echo "$ITEM_VALUE" > /sys/class/gpio/gpio${GPIO_NUM}/${ITEM}"
  VAL_SET=`gpio_sysentry_get_item ${GPIO_NUM} ${ITEM}`
  if [ "${VAL_SET}" != "${ITEM_VALUE}" ]; then
    die "Value for GPIO ${GPIO_NUM} was not set to ${ITEM_VALUE}"
  else
    test_print_trc "GPIO ${GPIO_NUM} was set to ${ITEM_VALUE}"
  fi
}

set_gpio_pinmux(){
  reg=$1
  mux_val=$2
  do_cmd devmem2 "$reg"
  reg_val_orig=`devmem2 "$reg" | grep "Read at address" |cut -d ":" -f2 `
  new_val=`echo $(( $(($reg_val_orig)) | $(($mux_val)) )) `
  new_val_hex=`echo "obase=16; $new_val" |bc `
  do_cmd devmem2 "$reg" w "$new_val_hex"
}


############################### CLI Params ###################################
while getopts  :l:t:i:h arg
do case $arg in
  l)  TEST_LOOP="$OPTARG";;
  t)  SYSFS_TESTCASE="$OPTARG";;
  i)  TEST_INTERRUPT="$OPTARG";;
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
: ${TEST_LOOP:='1'}
: ${TEST_INTERRUPT:='0'}

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use user-defined Params section above.
test_print_trc "STARTING GPIO Test... "
test_print_trc "TEST_LOOP:${TEST_LOOP}"
test_print_trc "SYSFS_TESTCASE:${SYSFS_TESTCASE}"

do_cmd "cat /sys/kernel/debug/gpio"

case $MACHINE in
  am180x-evm|omapl138-lcdk) 
    gpio_nums="368,399,426,484,511"
  ;;
  am335x-*|beaglebone|beaglebone-black)
    gpio_nums="31,40,64,98"
  ;;
  am335x-sk)
    gpio_nums="3,40,65,101"
  ;;
  beagleboard)
    gpio_nums="26,38,70,115"
  ;;
  k2hk-evm|k2e-evm|k2l-evm)
    gpio_nums="448,480"
  ;;
  am654x-evm|am654x-idk|j721e*)
    gpio_nums="285,344,440"
  ;;
  j784*)
    gpio_nums="344,440"
  ;;
  am64xx*|am62xx*|am62axx*)
    gpio_nums="420,450,325"
  ;;
  j720*|j721s*)
    gpio_nums="322,355,391"                  
  ;;
  am68*|am69*)
    gpio_nums="420,450"
  ;;
  k2g-evm)
    gpio_nums="346,281,484"
    if [[ "$MACHINE" == "k2g-evm" ]]; then
      # Based on k2g datasheet
      # gpio0_6
      set_gpio_pinmux "0x02621018" "0x3"
      # gpio0_24
      #set_gpio_pinmux "0x02621060" "0x3"
      # gpio0_25
      set_gpio_pinmux "0x02621064" "0x3"
      # gpio0_33
      set_gpio_pinmux "0x02621084" "0x3"
      # gpio0_48
      set_gpio_pinmux "0x026210c0" "0x3"
      # gpio0_73
      #set_gpio_pinmux "0x02621124" "0x3"
      # gpio0_86
      #set_gpio_pinmux "0x02621158" "0x3"
      # gpio0_97
      #set_gpio_pinmux "0x02621188" "0x3"
      # gpio0_121
      #set_gpio_pinmux "0x02621260" "0x3"
      # gpio0_135
      #set_gpio_pinmux "0x02621298" "0x3"
      # gpio1_57
      #set_gpio_pinmux "0x02621200" "0x3"
      # gpio1_65
      #set_gpio_pinmux "0x02621220" "0x3"
    fi
  ;;
  dra7xx-evm|am572x-idk|am571x-idk|am574x-idk) 
    gpio_nums="22,29,0,1,0,17,0,0"
  ;;
  am57xx-evm)
    gpio_nums="22,29,0,0,0,14,0,0"
  ;;
  am43xx-epos|am43xx-gpevm|am437x-idk)
    gpio_nums="0,32,95"
  ;;
  *)
    die "The gpio numbers are not specified for this platform $MACHINE"
  ;;  
esac

OIFS=$IFS
IFS=","
for gpio_num in $gpio_nums; do

    EXTRA_PARAMS=""
    test_print_trc "gpio_num:${gpio_num}"

    if [ "$TEST_INTERRUPT" = "1" ]; then
      do_cmd lsmod | grep gpio_test
      if [ $? -eq 0 ]; then
        test_print_trc "Module already inserted; Removing the module"
        do_cmd rmmod gpio_test.ko
        sleep 2
      fi
    fi

    if [ -n "$SYSFS_TESTCASE" ]; then
      if [ -e /sys/class/gpio/gpio"$gpio_num" ]; then
        do_cmd "echo ${gpio_num} > /sys/class/gpio/unexport"
        do_cmd ls /sys/class/gpio
        sleep 1
      fi
    fi

    if [ "$TEST_INTERRUPT" = "1" ]; then
      test_print_trc "Inserting gpio test module. Please wait..."
      do_cmd "cat /proc/interrupts"
      # wait TIMEOUT for app to finish; if not finished by TIMEOUT, kill it
      # gpio_test module return sucessfully only after the interrupt complete.
      # do_cmd "timeout 30 insmod ddt/gpio_test.ko gpio_num=${gpio_num} test_loop=${TEST_LOOP} ${EXTRA_PARAMS}"
      ( do_cmd insmod ddt/gpio_test.ko gpio_num=${gpio_num} test_loop=${TEST_LOOP} ${EXTRA_PARAMS} ) & pid=$!
      sleep 5; kill -9 $pid
      wait $pid
      if [ $? -ne 0 ]; then
        die "No interrupt is generated and gpio interrupt test failed."  
      fi 
      do_cmd cat /proc/interrupts |grep -i gpio
      #do_cmd check_debugfs 

      test_print_trc "Removing gpio test module. Please wait..."
      do_cmd rmmod gpio_test.ko
      sleep 3
      do_cmd cat /proc/interrupts
    fi

    # run sys entry tests if asked
    if [ -n "$SYSFS_TESTCASE" ]; then
      test_print_trc "Running sysfs test..."
      
      # test loop
      i=0
      while [ $i -lt $TEST_LOOP ]; do 
        test_print_trc "===LOOP: $i==="
        do_cmd "echo ${gpio_num} > /sys/class/gpio/export"
        do_cmd ls /sys/class/gpio
        if [ -e /sys/class/gpio/gpio"$gpio_num" ]; then
          case "$SYSFS_TESTCASE" in
          neg_reserve)
            test_print_trc "Try to reserve the same gpio again"
            test_print_trc "echo ${gpio_num} > /sys/class/gpio/export"
            echo ${gpio_num} > /sys/class/gpio/export
            if [ $? -eq 0 ]; then
              die "gpio should not be able to reserve gpio ${gpio_num} which is already being reserved"
            fi
            ;;
          out)
            gpio_sysentry_set_item "$gpio_num" "direction" "out"  
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to out"
            fi
            gpio_sysentry_set_item "$gpio_num" "value" "0"
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to 0"
            fi
            gpio_sysentry_set_item "$gpio_num" "value" "1"
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to 1"
            fi
            ;;
          in)
            gpio_sysentry_set_item "$gpio_num" "direction" "in" || die "gpio_sysentry_set_item failed to set ${gpio_num} to in"
            VAL=`gpio_sysentry_get_item "$gpio_num" "value"` || die "gpio_sysentry_set_item failed to get the value of ${gpio_num} " 
            test_print_trc "The value is ${VAL} for $gpio_num" 
            ;;
          edge)
            gpio_sysentry_set_item "$gpio_num" "direction" "in" || die "gpio_sysentry_set_item failed to set ${gpio_num} to in"
            gpio_sysentry_set_item "$gpio_num" "edge" "falling"
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to falling"
            fi
            gpio_sysentry_set_item "$gpio_num" "edge" "rising"
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to rising"
            fi
            gpio_sysentry_set_item "$gpio_num" "edge" "both"
            if [ $? -ne 0 ]; then
              die "gpio_sysentry_set_item failed to set ${gpio_num} to both"
            fi
            ;;
          pm_context_restore)
            gpio_sysentry_set_item "$gpio_num" "direction" "out" || die "gpio_sysentry_set_item failed to set ${gpio_num} to out"
            gpio_sysentry_set_item "$gpio_num" "value" "1" || die "gpio_sysentry_set_item failed to set ${gpio_num} to 1"
            VAL_BEFORE=`gpio_sysentry_get_item "$gpio_num" "value"` || die "gpio_sysentry_set_item failed to get the value of ${gpio_num} " 
            test_print_trc "The value was ${VAL_BEFORE} for $gpio_num before suspend" 
    
            simple_suspend_w_stats 'mem' 10 2
            
            # check if the value is still the same as the one before suspend
            VAL_AFTER=`gpio_sysentry_get_item "$gpio_num" "value"` || die "gpio_sysentry_set_item failed to get the value of ${gpio_num} " 
            test_print_trc "The value was ${VAL_AFTER} for $gpio_num after suspend" 

            # compare 
            if [ $VAL_BEFORE -ne $VAL_AFTER ]; then
              die "The value for gpio $gpio_num is different before and after suspend"
            else
              test_print_trc "The values are the same before and after"
            fi
            ;;
          esac
        else
          die "/sys/class/gpio/gpio${gpio_num} does not exist!"
        fi

        # remove gpio sys entry
        do_cmd "echo ${gpio_num} > /sys/class/gpio/unexport" 
        do_cmd "ls /sys/class/gpio/"

        i=`expr $i + 1`
      done  # while loop
    fi

done
IFS=$OIFS

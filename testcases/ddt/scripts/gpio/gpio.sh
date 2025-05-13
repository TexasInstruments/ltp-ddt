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
  usage: ./${0##*/}  [-l TEST_LOOP] [-t LIBGPIOD_TESTCASE] [-i TEST_INTERRUPT]
  -l TEST_LOOP  test loop
  -t LIBGPIOD_TESTCASE testcase
  -i TEST_INTERRUPT if test interrupt, default is 0.
  -h Help   print this usage
EOF
exit 0
}

gpio_set_item() {
  GPIO_CHIP=$1
  OFFSET=$2
  VALUE=$3
  `gpioset --mode=time -s 15 --background ${GPIO_CHIP} ${OFFSET}=${VALUE}`
}

set_gpio_pinmux() {
  reg=$1
  mux_val=$2
  do_cmd devmem2 "$reg"
  reg_val_orig=`devmem2 "$reg" | grep "Read at address" |cut -d ":" -f2 `
  new_val=`echo $(( $(($reg_val_orig)) | $(($mux_val)) )) `
  new_val_hex=`echo "obase=16; $new_val" |bc `
  do_cmd devmem2 "$reg" w "$new_val_hex"
}

gpio_chips=()
offsets=()
new_values=()
gpioinfo_extract_output_gpio_pins() {
    chip_info=$1
    curr_gpio_chip=""
    num_chips_count=0
    while IFS= read -r line
    do
      IFS=' '
      usage_status=""
      direction=""
      if [[ $num_chips_count -ge 2 ]]; then
          break
      fi
      read -a strarr <<< "$line"
      if [[ "$line" == *"gpiochip"* ]] 
      then
          curr_gpio_chip="${strarr[0]}"
      else
          usage_status="${strarr[3]}"
          direction="${strarr[4]}"
      fi
      if [[ "${usage_status}" == "unused" && "${direction}" == "output" ]]; then
        offsets[${#offsets[@]}]="${strarr[1]%:}"
        new_values[${#new_values[@]}]=1
        gpio_chips[${#gpio_chips[@]}]="${curr_gpio_chip}"
        num_chips_count=`expr $num_chips_count + 1`
      fi
    done < <(printf '%s\n' "$chip_info")
}

gpioinfo_extract_given_offset() {
    chip_info=$1
    offset=`expr $2 + 1`
    count=0
    while IFS= read -r line
    do
      if [[ "$count" -eq $offset ]]; then
	      IFS=' '
        read -a strarr <<< "$line"
        usage_status="${strarr[3]}"
        if [[ "${usage_status}" == "\"gpioset\"" ]]
        then
          test_print_trc "GPIOSET is successful\n"
        else
          die "GPIOSET is not successful\n"
        fi

      fi
      count=`expr $count + 1`
    done < <(printf '%s\n' "$chip_info")
}

############################### CLI Params ###################################
while getopts  :l:t:i:h arg
do case $arg in
  l)  TEST_LOOP="$OPTARG";;
  t)  LIBGPIOD_TESTCASE="$OPTARG";;
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
test_print_trc "LIBGPIOD_TESTCASE:${LIBGPIOD_TESTCASE}"

do_cmd "cat /sys/kernel/debug/gpio"

platforms=("am180x-evm|omapl138-lcdk" "am335x-|beaglebone|beaglebone-black" "am335x-sk" 
           "beagleboard" "k2hk-evm|k2e-evm|k2l-evm" "am654x-evm|am654x-idk" "j721e" 
           "j784" "j742" "am64xx|am62xx|am62axx|am62dxx|am62lxx" "j721s" "j7200" "am68|am69" "k2g-evm"
           "dra7xx-evm|am572x-idk|am571x-idk|am574x-idk" "am57xx-evm" 
           "am43xx-epos|am43xx-gpevm|am437x-idk" "am62p")

valid_platform=0
for mach in ${platforms[@]}; do
  mach="${mach%\"}"
  mach="${mach#\"}"
  if [[ "$MACHINE" =~ $mach || "$mach" =~ $MACHINE ]]; then
    chip_info=$(gpioinfo)
    gpioinfo_extract_output_gpio_pins "$chip_info"
    valid_platform=1
    break
  fi
done

if [[ valid_platform == 0 ]]; then
  die "The gpio numbers are not specified for this platform $MACHINE"
fi

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

OIFS=$IFS
IFS=","
for j in "${!gpio_chips[@]}"; do
    EXTRA_PARAMS=""
    test_print_trc "gpio_chip_num:${gpio_chips[j]} offset:${offsets[j]}"

    if [ "$TEST_INTERRUPT" = "1" ]; then
      do_cmd lsmod | grep gpio_test
      if [ $? -eq 0 ]; then
        test_print_trc "Module already inserted; Removing the module"
        do_cmd rmmod gpio_test.ko
        sleep 2
      fi
    fi

    if [ "$TEST_INTERRUPT" = "1" ]; then
      test_print_trc "Inserting gpio test module. Please wait..."
      do_cmd "cat /proc/interrupts"
      # wait TIMEOUT for app to finish; if not finished by TIMEOUT, kill it
      # gpio_test module return sucessfully only after the interrupt complete.
      # do_cmd "timeout 30 insmod ddt/gpio_test.ko gpio_num=${gpio_num} test_loop=${TEST_LOOP} ${EXTRA_PARAMS}"
      # ( do_cmd insmod ddt/gpio_test.ko gpio_num=${gpio_num} test_loop=${TEST_LOOP} ${EXTRA_PARAMS} ) & pid=$!
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

    # run libgpiod tests if asked
    if [ -n "$LIBGPIOD_TESTCASE" ]; then
      test_print_trc "Running libgpiod test..."

      # test loop
      i=0
      while [ $i -lt $TEST_LOOP ]; do 
        test_print_trc "===LOOP: $i==="
        gpio_set_item "${gpio_chips[j]}" "${offsets[j]}" "${new_values[j]}"
        chip_info=$(gpioinfo "${gpio_chips[j]}")
        gpioinfo_extract_given_offset "$chip_info" "${offsets[j]}"
        i=`expr $i + 1`
      done  # while loop
    fi

done
IFS=$OIFS

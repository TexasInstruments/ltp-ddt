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
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# @desc Script to check CM clkctrl reg modulemode for gpio

. "common.sh"

############################# Functions #######################################

# Check if module is disabled or enabled by checking MODULEMODE bits
# Input:
# $1 => clkctrl_register_addr
# $2 => (boolean) true-> should be enabled OR false->should be disabled
check_clkctrl_reg() {
	clkctrl_reg=$1
	should_enabled=$2
	MODULEMODE_MASK="0x3"

	reg_val=$(devmem2 "$clkctrl_reg" | grep -i 'Read at address' |cut -d":" -f2)
	test_print_trc "Register @ |$clkctrl_reg| value is: |$reg_val|"

	modulemode=$((reg_val & MODULEMODE_MASK))

	if [ "$modulemode" -eq 0 ];then
		test_print_trc "MODULEMODE = 0 -> Module is disabled"
		if [ "$should_enabled" = "true" ]; then
			die "The gpio module should not be disabled!"
		fi
	else
		test_print_trc "MODULEMODE != 0 -> Module is NOT disabled"
		if [ "$should_enabled" = "false" ]; then
			die "The gpio module should be disabled!"
		fi
	fi

}

############################### CLI Params ###################################
########################### DYNAMICALLY-DEFINED Params ########################

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use user-defined Params section above.

do_cmd "cat /sys/kernel/debug/gpio"
do_cmd "cat /proc/interrupts | grep -i gpio"

# gpio bank 0 starts at gpio 1 for dra7* and am57*
# gpio bank 0 counts from gpio 0 for am33* and am437*
# table for gpio bank/module : gpio_bank_clkctrl register address
case $MACHINE in
	am335x-evm)
		#gpio_banks="2:0x44E000B0 3:0x44E000B8"
		gpio_banks="481ac000:0x44E000B0" # gpio 2
	;;
	dra7xx-evm|dra72x-evm)
		#gpio_banks="0:0x4AE07838 1:0x4A009760" # 0=>CM_WKUPAON_GPIO1_CLKCTRL; 1=>CM_L4PER_GPIO2_CLKCTRL
		gpio_banks="48057000:0x4A009818" # gpio 3
	;;
	am57xx-evm)
		#gpio_banks="0:0x4AE07838 2:0x4A009768"
		gpio_banks="48057000:0x4A009818" #gpio 3
	;;
	am574x-idk|am572x-idk)
		#gpio_banks="0:0x4AE07838 2:0x4A009768"
		gpio_banks="48055000:0x4A009760" # gpio 2
	;;
	am43xx-epos|am43xx-gpevm|am437x-idk)
		gpio_banks="481ac000:0x44E000B0" #gpio 2
	;;
	*)
		die "The free gpio:reg pairs are not specified for this platform $MACHINE"
	;;
esac

if [ -z "$gpio_banks" ]; then
	test_print_trc "No free gpio bank for testing!"
	exit 1
fi

for gpio_bank_reg_pair in $gpio_banks; do

	gpio_addr=$(echo "$gpio_bank_reg_pair" |cut -d":" -f1)
	gpio_chip=$(grep "$gpio_addr" /sys/kernel/debug/gpio | grep -o "gpiochip.")
	clkctrl_reg=$(echo "$gpio_bank_reg_pair" |cut -d":" -f2)

	echo "Testing gpio chip: |$gpio_chip| @ gpio addr: |0x$gpio_addr| & clkctrl addr: |$clkctrl_reg|"

	test_print_trc "Checking clkctrl register for gpio chip |$gpio_chip| when bank is free"
	check_clkctrl_reg "$clkctrl_reg" false

	test_print_trc "Checking clkctrl register for gpio chip |$gpio_chip| when bank is NOT free"
	gpioset -s 10 --mode=time "$gpio_chip" 0=0&
	sleep 1
	check_clkctrl_reg "$clkctrl_reg" true
	killall gpioset
	sleep 1

	test_print_trc "Check when the bank is free again"
	check_clkctrl_reg "$clkctrl_reg" false
done

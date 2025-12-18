#!/bin/sh
#Copyright (C) 2025 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# k3conf_clk_set_freq_test.sh
# Verifies whether k3conf power domain commands work
# usage:  k3conf_clk_set_freq_test.sh

source "common.sh"
source "k3conf_common.sh"

set_freq_test(){
    local dev_id=$1
    local clk_id=$2
    local new_freq=$3
    local clk_reg=$4
    
    echo -n " Setting frequency of clock id $clk_id to $new_freq"
    cmd_set_clock_freq $dev_id $clk_id $new_freq
    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf set clock $dev_id $clk_id $new_freq\" failed"
    else
        echo " - command \"k3conf set clock $dev_id $clk_id $new_freq\" successfully executed"
    fi

    status=$(cmd_dump_clock_freq $dev_id $clk_id)
    echo " Frequency of Clock ID $clk_id - $status"

    freq=$(echo $status | awk -F":" '{print $2}' | xargs)
    if [ "$freq" == "$new_freq" ]; then
        echo " [PASS] Frequency set confirmed via k3conf"
    else
        echo " Expected frequency $new_freq "
        echo " Received frequency $freq "
        die "[FAIL] Incorrect output for command \"k3conf set clock $dev_id $clk_id $new_freq\""
    fi    

    if [[ -n $clk_reg ]]; then    
        local reg_value=$(sudo devmem2 $clk_reg w | grep Read | awk -F" " '{print $6}')
        echo " Clock reg value = $reg_value"
        hsdiv=$((reg_value & 127))
        echo " HSDIV value = $hsdiv"

        hsdiv_new=$((((prev_freq*(hsdiv_prev+1))/new_freq-1))) # Order changed to avoid floating point error
        if [ "$hsdiv" == "$hsdiv_new" ]; then
            echo " [PASS] Frequency set confirmed via PLL register"
        else
            echo " Expected HSDIV value $hsdiv_new "
            echo " Received HSDIV value $hsdiv "
            die "[FAIL] PLL register has incorrect HSDIV value"
        fi
    fi
}

check_state(){
    local dev_id=$1
    local clk_id=$2
    local clk_reg=$4
    status=$(cmd_dump_clock_state $dev_id $clk_id)
    echo " State of Clock ID $clk_id - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)

    if [ "$state" = "CLK_STATE_NOT_READY" ]; then
        echo " Given clock id is not ready... Enabling clock id $clk_id"
        cmd_enable_clock $dev_id $clk_id
        status=$(cmd_dump_clock_state $dev_id $clk_id)
        state=$(echo $status | awk -F":" '{print $2}' | xargs)
        if [ "$state" = "CLK_STATE_NOT_READY" ]; then
            die "[FAIL] Clock id $clk_id is not ready, so cannot set frequency"
        else
            echo " Clock id $clk_id is ready and frequency can be set"
        fi
    else
        echo " Clock id $clk_id is ready and frequency can be set"
    fi

    status=$(cmd_dump_clock_freq $dev_id $clk_id)
    prev_freq=$(echo $status | awk -F":" '{print $2}' | xargs)
    echo " Frequency of Clock ID $clk_id - $status"
    
    if [[ -n $clk_reg ]]; then
        local reg_value=$(sudo devmem2 $clk_reg w | grep Read | awk -F" " '{print $6}')
        echo " Clock reg value = $reg_value"
        hsdiv_prev=$((reg_value & 127))
        echo " HSDIV value = $hsdiv_prev"
    fi
}

echo "Testing k3conf clock domain command for setting frequency of clocks"
echo "---------------------------------------------------------------------"
echo "[Test 1] - k3conf set clock <dev id> <clock id> <freq>"
echo "This test checks if the k3conf set clock command sets the frequency correctly"

for arg in "$@"; do
    check_state $arg
    set_freq_test $arg
    echo ""
done

echo "---------------------------------------------------------------------"


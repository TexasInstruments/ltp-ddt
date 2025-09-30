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

# k3conf_clk_en_test.sh
# Verifies whether k3conf power domain commands work
# usage:  k3conf_clk_en_test.sh

source "common.sh"
source "k3conf_common.sh"

k3conf_clk_en_test(){
    dev=$1
    clk=$2
    status=$(cmd_dump_clock_state $dev $clk)
    echo " State of Clock id $clk - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "CLK_STATE_NOT_READY" ]; then
        echo -n " Enable Clock id $clk"
        cmd_enable_clock $dev $clk
            if [[ $? -eq 0 ]]
            then
                echo " - command \"k3conf enable device $dev\" successfully executed"
            else
                echo ""
                die "[FAIL] Command execution of \"k3conf enable clock $dev $clk\" failed"
            fi
    else
        echo " Clock id $clk is already ON... Try another Clock id "
        return
    fi

    status=$(cmd_dump_clock_state $dev $clk)
    echo " State of Clock id $clk - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)

    if [ "$state" = "CLK_STATE_NOT_READY" ]; then
        echo " Expected Clock id $clk state = CLK_STATE_READY "
        echo " Received Clock id $clk state = $state "
        die "[FAIL] Incorrect output for command \"k3conf enable clock $dev $clk\""
    else
        echo " [PASS] Clock enabled confirmed via k3conf"
    fi
}

echo "Testing k3conf clock domain command for enabling clocks"
echo "---------------------------------------------------------------------"
echo "[Test 1] - k3conf enable clock <dev id> <clock id>"
echo "This test checks if the k3conf enable clock command enables the clock correctly"

for arg in "$@"; do
    k3conf_clk_en_test $arg
    echo ""
done

echo " ------------------------------------------------------------------------- "


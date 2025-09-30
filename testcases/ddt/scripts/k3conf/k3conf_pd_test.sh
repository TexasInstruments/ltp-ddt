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

# k3conf_pd_test.sh
# Verifies whether k3conf power domain commands work
# usage:  k3conf_pd_test.sh

source "common.sh"
source "k3conf_common.sh"

readonly POWER_STATE_MASK=0x3
readonly POWER_ENABLED=0x3
readonly POWER_DISABLED=0x0
readonly MDSTAT_base=0x00400800

enable_test(){
    local dev=$1
    local lpsc=$2

    status=$(cmd_dump_device $dev)
    echo " State of Device $dev - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "DEVICE_STATE_OFF" ]; then
        # Not all device ids have a corresponding LPSC
        if [[ -n $lpsc ]]; then
            local offset=$(($lpsc*4))
            local lpsc_reg=$((MDSTAT_base+offset))
            reg_status=$(sudo devmem2 $lpsc_reg w | grep Read | awk -F" " '{print $6}')
            echo " MDSTAT reg for LPSC ID-$lpsc = $reg_status"
            if [[ $((reg_status & POWER_STATE_MASK)) -ne POWER_DISABLED ]]; then
                die "[FAIL] MDSTAT register indicates device is not disabled"
            fi
        fi

        echo -n " Enable Device $dev"
        cmd_enable_device $dev
            if [[ $? -eq 0 ]]
            then
                echo " - command \"k3conf enable device $dev\" successfully executed"
            else
                echo ""
                die "[FAIL] Command execution of \"k3conf enable device $dev\" failed"
            fi
    else
        echo " Device $dev is already ON... Try another Device ID "
        return
    fi
    
    status=$(cmd_dump_device $dev)
    echo " State of Device $dev - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "DEVICE_STATE_OFF" ]; then
        echo " Expected Device $dev state = DEVICE_STATE_ON "
        echo " Received Device $dev state = $state "
        die "[FAIL] Incorrect output for command \"k3conf enable device $dev\""
    else
        echo " [PASS] Device enable confirmed via k3conf"
    fi

    if [[ -n $lpsc ]]; then
        local offset=$(($lpsc*4))
        local lpsc_reg=$((MDSTAT_base+offset))
        reg_status=$(sudo devmem2 $lpsc_reg w | grep Read | awk -F" " '{print $6}')
        echo " MDSTAT reg for LPSC ID-$lpsc = $reg_status"

        if [[ $((reg_status & POWER_STATE_MASK)) -ne POWER_ENABLED ]]; then
            die "[FAIL] MDSTAT register indicates device is not enabled"
        else
            echo " [PASS] Device enable confirmed via MDSTAT register"
        fi
    fi
}

disable_test(){
    local dev=$1
    local lpsc=$2

    status=$(cmd_dump_device $dev)
    echo " State of Device $dev - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "DEVICE_STATE_ON" ]; then
        # Not all device ids have a corresponding LPSC
        if [[ -n $lpsc ]]; then
            local offset=$(($lpsc*4))
            local lpsc_reg=$((MDSTAT_base+offset))
            reg_status=$(sudo devmem2 $lpsc_reg w | grep Read | awk -F" " '{print $6}')
            echo " MDSTAT reg for LPSC ID-$lpsc = $reg_status"
            if [[ $((reg_status & POWER_STATE_MASK)) -ne POWER_ENABLED ]]; then
                die "[FAIL] MDSTAT register indicates device is not enabled"
            fi
        fi

        echo -n " Disable Device $dev"
        cmd_disable_device $dev
            if [[ $? -eq 0 ]]
            then
                echo " - command \"k3conf disable device $dev\" successfully executed"
            else
                echo ""
                die "[FAIL] Command execution of \"k3conf disable device $dev\" failed"
            fi
    else
        echo " Device $dev is already OFF "
        echo " Try another device "
        return
    fi
    
    status=$(cmd_dump_device $dev)
    echo " State of Device $dev - $status"
    state=$(echo $status | awk -F":" '{print $2}' | xargs)

    if [ "$state" = "DEVICE_STATE_ON" ]; then
        echo " Expected Device $dev state = DEVICE_STATE_OFF "
        echo " Received Device $dev state = $state "
        die "[FAIL] Incorrect output for command \"k3conf enable device $dev\""
    else
        echo " [PASS] Device enable confirmed via k3conf"
    fi

    if [[ -n $lpsc ]]; then
        local offset=$(($lpsc*4))
        local lpsc_reg=$((MDSTAT_base+offset))
        reg_status=$(sudo devmem2 $lpsc_reg w | grep Read | awk -F" " '{print $6}')
        echo " MDSTAT reg for LPSC ID-$lpsc = $reg_status"

        if [[ $((reg_status & POWER_STATE_MASK)) -ne POWER_DISABLED ]]; then
            die "[FAIL] MDSTAT register indicates device is not disabled"
        else
            echo " [PASS] Device enable confirmed via MDSTAT register"
        fi
    fi
}

echo "Testing k3conf power domain commands"
echo " ------------------------------------------------------------------------- "
echo "[Test 1] - k3conf enable device <dev id>"
echo "This test checks if the k3conf enable device command enables the device"

for arg in "${@:1:$#-1}"; do
    enable_test $arg
    echo ""
done

echo " ------------------------------------------------------------------------- "

echo "[Test 2] - k3conf disable device <dev id>"
echo "This test checks if the k3conf disable device command disables the device"

for arg in "${@:1:$#-1}"; do
    disable_test $arg
    echo ""
done

echo " ------------------------------------------------------------------------- "

if [[ "${@: -1}" == "enable" ]]; then

echo "[Test 3] - Toggle all devices"
echo "( Toggling devices that are in OFF state to not crash the system )"

# Number of devices
n=$(k3conf dump device | grep "DEVICE_STATE" | wc -l)
echo " Number of devices = $n"

for((i=0;i<n;i++)); do
status=$(cmd_dump_device $i)

state=$(echo $status | awk -F":" '{print $2}' | xargs)
if [ "$state" = "DEVICE_STATE_OFF" ]; then
    echo " --- Toggling Device $i --- "
    echo -n " Enable Device $i -"
    cmd_enable_device $i
        if [[ $? -ne 0 ]]
        then
            echo ""
            die "[FAIL] Command execution of \"k3conf enable device $i\" failed"
        fi
    state=$( cmd_dump_device $i | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "DEVICE_STATE_ON" ]; then
        echo " OK ... Device $i is ON "
    else
        die "[FAIL] Did not turn ON device $i"
    fi
    echo -n " Disable Device $i -"
    cmd_disable_device $i
        if [[ $? -ne 0 ]]
        then
            echo ""
            die "[FAIL] Command execution of \"k3conf disable device $i\" failed"
        fi
    state=$( cmd_dump_device $i | awk -F":" '{print $2}' | xargs)
    if [ "$state" = "DEVICE_STATE_OFF" ]; then
        echo " OK ... Device $i is OFF "
    else
        die "[FAIL] Did not turn OFF device $i"
    fi
    echo " Toggle Test Passed for Device $i "
fi
done

echo " [PASS] Toggle test passed for all devices"

fi
echo " ------------------------------------------------------------------------- "

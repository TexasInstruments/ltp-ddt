#!/bin/bash
#
# Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
# 
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# k3conf_test.sh
# Verifies whether few k3conf commands run without any errors
# Verifies whether silicon revision is reported correctly by k3conf
# usage:  k3conf_test.sh 

source "common.sh"

check_exec_status_cmds () {
    local cmd_arr=("$@")
    for cmd in "${cmd_arr[@]}"
    do
        output=$($cmd > /dev/null 2>&1)
        if [[ $? -eq 0 ]]
        then
            echo "Successful execution of \"${cmd}\""
        else
            die "Unsuccessful execution of \"${cmd}\""
        fi
    done
}

check_silicon_rev () {
    output=$(k3conf --version)
    while IFS= read -r line
    do
    pattern="\|\s*SoC\s*\|"
    if [[ "$line" =~ $pattern ]]
    then
            IFS='| '
            read -a strarr <<< "$line"
            k3conf_SOC_REV="${strarr[2]} ${strarr[3]}"
    fi
    done < <(printf '%s\n' "$output")

    family=$(cat /sys/devices/soc0/family)
    machine=$(cat /sys/devices/soc0/machine | cut -d' ' -f3)
    rev=$(cat /sys/devices/soc0/revision)
    sys_devices_SOC_REV="$family $rev"
    sys_devices_MACHINE_REV="$machine $rev"

    sys_socrev=`echo "$sys_devices_SOC_REV" | awk '{print tolower($0)}'`
    sys_machinerev=`echo "$sys_devices_MACHINE_REV" | awk '{print tolower($0)}'`
    k3conf_socrev=`echo "$k3conf_SOC_REV" | awk '{print tolower($0)}'`

    printf "SoC rev in /sys/devices/soc0/family=$sys_devices_SOC_REV\n"
    printf "SoC rev in /sys/devices/soc0/machine=$sys_devices_MACHINE_REV\n"
    printf "SoC rev reported by k3conf=$k3conf_SOC_REV\n"

    if [[ "$sys_socrev" == "$k3conf_socrev" ]]
    then
        echo "Correct silicon revision is reported"
    elif [[ "$sys_machinerev" == "$k3conf_socrev" ]]
    then
        echo "Correct silicon revision is reported"
    else
        die "Wrong silicon revision is reported"
    fi
}

cmd_arr=("$@")
check_exec_status_cmds "${cmd_arr[@]}" 
check_silicon_rev
#!/bin/sh
#
# Copyright (C) 2025 Texas Instruments Incorporated - http://www.ti.com/
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

# POWER DOMAIN
cmd_dump_device() {
    dev=$1
    k3conf dump device $dev 2> /dev/null | grep "DEVICE_STATE" | awk -F"|" '{print $3 ":" $4}' | xargs
}

cmd_enable_device() {
    dev=$1
    k3conf enable device $dev 2> /dev/null 1> /dev/null
}

cmd_disable_device() {
    dev=$1
    k3conf disable device $dev 2> /dev/null 1> /dev/null
}

# CLOCK DOMAIN

cmd_dump_clock() {
    dev=$1
    clk=$2
    k3conf dump clock $dev 2> /dev/null | awk -F'|' -v id="$clk" '{                                                                                         
    col=$3; gsub(/^ +| +$/, "", col)
    if (col == id) print
}'
}
cmd_dump_clock_state() {
    dev=$1
    clk=$2
    k3conf dump clock $dev 2> /dev/null | awk -F'|' -v id="$clk" '{                                                                                         
        col=$3; gsub(/^ +| +$/, "", col)
        if (col == id) print
    }' | awk -F"|" '{print $4 ":" $5}' | xargs
}

cmd_dump_clock_freq(){
    dev=$1
    clk=$2
    k3conf dump clock $dev 2> /dev/null | awk -F'|' -v id="$clk" '{                                                                                         
        col=$3; gsub(/^ +| +$/, "", col)
        if (col == id) print
    }' | awk -F"|" '{print $4 ":" $6}' | xargs
}

cmd_enable_clock(){
    dev=$1
    clk=$2
    k3conf enable clock $dev $clk 2> /dev/null 1> /dev/null
}

cmd_disable_clock(){
    dev=$1
    clk=$2
    k3conf disable clock $dev $clk 2> /dev/null 1> /dev/null
}

cmd_set_clock_freq(){
    dev=$1
    clk=$2
    freq=$3
    k3conf set clock $dev $clk $freq 2> /dev/null 1> /dev/null
}

# PARENT CLOCK DOMAIN

cmd_get_possible_parents(){
    dev=$1
    clk=$2
    k3conf dump parent_clock $dev $clk 2> /dev/null | awk -F'|' '
    /Clock Parent information/,EOF {
        if (NF == 7) {
            clock_id=$3; gsub(/^ +| +$/, "", clock_id)
            clock_name=$4; gsub(/^ +| +$/, "", clock_name)
            if (clock_id ~ /^[0-9]+$/) {
                print clock_id " : " clock_name
            }
        }
    }'
}

cmd_get_parent_clock(){
    dev=$1
    clk=$2
    k3conf dump parent_clock $dev $clk 2> /dev/null | awk -F'|' '
    /Clock Parent information/,EOF {
        if (NF == 7) {
            selected=$2; gsub(/^ +| +$/, "", selected)
            if (selected == "==>") {
                clock_id=$3; gsub(/^ +| +$/, "", clock_id)
                clock_name=$4; gsub(/^ +| +$/, "", clock_name)
                print clock_id " : " clock_name
                exit
            }
        }
    }'
}

cmd_set_parent_clock(){
    dev=$1
    clk=$2
    parent_clk=$3
    k3conf set parent_clock $dev $clk $parent_clk 2> /dev/null 1> /dev/null
}


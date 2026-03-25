#!/bin/sh
#Copyright (C) 2026 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# k3conf_clk_parent_test.sh
# Verifies whether k3conf parent clock commands work
# usage:  k3conf_clk_parent_test.sh

source "common.sh"
source "k3conf_common.sh"

parent_clock_test(){
    local dev=$1
    local clk=$2

    echo " [Test 1.1] GET possible parents for Clock ID $clk"
    echo -n " Getting possible parents"
    possible_parents=$(cmd_get_possible_parents $dev $clk)

    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf get parent_clock $dev $clk \" failed"
    else
        echo " - command \"k3conf get parent_clock $dev $clk \" successfully executed"
    fi

    echo ""
    echo " Possible parents:"
    echo "$possible_parents" | while read line; do
        echo "  $line"
    done

    echo ""
    echo " [Test 1.2] GET current parent for Clock ID $clk"
    echo -n " Getting current parent"
    current_parent=$(cmd_get_parent_clock $dev $clk)

    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf get parent_clock $dev $clk \" failed"
    else
        echo " - command \"k3conf get parent_clock $dev $clk \" successfully executed"
    fi

    echo " Current parent = $current_parent"
    current_parent_id=$(echo $current_parent | awk -F":" '{print $1}' | xargs)

    echo "---------------------------------------------------------------------"

    # Extract one of the possible parents (different from current)
    parent_id_to_set=""
    while read line; do
        line_id=$(echo $line | awk -F":" '{print $1}' | xargs)
        if [ "$line_id" != "$current_parent_id" ]; then
            parent_id_to_set=$line_id
            break
        fi
    done << EOF
    $possible_parents
EOF

    if [ -z "$parent_id_to_set" ]; then
        echo " [SKIP] Only one parent available, cannot test SET"
        return
    fi

    echo ""
    echo " [Test 2.1] SET parent to Clock ID $parent_id_to_set"
    echo -n " Setting parent clock to $parent_id_to_set"
    cmd_set_parent_clock $dev $clk $parent_id_to_set

    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf set parent_clock $dev $clk $parent_id_to_set\" failed"
    else
        echo " - command \"k3conf set parent_clock $dev $clk $parent_id_to_set\" successfully executed"
    fi

    echo -n " Verifying parent was set correctly"
    new_parent=$(cmd_get_parent_clock $dev $clk)

    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf get parent_clock $dev $clk \" failed"
    else
        echo " - command \"k3conf get parent_clock $dev $clk \" successfully executed"
    fi

    new_parent_id=$(echo $new_parent | awk -F":" '{print $1}' | xargs)
    if [ "$new_parent_id" == "$parent_id_to_set" ]; then
        echo " [PASS] Parent clock set confirmed - Current parent: $new_parent"
    else
        echo " Expected parent ID: $parent_id_to_set"
        echo " Received parent ID: $new_parent_id"
        die "[FAIL] Parent clock was not set correctly"
    fi

    echo ""
    echo " [Test 2.2] SET parent to invalid Clock ID"
    invalid_parent_id=$clk # Setting parent to its own clock ID which should be invalid
    echo " Setting parent clock to invalid ID $invalid_parent_id"
    output=$(k3conf set parent_clock $dev $clk $invalid_parent_id 2>&1)

    if echo "$output" | grep -q "SCMI_ERROR"; then
        echo "[PASS] Expected error received: SCMI_ERROR"
    else
        echo ""
        die "[FAIL] Expected SCMI_ERROR for invalid parent ID, but got: $output"
    fi

    echo ""
    echo " [Test 2.3] Restore original parent"
    echo -n " Restoring original parent clock to $current_parent_id"
    cmd_set_parent_clock $dev $clk $current_parent_id

    if [ $? -ne 0 ]; then
        echo ""
        die "[FAIL] Command execution of \"k3conf set parent_clock $dev $clk $current_parent_id\" failed"
    else
        echo " - command successfully executed"
    fi

    restored_parent=$(cmd_get_parent_clock $dev $clk)
    restored_parent_id=$(echo $restored_parent | awk -F":" '{print $1}' | xargs)

    if [ "$restored_parent_id" == "$current_parent_id" ]; then
        echo " [PASS] Original parent clock restored - Current parent: $restored_parent"
    else
        echo " Expected parent ID: $current_parent_id"
        echo " Received parent ID: $restored_parent_id"
        die "[FAIL] Original parent clock was not restored correctly"
    fi
}

echo "Testing k3conf parent clock domain commands"
echo "---------------------------------------------------------------------"
echo "[Test] - k3conf parent clock GET/SET operations"
echo "This test checks if the k3conf parent clock commands work correctly"
echo ""
set -o pipefail
for arg in "$@"; do
    parent_clock_test $arg
    echo ""
done

echo "---------------------------------------------------------------------"


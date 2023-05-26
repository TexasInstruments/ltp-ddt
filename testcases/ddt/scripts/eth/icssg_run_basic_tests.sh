#!/bin/sh

### Script to run all basic tests related to ICSSG (Mac Mode)
### Returns 0 in success and 1 on failure.

source "common.sh"
source "netlib.sh"

driver=$1
test_to_run=$2

interfaces=$(get_eth_list)

### ICSSG interfaces are not up by default in NFS boot.
### This for loop will try to bring all ICSSG interfaces up if they are down.
down_interfaces=0;
for iface in $interfaces
do
        if [[ "$driver" == "$(get_if_drv $iface)" ]]
        then
                interface_state=$(get_state $iface)
                if [[ "up" != $interface_state ]]
                then
                        down_interfaces=$(($down_interfaces+1));
                        echo "Trying to bring interface $iface up" >&2;
                        ifconfig $iface up;
                fi
        fi
done

echo "Down interfaces = $down_interfaces" >&2;

if [[ $down_interfaces -gt 0 ]]
then
        sleep 10;
fi

result=0;
result=$($test_to_run $driver);

if [[ $result != 1 ]]
then
        exit 1;
fi

if [[ $result == 0 ]]
then
        exit 1;
else
        exit 0;
fi

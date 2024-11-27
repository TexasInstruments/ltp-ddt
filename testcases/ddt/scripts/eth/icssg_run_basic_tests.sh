#!/bin/sh

### Script to run all basic tests related to ICSSG (Mac Mode)
### Returns 0 in success and 1 on failure.

source "common.sh"
source "netlib.sh"

driver=$1
test_to_run=$2
optargs=${@:3};

interfaces=$(get_eth_list)

### ICSSG interfaces are not up by default in NFS boot.
### This for loop will try to bring all ICSSG interfaces up if they are down.
down_interfaces=0;
for iface in $interfaces
do
        interface_state=$(get_state $iface)
        if [[ "up" != $interface_state ]]
        then
                down_interfaces=$(($down_interfaces+1));
                echo "Trying to bring interface $iface up" >&2;
                ifconfig $iface up;
        fi
done

echo "Down interfaces = $down_interfaces" >&2;

if [[ $down_interfaces -gt 0 ]]
then
        sleep 10;
fi

result=0;

### Testing PPS requires enabling PPS for both IEP and CPTS drivers.
### IEP driver: For testing PPS signal of ICSSG.
### CPTS driver: Since HW_PUSH events are bring used to generate pps
### events, this drivers pps source needs to be enabled and tested.
### Hence the driver needs to be overwritten accordingly for PPS testcase.
if [[ "$test_to_run" == "test_drv_pps" ]]
then
        test_run_pps $driver;
        driver="am65-cpts";
fi

echo "Executing test: $test_to_run for driver: $driver" >&2;
if [[ -z "$optargs" ]]
then
        result=$($test_to_run $driver);
else
        result=$($test_to_run $driver $optargs);
fi

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

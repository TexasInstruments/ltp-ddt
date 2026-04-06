#!/bin/sh

source "common.sh"
source "netlib.sh"

testname=$1;
driver=$2;
optargs=${@:3};

interfaces=$(get_eth_list)

### All Interfaces may not be up by default.
### This for loop will try to bring all interfaces of the given driver up if they are down.
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
echo "Executing test: $testname for driver: $driver" >&2;
if [[ -z "$optargs" ]]
then
	result=$($testname $driver);
else
	result=$($testname $driver $optargs);
fi
if [[ $result == 0 ]]
then
        exit 1;
else
        exit 0;
fi

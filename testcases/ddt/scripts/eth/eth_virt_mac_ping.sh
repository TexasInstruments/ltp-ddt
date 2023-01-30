#!/bin/sh

source "common.sh"
source "netlib.sh"

driver=$1
interface_list=$(get_eth_list)
result=0;
for iface in $interface_list
do
  if_drv=$(get_if_drv $iface);
  if [[ $if_drv == $driver ]]
  then
    check=$(check_mac_only $iface);
    if [[ $check == 1 ]]
    then
      result=$(test_ping $iface);
      if [[ $result != 1 ]]
      then
        exit 1;
      fi
    fi
  fi
done
if [[ $result == 0 ]]
then
        exit 1;
else
        exit 0;
fi

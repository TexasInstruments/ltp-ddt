#!/bin/sh

source "common.sh"
source "netlib.sh"

testname=$1;
driver=$2;
result=0;
echo "Executing test: $testname for driver: $driver" >&2;
result=$($testname $driver);
if [[ $result == 0 ]]
then
        exit 1;
else
        exit 0;
fi

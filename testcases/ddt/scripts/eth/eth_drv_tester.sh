#!/bin/sh

source "common.sh"
source "netlib.sh"

testname=$1;
driver=$2;
optargs=$3;
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

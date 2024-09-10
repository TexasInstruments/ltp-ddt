#!/bin/sh

source "common.sh"
source "pcielib.sh"

testname=$1;
vendorid=$2;
optargs=${@:3};
result=0;
echo -e "Executing test: $testname for vendor id: $vendorid\n" >&2;
if [[ -z "$optargs" ]]
then
        result=$($testname $vendorid);
else
        result=$($testname $vendorid $optargs);
fi
if [[ $result == 0 ]]
then
        exit 1;
else
        exit 0;
fi

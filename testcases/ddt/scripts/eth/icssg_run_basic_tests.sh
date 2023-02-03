#!/bin/sh

### Script to run all basic tests related to ICSSG (Mac Mode)
### Returns 0 in success and 1 on failure.

source "common.sh"
source "netlib.sh"

driver=$1
test_to_run=$2

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

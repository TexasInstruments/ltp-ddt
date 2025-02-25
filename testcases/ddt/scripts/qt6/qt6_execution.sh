#!/bin/bash

source "common.sh"

/usr/share/examples/qtestlib/$1/bin/$1 > results.txt

exit_code=$?

num_failed=$(grep -oE '([0-9]+) failed' results.txt | awk '{print $1}')


if (( exit_code != 0 )); then
        test_print_err "FATAL: Test failed, exit code is: ${exit_code}"
        exit $exit_code
elif (( num_failed != 0 )); then
        die "Test failed, number of failed sub tests: ${num_failed}"
fi
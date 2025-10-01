#! /bin/bash
#
# Copyright (C) 2024 Texas Instruments Incorporated - https://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# cpu_load_test.sh
# Verifies whether our CPU loader runs without errors on nproc number of cores
# usage:  cpu_load_test.sh


source "functions.sh"

output=$( cpu_load_nproc 100 10 )
if [[ $? -eq 0 ]]
then
		echo "Successful execution : \"$output\""
else
		die "Unsuccessful execution : \"$output\""
fi


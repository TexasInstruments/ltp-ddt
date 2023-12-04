#! /bin/sh
###############################################################################
# Copyright (C) 2018 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
###############################################################################

source "common.sh"  # Import do_cmd(), die() and other functions

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are
# initilized and exported by runltp script based on platform option (-P)

# Define default values for variables being overriden
PREFIX='k3'

case $ARCH in
esac
case $DRIVER in
esac
case $SOC in
	j784s4) PREFIX='k3-j784s4-evm';;
	j721e) PREFIX='k3-j721e-evm';;
	j721s2) PREFIX='k3-j721s2-evm';;
	j722s) PREFIX='k3-j722s-evm';;
	j7200) PREFIX='k3-j7200-evm';;
	am654) PREFIX='k3-am654*';;
	am62xx) PREFIX='k3-am625-sk';;
esac
case $MACHINE in
esac


########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

echo ${PREFIX}

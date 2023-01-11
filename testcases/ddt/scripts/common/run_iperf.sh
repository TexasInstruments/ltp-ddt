#! /bin/sh
############################################################################### 
# Copyright (C) 2011 Texas Instruments Incorporated - http://www.ti.com/
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

# @desc Run IPERF http://sourceforge.net/projects/iperf/ 

source "common.sh"  # Import do_cmd(), die() and other functions
source "st_log.sh"  # Import log functions such as test_print_trc()

############################# Functions #######################################
usage()
{
	echo "run_iperf.sh -v 3 -H <host> -- [other iperf options (see iperf help)"
	echo " -H <host>: IP address of Host running iperf in server mode"
	echo " -v <version>: Use specific iperf version"
	echo " all other args are passed as-is to iperf"
	echo " iperf help:"
        echo `iperf -h`
	exit 1
}

resolve_iperf_version() 
{
	local version=$1
	echo "Checking for iperf installation version: $version"	
	case $version in
		2)
			if ! [ -x "$(command -v iperf)" ]; then
		    		echo "[ERROR] iperf version 2 is not installed... exiting"
				exit 1
			else
				IPERF_BIN=`which iperf`	    	
				echo "[INFO]: iperf binary set to: $IPERF_BIN"
			fi
			;;
		3) if ! [ -x "$(command -v iperf3)" ]; then
		        echo "[ERROR] iperf version 3 is not installed... exiting"
                        exit 1
                   else
                        IPERF_BIN=`which iperf3`
                        echo "[INFO]: iperf binary set to: $IPERF_BIN"
                   fi
                   ;;
		*) echo "Iperf version not found... exiting"
		   exit 1
		   ;;
	esac
}

################################ CLI Params ####################################
# Please use getopts
IPERF_BIN="iperf"
while getopts  :H:v:h arg
do case $arg in
        H)      IPERFHOST="$OPTARG"; shift 2 ;;
        h)      usage;;
        v)      resolve_iperf_version $OPTARG;;
        *)      ;;
        :)      ;;
        \?)     ;;
esac
done
shift $(($OPTIND - 1))

# Define default values if possible

############################ USER-DEFINED Params ###############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically. ARCH, DRIVER, SOC and MACHINE are 
# initilized and exported by runltp script based on platform option (-P)
case $ARCH in
esac
case $DRIVER in
esac
case $SOC in
esac
case $MACHINE in
esac
# Define default values for variables being overriden

########################### DYNAMICALLY-DEFINED Params #########################
# Try to use /sys and /proc information to determine values dynamically.
# Alternatively you should check if there is an existing script to get the
# value you want

: ${IPERFHOST:=`cat /proc/cmdline | awk '{for (i=1; i<=NF; i++) { print $i} }' | grep 'nfsroot=' | awk -F '[=:]' '{print $2}'`}

########################### REUSABLE TEST LOGIC ###############################
# DO NOT HARDCODE any value. If you need to use a specific value for your setup
# use USER-DEFINED Params section above.

[ -n "$IPERFHOST" ] || IPERFHOST=`get_eth_gateway.sh`
[ -n "$IPERFHOST" ] || die "IPERF server IP address could not be determined \
dynamically. Please specify it when calling the script. \
(i.e. run_iperf.sh -v 3 -H <host>)"

#IPERFCMD=`echo $* | sed -r s/-H[[:space:]]+[0-9\.]+/-c $IPERFHOST/`

test_print_trc "Starting IPERF TEST"

do_cmd "${IPERF_BIN} -c ${IPERFHOST} $*"


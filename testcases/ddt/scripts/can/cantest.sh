#! /bin/bash
###############################################################################
# Copyright (C) 2011 Texas Instruments Incorporated -
# http://www.ti.com/ # # This program is free software; you can
# redistribute it and/or # modify it under the terms of the GNU General
# Public License as # published by the Free Software Foundation version 2
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
###############################################################################
. "common.sh"  # Import do_cmd(), die() and other functions

DEFAULT_BITRATE='1000000'
DEFAULT_CAN_IFACE='mcu_mcan0'

INIT_STAT_RX=0;
INIT_STAT_TX=0;
PREFINAL_STAT_RX=0;
PREFINAL_STAT_TX=0;
FINAL_STAT_RX=0;
FINAL_STAT_TX=0;
INIT_ERRSTAT_RX=0;
INIT_ERRSTAT_TX=0;
FINAL_ERRSTAT_RX=0;
FINAL_ERRSTAT_TX=0;

############################# Functions #######################################
usage()
{
	echo "cantest.sh <interface - mcu_mcan0> <bitrate> <dbitrate> <test to run - loopback or modular> "
	exit 1
}

set_can_interface()
{
	status=$1
	do_cmd "ip link set $iface down";
	do_cmd "ip link set $iface $status";
}

send_packets()
{
	command=$1
	mode=$2
	if [[ $command == 'start' ]]; then
		do_cmd "candump -d -s 2 $iface &";
		if [[ $mode == 'fd' ]]; then do_cmd "cangen -b -L 16 $iface &";
		else do_cmd "cangen -L 16 $iface &"; fi
	else
		do_cmd "killall candump";
		do_cmd "killall cangen";
	fi
}

wait_for_stats()
{
	stat="/proc/net/can/stats"
	loop="0"

	while [ ! -e "$stat" ] && [ "$loop" -le "5" ]; do do_cmd "sleep 1"; echo "Waiting for $stat" ; loop=$((loop+1)); done;
	if [ ! -e "$stat" ]; then set_can_interface 'down'; die "Failed to find stats in $stat"; fi;

}

get_stats()
{
	stage=$1
	type=$2
	if [[ $type == 'error' ]]; then
		tx_err=$(get_can_error_stats.sh -i "$iface" -s 'tx');
		rx_err=$(get_can_error_stats.sh -i "$iface" -s 'rx');
		if [ "$stage" == 'init' ]; then
			INIT_ERRSTAT_TX=$tx_err;
			INIT_ERRSTAT_RX=$rx_err;
		else
			FINAL_ERRSTAT_TX=$tx_err;
			FINAL_ERRSTAT_RX=$rx_err;
		fi
	else
		wait_for_stats;
		txf=$(get_can_stats.sh -s 'TXF');
		rxf=$(get_can_stats.sh -s 'RXF');
		if [ "$stage" == 'init' ]; then
			INIT_STAT_TX=$txf;
			INIT_STAT_RX=$rxf;
		elif [ "$stage" == 'prefinal' ]; then
			PREFINAL_STAT_TX=$txf;
			PREFINAL_STAT_RX=$rxf;
		else
			FINAL_STAT_TX=$txf;
			FINAL_STAT_RX=$rxf;
		fi
	fi
}

compare_stats()
{
	stats=$1
	case $stats in
		error)
			echo "Dump error stats before compare: [$FINAL_ERRSTAT_TX,$INIT_ERRSTAT_TX,$FINAL_ERRSTAT_RX,$INIT_ERRSTAT_RX]"
			if [ "$FINAL_ERRSTAT_TX" == "$INIT_ERRSTAT_TX" ] && \
			[ "$FINAL_ERRSTAT_RX" == "$INIT_ERRSTAT_RX" ]; then
				echo "TX err stats | Final: $FINAL_ERRSTAT_TX == init: $INIT_ERRSTAT_TX";
				echo "RX err stats | Final: $FINAL_ERRSTAT_RX == init: $INIT_ERRSTAT_RX";
			else exit 1; fi;
		;;
		three_stage)
			echo "Dump stats before compare: [$FINAL_STAT_TX,$PREFINAL_STAT_TX,$INIT_STAT_TX,$FINAL_STAT_RX,$PREFINAL_STAT_RX,$INIT_STAT_RX]"
			if [ "$FINAL_STAT_TX" -gt "$PREFINAL_STAT_TX" ] && \
			[ "$FINAL_STAT_RX" -gt "$PREFINAL_STAT_RX" ] && \
			[ "$PREFINAL_STAT_TX" -gt "$INIT_STAT_TX" ] && \
			[ "$PREFINAL_STAT_RX" -gt "$INIT_STAT_RX" ]; then
				echo "TX stats | Final: $FINAL_STAT_TX > Prefinal: $PREFINAL_STAT_TX";
				echo "RX stats | Final: $FINAL_STAT_RX > Prefinal: $PREFINAL_STAT_RX";
				echo "TX stats | Prefinal: $PREFINAL_STAT_TX > init: $INIT_STAT_TX";
				echo "RX stats | Prefinal: $PREFINAL_STAT_RX > init: $INIT_STAT_RX";
			else exit 1; fi;
		;;
		two_stage)
			echo "Dump stats before compare: [$FINAL_STAT_TX,$INIT_STAT_TX,$FINAL_STAT_RX,$INIT_STAT_RX]"
			if [ "$FINAL_STAT_TX" -gt "$INIT_STAT_TX" ] && \
			[ "$FINAL_STAT_RX" -gt "$INIT_STAT_RX" ]; then
				echo "TX stats | Final: $FINAL_STAT_TX > init: $INIT_STAT_TX";
				echo "RX stats | Final: $FINAL_STAT_RX > init: $INIT_STAT_RX";
			else exit 1; fi;
			;;
		*)
		end 1;;
	esac
}

modular()
{
	echo "Running Can Modular Test on $iface"
	can_interface="/sys/class/net/$iface";
	if ! [ -d "$can_interface" ]; then die "Check dtb to see if CAN is included"; fi;
	can_module=$(zcat /proc/config.gz |grep CONFIG_CAN=m);
	if [ -z "$can_module" ]; then die "Check dtb to see if CAN is included"; fi;
}

suspend()
{
	bitrate=$1
	do_cmd config_can_interface.sh -i "$iface" -c 'ip_link' -b "$bitrate";
	set_can_interface 'up';
	init_state=$(cat /sys/class/net/"$iface"/operstate);
	do_cmd "rtcwake -s 5 -m mem";
	final_state=$(cat /sys/class/net/"$iface"/operstate);
	set_can_interface 'down';
	if [ "$init_state" != "$final_state" ]; then die "Suspend resume did not restore CAN state"; fi;
}

modular_suspend()
{
	bitrate=$1
	dbitrate=$2
	do_cmd config_can_interface.sh -i "$iface" -c 'ip_link' -b "$bitrate" -l;
	set_can_interface 'up';
	send_packets 'start';
	get_stats 'init';
	do_cmd "rtcwake -s 5 -m mem";
	get_stats 'prefinal';
	do_cmd "sleep 5";
	get_stats 'final';
	send_packets 'stop';
	set_can_interface 'down';
	echo "==============================================================";
	echo "Dump transmitted and received frames from: /proc/net/can/stats";
	compare_stats 'three_stage';
	echo "==============================================================";
}

loopback()
{
	bitrate=$1
	dbitrate=$2
	do_cmd config_can_interface.sh -i "$iface"  -c 'ip_link' -b "$bitrate" -d "$dbitrate" -l -f;
	set_can_interface 'up';
	send_packets 'start' 'fd';
	get_stats 'init';
	get_stats 'init' 'error';
	do_cmd "sleep 5";
	get_stats 'final';
	get_stats 'final' 'error';
	send_packets 'stop';
	set_can_interface 'down';
	echo "==============================================================";
	echo "Dump transmitted and received frames from: /proc/net/can/stats";
	compare_stats 'two_stage';
	echo "Dump Error stats from: /sys/class/net/$iface/statistics";
	compare_stats 'error';
	echo "==============================================================";
}

################################ CLI Params ####################################

while [ $# -gt 0 ]
do
	case $1 in
	-m|--modular)
		test="modular" ;;
	-s|--suspend)
		test="suspend" ;;
	-c|--modular_suspend)
		test="modular_suspend" ;;
	-l|--loopback)
		test="loopback" ;;
	-i|--interface)
		interface="$2" ; shift;;
	-b|--bitrate)
		bitrate="$2" ; shift;;
	-d|--dbitrate)
		dbitrate="$2" ; shift;;
	(--)
	  shift; break;;
	(-*)
	  echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
	(*)
	  break;;
	esac
	shift
done

interface=$(echo "$interface" | tr -d "\"\'\`");
bitrate=$(echo "$bitrate" | tr -d "\"\'\`");
dbitrate=$(echo "$dbitrate" | tr -d "\"\'\`");
iface="${iface:=$DEFAULT_CAN_IFACE}"
brate="${bitrate:=$DEFAULT_BITRATE}"
dbrate="${dbitrate:=$DEFAULT_BITRATE}"

if [ -n "$interface" ]; then iface=$interface; fi;

case $test in
  modular)
	modular
	;;
  suspend)
	suspend $brate
	;;
  modular_suspend)
	modular_suspend $brate
	;;
  loopback)
	loopback $brate $dbrate
	;;
  *)
	end 1
	;;
esac

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
TEST_ALL_INTERFACES=false
FD=false

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
	echo "Usage: cantest.sh [options]"
	echo "Options:"
	echo "  -b, --bitrate                 Bitrate in bps (default: 1000000)"
	echo "  -d, --dbitrate                Data bitrate for CAN FD in bps (default: 1000000)"
	echo "  -i, --interface               CAN interface (default: mcu_mcan0)"
	echo "  -r, --rx_iface                RX interface for latency test"
	echo "  -t, --tx_iface                TX interface for latency test"
	echo "  -f, --fd                      Enable CAN FD mode"
	echo "  -m, --modular                 Run modular test"
	echo "  -s, --suspend                 Run suspend test"
	echo "  -c, --modular_suspend         Run modular_suspend test"
	echo "  -l, --loopback                Run internal loopback test"
	echo "  -e, --latency_extlbk          Run external loopback latency test"
	echo "  -a, --all_interfaces          Test all available interfaces"
	exit 1
}

set_can_interface()
{
	can_iface="$1"
	status="$2"
	if [ "$status" == "down" ]; then
		do_cmd "ip link set $can_iface down";
	else
		do_cmd "ip link set $can_iface down";
		do_cmd "ip link set $can_iface $status";
	fi
}

send_packets()
{
	can_iface="$1"
	command="$2"
	mode="$3"
	if [[ $command == 'start' ]]; then
		do_cmd "candump -d -s 2 $can_iface &";
		if [[ $mode == 'fd' ]]; then do_cmd "cangen -b -L 16 $can_iface &";
		else do_cmd "cangen -L 16 $can_iface &"; fi
	else
		do_cmd "killall candump";
		do_cmd "killall cangen";
	fi
}

wait_for_stats()
{
	can_iface="$1"
	stat="/proc/net/can/stats"
	loop="0"

	while [ ! -e "$stat" ] && [ "$loop" -le "5" ]; do do_cmd "sleep 1"; echo "Waiting for $stat" ; loop=$((loop+1)); done;
	if [ ! -e "$stat" ]; then set_can_interface "$can_iface" 'down'; die "Failed to find stats in $stat"; fi;
}

get_stats()
{
	can_iface="$1"
	stage="$2"
	type="$3"
	if [[ $type == 'error' ]]; then
		tx_err=$(get_can_error_stats.sh -i "$can_iface" -s 'tx');
		rx_err=$(get_can_error_stats.sh -i "$can_iface" -s 'rx');
		if [ "$stage" == 'init' ]; then
			INIT_ERRSTAT_TX=$tx_err;
			INIT_ERRSTAT_RX=$rx_err;
		else
			FINAL_ERRSTAT_TX=$tx_err;
			FINAL_ERRSTAT_RX=$rx_err;
		fi
	else
		wait_for_stats "$can_iface";
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
			exit 1;;
	esac
}

suspend()
{
	can_iface="$1"
	bitrate="$2"
	do_cmd config_can_interface.sh -i "$can_iface" -c 'ip_link' -b "$bitrate";
	set_can_interface "$can_iface" 'up';
	init_state=$(cat /sys/class/net/"$can_iface"/operstate);
	do_cmd "rtcwake -s 5 -m mem";
	final_state=$(cat /sys/class/net/"$can_iface"/operstate);
	set_can_interface "$can_iface" 'down';
	if [ "$init_state" != "$final_state" ]; then die "Suspend resume did not restore CAN state"; fi;
}

modular_suspend()
{
	can_iface="$1"
	bitrate="$2"
	do_cmd config_can_interface.sh -i "$can_iface" -c 'ip_link' -b "$bitrate" -l;
	set_can_interface "$can_iface" 'up';
	send_packets "$can_iface" 'start';
	get_stats "$can_iface" 'init';
	do_cmd "rtcwake -s 5 -m mem";
	get_stats "$can_iface" 'prefinal';
	do_cmd "sleep 5";
	get_stats "$can_iface" 'final';
	send_packets "$can_iface" 'stop';
	set_can_interface "$can_iface" 'down';
	echo "==============================================================";
	echo "Dump transmitted and received frames from: /proc/net/can/stats";
	compare_stats 'three_stage';
	echo "==============================================================";
}

loopback_one()
{
	can_under_test="$1"
	bitrate="$2"
	dbitrate="$3"
	set_can_interface "$can_under_test" 'down';
	do_cmd config_can_interface.sh -i "$can_under_test"  -c 'ip_link' -b "$bitrate" -d "$dbitrate" -l -f;
	set_can_interface "$can_under_test" 'up';
	send_packets "$can_under_test" 'start' 'fd';
	get_stats "$can_under_test" 'init';
	get_stats "$can_under_test" 'init' 'error';
	do_cmd "sleep 5";
	get_stats "$can_under_test" 'final';
	get_stats "$can_under_test" 'final' 'error';
	send_packets "$can_under_test" 'stop';
	set_can_interface "$can_under_test" 'down';
	echo "==============================================================";
	echo "Dump transmitted and received frames from: /proc/net/can/stats";
	compare_stats 'two_stage';
	echo "Dump Error stats from: /sys/class/net/$can_under_test/statistics";
	compare_stats 'error';
	echo "==============================================================";
}

loopback_all()
{
	bitrate="$1"
	dbitrate="$2"
	echo "Getting CAN Interfaces for $MACHINE"
	cans=$(get_can_interfaces.sh "$MACHINE")

	if [ -z "$cans" ]; then	die "No CAN Interface found for the platform $MACHINE";	fi;

	echo "Available CANs for $MACHINE : |$cans|"
	for can in $cans
	do
		loopback_one "$can" "$bitrate" "$dbitrate"
	done
}

loopback()
{
	can_iface="$1"
	bitrate="$2"
	dbitrate="$3"
	if [[ "$TEST_ALL_INTERFACES" == "true" ]]; then
		loopback_all "$bitrate" "$dbitrate"
	else
		loopback_one "$can_iface" "$bitrate" "$dbitrate"
	fi
}

modular_one()
{
	can_under_test=$1
	echo "Running CAN Modular Test on $can_under_test"
	can_interface="/sys/class/net/$can_under_test";
	if ! [ -d "$can_interface" ]; then die "Check dtb to see if $can_under_test is included"; fi;
	can_module=$(zcat /proc/config.gz |grep CONFIG_CAN=m);
	if [ -z "$can_module" ]; then die "Check Configs to see if CAN is included"; fi;
}

modular_all()
{
	echo "Getting CAN Interfaces for $MACHINE"
	cans=$(get_can_interfaces.sh "$MACHINE")

	if [ -z "$cans" ]; then	die "No CAN Interface found for the platform $MACHINE";	fi;

	echo "Available CANs for $MACHINE : |$cans|"
	for can in $cans
	do
		modular_one "$can"
	done
}

modular()
{
	can_iface="$1"
	if [[ "$TEST_ALL_INTERFACES" == "true" ]]; then
		modular_all
	else
		modular_one "$can_iface"
	fi
}

latency_extlbk()
{
	can_rx="$1"
	can_tx="$2"
	bitrate="$3"
	dbitrate="$4"
	fd_flag="$5"
	num_frames="${6:-20}"
	received_frames=0
	total_latency_us=0
	min_latency_us=999999999
	max_latency_us=0
	candump_log="/tmp/candump_$$.log"
	cansend_log="/tmp/cansend_$$.log"
	timeout=$((num_frames / 5 + 15))

	if [ "$fd_flag" = "true" ]; then fd_flag="-f"; else fd_flag=""; fi

	trap '[ -n "$candump_pid" ] && kill $candump_pid 2>/dev/null; [ -n "$can_rx" ] && set_can_interface "$can_rx" "down"; [ -n "$can_tx" ] && set_can_interface "$can_tx" "down"; [ -f "$candump_log" ] && rm -f "$candump_log"; [ -f "$cansend_log" ] && rm -f "$cansend_log"' EXIT

	set_can_interface "$can_rx" 'down';
	do_cmd config_can_interface.sh -i "$can_rx" -c 'ip_link' -b "$bitrate" -d "$dbitrate" "$fd_flag";
	set_can_interface "$can_rx" 'up';
	set_can_interface "$can_tx" 'down';
	do_cmd config_can_interface.sh -i "$can_tx" -c 'ip_link' -b "$bitrate" -d "$dbitrate" "$fd_flag";
	set_can_interface "$can_tx" 'up';
	sleep 1

	do_cmd "timeout $timeout candump -t A $can_rx > $candump_log 2>&1 &";
	candump_pid=$!

	sleep 0.5

	echo ""
	echo "Sending $num_frames test frames..."
	for i in $(seq 1 "$num_frames"); do
		can_id=$(printf "%03X" $((0x600 + i)))
		data="0102030405060708"
		tx_time_float="${EPOCHREALTIME}"

		do_cmd "cansend $can_tx $can_id#$data"

		# Save TX time in human-readable format (microsecond precision)
		tx_sec="${tx_time_float%.*}"
		tx_us="${tx_time_float#*.}"
		tx_time=$(date -d @"$tx_sec" "+%Y-%m-%d %H:%M:%S.$tx_us")
		echo "  Frame $i: $can_id#$data - TX time: $tx_time"
		echo "$i $can_id $tx_time" >> "$cansend_log"

		sleep 0.2
	done

	sleep 1

	pkill candump
	wait $candump_pid 2>/dev/null

	echo ""
	echo "==============================================================";
	echo "Latency Measurement Results"
	echo "==============================================================";

	if [ ! -f "$candump_log" ] || [ ! -s "$candump_log" ]; then echo "FAILED: No frames captured on RX interface"; exit 1; fi;

	echo ""
	echo "Candump captured frames:"
	cat "$candump_log"

	echo ""
	echo "TX-to-RX Latencies:"

	while read -r tx_frame_num tx_can_id tx_date tx_time; do
		tx_timestamp="$tx_date $tx_time"

		rx_line=$(grep "[[:space:]]${tx_can_id}[[:space:]]" "$candump_log" | head -1)
		if [ -z "$rx_line" ]; then echo "  Frame $tx_frame_num ($tx_can_id): NOT RECEIVED"; continue; fi;
		# Extract RX timestamp (format: YYYY-MM-DD HH:MM:SS.SSSSSS)
		rx_timestamp=$(echo "$rx_line" | sed -n 's/^[[:space:]]*(\([^)]*\)).*/\1/p')
		if [ -z "$rx_timestamp" ]; then echo "  Frame $tx_frame_num ($tx_can_id): Could not parse timestamp"; continue; fi;

		# Convert timestamps to microseconds
		tx_time=$(date -d "$tx_timestamp" +%s%N 2>/dev/null | sed 's/...$//')
		rx_time=$(date -d "$rx_timestamp" +%s%N 2>/dev/null | sed 's/...$//')
		if [ -z "$tx_time" ] || [ "$tx_time" -eq 0 ]; then echo "  Frame $tx_frame_num ($tx_can_id): Could not convert TX timestamp"; continue; fi;
		if [ -z "$rx_time" ] || [ "$rx_time" -eq 0 ]; then echo "  Frame $tx_frame_num ($tx_can_id): Could not convert RX timestamp"; continue; fi;

		latency_us=$((rx_time - tx_time))
		[ $latency_us -lt 0 ] && { echo "Frame $tx_frame_num: Invalid negative latency, skipping"; continue; }
		latency_ms=$(echo "scale=3; $latency_us / 1000" | bc 2>/dev/null || echo "N/A")
		echo "  Frame $tx_frame_num ($tx_can_id): ${latency_us} us (${latency_ms} ms)"
		total_latency_us=$((total_latency_us + latency_us))
		if [ $latency_us -lt $min_latency_us ]; then min_latency_us=$latency_us; fi;
		if [ $latency_us -gt $max_latency_us ]; then max_latency_us=$latency_us; fi;
		received_frames=$((received_frames + 1))

	done < "$cansend_log"

	echo ""
	if [ "$received_frames" -eq 0 ]; then
		echo "Test FAILED: No frames received"; exit 1;
	else
		avg_latency_us=$((total_latency_us / received_frames))
		avg_latency_ms=$(echo "scale=3; $avg_latency_us / 1000" | bc 2>/dev/null || echo "N/A")
		min_latency_ms=$(echo "scale=3; $min_latency_us / 1000" | bc 2>/dev/null || echo "N/A")
		max_latency_ms=$(echo "scale=3; $max_latency_us / 1000" | bc 2>/dev/null || echo "N/A")
		echo "Test PASSED: $received_frames/$num_frames frames received"
		echo "Min latency:     $min_latency_us us (${min_latency_ms} ms)"
		echo "Max latency:     $max_latency_us us (${max_latency_ms} ms)"
		echo "Average latency: $avg_latency_us us (${avg_latency_ms} ms)"
	fi
	echo "==============================================================";
	echo ""
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
	-e|--latency_extlbk)
		test="latency_extlbk" ;;
	-a|--all_interfaces)
		TEST_ALL_INTERFACES=true ;;
	-i|--interface)
		iface="$2" ; shift;;
	-r|--rx_iface)
		rx_iface="$2" ; shift;;
	-t|--tx_iface)
		tx_iface="$2" ; shift;;
	-b|--bitrate)
		bitrate="$2" ; shift;;
	-d|--dbitrate)
		dbitrate="$2" ; shift;;
	-f|--fd)
		FD="true" ;;
	(--)
	  shift; break;;
	(-*)
	  echo "$0: Error: unrecognized option $1" 1>&2; usage;;
	(*)
	  break;;
	esac
	shift
done

iface=$(echo "$iface" | tr -d "\"\'\`");
rx_iface=$(echo "$rx_iface" | tr -d "\"\'\`");
tx_iface=$(echo "$tx_iface" | tr -d "\"\'\`");
bitrate=$(echo "$bitrate" | tr -d "\"\'\`");
dbitrate=$(echo "$dbitrate" | tr -d "\"\'\`");

iface="${iface:=$DEFAULT_CAN_IFACE}"
brate="${bitrate:=$DEFAULT_BITRATE}"
dbrate="${dbitrate:=$DEFAULT_BITRATE}"

case $test in
	modular)
		modular "$iface"
		;;
	suspend)
		suspend "$iface" "$brate"
		;;
	modular_suspend)
		modular_suspend "$iface" "$brate"
		;;
	loopback)
		loopback "$iface" "$brate" "$dbrate"
		;;
	latency_extlbk)
		if [ -z "$rx_iface" ] || [ -z "$tx_iface" ]; then echo "$0: Error: Test requires both RX & TX CAN interfaces" 1>&2; usage; fi;
		latency_extlbk "$rx_iface" "$tx_iface" "$brate" "$dbrate" "$FD"
		;;
	*)
		echo "$0: Error: Invalid test type" 1>&2; usage
		;;
esac

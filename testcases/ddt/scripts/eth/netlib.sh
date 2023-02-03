#!/bin/sh

#########################################################################################
##### HELPER FUNCTIONS ##################################################################
#########################################################################################

### Get MTU size for interface.
get_mtu () {
	mtu=$(cat /sys/class/net/$1/mtu);
	echo $mtu;
}

### Get speed of interface.
get_speed () {
	speed=$(cat /sys/class/net/$1/speed);
	echo $speed;
}

### Get MAC address of interface.
get_mac () {
	mac=$(cat /sys/class/net/$1/address);
	echo $mac;
}

### Get IPv4 address of interface.
get_ip () {
	interface=$1;
	ip=$(/sbin/ifconfig $interface | grep "inet " | awk '{print $2}')
	echo $ip;
}

### Get interface status (UP/DOWN).
get_state () {
	state=$(cat /sys/class/net/$1/operstate);
	echo $state;
}

### Get rx-checksum offload status (on/off).
get_rx_chksum () {
	interface=$1;
	chksum_status=$(ethtool -k $interface | grep "rx-checksum" | awk '{print $2}')
	echo $chksum_status;
}

### Get promiscuous mode state of interface.
get_promisc () {
	interface=$1;
	promisc=$(/sbin/ip -d link | grep $interface | grep "PROMISC" | wc -l)
	echo $promisc;
}

### Set promiscuous mode state of interface.
set_promisc () {
	interface=$1;
	mode=$2;
	if [[ $mode == 1 ]]
	then
		$(/sbin/ifconfig $interface promisc) > /dev/null 2>&1;
	else
		$(/sbin/ifconfig $interface -promisc) > /dev/null 2>&1;
	fi
}

### Get phy mode.
get_phy_mode () {
	phy_mode=$(cat /sys/class/net/$1/phydev/phy_interface);
	echo $phy_mode;
}

### Get driver name for ethernet interface.
get_if_drv () {
	driver=$(basename `readlink -f /sys/class/net/$1/device/driver`);
	echo $driver;
}

### Check if interface is MAC-Only interface
### for virtual ethernet EthFw driver.
check_mac_only () {
	interface=$1
	mac_check=$(cat /sys/class/net/$interface/device/of_node/ti,remote-name | grep "ethmac" | wc -l);
	if [[ $mac_check == 1 ]]
	then
		echo 1;
	else
		echo 0;
	fi
}

### Get eth interface list.
get_eth_list () {
	interfaces=$(ls /sys/class/net/ | grep eth)
	echo $interfaces;
}

### Does interface exist?
is_valid() {
	interface=$1;
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$iface" == "$interface" ]]
		then
			echo 1;
			return;
		fi
	done
	echo 0;
}

### Get ptp device for pps source
get_pps_ptp () {
	pps_src=$1
	ptp_dev=$(cat /sys/class/pps/$pps_src/name);
	echo $ptp_dev;
}

### Get driver for ptp device
get_ptp_drv () {
	ptp_dev=$1
	driver=$(basename `readlink -f /sys/class/ptp/$ptp_dev/device/driver`);
	echo $driver;
}

### Get tx packet count of interface
get_tx_count () {
	interface=$1
	tx_count=$(/sbin/ifconfig $interface | grep "TX packets" | awk '{print $3}')
	echo $tx_count;
}

### Get rx packet count of interface
get_rx_count () {
	interface=$1
	rx_count=$(/sbin/ifconfig $interface | grep "RX packets" | awk '{print $3}')
	echo $rx_count;
}

### Get tx coalesce parameter
get_tx_coal () {
	interface=$1
	tx_usecs=$(/usr/sbin/ethtool -c $interface | grep "tx-usecs:" | awk '{print $2}')
	echo $tx_usecs;
}

### Get rx coalesce parameter
get_rx_coal () {
	interface=$1
	rx_usecs=$(/usr/sbin/ethtool -c $interface | grep "rx-usecs:" | awk '{print $2}')
	echo $rx_usecs;
}

### Set tx coalesce parameter
set_tx_coal () {
	interface=$1
	tx_usecs=$2
	/usr/sbin/ethtool -C $interface tx-usecs $tx_usecs > /dev/null 2>&1;
}

### Set rx coalesce parameter
set_rx_coal () {
	interface=$1
	rx_usecs=$2
	/usr/sbin/ethtool -C $interface rx-usecs $rx_usecs > /dev/null 2>&1;
}

### Get DHCP Server IP
get_server_ip () {
	interface=$1
	check=$(/sbin/udhcpc -n -i $interface 2>&1 | grep "no lease" | wc -l)
	if [[ $check == 1 ]]
	then
		echo "0.0.0.0"
		return;
	fi
	server_ip=$(journalctl | grep DHCP | grep $interface | grep via | tail -1 | awk '{ print $NF }')
	echo $server_ip;
}

### Get TX pause option of interface (Same as RX pause)
get_pause () {
	interface=$1
	tx_pause=$(/usr/sbin/ethtool -a $interface | grep "TX:" | awk '{print $2}');
	echo $tx_pause;
}

### Set TX pause option of interface.
set_tx_pause () {
	interface=$1
	pause=$2
	$(/usr/sbin/ethtool -A $interface rx $pause tx $pause);
}

### Get toggled pause option.
toggle_pause () {
	pause=$1
	if [[ "on" == "$pause" ]]
	then
		echo "off";
		return;
	fi
	echo "on";
}

### Does Multicast MAC address exist for an interface?
is_valid_mcast () {
	interface=$1
	addr=$2
	check=$(/sbin/ip maddr show dev $interface | grep "$addr" | wc -l)
	if [[ $check != 1 ]]
	then
		echo 0;
		return;
	fi
	echo 1;
}

### Add Multicast MAC address to an interface.
add_mcast () {
	interface=$1
	addr=$2
	/sbin/ip maddr add $addr dev $interface
}

### Delete Multicast MAC address to an interface.
del_mcast () {
	interface=$1
	addr=$2
	/sbin/ip maddr del $addr dev $interface
}

#########################################################################################
##### INTERFACE LEVEL TESTS #############################################################
#########################################################################################

### Verify that PPS signal can be generated.
test_pps () {
	ptp_dev=$1
	pps_src=$2
	# Request pps generation
	echo 1 > /sys/class/ptp/$ptp_dev/pps_enable;
	# Sample at 1 second intervals and compare
	# timestamps and sequences.
	r1=$(cat /sys/class/pps/$pps_src/assert)
	sleep 1;
	r2=$(cat /sys/class/pps/$pps_src/assert)
	sleep 1;
	r3=$(cat /sys/class/pps/$pps_src/assert)
	seq1=$(echo $r1 | cut -d "#" -f2-);
	seq2=$(echo $r2 | cut -d "#" -f2-);
	seq3=$(echo $r3 | cut -d "#" -f2-);
	s21=$(echo "$seq2-$seq1" | bc -l);
	s32=$(echo "$seq3-$seq2" | bc -l);
	t1=$(echo $r1 | bc -l);
	t2=$(echo $r2 | bc -l);
	t3=$(echo $r3 | bc -l);
	t21=$(echo "$t2-$t1" | bc -l);
	t32=$(echo "$t3-$t2" | bc -l);
	f1=$(echo "scale=3; $t21/$s21" | bc -l);
	f2=$(echo "scale=3; $t32/$s32" | bc -l);
	if [[ $f1 != 1.000 ]]
	then
		echo 0;
		return;
	fi
	if [[ $f2 != 1.000 ]]
	then
		echo 0;
		return;
	fi
	echo 1;
}

### Verify that interface supports promiscuous mode.
test_promisc () {
	interface=$1
	init_mode=$(get_promisc $interface)
	if [[ $init_mode == 1 ]]
	then
		$(set_promisc $interface 0)
	else
		$(set_promisc $interface 1)
	fi
	sleep 5;
	curr_mode=$(get_promisc $interface)
	if [[ $init_mode == $curr_mode ]]
	then
		echo 0;
		return;
	fi
	# Restore original mode
	$(set_promisc $interface $init_mode)
	sleep 5;
	echo 1;
}

### Verify that VLAN interface can be added/deleted.
test_vlan_adddel () {
	interface=$1;
	vlanif=$(echo "$interface.100")
	/sbin/ip link add link $interface name $vlanif type vlan id 100
	check=$(is_valid $vlanif)
	if [[ $check == 0 ]]
	then
		echo 0;
		return;
	fi
	/sbin/ip link del $vlanif
	check=$(is_valid $vlanif)
	if [[ $check == 1 ]]
	then
		echo 0;
		return;
	fi
	echo 1;
}

### Verify that RX-Checksum can be enabled/disabled
### for an interface.
test_rx_chksum () {
	interface=$1;
	original_chksum_state=$(get_rx_chksum $interface);
	# Verify that RX-Checksum can be disabled.
	/usr/sbin/ethtool -K $interface rx-checksum off;
	curr_chksum_state=$(get_rx_chksum $interface);
	if [[ "$curr_chksum_state" != "off" ]]
	then
		# Restore original checksum state
		/usr/sbin/ethtool -K $interface rx-checksum $original_chksum_state;
		echo 0;
		return;
	fi
	# Verify that RX-Checksum can be enabled.
	/usr/sbin/ethtool -K $interface rx-checksum on;
	curr_chksum_state=$(get_rx_chksum $interface);
	if [[ "$curr_chksum_state" != "on" ]]
	then
		# Restore original checksum state
		/usr/sbin/ethtool -K $interface rx-checksum $original_chksum_state;
		echo 0;
		return;
	fi
	# Restore original checksum state
	/usr/sbin/ethtool -K $interface rx-checksum $original_chksum_state;
	echo 1;
}

### Verify that interface can ping.
test_ping () {
	interface=$1
	interface_state=$(get_state $interface)
	# Verify that interface is up.
	if [[ "up" == $interface_state || "unknown" == $interface_state ]]
	then
		server_ip=$(get_server_ip $interface)
		if [[ $server_ip == "0.0.0.0" ]]
		then
			echo 0;
			return;
		fi
		ping_result=$(/bin/ping -I $interface -c 5 $server_ip 2>&1 | grep "100% packet loss" | wc -l)
		if [[ $ping_result == 1 ]]
		then
			echo 0;
			return;
		fi
	else
		echo 0;
		return;
	fi
	echo 1
}

### Verify that interface supports interrupt-pacing
### by trying to configure its tx and rx coalesce
### parameters.
test_irq_pacing () {
	interface=$1
	init_tx_usecs=$(get_tx_coal $interface)
	init_rx_usecs=$(get_rx_coal $interface)
	test_tx_usecs=250
	test_rx_usecs=500
	# Attempt to set test tx and rx coalesce values
	$(set_tx_coal $interface $test_tx_usecs)
	$(set_rx_coal $interface $test_rx_usecs)
	# Verify that they have been set
	curr_tx_usecs=$(get_tx_coal $interface)
	curr_rx_usecs=$(get_rx_coal $interface)
	if [[ "$curr_tx_usecs" != $test_tx_usecs ]]
	then
		echo 0;
		return;
	fi
	if [[ "$curr_rx_usecs" != $test_rx_usecs ]]
	then
		echo 0;
		return;
	fi
	# Restore initial values
	$(set_tx_coal $interface $init_tx_usecs)
	$(set_rx_coal $interface $init_rx_usecs)
	echo 1;
}

### Verify that interface supports restarting N-way
### auto-negotiation
test_nway () {
	interface=$1
	interface_state=$(get_state $interface)
	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		# Restart auto-negotiation
		/usr/sbin/ethtool -r $interface;
		# Wait for interface to be up
		sleep 5;
		interface_state=$(get_state $interface)
		if [[ "up" != $interface_state ]]
		then
			echo 0;
			return;
		fi
	fi
	echo 1;
}

### Verify that interface supports configuring
### pause options.
test_pause () {
	interface=$1
	interface_state=$(get_state $interface)
	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		# Store initial pause configuration
		init_pause=$(get_pause $interface)
		# Toggle pause options and test
		curr_pause=$(toggle_pause $init_pause)
		$(set_tx_pause $interface $curr_pause)
		sleep 5;
		curr_pause=$(get_pause $interface)
		if [[ "$curr_pause" == "$init_pause" ]]
		then
			echo 0;
			return;
		fi
		# Restore initial pause configuration
		$(set_tx_pause $interface $init_pause)
		sleep 5;
	fi
	echo 1;
}

### Verify that interface supports X Mbps speed.
test_xmbps () {
	interface=$1
	speed=$2
	interface_state=$(get_state $interface)
	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		# Set interface speed to 10 Mbps
		/usr/sbin/ethtool -s $interface speed $speed;
		# Wait for interface to be up
		sleep 5;
		interface_state=$(get_state $interface)
		if [[ "up" != $interface_state ]]
		then
			echo 0;
			return;
		fi
	fi
	echo 1;
}

### Verify that interface supports 10 Mbps speed.
test_10mbps() {
	interface=$1
	ret=$(test_xmbps $interface 10);
	echo $ret;
}

### Verify that interface supports 100 Mbps speed.
test_100mbps() {
	interface=$1
	ret=$(test_xmbps $interface 100);
	echo $ret;
}

### Verify that interface supports 1000 Mbps speed.
test_1000mbps() {
	interface=$1
	ret=$(test_xmbps $interface 1000);
	echo $ret;
}

### Verify that IP address can be configured
### for an interface.
test_ip_config () {
	interface=$1
	interface_state=$(get_state $interface)
	test_ip_1="111.222.111.222"
	test_ip_2="222.111.222.111"

	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		original_ip=$(get_ip $interface)
		# Assign test_ip_1 and verify
		/sbin/ifconfig $interface $test_ip_1;
		curr_ip=$(get_ip $interface)
		if [[ "$curr_ip" != $test_ip_1 ]]
		then
			# Restore original IP
			/sbin/ifconfig $interface $original_ip;
			echo 0;
			return;
		fi
		# Assign test_ip_2 and verify
		/sbin/ifconfig $interface $test_ip_2;
		curr_ip=$(get_ip $interface)
		if [[ "$curr_ip" != $test_ip_2 ]]
		then
			# Restore original IP
			/sbin/ifconfig $interface $original_ip;
			echo 0;
			return;
		fi
		# Restore original IP
		/sbin/ifconfig $interface $original_ip;
	fi
	echo 1;
}

### Verify that MAC address can be configured
### for an interface.
test_mac_config () {
	interface=$1
	original_mac=$(get_mac $interface)
	# Bring interface down
	/sbin/ifconfig $interface down;
	test_mac_1="aa:bb:cc:dd:ee:ff"
	test_mac_2="ee:ff:cc:dd:aa:bb"

	# Verify that interface is down.
	interface_state=$(get_state $interface)
	if [[ "down" == $interface_state ]]
	then
		# Assign test_mac_1 and verify
		/sbin/ifconfig $interface hw ether $test_mac_1;
		curr_mac=$(get_mac $interface)
		if [[ "$curr_mac" != $test_mac_1 ]]
		then
			# Restore original MAC
			/sbin/ifconfig $interface hw ether $original_mac;
			# Bring up interface
			/sbin/ifconfig $interface up;
			sleep 5;
			echo 0;
			return;
		fi
		# Assign test_mac_2 and verify
		/sbin/ifconfig $interface hw ether $test_mac_2;
		curr_mac=$(get_mac $interface)
		if [[ "$curr_mac" != $test_mac_2 ]]
		then
			# Restore original MAC
			/sbin/ifconfig $interface hw ether $original_mac;
			# Bring up interface
			/sbin/ifconfig $interface up;
			sleep 5;
			echo 0;
			return;
		fi
		# Restore original MAC
		/sbin/ifconfig $interface hw ether $original_mac;
		# Bring up interface
		/sbin/ifconfig $interface up;
		sleep 5;
	fi
	echo 1;
}

### Verify that MTU can be configured
### for an interface.
test_mtu_config () {
	interface=$1
	original_mtu=$(get_mtu $interface)
	test_mtu_1=1000
	test_mtu_2=100

	# Assign test_mtu_1 and verify
	/sbin/ifconfig $interface mtu $test_mtu_1;
	curr_mtu=$(get_mtu $interface)
	if [[ "$curr_mtu" != $test_mtu_1 ]]
	then
		# Restore original MTU
		/sbin/ifconfig $interface mtu $original_mtu;
		echo 0;
		return;
	fi
	# Assign test_mtu_2 and verify
	/sbin/ifconfig $interface mtu $test_mtu_2;
	curr_mtu=$(get_mtu $interface)
	if [[ "$curr_mtu" != $test_mtu_2 ]]
	then
		# Restore original MTU
		/sbin/ifconfig $interface mtu $original_mtu;
		echo 0;
		return;
	fi
	# Restore original MTU
	/sbin/ifconfig $interface mtu $original_mtu;
	echo 1;
}

### Verify that Multicast MAC address can be added/deleted
### for an interface.
test_mcast_adddel () {
	interface=$1
	test_mcast_1="01:aa:bb:cc:dd:ee"
	test_mcast_2="01:ff:ee:dd:cc:bb"

	# Add first multicast address and verify
	$(add_mcast $interface $test_mcast_1)
	check=$(is_valid_mcast $interface $test_mcast_1)
	if [[ $check != 1 ]]
	then
		echo 0;
		return;
	fi
	# Delete first multicast address and verify
	$(del_mcast $interface $test_mcast_1)
	check=$(is_valid_mcast $interface $test_mcast_1)
	if [[ $check != 0 ]]
	then
		echo 0;
		return;
	fi
	# Add second multicast address and verify
	$(add_mcast $interface $test_mcast_2)
	check=$(is_valid_mcast $interface $test_mcast_2)
	if [[ $check != 1 ]]
	then
		echo 0;
		return;
	fi
	# Delete second multicast address and verify
	$(del_mcast $interface $test_mcast_2)
	check=$(is_valid_mcast $interface $test_mcast_2)
	if [[ $check != 0 ]]
	then
		echo 0;
		return;
	fi
	echo 1;
}

#########################################################################################
##### DRIVER LEVEL TESTS ################################################################
#########################################################################################

### Verify that all interfaces connected to a driver
### support configuring promiscuous mode.
test_drv_promisc () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_promisc $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that PPS signal can be generated from
### the PPS source corresponding to the driver's
### ptp device.
test_drv_pps () {
	driver=$1
	# Find pps sources. No pps sources => Fail.
	num_pps_sources=$(ls -l /dev/pps* | wc -l)
	if [[ $num_pps_sources == 0 ]]
	then
		echo 0;
		return;
	fi
	index=0
	while [ $index -ne $num_pps_sources ]
	do
		pps_src=$(echo "pps$index");
		ptp_dev=$(get_pps_ptp $pps_src);
		ptp_drv=$(get_ptp_drv $ptp_dev);
		if [[ "$driver" == "$ptp_drv" ]]
		then
			check=$(test_pps $ptp_dev $pps_src);
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
		index=$(($index+1));
	done
	echo 1;
}

### Verify that all interfaces corresponding to a driver
### support interrupt pacing.
test_drv_irq_pacing () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_irq_pacing $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### support configuring pause options.
test_drv_pause () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_pause $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support restarting N-way
### auto-negotiation.
test_drv_nway () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_nway $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 10 Mbps speed.
test_drv_10mbps () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_10mbps $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 100 Mbps speed.
test_drv_100mbps () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_100mbps $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 1000 Mbps speed.
test_drv_1000mbps () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_1000mbps $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running, can ping.
test_drv_ping () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_ping $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that VLAN interfaces can be added/deleted
### for all interfaces belonging to a driver.
test_drv_vlan_adddel () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_vlan_adddel $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that Multicast MAC addresses can be added/deleted
### for all interfaces belonging to a driver.
test_drv_mcast_adddel () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_mcast_adddel $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that RX-Checksum can be configured
### for all interfaces belonging to a driver.
test_drv_rx_chksum_config () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_rx_chksum $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that IP address can be configured
### for all interfaces belonging to a driver
### provided that they are up and running.
test_drv_ip_config () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_ip_config $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that MAC address can be configured
### for all interfaces belonging to a driver.
test_drv_mac_config () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_mac_config $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

### Verify that MTU can be configured
### for all interfaces belonging to a driver.
test_drv_mtu_config () {
	driver=$1
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_mtu_config $iface)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo 1;
}

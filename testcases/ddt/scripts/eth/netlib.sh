#!/bin/sh

#########################################################################################
##### HELPER FUNCTIONS ##################################################################
#########################################################################################

### Get MTU size for interface.
get_mtu () {
	mtu=$(cat /sys/class/net/$1/mtu);
	echo "${FUNCNAME[0]}: MTU: $mtu" >&2;
	echo $mtu;
}

### Set MTU size for interface.
set_mtu () {
	ifconfig $1 mtu $2 > /dev/null;
	echo "${FUNCNAME[0]}: $1 Setting MTU to: $2" >&2;
}

### Get speed of interface.
get_speed () {
	speed=$(cat /sys/class/net/$1/speed);
	echo "${FUNCNAME[0]}: Speed: $speed" >&2;
	echo $speed;
}

### Get MAC address of interface.
get_mac () {
	mac=$(cat /sys/class/net/$1/address);
	echo "${FUNCNAME[0]}: MAC: $mac" >&2;
	echo $mac;
}

### Get IPv4 address of interface.
get_ip () {
	interface=$1;
	ip=$(ifconfig $interface | grep "inet " | awk '{print $2}')
	echo "${FUNCNAME[0]}: IP: $ip" >&2;
	echo $ip;
}

### Get interface status (UP/DOWN).
get_state () {
	state=$(cat /sys/class/net/$1/operstate);
	echo "${FUNCNAME[0]}: Interface State: $state" >&2;
	echo $state;
}

### Get rx-checksum offload status (on/off).
get_rx_chksum () {
	interface=$1;
	chksum_status=$(ethtool -k $interface | grep "rx-checksum" | awk '{print $2}')
	echo "${FUNCNAME[0]}: Checksum status: $chksum_status" >&2;
	echo $chksum_status;
}

### Get promiscuous mode state of interface.
get_promisc () {
	interface=$1;
	promisc=$(ip -d link | grep $interface | grep "PROMISC" | wc -l)
	echo "${FUNCNAME[0]}: Promiscuous state: $promisc" >&2;
	echo $promisc;
}

### Set promiscuous mode state of interface.
set_promisc () {
	interface=$1;
	mode=$2;
	if [[ $mode == 1 ]]
	then
		echo "${FUNCNAME[0]}: Enabling promiscuous mode" >&2;
		$(ifconfig $interface promisc) > /dev/null 2>&1;
	else
		echo "${FUNCNAME[0]}: Disabling promiscuous mode" >&2;
		$(ifconfig $interface -promisc) > /dev/null 2>&1;
	fi
}

### Get phy mode.
get_phy_mode () {
	phy_mode=$(cat /sys/class/net/$1/phydev/phy_interface);
	echo "${FUNCNAME[0]}: PHY Mode: $phy_mode" >&2;
	echo $phy_mode;
}

### Get driver name for ethernet interface.
get_if_drv () {
	driver=$(basename `readlink -f /sys/class/net/$1/device/driver`);
	echo "${FUNCNAME[0]}: Ethernet Driver: $driver" >&2;
	echo $driver;
}

### Get name of tx interrupt number "index" for interface.
get_if_tx_irq () {
	interface=$1
	index=$2
	dev_name=$(ethtool -i $interface | grep "bus-info" | awk '{print $2}');
	tx_irq=$(echo "${dev_name}-tx${index}")
	echo "${FUNCNAME[0]}: TX IRQ $index: $tx_irq" >&2;
	echo $tx_irq;
}

### Check if a specified number of TX IRQs exists for the interface.
check_if_tx_irqs () {
	interface=$1
	num_tx_irqs=$2
	index=0
	while [[ $index -ne $num_tx_irqs ]]
	do
		irq_name=$(get_if_tx_irq $interface $index);
		echo "${FUNCNAME[0]}: Checking for $irq_name" >&2;
		check=$(cat /proc/interrupts | grep "$irq_name" | wc -l);
		if [[ $check != 1 ]]
		then
			echo 0;
			return;
		fi
		index=$(($index+1));
	done
	echo 1;
}

### Check if interface is MAC-Only interface
### for virtual ethernet EthFw driver.
check_mac_only () {
	interface=$1
	mac_check=$(cat /sys/class/net/$interface/device/of_node/ti,remote-name | grep "ethmac" | wc -l);
	if [[ $mac_check == 1 ]]
	then
		echo "${FUNCNAME[0]}: Interface is MAC-Only interface" >&2;
		echo 1;
	else
		echo "${FUNCNAME[0]}: Interface is NOT MAC-Only interface" >&2;
		echo 0;
	fi
}

### Get eth interface list.
get_eth_list () {
	interfaces=$(ls /sys/class/net/ | grep eth)
	echo -e "${FUNCNAME[0]}: Interface List:\n$interfaces" >&2;
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
			echo "${FUNCNAME[0]}: Interface Exists" >&2;
			echo 1;
			return;
		fi
	done
	echo "${FUNCNAME[0]}: Interface NOT Found" >&2;
	echo 0;
}

### Get ptp device for pps source
get_pps_ptp () {
	pps_src=$1
	ptp_dev=$(cat /sys/class/pps/$pps_src/name);
	echo "${FUNCNAME[0]}: For PPS Source: $pps_src, PTP Dev is: $ptp_dev" >&2;
	echo $ptp_dev;
}

### Get driver for ptp device
get_ptp_drv () {
	ptp_dev=$1
	driver=$(basename `readlink -f /sys/class/ptp/$ptp_dev/device/driver`);
	echo "${FUNCNAME[0]}: For PTP Dev: $ptp_dev, driver is: $driver" >&2;
	echo $driver;
}

### Get ptp device for a given driver
get_drv_ptp () {
	driver=$1
	# Find ptp sources. No ptp sources => Fail.
	num_ptp_sources=$(ls -l /dev/ptp* | wc -l)
	if [[ "$num_ptp_sources" == 0 ]]
	then
		echo 0;
		return;
	fi
	index=0
	while [ $index -ne $num_ptp_sources ]
	do
		ptp_dev=$(echo "ptp$index");
		ptp_drv=$(get_ptp_drv $ptp_dev);
		if [[ "$driver" == "$ptp_drv" ]]
		then
			echo $ptp_dev;
			return;
		fi
		index=$(($index+1));
	done

	echo 0;
}

### Get pps source from ptp device
get_ptp_pps () {
	ptp_dev=$1
	pps_src=$(dmesg | grep $ptp_dev | grep pps | awk '{print $4}' | cut -d ':' -f1)
	echo "${FUNCNAME[0]}: For PTP Dev: $ptp_dev, PPS source is: $pps_src" >&2;
	echo $pps_src;
}

### Run PPS for a given driver
test_run_pps () {
	driver=$1;
	echo "Enable PPS for driver: $driver" >&1;
	# Find ptp device for this driver. No ptp device => Fail.
	ptp_dev=$(get_drv_ptp $driver);
	if [[ "$ptp_dev" == 0 ]]
	then
		echo "${FUNCNAME[0]}: Failure! No ptp device found for the driver: $driver" >&2;
		echo 0;
		return;
	fi
	# Request pps generation
	echo 1 > /sys/class/ptp/$ptp_dev/pps_enable;
	echo "${FUNCNAME[0]}: PPS has been generated for $ptp_dev" >&2;
}

### Get tx packet count of interface
get_tx_count () {
	interface=$1
	tx_count=$(ifconfig $interface | grep "TX packets" | awk '{print $3}')
	echo "${FUNCNAME[0]}: For $interface: TX Packet Count is: $tx_count" >&2;
	echo $tx_count;
}

### Get rx packet count of interface
get_rx_count () {
	interface=$1
	rx_count=$(ifconfig $interface | grep "RX packets" | awk '{print $3}')
	echo "${FUNCNAME[0]}: For $interface: RX Packet Count is: $rx_count" >&2;
	echo $rx_count;
}

### Get tx coalesce parameter
get_tx_coal () {
	interface=$1
	tx_usecs=$(ethtool -c $interface | grep "tx-usecs:" | awk '{print $2}')
	echo "${FUNCNAME[0]}: For $interface: tx_usecs is: $tx_usecs" >&2;
	echo $tx_usecs;
}

### Get rx coalesce parameter
get_rx_coal () {
	interface=$1
	rx_usecs=$(ethtool -c $interface | grep "rx-usecs:" | awk '{print $2}')
	echo "${FUNCNAME[0]}: For $interface: rx_usecs is: $rx_usecs" >&2;
	echo $rx_usecs;
}

### Set tx coalesce parameter
set_tx_coal () {
	interface=$1
	tx_usecs=$2
	echo "${FUNCNAME[0]}: For $interface: setting tx_usecs to $tx_usecs" >&2;
	ethtool -C $interface tx-usecs $tx_usecs > /dev/null 2>&1;
}

### Set rx coalesce parameter
set_rx_coal () {
	interface=$1
	rx_usecs=$2
	echo "${FUNCNAME[0]}: For $interface: setting rx_usecs to $rx_usecs" >&2;
	ethtool -C $interface rx-usecs $rx_usecs > /dev/null 2>&1;
}

### Get DHCP Server IP
get_dhcp_server_ip () {
	interface=$1
	check=$(udhcpc -n -i $interface 2>&1 | grep "no lease" | wc -l)
	if [[ $check == 1 ]]
	then
		echo "${FUNCNAME[0]}: For $interface: DHCP server's IP Address NOT found!!!" >&2;
		echo "";
		return;
	fi
	dhcp_server_ip=$(journalctl | grep DHCP | grep $interface | grep via | tail -1 | awk '{ print $NF }')
	if [[ -n "$dhcp_server_ip" ]]
	then
		echo "${FUNCNAME[0]}: For $interface: DHCP server's IP Address is: $dhcp_server_ip" >&2;
	else
		echo "${FUNCNAME[0]}: For $interface: Journalctl log did not capture DHCP server's IP Address" >&2;
	fi
	echo $dhcp_server_ip;
}

### Get Broadcast IP for a given interface
get_broadcast_ip () {
	interface=$1;
	broadcast_ip=$(ifconfig $interface | grep "broadcast" | awk '{print $NF}')
	echo "${FUNCNAME[0]}: For $interface: Broadcast IP Address is: $broadcast_ip" >&2;
	echo $broadcast_ip;
}

### Get TX pause option of interface (Same as RX pause)
get_pause () {
	interface=$1
	tx_pause=$(ethtool -a $interface | grep "TX:" | awk '{print $2}');
	echo "${FUNCNAME[0]}: For $interface: tx_pause is: $tx_pause" >&2;
	echo $tx_pause;
}

### Set TX pause option of interface.
set_tx_pause () {
	interface=$1
	pause=$2
	echo "${FUNCNAME[0]}: For $interface: Setting tx_pause to: $pause" >&2;
	$(ethtool -A $interface rx $pause tx $pause);
}

### Get toggled pause option.
toggle_pause () {
	pause=$1
	if [[ "on" == "$pause" ]]
	then
		echo "${FUNCNAME[0]}: Toggled Pause to OFF" >&2;
		echo "off";
		return;
	fi
	echo "${FUNCNAME[0]}: Toggled Pause to ON" >&2;
	echo "on";
}

### Does Multicast MAC address exist for an interface?
is_valid_mcast () {
	interface=$1
	addr=$2
	check=$(ip maddr show dev $interface | grep "$addr" | wc -l)
	if [[ $check != 1 ]]
	then
		echo "${FUNCNAME[0]}: For $interface: Multicast MAC address $addr doesn't exist" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: For $interface: Multicast MAC address $addr exists" >&2;
	echo 1;
}

### Add Multicast MAC address to an interface.
add_mcast () {
	interface=$1
	addr=$2
	echo "${FUNCNAME[0]}: For $interface: Adding Multicast MAC address $addr" >&2;
	ip maddr add $addr dev $interface
}

### Delete Multicast MAC address to an interface.
del_mcast () {
	interface=$1
	addr=$2
	echo "${FUNCNAME[0]}: For $interface: Deleting Multicast MAC address $addr" >&2;
	ip maddr del $addr dev $interface
}

### Dump ALE entries in a sorted manner with pre-processing
### for a given interface. This is useful when comparing the
### ALE entries. The entries are output to the file that is
### passed as a parameter.
dump_ale_sorted () {
	interface=$1
	filename=$2
	echo "${FUNCNAME[0]}: For $interface: Dumping ALE entries to $filename" >&2;
	switch-config -I $interface -d | tail -n +3 | cut -d":" -f2- | sort > $filename;
}


### Try to get the IP Address to ping for the purpose of checking outgoing packet length
### Three ways to do that.
### 1. Try getting the IPERF server if IPERFHOST variable is exported by host.
### 2. Try getting the DHCP server if journalctl log captures IP of DHCP server.
### 3. Try broadcast IP Address.
get_destip () {
	interface=$1
	if [[ -n "$IPERFHOST" ]]
	then
		echo "${FUNCNAME[0]}: IPERF server's IP Address is: $IPERFHOST" >&2;
		dest_ip=$IPERFHOST;
	else
		### IPERF server IP is not exported by host.
		dhcp_server_ip=$(get_dhcp_server_ip $interface);
		if [[ -n "$dhcp_server_ip" ]]
		then
			echo "${FUNCNAME[0]}: DHCP server's IP Address is: $dhcp_server_ip" >&2;
			dest_ip=$dhcp_server_ip;
		else
			### Journalctl log did not capture DHCP server's IP.
			dest_ip=$(get_broadcast_ip $interface);
			echo "${FUNCNAME[0]}: Attempting broadcast ping to : $dest_ip" >&2;
		fi
	fi
	echo $dest_ip;
}

# Returns the base address for the interface
get_basename () {
	iface=$1
	base=$(ethtool -i $iface | grep "bus-info" | awk '{print $2}')
	echo "${FUNCNAME[0]}: $iface Basename: $base" >&2;
	echo $base;
}

#########################################################################################
##### INTERFACE LEVEL TESTS #############################################################
#########################################################################################

### Verify that PPS signal can be generated.
test_pps () {
	ptp_dev=$1
	pps_src=$2
	# Request pps generation
	echo "${FUNCNAME[0]}: PTP DEV: $ptp_dev PPS SOURCE: $pps_src" >&2;
	echo 1 > /sys/class/ptp/$ptp_dev/pps_enable;
	# Wait for PPS signal to be enabled.
	sleep 2;
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
		echo "${FUNCNAME[0]}: Frequency f1: $f1 is not 1" >&2;
		echo 0;
		return;
	fi
	if [[ $f2 != 1.000 ]]
	then
		echo "${FUNCNAME[0]}: Frequency f2: $f2 is not 1" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: PPS Signal Verified" >&2;
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface supports promiscuous mode.
test_promisc () {
	interface=$1
	echo "${FUNCNAME[0]}: Testing promiscuous mode for $interface" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that VLAN interface can be added/deleted.
test_vlan_adddel () {
	interface=$1;
	echo "${FUNCNAME[0]}: Testing VLAN support for $interface" >&2;
	vlanif=$(echo "$interface.100")
	echo "${FUNCNAME[0]}: Creating VLAN Interface $vlanif" >&2;
	ip link add link $interface name $vlanif type vlan id 100
	check=$(is_valid $vlanif)
	if [[ $check == 0 ]]
	then
		echo "${FUNCNAME[0]}: Failed to create $vlanif" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: Removing VLAN Interface $vlanif" >&2;
	ip link del $vlanif
	check=$(is_valid $vlanif)
	if [[ $check == 1 ]]
	then
		echo "${FUNCNAME[0]}: Failed to remove $vlanif" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that RX-Checksum can be enabled/disabled
### for an interface.
test_rx_chksum () {
	interface=$1;
	original_chksum_state=$(get_rx_chksum $interface);
	# Verify that RX-Checksum can be disabled.
	ethtool -K $interface rx-checksum off;
	curr_chksum_state=$(get_rx_chksum $interface);
	if [[ "$curr_chksum_state" != "off" ]]
	then
		# Restore original checksum state
		ethtool -K $interface rx-checksum $original_chksum_state;
		echo 0;
		return;
	fi
	# Verify that RX-Checksum can be enabled.
	ethtool -K $interface rx-checksum on;
	curr_chksum_state=$(get_rx_chksum $interface);
	if [[ "$curr_chksum_state" != "on" ]]
	then
		# Restore original checksum state
		ethtool -K $interface rx-checksum $original_chksum_state;
		echo 0;
		return;
	fi
	# Restore original checksum state
	ethtool -K $interface rx-checksum $original_chksum_state;
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface can ping.
### Three ways to verify ping:
### 1. Try pinging the IPERF server if IPERFHOST variable is exported by host.
### 2. Try pinging the DHCP server if journalctl log captures IP of DHCP server.
### 3. Try broadcast ping.
### The test involves verifying ping through any of the three ways in the order
### listed above, until one of them works.
test_ping () {
	interface=$1
	interface_state=$(get_state $interface)
	echo "${FUNCNAME[0]}: Interface: $interface is $interface_state" >&2;
	# Verify that interface is up.
	if [[ "up" == $interface_state || "unknown" == $interface_state ]]
	then
		### Try pinging the IPERF server if IP is exported by host.
		if [[ -n "$IPERFHOST" ]]
		then
			echo "${FUNCNAME[0]}: IPERF server's IP Address is: $IPERFHOST" >&2;
			dest_ip=$IPERFHOST;
		else
			### IPERF server IP is not exported by host.
			### Try pinging the DHCP server if journalctl log captures its IP.
			dhcp_server_ip=$(get_dhcp_server_ip $interface);
			if [[ -n "$dhcp_server_ip" ]]
			then
				echo "${FUNCNAME[0]}: DHCP server's IP Address is: $dhcp_server_ip" >&2;
				dest_ip=$dhcp_server_ip;
			else
				### Journalctl log did not capture DHCP server's IP.
				### Try broadcast ping as a last resort.
				dest_ip=$(get_broadcast_ip $interface);
				echo "${FUNCNAME[0]}: Attempting broadcast ping to : $dest_ip" >&2;
			fi
		fi
		ping_result=$(ping -I $interface -c 5 $dest_ip 2>&1 | grep "0% packet loss" | wc -l)
		if [[ $ping_result != 1 ]]
		then
			echo "${FUNCNAME[0]}: Ping Failed" >&2;
			echo 0;
			return;
		fi
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is down" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1
}

### Verify that interface supports interrupt-pacing
### by trying to configure its tx and rx coalesce
### parameters.
test_irq_pacing () {
	interface=$1
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	init_tx_usecs=$(get_tx_coal $interface)
	init_rx_usecs=$(get_rx_coal $interface)
	test_tx_usecs=250
	test_rx_usecs=500
	echo "${FUNCNAME[0]}: test_tx_usecs: $test_tx_usecs test_rx_usecs: $test_rx_usecs" >&2;
	# Attempt to set test tx and rx coalesce values
	$(set_tx_coal $interface $test_tx_usecs)
	$(set_rx_coal $interface $test_rx_usecs)
	# Verify that they have been set
	curr_tx_usecs=$(get_tx_coal $interface)
	curr_rx_usecs=$(get_rx_coal $interface)
	if [[ "$curr_tx_usecs" != $test_tx_usecs ]]
	then
		echo "${FUNCNAME[0]}: curr_tx_usecs: $curr_tx_usecs" >&2;
		echo "${FUNCNAME[0]}: Failed to set tx_usecs" >&2;
		echo 0;
		return;
	fi
	if [[ "$curr_rx_usecs" != $test_rx_usecs ]]
	then
		echo "${FUNCNAME[0]}: curr_rx_usecs: $curr_rx_usecs" >&2;
		echo "${FUNCNAME[0]}: Failed to set rx_usecs" >&2;
		echo 0;
		return;
	fi
	# Restore initial values
	$(set_tx_coal $interface $init_tx_usecs)
	$(set_rx_coal $interface $init_rx_usecs)
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface supports restarting N-way
### auto-negotiation
test_nway () {
	interface=$1
	interface_state=$(get_state $interface)
	echo "${FUNCNAME[0]}: Testing nway auto-negotiation for $interface" >&2;
	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		# Restart auto-negotiation
		echo "${FUNCNAME[0]}: Restarting auto-negotiation" >&2;
		ethtool -r $interface;
		# Wait for interface to be up
		sleep 5;
		interface_state=$(get_state $interface)
		if [[ "up" != $interface_state ]]
		then
			echo "${FUNCNAME[0]}: Interface failed to come up!" >&2;
			echo 0;
			return;
		fi
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is down!" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface supports configuring
### pause options.
test_pause () {
	interface=$1
	interface_state=$(get_state $interface)
	echo "${FUNCNAME[0]}: Testing pause options for $interface" >&2;
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
			echo "${FUNCNAME[0]}: Failed to toggle pause option!" >&2;
			echo 0;
			return;
		fi
		# Restore initial pause configuration
		$(set_tx_pause $interface $init_pause)
		sleep 5;
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is down!" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface supports X Mbps speed.
test_xmbps () {
	interface=$1
	speed=$2
	interface_state=$(get_state $interface)
	echo "${FUNCNAME[0]}: Testing speed $speed for interface $interface" >&2;
	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		# Set interface speed to X Mbps
		ethtool -s $interface speed $speed;
		# Wait for interface to be up
		sleep 5;
		interface_state=$(get_state $interface)
		if [[ "up" != $interface_state ]]
		then
			echo "${FUNCNAME[0]}: Interface failed to come up!" >&2;
			echo 0;
			return;
		fi
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is down!" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that interface supports 10 Mbps speed.
test_10mbps() {
	interface=$1
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	ret=$(test_xmbps $interface 10);
	echo $ret;
}

### Verify that interface supports 100 Mbps speed.
test_100mbps() {
	interface=$1
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	ret=$(test_xmbps $interface 100);
	echo $ret;
}

### Verify that interface supports 1000 Mbps speed.
test_1000mbps() {
	interface=$1
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	ret=$(test_xmbps $interface 1000);
	echo $ret;
}

### Test all speed
test_all_speed() {
	iface=$1
	result_ten=$(test_10mbps $iface);
	result_hundred=$(test_100mbps $iface);
	result_thousand=$(test_1000mbps $iface);

	if [[ "$result_ten" == 1 && "$result_hundred" == 1 && "$result_thousand" == 1 ]]
	then
		echo "${FUNCNAME[0]}: TEST PASSED" >&2;
		echo 1
	else
		echo "${FUNCNAME[0]}: TEST FAILED" >&2;
		echo 0
	fi
}


### Verify that IP address can be configured
### for an interface.
test_ip_config () {
	interface=$1
	interface_state=$(get_state $interface)
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	test_ip_1="111.222.111.222"
	test_ip_2="222.111.222.111"

	# Verify that interface is up.
	if [[ "up" == $interface_state ]]
	then
		original_ip=$(get_ip $interface)
		echo "${FUNCNAME[0]}: $interface original IP: $original_ip" >&2;
		# Assign test_ip_1 and verify
		echo "${FUNCNAME[0]}: $interface Setting IP to: $test_ip_1" >&2;
		ifconfig $interface $test_ip_1;
		curr_ip=$(get_ip $interface)
		if [[ "$curr_ip" != $test_ip_1 ]]
		then
			echo "${FUNCNAME[0]}: $interface Current IP: $curr_ip" >&2;
			# Restore original IP
			ifconfig $interface $original_ip;
			echo 0;
			return;
		fi
		# Assign test_ip_2 and verify
		echo "${FUNCNAME[0]}: $interface Setting IP to: $test_ip_2" >&2;
		ifconfig $interface $test_ip_2;
		curr_ip=$(get_ip $interface)
		if [[ "$curr_ip" != $test_ip_2 ]]
		then
			echo "${FUNCNAME[0]}: $interface Current IP: $curr_ip" >&2;
			# Restore original IP
			ifconfig $interface $original_ip;
			echo 0;
			return;
		fi
		# Restore original IP
		ifconfig $interface $original_ip;
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is down!" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that MAC address can be configured
### for an interface.
test_mac_config () {
	interface=$1
	original_mac=$(get_mac $interface)
	echo "${FUNCNAME[0]}: $interface: Original MAC: $original_mac" >&2;
	# Bring interface down
	echo "${FUNCNAME[0]}: Bringing $interface down" >&2;
	ifconfig $interface down;
	test_mac_1="aa:bb:cc:dd:ee:ff"
	test_mac_2="ee:ff:cc:dd:aa:bb"

	# Verify that interface is down.
	interface_state=$(get_state $interface)
	if [[ "down" == $interface_state ]]
	then
		# Assign test_mac_1 and verify
		echo "${FUNCNAME[0]}: $interface Setting IP to: $test_mac_1" >&2;
		ifconfig $interface hw ether $test_mac_1;
		curr_mac=$(get_mac $interface)
		if [[ "$curr_mac" != $test_mac_1 ]]
		then
			echo "${FUNCNAME[0]}: $interface Current MAC: $curr_mac" >&2;
			# Restore original MAC
			ifconfig $interface hw ether $original_mac;
			# Bring up interface
			ifconfig $interface up;
			sleep 5;
			echo 0;
			return;
		fi
		# Assign test_mac_2 and verify
		echo "${FUNCNAME[0]}: $interface Setting IP to: $test_mac_2" >&2;
		ifconfig $interface hw ether $test_mac_2;
		curr_mac=$(get_mac $interface)
		if [[ "$curr_mac" != $test_mac_2 ]]
		then
			echo "${FUNCNAME[0]}: $interface Current MAC: $curr_mac" >&2;
			# Restore original MAC
			ifconfig $interface hw ether $original_mac;
			# Bring up interface
			ifconfig $interface up;
			sleep 5;
			echo 0;
			return;
		fi
		# Restore original MAC
		ifconfig $interface hw ether $original_mac;
		# Bring up interface
		echo "${FUNCNAME[0]}: Bringing $interface up" >&2;
		ifconfig $interface up;
		sleep 5;
	else
		echo "${FUNCNAME[0]}: Skipping test as interface is up!" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that MTU can be configured
### for an interface.
test_mtu_config () {
	interface=$1
	original_mtu=$(get_mtu $interface)
	echo "${FUNCNAME[0]}: $interface: Original MTU: $original_mtu" >&2;
	test_mtu_1=1000
	test_mtu_2=100

	# Assign test_mtu_1 and verify
	echo "${FUNCNAME[0]}: $interface Setting MTU to: $test_mtu_1" >&2;
	ifconfig $interface mtu $test_mtu_1;
	curr_mtu=$(get_mtu $interface)
	if [[ "$curr_mtu" != $test_mtu_1 ]]
	then
		echo "${FUNCNAME[0]}: $interface Current MTU: $curr_mtu" >&2;
		# Restore original MTU
		ifconfig $interface mtu $original_mtu;
		echo 0;
		return;
	fi
	# Assign test_mtu_2 and verify
	echo "${FUNCNAME[0]}: $interface Setting MTU to: $test_mtu_2" >&2;
	ifconfig $interface mtu $test_mtu_2;
	curr_mtu=$(get_mtu $interface)
	if [[ "$curr_mtu" != $test_mtu_2 ]]
	then
		echo "${FUNCNAME[0]}: $interface Current MTU: $curr_mtu" >&2;
		# Restore original MTU
		ifconfig $interface mtu $original_mtu;
		echo 0;
		return;
	fi
	# Restore original MTU
	ifconfig $interface mtu $original_mtu;
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that Multicast MAC address can be added/deleted
### for an interface.
test_mcast_adddel () {
	interface=$1
	echo "${FUNCNAME[0]}: Testing for $interface" >&2;
	test_mcast_1="01:aa:bb:cc:dd:ee"
	test_mcast_2="01:ff:ee:dd:cc:bb"

	# Add first multicast address and verify
	echo "${FUNCNAME[0]}: $interface Adding Mcast address: $test_mcast_1" >&2;
	$(add_mcast $interface $test_mcast_1)
	check=$(is_valid_mcast $interface $test_mcast_1)
	if [[ $check != 1 ]]
	then
		echo "${FUNCNAME[0]}: $interface Failed to add: $test_mcast_1" >&2;
		echo 0;
		return;
	fi
	# Delete first multicast address and verify
	echo "${FUNCNAME[0]}: $interface Deleting Mcast address: $test_mcast_1" >&2;
	$(del_mcast $interface $test_mcast_1)
	check=$(is_valid_mcast $interface $test_mcast_1)
	if [[ $check != 0 ]]
	then
		echo "${FUNCNAME[0]}: $interface Failed to delete: $test_mcast_1" >&2;
		echo 0;
		return;
	fi
	# Add second multicast address and verify
	echo "${FUNCNAME[0]}: $interface Adding Mcast address: $test_mcast_2" >&2;
	$(add_mcast $interface $test_mcast_2)
	check=$(is_valid_mcast $interface $test_mcast_2)
	if [[ $check != 1 ]]
	then
		echo "${FUNCNAME[0]}: $interface Failed to add: $test_mcast_2" >&2;
		echo 0;
		return;
	fi
	# Delete second multicast address and verify
	echo "${FUNCNAME[0]}: $interface Deleting Mcast address: $test_mcast_2" >&2;
	$(del_mcast $interface $test_mcast_2)
	check=$(is_valid_mcast $interface $test_mcast_2)
	if [[ $check != 0 ]]
	then
		echo "${FUNCNAME[0]}: $interface Failed to delete: $test_mcast_2" >&2;
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

test_mtu_size () {
	iface=$1
	framesize=$2
	iterations=$3
	ethernet_hdr=14
	ip_hdr=20
	icmp_hdr=8
	required_mtu=$(($framesize-$ethernet_hdr))
	payload_size=$(($required_mtu-$icmp_hdr-$ip_hdr))
	icmp_packet_size=$(($payload_size+$icmp_hdr))
	echo "${FUNCNAME[0]}: Interface: $iface is $(cat /sys/class/net/$iface/operstate)" >&2;
	if [[ "$(cat /sys/class/net/$iface/operstate)" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		dest_ip=$(get_destip $iface)
		echo "Destination IP: $dest_ip" >&2;
		if [[ "$dest_ip" == "0" || "$dest_ip" == "" ]]
		then
			echo "Dest IP is not available" >&2;
		else
			init_mtu=$(get_mtu $iface)
			iter=0
			$(set_mtu $iface $required_mtu);
			ping -I $iface -s $payload_size $dest_ip > /dev/null &
			while [[ $iter -lt $iterations ]]
			do
				size=`tcpdump -c 1 -i $iface -Q out -e icmp and len==$framesize`
				if [[ "$size" == *"length $framesize"* && "$size" == *"length $icmp_packet_size"* ]]
				then
					if [[ "$(ps -aux | grep "ping -I $iface -s $framesize $dest_ip" | awk '{print $2}' | head -1)" != "" ]]
					then
						kill -9 $(ps -aux | grep "ping -I $iface -s $framesize $dest_ip" | awk '{print $2}' | head -1)
					fi
					set_mtu $iface $init_mtu;
					echo "${FUNCNAME[0]}: TEST PASSED" >&2;
					echo 1;
					return;
				fi
				iter=$((iter+1))
			done
			if [[ "$(ps -aux | grep "ping -I $iface -s $framesize $dest_ip" | awk '{print $2}' | head -1)" != "" ]]
			then
				kill -9 $(ps -aux | grep "ping -I $iface -s $framesize $dest_ip" | awk '{print $2}' | head -1)
			fi
			set_mtu $iface $init_mtu;
		fi
	fi
	echo 0;
}

test_pause_frame_server () {
	iface=$1
	interface_state=$(cat /sys/class/net/$iface/operstate)
	server_ip=25.24.50.1
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		$(ethtool -A $iface rx on tx on)
		$(ifconfig $iface $server_ip)
		init_rx_pause_frames=$(ethtool -S $iface | grep pause | head -1 | awk '{print $2}')
		init_tx_pause_frames=$(ethtool -S $iface | grep pause | tail -1 | awk '{print $2}')
		echo "$(iperf3 -s -B $server_ip)" >&2;
		cur_rx_pause_frames=$(ethtool -S $iface | grep pause | head -1 | awk '{print $2}')
		cur_tx_pause_frames=$(ethtool -S $iface | grep pause | tail -1 | awk '{print $2}')
		diff_rx=$cur_rx_pause_frames-$init_rx_pause_frames
		diff_tx=$cur_tx_pause_frames-$init_tx_pause_frames
		if [[ $diff_rx -gt 0 && $diff_tx -gt 0 ]]
		then
			echo "${FUNCNAME[0]}: TEST PASSED" >&2;
			echo 1;
			return;
		fi
	fi
	echo 0;
}


test_pause_frame_client () {
	iface=$1
	time_interval=$2
	server_ip=25.24.50.1
	client_ip=25.24.50.$3
	interface_state=$(cat /sys/class/net/$iface/operstate)
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		$(ethtool -A $iface rx on tx on);
		$(ifconfig $iface $client_ip);
		init_rx_pause_frames=$(ethtool -S $iface | grep pause | head -1 | awk '{print $2}')
		init_tx_pause_frames=$(ethtool -S $iface | grep pause | tail -1 | awk '{print $2}')
		echo "$(iperf3 -c $server_ip -B $client_ip -u -b0 -t $time_interval --bidir)" >&2;
		cur_rx_pause_frames=$(ethtool -S $iface | grep pause | head -1 | awk '{print $2}')
		cur_tx_pause_frames=$(ethtool -S $iface | grep pause | tail -1 | awk '{print $2}')
		diff_rx=$cur_rx_pause_frames-$init_rx_pause_frames
		diff_tx=$cur_tx_pause_frames-$init_tx_pause_frames
		if [[ $diff_rx -gt 0 && $diff_tx -gt 0 ]]
		then
			echo "${FUNCNAME[0]}: TEST PASSED" >&2;
			echo 1;
			return;
		fi
	fi
	echo 0;
}

test_interrupt_pacing_server () {
	iface=$1
	server_ip=25.24.50.1
	interface_state=$(cat /sys/class/net/$iface/operstate)
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		$(ifconfig $iface $server_ip)
		port1=8001
		port2=8002
		echo "$(iperf3 -s -p $port1 & iperf3 -s -p $port2)" >&2;
		echo 1;
	fi
}

test_interrupt_pacing_client () {
	iface=$1
	server_ip=25.24.50.1
	client_ip=25.24.50.$2
	interface_state=$(cat /sys/class/net/$iface/operstate)
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		$(ifconfig $iface $client_ip)
		port1=8001
		port2=8002
		$(ethtool -C $iface tx-usecs 0 rx-usecs 0)
		iperf3 -c $server_ip -p $port1 -u -b0 > /dev/null &
		val1=$(mpstat -A -P ALL 1 10 | grep "%idle" -A 1 | grep -v "%idle" | grep -v '^\d*$' | awk '{print $11}')
		val1="${val1//$'\n'/ }"
		val1="${val1//  / }"
		IFS=' ' read -r -a array <<< "$val1"
		res1=101
		for element in "${array[@]}"
		do
			if [[ "$(echo "$element < $res1" | bc)" -eq 1 ]]
			then
				res1=$element
			fi
		done
		echo "CPU idle % without interrupt pacing $res1" >&2;
		sleep 2
		$(ethtool -C $iface tx-usecs 250 rx-usecs 250)
		iperf3 -c $server_ip -p $port2 -u -b0 > /dev/null &
		val2=$(mpstat -A -P ALL 1 10 | grep "%idle" -A 1 | grep -v "%idle" | grep -v '^\d*$' | awk '{print $11}')
		val2="${val2//$'\n'/ }"
		val2="${val2//  / }"
		IFS=' ' read -r -a array <<< "$val2"
		res2=101
		for element in "${array[@]}"
		do
			if [[ "$(echo "$element < $res2" | bc)" -eq 1 ]]
			then
				res2=$element
			fi
		done
		echo "CPU idle % with interrupt pacing $res2" >&2;
		$(ethtool -C $iface tx-usecs 0 rx-usecs 0)
		if [[ $res1 < $res2 ]]
		then
			echo "${FUNCNAME[0]}: TEST PASSED" >&2;
			echo 1;
			return;
		fi
	fi
	echo 0;
}

test_dma_rate_limit_server () {
	iface=$1
	server_ip=25.24.50.1
	interface_state=$(cat /sys/class/net/$iface/operstate)
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		echo "$(iperf3 -s)" >&2;
	fi
}



test_dma_rate_limit_client () {
	iface=$1
	server_ip=25.24.50.1
	client_ip=25.24.50.3
	interface_state=$(cat /sys/class/net/$iface/operstate)
	echo "${FUNCNAME[0]}: Interface: $iface is $interface_state" >&2;
	if [[ "$interface_state" == "down" ]]
	then
		echo "${FUNCNAME[0]}: Failed as Interface is down" >&2;
	else
		echo 0 > /sys/class/net/$iface/queues/tx-0/tx_maxrate
		init_bandwidth=$(iperf3 -c $server_ip -b0 -t10 --forceflush | awk '/[0-9]]/{sub(/.*]/,"");print $5}' | tail -1)
		echo "Bandwidth befor DMA Rate Limiting --> $init_bandwidth" >&2;
		echo 200 > /sys/class/net/eth0/queues/tx-0/tx_maxrate
		curr_bandwidth=$(iperf3 -c $server_ip -b0 -t10 --forceflush | awk '/[0-9]]/{sub(/.*]/,"");print $5}' | tail -1)
		echo "Bandwidth after DMA Rate Limiting to 200 Mbits --> $curr_bandwidth" >&2;
		if [[ $curr_bandwidth -lt 200 ]]
		then
			echo 0 > /sys/class/net/$iface/queues/tx-0/tx_maxrate
			echo "${FUNCNAME[0]}: TEST PASSED" >&2;
			echo 1;
			return;
		fi
		echo 0 > /sys/class/net/$iface/queues/tx-0/tx_maxrate
	fi
	echo 0;
}

# Enable Hardware Switch mode for the interfaces provided
test_switch_mode () {
	base=$1
	iface1=$2
	iface2=$3
	devlink dev param set platform/$base name switch_mode value true cmode runtime
	ip link add name br0 type bridge
	ip link set dev br0 type bridge ageing_time 1000
	ip link set dev $iface1 up
	ip link set dev $iface2 up
	sleep 10
	ip link set dev $iface1 master br0
	ip link set dev $iface2 master br0
	ip link set dev br0 up
	ip link set dev br0 type bridge vlan_filtering 1
	bridge vlan add dev br0 vid 1 self
	bridge vlan add dev br0 vid 1 pvid untagged self
	bridge vlan add dev $iface1 vid 100 master
	bridge vlan add dev $iface2 vid 100 master
}

#########################################################################################
##### DRIVER LEVEL TESTS ################################################################
#########################################################################################

### Verify that all interfaces connected to a driver
### support configuring promiscuous mode.
test_drv_promisc () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that PPS signal can be generated from
### the PPS source corresponding to the driver's
### ptp device.
test_drv_pps () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	# Find ptp device for this driver. No ptp device => Fail.
	ptp_dev=$(get_drv_ptp $driver);
	if [[ "$ptp_dev" == 0 ]]
	then
		echo "${FUNCNAME[0]}: Failure! No ptp device found for the driver: $driver" >&2;
		echo 0;
		return;
	fi

	# Find pps source for the ptp device. No pps source => Fail.
	pps_src=$(get_ptp_pps $ptp_dev);
	if [[ "$pps_src" == 0 ]]
	then
		echo "${FUNCNAME[0]}: Failure! No pps source found for the ptp device: $ptp_dev" >&2;
		echo 0;
		return;
	fi

	# Test PPS with given pps_src and ptp_dev
	check=$(test_pps $ptp_dev $pps_src);
	if [[ "$check" == 0 ]]
	then
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces corresponding to a driver
### support interrupt pacing.
test_drv_irq_pacing () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### support configuring pause options.
test_drv_pause () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support restarting N-way
### auto-negotiation.
test_drv_nway () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 10 Mbps speed.
test_drv_10mbps () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 100 Mbps speed.
test_drv_100mbps () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running support 1000 Mbps speed.
test_drv_1000mbps () {
	driver=$1
	interfaces=$(get_eth_list)
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running can support 10/100/1000 Mbps
test_drv_all_speed () {
        driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
        interfaces=$(get_eth_list)
        for iface in $interfaces
        do
                if [[ "$driver" == "$(get_if_drv $iface)" ]]
                then
                        check=$(test_all_speed $iface)
                        if [[ $check == 0 ]]
                        then
                                echo 0;
                                return;
                        fi
                fi
        done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
        echo 1;
}

### Verify that all interfaces connected to a driver
### that are up and running, can ping.
test_drv_ping () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that VLAN interfaces can be added/deleted
### for all interfaces belonging to a driver.
test_drv_vlan_adddel () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that Multicast MAC addresses can be added/deleted
### for all interfaces belonging to a driver.
test_drv_mcast_adddel () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that RX-Checksum can be configured
### for all interfaces belonging to a driver.
test_drv_rx_chksum_config () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that IP address can be configured
### for all interfaces belonging to a driver
### provided that they are up and running.
test_drv_ip_config () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that MAC address can be configured
### for all interfaces belonging to a driver.
test_drv_mac_config () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that MTU can be configured
### for all interfaces belonging to a driver.
test_drv_mtu_config () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
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
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### Verify that all interfaces in specified mode
### for the given driver can ping successfully.
test_drv_phy_mode_ping () {
	driver=$1
	phy_mode=$2
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	interfaces=$(get_eth_list)
	count=0
	### Bring up all interfaces.
	for iface in $interfaces
	do
		ifconfig $iface up;
	done
	sleep 10;

	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			if_mode=$(get_phy_mode $iface)
			if [[ "$if_mode" == "$phy_mode" ]]
			then
				echo "${FUNCNAME[0]}: $driver: Found $phy_mode interface: $iface" >&2;
				# Test that the interface can ping.
				check=$(test_ping $iface)
				if [[ $check == 0 ]]
				then
					echo 0;
					return;
				else
					count=$(($count+1));
				fi
			fi
		fi
	done
	if [[ $count == 0 ]]
	then
		echo 0;
		return;
	fi
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

### For all interfaces corresponding to the driver, verify that
### num_tx_irqs number of tx interrupts can be enabled.
test_drv_multi_dma_tx_irqs () {
	driver=$1
	num_tx_irqs=$2
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	interfaces=$(get_eth_list)

	### First bring down all interfaces corresponding to the driver.
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			ifconfig $iface down;
		fi
	done
	sleep 10;

	### Next, enable num_tx_irqs number of channels
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			ethtool -L $iface tx $num_tx_irqs;
		fi
	done

	### Bring up all interfaces corresponding to the driver.
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			ifconfig $iface up;
		fi
	done
	sleep 10;

	### Verify that $num_tx_irqs number of TX interrupts
	### are present for each of the interfaces in the
	### output of /proc/interrupts.

	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			echo "${FUNCNAME[0]}: Checking $num_tx_irqs TX IRQs for $iface" >&2;
			check=$(check_if_tx_irqs $iface $num_tx_irqs);
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}


### For all ethernet interfaces, verifies the
### MTU size to be 1518 for all outgoing packets.
test_drv_mtu_size(){
	driver=$1
	parameters=${@:2}
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	interfaces=$(get_eth_list)
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_mtu_size $iface $parameters)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
	done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}


# For all interfaces corresponding to drivers, verifies
# whether it can send/receive the pause frame or not.
test_drv_pause_frame(){
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver " >&2;
	interfaces=$(get_eth_list)
	iter=3
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=0
			time_interval=$2
			check=$(test_pause_frame_client $iface $time_interval $iter);
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
		iter=$(($iter+1));
	done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

# For all interfaces corresponding to drivers, verifies
# whether cpu performance increases or not with changing the
# traffic service time from 0 to 250.
test_drv_interrupt_pacing(){
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver " >&2;
	interfaces=$(get_eth_list)
	iter=3
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=0
			check=$(test_interrupt_pacing_client $iface $iter);
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
		iter=$(($iter+1));
	done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

# For all interfaces corresponding to drivers, verifies
# whether it can limit the bandwidth to 200 Mbps or not.
test_drv_dma_rate_limit(){
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	interfaces=$(get_eth_list)
	iter=3
	for iface in $interfaces
	do
		if [[ "$driver" == "$(get_if_drv $iface)" ]]
		then
			check=$(test_dma_rate_limit_client $iface $iter)
			if [[ $check == 0 ]]
			then
				echo 0;
				return;
			fi
		fi
		iter=$(($iter+1));
	done
	echo "${FUNCNAME[0]}: TEST PASSED" >&2;
	echo 1;
}

# For the interfaces corresponding to drivers and base address,
# Enables the switch mode
test_drv_switch_mode () {
	driver=$1
	echo "${FUNCNAME[0]}: Testing for driver: $driver" >&2;
	interfaces=$(get_eth_list)
	iter=0
	base=$2
	declare -A iface_arr
	for iface in $interfaces
	do
		interface_state=$(cat /sys/class/net/$iface/operstate)
		basename=$(get_basename $iface)
		if [[ "$driver" == "$(get_if_drv $iface)" && "$interface_state" == "up" && "$basename" == "$base" ]]
		then
			iface_arr[$iter]=$iface
			iter=$(($iter+1))
			if [[ $iter -gt 1 ]]
			then
				echo "Iter value $iter" >&2;
				break
			fi
		fi
	done
	if [[ $iter -lt 2 ]]
	then
		echo "Failed: Not enough interfaces are up" >&2;
		echo 0;
		return;
	fi
	$(test_switch_mode $base ${iface_arr[0]} ${iface_arr[1]})
	echo 1;
}


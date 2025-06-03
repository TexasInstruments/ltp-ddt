# Library of functions for PCIe functionality testing.

source "common.sh"

get_rc_id_by_domain()
{
  pci_domain=$1
  rc_id=`lspci -D -s "$pci_domain:*:*.*" | grep -E "^000[0-9]+:00:" | cut -d" " -f1`
  if [[ -z $rc_id ]]; then
    die "Could not get RC ID"
  fi
  echo -e "${FUNCNAME[0]}: RC ID: $rc_id\n" >&2
  echo "$rc_id"
}

get_ep_id_by_domain()
{
  pci_domain=$1
  ep_id=`lspci -D -s "$pci_domain:*:*.*" | grep -E "^000[0-9]+:01:" | cut -d" " -f1`
  if [[ -z $ep_id ]]; then
    die "Could not get EP ID"
  fi
  echo -e "${FUNCNAME[0]}: EP ID: $ep_id\n" >&2
  echo "$ep_id"
}

get_rc_node_base()
{
  rc_domain_bus=$1
  rc_base=$(basename `readlink -f /sys/class/pci_bus/$rc_domain_bus/of_node` | cut -d '@' -f2)
  echo -e "${FUNCNAME[0]}: $rc_domain_bus at Base Address: $rc_base\n" >&2
  echo "$rc_base"
}

get_pcie_speed()
{
  pci_id=$1
  item2check=$2 # 'lnkcap:' or 'lnksta:'

  lnk_speed=`lspci -Dvv |grep ${pci_id} -A60 |grep -i "${item2check}"|head -1 |grep -Eoi "Speed [0-9\.]+GT/s" |cut -d' ' -f2 |cut -d'G' -f1 `
  if [[ -z $lnk_speed ]]; then
    die "Could not get pcie speed capability or status"
  fi
  echo -e "${FUNCNAME[0]}: $pci_id at Link Speed: $lnk_speed GT/s\n" >&2
  echo $lnk_speed
}

get_pcie_width()
{
  pci_id=$1
  item2check=$2 # 'lnkcap:' or 'lnksta:'

  lnk_width=`lspci -Dvv |grep $1 -A60 |grep -i "${item2check}" |head -1 |grep -Eoi "Width x[0-9]+" |grep -Eo "[0-9]+" `
  if [[ -z $lnk_width ]]; then
    die "Could not get pcie width capability or status"
  fi
  echo -e "${FUNCNAME[0]}: $pci_id at Link Width: x$lnk_width\n" >&2
  echo $lnk_width
}

get_pcie_vendor_devices()
{
  vendor_id=$1
  pci_list=`lspci -D -d "$vendor_id:" | cut -d" " -f1`
  if [[ -z $pci_list ]]; then
    die "Could not get pcie devices with vendor ID $vendor_id"
  fi
  echo -e "${FUNCNAME[0]}: PCIe Devices:\n$pci_list\n" >&2
  echo $pci_list
}

get_pcie_device_domain()
{
  pci_dev=$1
  pci_domain=`echo $pci_dev | cut -d":" -f1`
  echo -e "${FUNCNAME[0]}: PCIe Device: $pci_dev is in Domain: $pci_domain\n" >&2
  echo $pci_domain
}

get_pcie_device_bus()
{
  pci_dev=$1
  pci_bus=`echo $pci_dev | cut -d":" -f2`
  echo -e "${FUNCNAME[0]}: PCIe Device: $pci_dev is on Bus: $pci_bus\n" >&2
  echo $pci_bus
}

is_ep_present()
{
  pci_domain=$1
  num_devices=`lspci -D -s "$pci_domain:*:*.*" | wc -l`
  if [[ $num_devices -gt 1 ]]
  then
    echo -e "${FUNCNAME[0]}: Domain: $pci_domain has an Endpoint\n" >&2
    echo 1
  else
    echo -e "${FUNCNAME[0]}: Domain: $pci_domain doesn't have an Endpoint\n" >&2
    echo 0
  fi
}

get_range_start()
{
  reg_name=$1
  start_addr=$(cat /proc/iomem | grep "${reg_name}" | cut -d "-" -f1)
  start_addr=$(echo "$start_addr" | tr '[a-f]' '[A-F]')
  echo -e "${FUNCNAME[0]}: Start address of $reg_name is $start_addr\n" >&2
  echo "$start_addr"
}

get_range_end()
{
  reg_name=$1
  end_addr=$(cat /proc/iomem | grep "${reg_name}" | cut -d ":" -f1 | sed 's/ *$//' | cut -d "-" -f2)
  end_addr=$(echo "$end_addr" | tr '[a-f]' '[A-F]')
  echo -e "${FUNCNAME[0]}: End address of $reg_name is $end_addr\n" >&2
  echo "$end_addr"
}

get_num_bits_from_hex()
{
  addr_hex=$1
  addr_hex=$(echo "$addr_hex" | tr '[a-f]' '[A-F]')
  addr_bin=$(echo "ibase=16 ; obase=2 ; $addr_hex" | bc)
  echo -e "${FUNCNAME[0]}: Hex: $addr_hex is Bin: $addr_bin\n" >&2
  num_bits=$(($(echo $addr_bin | wc -m) - 1))
  echo -e "${FUNCNAME[0]}: Hex: $addr_hex has $num_bits bits\n" >&2
  echo "$num_bits"
}

### Test Cases ###
test_rc_gen()
{
  vendor_id=$1
  # RC Gen in terms of GT/s
  rc_gts=$2
  # Get all devices matching the vendor-id
  pci_list=`get_pcie_vendor_devices $vendor_id`
  for pci_dev in $pci_list
  do
    pci_domain=`get_pcie_device_domain $pci_dev`
    ep_exists=`is_ep_present $pci_domain`
    if [[ "$ep_exists" == "1" ]]
    then
      ep_id=`get_ep_id_by_domain $pci_domain`
      rc_id=`get_rc_id_by_domain $pci_domain`
      ep_gen=`get_pcie_speed $ep_id "lnksta:"`
      echo -e "${FUNCNAME[0]}: RC: $rc_id and EP: $ep_id at $ep_gen GT/s\n" >&2
      if [[ $ep_gen == $rc_gts ]]
      then
        echo 1
        die
      fi
    fi
  done
  echo -e "${FUNCNAME[0]}: Failed to find RC and EP at $rc_gts GT/s\n" >&2
  echo 0
}

test_rc_width()
{
  vendor_id=$1
  link_width=$2
  # Get all devices matching the vendor-id
  pci_list=`get_pcie_vendor_devices $vendor_id`
  for pci_dev in $pci_list
  do
    pci_domain=`get_pcie_device_domain $pci_dev`
    ep_exists=`is_ep_present $pci_domain`
    if [[ "$ep_exists" == "1" ]]
    then
      ep_id=`get_ep_id_by_domain $pci_domain`
      rc_id=`get_rc_id_by_domain $pci_domain`
      ep_width=`get_pcie_width $ep_id "lnksta:"`
      echo -e "${FUNCNAME[0]}: RC: $rc_id and EP: $ep_id at x$ep_width\n" >&2
      if [[ $ep_width -ge $link_width ]]
      then
        echo 1
        die
      fi
    fi
  done
  echo -e "${FUNCNAME[0]}: Failed to find RC and EP at x$link_width\n" >&2
  echo 0
}

test_rc_64_bit()
{
  vendor_id=$1
  # Get all devices matching the vendor-id
  pci_list=`get_pcie_vendor_devices $vendor_id`
  echo -e "$(cat /proc/iomem)" >&2
  found_ep=0
  for pci_dev in $pci_list
  do
    pci_domain=`get_pcie_device_domain $pci_dev`
    ep_exists=`is_ep_present $pci_domain`
    if [[ "$ep_exists" == "1" ]]
    then
      found_ep=1
      rc_id=`get_rc_id_by_domain $pci_domain`
      rc_domain=`get_pcie_device_domain $rc_id`
      rc_bus=`get_pcie_device_bus $rc_id`
      rc_domain_bus=$(echo "$rc_domain:$rc_bus")
      rc_base=`get_rc_node_base $rc_domain_bus`
      cfg_reg_name="$(echo "${rc_base}.pcie cfg")"
      echo -e "${FUNCNAME[0]}: Config Space Reg: $cfg_reg_name\n" >&2
      cfg_low=`get_range_start "$cfg_reg_name"`
      cfg_high=`get_range_end "$cfg_reg_name"`
      echo -e "${FUNCNAME[0]}: Config Space from: $cfg_low to $cfg_high\n" >&2
      cfg_low_bits=`get_num_bits_from_hex "$cfg_low"`
      cfg_high_bits=`get_num_bits_from_hex "$cfg_high"`
      if [[ $cfg_low_bits -le "32" ]]
      then
        echo -e "${FUNCNAME[0]}: Config Space starts in 32-bit Address Space\n" >&2
        echo 0;
	return;
      fi
      if [[ $cfg_high_bits -le "32" ]]
      then
        echo -e "${FUNCNAME[0]}: Config Space ends in 32-bit Address Space\n" >&2
        echo 0;
	return;
      fi
      mem_reg_name=$(echo "nvme")
      echo -e "${FUNCNAME[0]}: Memory Space Reg: $mem_reg_name\n" >&2
      mem_low=`get_range_start "$mem_reg_name"`
      mem_high=`get_range_end "$mem_reg_name"`
      echo -e "${FUNCNAME[0]}: Memory Space from: $mem_low to $mem_high\n" >&2
      mem_low_bits=`get_num_bits_from_hex "$mem_low"`
      mem_high_bits=`get_num_bits_from_hex "$mem_high"`
      if [[ $mem_low_bits -le "32" ]]
      then
        echo -e "${FUNCNAME[0]}: Memory Space starts in 32-bit Address Space\n" >&2
        echo 0;
	return;
      fi
      if [[ $mem_high_bits -le "32" ]]
      then
        echo -e "${FUNCNAME[0]}: Memory Space ends in 32-bit Address Space\n" >&2
        echo 0;
	return;
      fi
    fi
  done
  if [[ $found_ep == 0 ]]
  then
	  echo 0;
	  return;
  fi
  echo 1;
}

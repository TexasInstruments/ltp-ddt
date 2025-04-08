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

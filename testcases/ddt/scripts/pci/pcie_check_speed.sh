#! /bin/sh 
#
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
#

# Check PCIe running speed by LnkSta

source "common.sh"

lanes_supported=$1    # number of lanes should be supported by host 

get_rc_id()
{
  rc_id=`lspci -Dn |grep -E "^000[0-9]+:00:" |cut -d" " -f3 |head -1`
  if [[ -z $rc_id ]]; then
    die "Could not get RC ID"
  fi
  echo "$rc_id"
}

get_ep_id()
{
  ep_id=`lspci -Dn |grep -E "^000[0-9]+:01:" |cut -d" " -f3 |head -1`
  if [[ -z $ep_id ]]; then
    die "Could not get EP ID"
  fi
  echo "$ep_id"
}

get_pcie_speed()
{
  pci_id=$1
  item2check=$2 # 'lnkcap:' or 'lnksta:'

  #lnk_speed=`lspci -d "$pci_id" -vv |grep -i "$item2check"|head -1 |grep -Eoi "Speed [0-9\.]+GT/s" |cut -d' ' -f2 |cut -d'G' -f1 `
  lnk_speed=`lspci -Dvv |grep ${pci_id} -A60 |grep -i "${item2check}"|head -1 |grep -Eoi "Speed [0-9\.]+GT/s" |cut -d' ' -f2 |cut -d'G' -f1 `
  if [[ -z $lnk_speed ]]; then
    die "Could not get pcie speed capability or status"
  fi
  echo $lnk_speed
}

get_pcie_width()
{
  pci_id=$1
  item2check=$2 # 'lnkcap:' or 'lnksta:'

  #lnk_width=`lspci -d "$pci_id" -vv |grep -i "$item2check" |head -1 |grep -Eoi "Width x[0-9]+" |grep -Eo "[0-9]+" `
  lnk_width=`lspci -Dvv |grep $1 -A60 |grep -i "${item2check}" |head -1 |grep -Eoi "Width x[0-9]+" |grep -Eo "[0-9]+" `
  if [[ -z $lnk_width ]]; then
    die "Could not get pcie width capability or status"
  fi
  echo $lnk_width
}


is_lnksta_expected()
{
  rc_cap=$1
  ep_cap=$2
  lnksta=$3
  item=$4   # speed or width
  max_width=$5

  unit=''
  if [[ $item = 'speed' ]]; then
    unit="GT/S"
  elif [[ $item = 'width' ]]; then
    unit=""
  else
    die "Wrong item passed to is_lnksta_expected function"
  fi

  if [[ $(echo "$rc_cap < $ep_cap" |bc -l) -ne 0 ]]; then
    expected=$rc_cap
  else
    expected=$ep_cap
  fi
  # Lower the expected width based on max_width.
  if [[ $item = 'width' ]]; then
    if [[ $(echo "$expected > $max_width" |bc -l) -ne 0 ]]; then
      expected=$max_width
    fi  
  fi

  if [[ -z $expected ]]; then
    die "Could not find the expected lnksta"
  fi
  echo "expected lnksta:$expected"

  if [[ $(echo "$lnksta == $expected" |bc -l) -eq 1 ]]; then
    echo "The PCIe LnkSta is at expected ${item}: ${expected}$unit "
  elif [[ $(echo "$lnksta > $expected" |bc -l) -eq 1 ]]; then
    die "The PCIe LnkSta $item is greater than the $item capability. Maybe the reporting is wrong!"
  else
    die "The PCIe LnkSta ${item} is lower than the expected $item:${expected}$unit " 
  fi
}

get_dut_max_width()
{
  case $MACHINE in
    am654x-idk | am574x-idk | j721e-idk-gw | j721e-evm | j7200-evm | j7200-idk-gw | j721e-sk | j721s2-evm | am68_sk-fs | j784s4-evm)
      rtn=4;;
    *)
      rtn=1;;
  esac
  echo $rtn 
}


#########################################################################
do_cmd 'lspci -nn' 
lspci -nn |grep '01:00' || die "EP is not showing in RC"

echo "=============Output of lspci -Dvv=============="
do_cmd 'lspci -Dvv'
echo "=============================================="

#rc_id=`get_rc_id` || die "error getting rc_id: $rc_id"
#ep_id=`get_ep_id` || die "error getting ep_id: $ep_id"

# loop through all domains (instances)
max_d=3 # The max pci instances we have is 3 for now
for (( i=1; i<=$max_d; i++ ))
do
  echo "Domain: $i"
  case $i in
    1) domain_num='0000';;
    2) domain_num='0001';;
    3) domain_num='0002';;
  esac
  lspci -Dn |grep "${domain_num}:" || continue
 
  rc_bus='00'
  rc_id="${domain_num}:${rc_bus}"

  lspci -Dn |grep $rc_id || continue
  rc_speed_cap=`get_pcie_speed "$rc_id" "lnkcap:" ` || die "error when getting speed cap for RC:${rc_speed_cap}"
  rc_width_cap=`get_pcie_width "$rc_id" "lnkcap:" ` || die "error when getting width cap for RC:${rc_width_cap}"

  ep_bus='01'
  ep_id="${domain_num}:${ep_bus}"
  lspci -Dn |grep $ep_id || continue
  ep_speed_cap=`get_pcie_speed "$ep_id" "lnkcap:" ` || die "error when getting speed cap for EP:${ep_speed_cap}"
  ep_width_cap=`get_pcie_width "$ep_id" "lnkcap:" ` || die "error when getting width cap for EP:${ep_width_cap}"

  rc_speed_sta=`get_pcie_speed "$rc_id" "lnksta:" ` || die "error when getting speed sta for RC:${rc_speed_sta}"
  rc_width_sta=`get_pcie_width "$rc_id" "lnksta:" ` || die "error when getting width sta for RC:${rc_width_sta}"
  ep_speed_sta=`get_pcie_speed "$ep_id" "lnksta:" ` || die "error when getting speed sta for EP:${ep_speed_sta}"
  ep_width_sta=`get_pcie_width "$ep_id" "lnksta:" ` || die "error when getting width sta for EP:${ep_width_sta}"

  echo "::::::::RC and EP Capbility::::::::"
  echo "::::::::RC Speed ${rc_speed_cap}GT/s::::::::"
  echo "::::::::RC Width x${rc_width_cap}::::::::"
  echo "::::::::EP Speed ${ep_speed_cap}GT/s::::::::"
  echo "::::::::EP Width x${ep_width_cap}::::::::"
  echo "::::::::::::::::::::::::::::::::::"

  echo "::::::::RC and EP Link Status::::::::"
  echo "::::::::RC Speed ${rc_speed_sta}GT/s::::::::"
  echo "::::::::RC Width x${rc_width_sta}::::::::"
  echo "::::::::EP Speed ${ep_speed_sta}GT/s::::::::"
  echo "::::::::EP Width x${ep_width_sta}::::::::"
  echo "::::::::::::::::::::::::::::::::::"

  echo "=============================================="

  # check if the speed and width is at expected through LnkSta 
  is_lnksta_expected $rc_speed_cap $ep_speed_cap $rc_speed_sta 'speed' || die "PCIe link speed is not at expected speed!"

  # Since dut has limitation of width, so pass dut max width here to compare
  dut_max_width=`get_dut_max_width`
  is_lnksta_expected $rc_width_cap $ep_width_cap $rc_width_sta 'width' $dut_max_width || die "PCIe link width is not at expected width!"

  # if test case pass lanes_supported, check if its cap showed in lspci matches this to check if the support is in
  if [[ -n $lanes_supported ]]; then 
    # check if rc width cap matches the supported_lane
    if [[ $rc_width_cap -lt $lanes_supported ]]; then
      die "RC should support $lanes_supported lanes; but lspci shows it only support $rc_width_cap "
    fi
  fi
  #i=$(( $i + 1 ))

done # for loop max_d
# end of script

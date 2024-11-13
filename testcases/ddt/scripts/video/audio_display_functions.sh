#! /bin/bash
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

# search for USB audio devices

source "common.sh"
source "st_log.sh"
source "functions.sh"

#Function to obtain the hw id of the hdmi audio device 
get_hdmi_audio_devnode()
{
  case $MACHINE in
    beaglebone)
      get_audio_devnodes.sh -d hifi
    ;;
    k2g*)
      get_audio_devnodes.sh -d i2s-hifi
    ;;
    *)
      get_audio_devnodes.sh -d hdmi
    ;;
  esac
}

#Function to obtain the driver hint (if any) needed so that modetest
#knows which driver to use
#Output:
#the -M <driver> hint it needed, otherwise empty string
get_modetest_hint()
{
  case $MACHINE in
    am6*|k2g*|j7*)
      echo "-M tidss"
    ;;
  esac
}

#Function to obtain the connector ids and modes supported by a connector.
#This function will only return information of connectors with connected
#status
#Inputs:
#  $1: the connector type hdmi, unknown
#  $2: (Optional) a mode regex to look for, i.e, 1920x1080, 720x480. If 
#      this parameter is not specified the list will contain all the
#      modes supported by each connector
#Output:
#a list whose element comply with format <connector id>:<mode>,
#i.e 5:1920x1080-60 5:720x480-30
get_video_connector_info()
{
  assert [ ${#} -eq 1 -o ${#} -eq 2 ]
  local __info=$(modetest $(get_modetest_hint))
  local __dss_info
  local __conn_inf
  local __conn_ids
  local __modes_inf
  local __conn_vals
  local __val_inf
  local __mode_regex="^[0-9][0-9][0-9]"
  local __result=()
  local __c_mode
  local __c_id
  local __conn_type=$1
  local __format

  if [ ${#} -gt 1 ]; then
    __mode_regex="$2"
  fi
  get_sections "^[A-Za-z]*:" "$__info" "~" __dss_info
  local connectors=$(get_section_val "Connectors:" __dss_info[@] "~")
  get_sections "^[0-9].*" "$connectors" "~" __conn_inf
  get_sections_keys __conn_inf[@] "~" __conn_ids
  case $MACHINE in
    beaglebone)
      __format="@XB24"
    ;;
    *)
      __format=""
    ;;
  esac
  for conn in "${__conn_ids[@]}"
  do
    __info=$(echo -e "$conn" | grep -Ei $'\t'connected$'\t'$__conn_type)
    if [ $? -eq 0 ]; then
      __c_id=$(echo "$conn" | cut -d $'\t' -f 1)
      __val_inf=$(get_section_val "$conn" __conn_inf[@] "~")
      get_sections "^  [A-Za-z].*:" "$__val_inf" "~" __conn_vals
      __modes_inf=$(get_section_val "  modes:" __conn_vals[@] "~")
      local __old_ifs=$IFS
      IFS=$'\n'
      for mode in $__modes_inf
      do
        echo $mode | grep '#' > /dev/null
        if [ $? -eq 0 ]
        then
          __c_mode=$(echo $mode | cut -d ' ' -f 4,5)
        else
          __c_mode=$(echo $mode | cut -d ' ' -f 3,4)
        fi
        __c_mode=${__c_mode/ /-}
        if [[ "$__c_mode" =~ $__mode_regex ]]; then
          __result[${#__result[@]}]="$__c_id:$__c_mode$__format"
        fi
      done
      IFS=$__old_ifs
    fi
  done
  echo "${__result[@]}"
}

#Function to run a display test with modetest with the option to
#simultaneously play and audio file.
#Inputs:
#  $1: string containing the type of connector, i.e hdmi
#  $2: list of modes to run. the format of the elements in the list must
#      comply with <connector id>:<mode>, i.e 5:1280x720-60
#  $3: time is sec the test should last
#  $4 and $5: (Optional) the sampling rate and audio device id. At least
#             $4 has to be specified for the function to also test audio
#Returns
#  0 if the frame rate printed is within 1 Hz of the expected frame rate
#  for the mode and the audio test rc is 0; 1 otherwise
disp_audio_test()
{
  assert [ ${#} -gt 2 ]
  local __alsa_test_cmd="sleep $3"
  local __conn_type=$1
  local __m_array=$2[@]
  local __modes=( "${!__m_array}" )
  local __expected_fr
  local __freqs
  local __result=0
  local __fr_delta
  local __alsa_rc
  local __fmt_freqs
  local __fr_length
  local __freqs_detected
  local __freqs_result
  local __test_log
  local __diff
  local __min_delta
  local __failed_fr
  local __min_diff_fr_idx=0

  assert [ ${#__modes[@]} -gt 0 ]
  stop_daemon weston && sleep 3
  if [ ${#} -gt 3 ]; then
    __alsa_test_cmd="alsa_tests.sh -s mmc -d $3 -t playback -r $4"
  fi
  if [ ${#} -gt 4 ]; then
    __alsa_test_cmd="$__alsa_test_cmd -D $5"
  fi
  for mode in "${__modes[@]}"; do
    __diff=0
    __failed_fr=0
    __expected_fr=( $(echo "$mode" | grep -o '\-[0-9.]\+' | cut -d '-' -f 2 | sort | uniq) )
    echo "Expected frame rates: ${__expected_fr[@]}"
    echo "modetest $(get_modetest_hint) -t -d -v -s $mode &>mode_test_log.txt & mt_pid=\$! ; sleep 3 && $__alsa_test_cmd ; __alsa_rc=\$? ; kill -9 \$mt_pid"
    __test_log=$(modetest $(get_modetest_hint) -t -v -s $mode 2>&1 & mt_pid=$! ; sleep 3 && $__alsa_test_cmd ; __alsa_rc=$? ; kill -9 $mt_pid; echo alsa_rc=$__alsa_rc)
    echo "$__test_log"
    __alsa_rc=$(echo "$__test_log" | grep alsa_rc= | cut -d '=' -f 2) 
    __freqs=( $(echo -e "$__test_log" | grep freq: | cut -d ' ' -f 2) )
    __fmt_freqs=( $(echo -e "$__test_log" | grep freq: | cut -d ' ' -f 2 | cut -d 'H' -f 1) )
    __fr_length=$((${#__freqs[@]} - 2))
    old_IFS=$IFS
    IFS=$'\n'
    test_print_trc " MODE_FREQS | $__conn_type-$mode = ${__freqs[@]:1:$__fr_length}"
    IFS=$old_IFS
    if [ $__fr_length -lt 1 ]; then
      __result=2
    fi
    __freqs_detected=()
    __min_diff_fr_idx=-1
    for fr in ${__fmt_freqs[@]:1:$__fr_length}
    do
      __min_delta=1
      for i in `seq 0 $((${#__expected_fr[@]} - 1))`
      do
        __fr_delta=`expr "${__expected_fr[$i]} - $fr" | bc`
        if(( $(echo "$__fr_delta < 0" |bc -l) )); then
          __fr_delta=`expr "$__fr_delta * -1" | bc`
        fi
        if(( $(echo "$__fr_delta < $__min_delta" |bc -l) )); then
          __min_delta=$__fr_delta
          __min_diff_fr_idx=$i
        fi
      done
      #  failure condition - check
      if [ $__min_diff_fr_idx -eq -1 ]; then
        __freqs_result=1
      else
        __freqs_detected[$__min_diff_fr_idx]=${__expected_fr[$__min_diff_fr_idx]}
        __freqs_result=0
      fi
      __diff=`expr "$__diff + $__min_delta" | bc`
      if [ $__freqs_result -ne 0 ]; then
      __failed_fr=$((__failed_fr+1))
        echo "Display test failed for mode $mode expected ${__expected_fr[@]} got $fr"
      fi
      let "__result|=$__freqs_result"
    done
    if [ $__result -ne 0 -a $__failed_fr -gt 0 -a $__failed_fr -lt 5 ]; then
      if [ $((__diff/__fr_length)) -lt 1 ]; then
        echo "${__failed_fr} fps values were not in spec but overall fps is good error~${__diff}/${__fr_length}"
        __result=0
      fi
    fi
    if [ ${#__freqs_detected[@]} -ne ${#__expected_fr[@]} ]; then
      echo "Display test failed for mode $mode expected ${__expected_fr[@]} detected freqs ${__freqs_detected[@]}"
      __result=1
    fi
    if [  $__alsa_rc -ne 0 ]; then
      echo "Audio test failed with mode $mode"
      __result=1
    fi
  done
  exit $__result
}

#Function to obtain an array of combined modes (<connector id>:<mode>)
#supported by the board 
#This function will only return information of connectors with connected
#status
#Inputs:
#  $1: a variable where the array will be stored
#  $2: (Optional) a mode regex to look for, i.e, 1920x1080, 720x480. If 
#      this parameter is not specified the list will contain all the
#      combined modes (<connector id>:<mode>) supported by board
#Output:
#an array stored on $1 whose element comply with format 
#<connector id>:<mode>[ -s <connector id>:<mode>.... -s -s <connector id>:<mode>]
get_multidisplay_modes()
{
  assert [ ${#} -eq 1 -o ${#} -eq 2 ]
  local __modes=$(get_video_connector_info '*')
  local __conns=( $(echo $__modes | grep -o [0-9]*: | uniq) )
  local __max_con_modes=0
  local __max_con
  local __num_modes
  local __mode_regex=".*"
  local __result
  local __c_modes
  eval "$1=()"
  if [ ${#} -gt 1 ]; then
    __mode_regex="$2"
  fi

  for cn in ${__conns[@]}
  do
    __num_modes=$(echo $__modes | grep -o $cn | wc -l)
    if [ $__num_modes -gt $__max_con_modes ]; then
      __max_con="$cn"
      __max_con_modes=$__num_modes
    fi
  done
  __result=( $(echo $__modes | grep -o $__max_con[0-9]*x[0-9i]*-[0-9.]*) )
  for i in `seq 0 $(($__max_con_modes - 1))`
  do
    for con in ${__conns[@]}
    do
      if [ "$con" == "$__max_con" ]; then
        continue
      fi
      __c_modes=( $(echo $__modes | grep -o ${con}[0-9]*x[0-9i]*-[0-9.]*) )
      __result[$i]="${__result[$i]} -d -s ${__c_modes[$(($i % ${#__c_modes[@]}))]}"
    done
    if [[ "${__result[$i]}" =~ $__mode_regex ]]; then
      eval "$1+=(\"${__result[$i]}\")"
    fi
  done
}

#Function to obtain the connector ids of connectors with connected
#status.
#Inputs:
#  $1: (Optional) the connector type hdmi, unknown
#Output:
#a list containing the connector ids, one per line if $1 is not defined
get_video_connectors_id()
{
	local __filter="."
	if [ ${#} -gt 0 ]; then
	  __filter=$*
  fi
  
  modetest $(get_modetest_hint) -c | grep -i -v disconnected | grep -i $__filter | grep -o ^[0-9]*
}

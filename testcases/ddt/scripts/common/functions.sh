#!/bin/bash
#
# PM-QA validation test suite for the power management on Linux
#
# Copyright (C) 2011, Linaro Limited.
# Copyright (C) 2013 Texas Instruments Incorporated - http://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Contributors:
#     Daniel Lezcano <daniel.lezcano@linaro.org> (IBM Corporation)
#       - initial API and implementation
#     Carlos Hernandez <ceh@ti.com>
#       - Add new functions
#     Alejandro Hernandez <ajhernandez@ti.com>
#       - Add new functions
#

source "common.sh"     # include ltp-ddt common functions

CPU_PATH="/sys/devices/system/cpu"
TEST_NAME=$(basename ${0%.sh})
PREFIX=$TEST_NAME
INC=0
CPU=
pass_count=0
fail_count=0

test_status_show() {
    echo "-------- total = $(($pass_count + $fail_count))"
    echo "-------- pass = $pass_count"
    # report failure only if it is there
    if [ $fail_count -ne 0 ] ; then
      echo "-------- fail = $fail_count"
      exit 1
    fi
}

if [ -f /sys/power/wake_lock ]; then
    use_wakelock=1
else
    use_wakelock=0
fi

log_begin() {
    printf "%-76s" "$TEST_NAME.$INC$CPU: $@... "
    INC=$(($INC+1))
}

log_end() {
    printf "$*\n"
}

log_skip() {
    log_begin "$@"
    log_end "skip"
}

check() {

    local descr=$1
    local func=$2
    shift 2;

    log_begin "checking $descr"

    $func $@
    if [ $? != 0 ]; then
    log_end "fail"
    fail_count=$(($fail_count + 1))
    return 1
    fi

    log_end "pass"
    pass_count=$(($pass_count + 1))

    return 0
}

check_file() {
    local file=$1
    local dir=$2

    check "'$file' exists" "test -f" $dir/$file
}


for_each_cpu() {

    local func=$1
    shift 1

    cpus=$(ls $CPU_PATH | grep "cpu[0-9].*")

    for cpu in $cpus; do
	INC=0
	CPU=/$cpu
	$func $cpu $@
    done

    return 0
}

get_num_cpus() {
    cpus=$(ls $CPU_PATH | grep "cpu[0-9].*")
    echo ${#cpus[@]}
}

for_each_governor() {

    local cpu=$1
    local func=$2
    local dirpath=$CPU_PATH/$cpu/cpufreq
    local governors=$(cat $dirpath/scaling_available_governors)
    shift 2

    for governor in $governors; do
	$func $cpu $governor $@
    done

    return 0
}

for_each_frequency() {

    local cpu=$1
    local func=$2
    local dirpath=$CPU_PATH/$cpu/cpufreq
    local frequencies=$(cat $dirpath/scaling_available_frequencies)
    shift 2

    for frequency in $frequencies; do
	$func $cpu $frequency $@
    done

    return 0
}

set_governor() {

    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq/scaling_governor
    local newgov=$2

    echo $newgov > $dirpath
}

get_governor() {

    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq/scaling_governor

    cat $dirpath
}

wait_latency() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq
    local latency=
    local nrfreq=

    latency=$(cat $dirpath/cpuinfo_transition_latency)
    if [ $? != 0 ]; then
	return 1
    fi

    nrfreq=$(cat $dirpath/scaling_available_frequencies | wc -w)
    if [ $? != 0 ]; then
	return 1
    fi

    nrfreq=$((nrfreq + 1))
    ../utils/nanosleep $(($nrfreq * $latency))
}

frequnit() {
    local freq=$1
    local ghz=$(echo "scale=1;($freq / 1000000)" | bc -l)
    local mhz=$(echo "scale=1;($freq / 1000)" | bc -l)

    res=$(echo "($ghz > 1.0)" | bc -l)
    if [ "$res" = "1" ]; then
	echo $ghz GHz
	return 0
    fi

    res=$(echo "($mhz > 1.0)" | bc -l)
    if [ "$res" = "1" ];then
	echo $mhz MHz
	return 0
    fi

    echo $freq KHz
}

set_frequency() {

    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq
    local newfreq=$2
    local setfreqpath=$dirpath/scaling_setspeed

    echo $newfreq > $setfreqpath
    wait_latency $cpu
}

get_frequency() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq/scaling_cur_freq
    cat $dirpath
}

# Save cpufreq transition stats into an array
# $1: Array to save values into
get_cpufreq_transition_values() {
    local __arrayvar=$1
    eval $__arrayvar="($(cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state | cut -d' ' -f 2))"
}

# Get array of clock rates
# $1: Array to save values into
get_clk_summary() {
  local __arrayvalues=$1
  data=`mktemp`
  cat /sys/kernel/debug/clk/clk_summary  > $data
  sed -i -e 's/\-*//' -e 's/.*clock.*count.*rate.*//' -e 's/.*enable.*prepare.*//' $data
  eval $__arrayvalues="($(awk -- '{print $5};' $data))"
  rm $data
}


# Function to check operator ($3) in  corresponding elements in 2 arrays
# $1: First array
# $2: Second array
# $3: comparison operation e.g. "-lt"
# $4: [Optional] First array multiplier.
check_array_values() {
    local multiplier=1
    if [ -n "$4" ]; then
        multiplier=$4
    fi
    local old=("${!1}")
    local new=("${!2}")
    for i in "${!old[@]}"; do
        echo "Checking assertion for index $i"
        adjusted_value=$(echo "(${old[$i]} * $multiplier)/1" | bc)
        assert [ $adjusted_value $3 ${new[$i]} ]
    done
}


get_max_frequency() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq/scaling_max_freq
    cat $dirpath
}

get_min_frequency() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu/cpufreq/scaling_min_freq
    cat $dirpath
}

set_online() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu
    echo 1 > $dirpath/online
    report "$cpu online"
}

set_offline() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu
    echo 0 > $dirpath/online
    report "$cpu offline"
}

get_online() {
    local cpu=$1
    local dirpath=$CPU_PATH/$cpu

    cat $dirpath/online
}

# Online/offline CPU1 or higher - mess with governor
cpu_online_random()
{
    local num_cpu=`get_num_cpus`
    local random_cpu=cpu`random_ne0 $num_cpu`
    local k=`random 1`
    if [ -f $CPU_PATH/$random_cpu/online -a $k -eq 1 ]; then
        set_online $random_cpu
    fi
}

# IF WE HAVE A BUG CREATION LOGIC, TRIGGER IT
bug_random()
{
    if [ -f $DEBUGFS_LOCATION/pm_debug/bug ]; then
        k=`random 1`
        echo -n "$k"> $DEBUGFS_LOCATION/pm_debug/bug
        report "BUG : $k"
    fi
}

# Do off or not
offmode_random()
{
    k=`random 1`
    echo -n "$k"> $DEBUGFS_LOCATION/pm_debug/enable_off_mode
    report "enable_off_mode : $k"
}

# automated waker.. dont want hitting keyboards..
wakeup_time_random()
{
    # add this variable to have bigger wakeup time
    max_wtime=$1
    if [ -z $max_wtime ]; then
      max_wtime=10
    fi
    k=`random_ne0 $max_wtime`
    sec=`expr $k % 1000`
    msec=`expr $k / 1000`
    if [ -e $DEBUGFS_LOCATION/pm_debug/wakeup_timer_seconds ]; then
      echo $sec > $DEBUGFS_LOCATION/pm_debug/wakeup_timer_seconds
      echo $msec > $DEBUGFS_LOCATION/pm_debug/wakeup_timer_milliseconds
    fi
    report "wakeup - $sec sec $msec msec"
}

# cleanup stress-ng
stop_cpu_load()
{
    if [ `which stress-ng` ]; then
        sleep 5
        killall stress-ng 2>/dev/null
        report "killed stress-ng"
    else
        report "stress-ng is not installed"
    fi
}

# Blocking call as a wrapper for stress-ng across all cpu cores
cpu_load_nproc()
{
    local cpus_load=$1
    local duration=$1
    local RETVAL=0
    cmd="stress-ng -c 0 -l ${cpus_load} -t ${duration}s"
    eval "$cmd" || RETVAL=$?
    report "'$cmd' returned ${RETVAL}!"
    return $RETVAL
}

# start up stress-ng
cpu_load_random()
{
    if [ `which stress-ng` ]; then
        trap on_exit EXIT
        local cpus_load=`random_ne0 100`
        local duration=`random_ne0 600`
        cmd="stress-ng -c 0 -l ${cpus_load} -t ${duration}s"
        report "$cmd"
        time $cmd &
    else
        report "stress-ng is not installed"
    fi
}

#Run memtest
# $1: use memory percentage
# $2: number of iterations
run_memtest()
{
    trap on_exit EXIT
    export m1=`free|cut -d ":" -f2|sed -e "s/^\s\s*//g"|head -2|tail -1|cut -d ' ' -f1`
    export m2=M
    export m=`expr $m1 \* $1 / 100 / 1024`

    report "Testing $m$m2 of memory $2 times"
    memtester $m$m2 $2
}

#Start memtest
# $1: use memory percentage
start_memtest()
{
    trap on_exit EXIT
    # Step 1- start up memtest
    export m1=`free|cut -d ":" -f2|sed -e "s/^\s\s*//g"|head -2|tail -1|cut -d ' ' -f1`
    export m2=M
    export m=`expr $m1 \* $1 / 100 / 1024`

    report "Testing memory for $m$m2"
    memtester $m$m2 &

}
# pause memtester
pause_memtest()
{
    MEMTESTERPID=`ps | grep memtester | grep -v grep | cut -c 0-5`
    kill -STOP $MEMTESTERPID
    report "pause memtest"
}

# resume memtester
# $1: use memory percentage
resume_memtest()
{
    MEMTESTERPID=`ps | grep memtester | grep -v grep | cut -c 0-5`
    if [ -z "$MEMTESTERPID" ]; then
        start_memtest $1
    else
        kill -CONT $MEMTESTERPID
    fi
    report "resume memtest"
}

# kill memtester
kill_memtest()
{
     if [ `which memtester` ]; then  
        sleep 2                      
        killall memtester 2>/dev/null
    	report "killed memtest"
     else                                    
        report "memtester is not installed"
     fi
}

# give me some idle time
idle_random()
{
    time=`random 10`
    report "smallidle: $time seconds"
    sleep $time
}

# give me some idle time
idlebig_random()
{
    time=`random_ne0 300`
    report "bigidle: $time seconds"
    report "Processes running:"
    ps 
    report "cpu1 status:"
    cat /sys/devices/system/cpu/cpu1/online
    sleep $time
}

# dont suspend
no_suspend()
{
    if [ $use_wakelock -ne 0 ]; then
        echo "$PSID" >/sys/power/wake_lock
        report "wakelock $PSID"
    fi
}

# suspend / standby me
# input
#   -p power_state  optional; power state like 'mem' or 'standby'; default to 'mem'
#   -t max_stime    optional; maximum suspend or standby time; default to 10s; the suspend time will be a random number
#   -i iterations   optional; iterations to suspend/resume; default to 1
#   -u usb_remove   optional; usb_state to indicate if usb module needs to be removed prior to suspend; default to '0'
#                              0 indicates 'dont care'; 1 indicates 'remove usb module'; 2 indicates 'do not remove usb module'
#   -m usb_module   optional; usb_module to indicate the name of usb module to be removed; default to ''
#   -a max_atime    optional; maximum active time between suspend calls; default to 5s; it will be a random number
suspend()
{
    OPTIND=1 
    local _iterations
    while getopts :p:t:i:u:m: arg
    do case $arg in
      p)  power_state="$OPTARG";;
      t)  max_stime="$OPTARG";;
      a)  max_atime="$OPTARG";;
      i)  _iterations="$OPTARG";;
      u)  usb_remove="$OPTARG";;
      m)  usb_module="$OPTARG";;

      \?)  test_print_trc "Invalid Option -$OPTARG ignored." >&2
      exit 1
      ;;
    esac
    done

    # for backward compatible
    : ${power_state:='mem'}
    : ${max_stime:='10'}
    : ${max_atime:='5'}
    : ${_iterations:='1'}
    : ${usb_remove:='0'}
    : ${usb_module:=''}

    case "$MACHINE" in        
        am335x-evm|am335x-sk|beaglebone|beaglebone-black|beaglebone_green_eco-gp)
                rtc_dev="/dev/rtc1";;                                          
        *)                                                              
                rtc_dev="/dev/rtc0";;
    esac 

    test_print_trc "suspend function: power_state: $power_state"
    test_print_trc "suspend function: max_stime: $max_stime"
    test_print_trc "suspend function: max_atime: $max_atime"
    test_print_trc "suspend function: iterations: $_iterations"
    test_print_trc "suspend function: usb_remove: $usb_remove"
    test_print_trc "suspend function: usb_module: $usb_module"
    test_print_trc "suspend function: rtc_dev: $rtc_dev"

    enable_pm_debug_messages

    if [ $use_wakelock -ne 0 ]; then
        report "removing wakelock $PSID (sec=$sec msec=$msec off=$off bug=$bug)"
        echo "$PSID" >/sys/power/wake_unlock
    fi

    local i=0
    while [ $i -lt $_iterations ]; do
      test_print_trc "===suspend iteration $i==="

      wakeup_time_random $max_stime
      suspend_time=$sec
      if [ $usb_remove = 1 ]; then
         if [ "$usb_module" = '' ]; then
            die "No usb_module in command line although usb module remove flag has been selected"
         fi
         `modprobe -r $usb_module`
      elif [ $usb_remove = 2 ]; then
         inverted_return='true'
      fi 
      # clear dmesg before suspend
      dmesg -c > /dev/null
      local suspend_failures=`get_value_for_key_from_file /sys/kernel/debug/suspend_stats fail :`
      if [ -e ${rtc_dev} ]; then
          report "Use rtc to suspend resume, adding 10 secs to suspend time"
          suspend_time=$((suspend_time+10))
          # sending twice in case a late interrupt aborted the suspend path.
          # since this is not common, it is expected that 2 tries should be enough
          rtcwake -d ${rtc_dev} -m ${power_state} -s ${suspend_time} || rtcwake -d ${rtc_dev} -m ${power_state} -s $(expr ${suspend_time} + 10) || die "rtcwake failed 2 consecutive times"
      elif [ -e $DEBUGFS_LOCATION/pm_debug/wakeup_timer_seconds ]; then
          report "Use wakeup_timer"
          report "suspend(sec=$sec msec=$msec off=$off bug=$bug)"
          echo -n "$power_state" > /sys/power/state
      else
          # Stop the test if there is no rtcwake or wakeup_timer support 
          die "There is no automated way (wakeup_timer or ${rtc_dev}) to wakeup the board. No suspend!" 
      fi
     
      if [ $usb_remove = 2 ]; then
         check_suspend_fail
      else
         check_suspend
         check_resume
         check_suspend_stats $suspend_failures
         check_suspend_errors
         if [ $usb_remove = 1 ]; then
            echo "USB_REMOVE flag is $usb_remove"
            `modprobe $usb_module`
         fi 
      fi
      sleep `random_ne0 $max_atime`

      i=`expr $i + 1`
    done

    no_suspend
}

enable_pm_debug_messages()
{
    grep '1' /sys/power/pm_debug_messages || echo 1 > /sys/power/pm_debug_messages
    grep '^8' /proc/sys/kernel/printk || echo 8 > /proc/sys/kernel/printk
}

# check if suspend/standby is ok by checking the kernel messages
check_suspend()
{
    local expect="PM: suspend of devices complete"
    local k3_expect="PM: suspend entry"
    dmesg | grep -i "$expect\|$k3_expect" && report "suspend successfully" || die "suspend failed"
}

# check if suspend/standby failed as expected by checking the kernel messages
check_suspend_fail()
{
    local expect="PM: Some devices failed to suspend"
    dmesg | grep -i "$expect" && report "suspend failed as expected" || die "suspend did not fail as expected"
}

# check if resume is ok by checking the kernel messages
check_resume()
{
    local expect="PM: resume of devices complete"
    local k3_expect="PM: suspend exit"
    dmesg | grep -i "$expect\|$k3_expect" && report "resume successfully" || die "resume failed"
}

check_suspend_errors()
{
    local expect="Could not enter target state in pm_suspend|_wait_target_disable failed"
    dmesg | egrep -i "$expect" && die "$expect errors observed"
}

# $1: previous failures
check_suspend_stats()
{
    local failures=`get_value_for_key_from_file /sys/kernel/debug/suspend_stats fail :`
    [ $((failures - $1)) -le 1 ] || die "/sys/kernel/debug/suspend_stats reports failures"
}

check_cpufreq_files() {

    local dirpath=$CPU_PATH/$1/cpufreq
    shift 1

    for i in $@; do
	check_file $i $dirpath || return 1
    done

    return 0
}

check_sched_mc_files() {

    local dirpath=$CPU_PATH

    for i in $@; do
	check_file $i $dirpath || return 1
    done

    return 0
}

check_topology_files() {

    local dirpath=$CPU_PATH/$1/topology
    shift 1

    for i in $@; do
	check_file $i $dirpath || return 1
    done

    return 0
}

check_cpuhotplug_files() {

    local dirpath=$CPU_PATH/$1
    shift 1

    for i in $@; do
	check_file $i $dirpath || return 1
    done

    return 0
}

save_governors() {

    governors_backup=
    local index=0

    for i in $(ls $CPU_PATH | grep "cpu[0-9].*"); do
	governors_backup[$index]=$(cat $CPU_PATH/$i/cpufreq/scaling_governor)
	index=$((index + 1))
    done
}

restore_governors() {

    local index=0
    local oldgov=

    for i in $(ls $CPU_PATH | grep "cpu[0-9].*"); do
	oldgov=${governors_backup[$index]}
	echo $oldgov > $CPU_PATH/$i/cpufreq/scaling_governor
	index=$((index + 1))
    done
}

save_frequencies() {

    frequencies_backup=
    local index=0
    local cpus=$(ls $CPU_PATH | grep "cpu[0-9].*")
    local cpu=

    for cpu in $cpus; do
	frequencies_backup[$index]=$(cat $CPU_PATH/$cpu/cpufreq/scaling_cur_freq)
	index=$((index + 1))
    done
}

restore_frequencies() {

    local index=0
    local oldfreq=
    local cpus=$(ls $CPU_PATH | grep "cpu[0-9].*")

    for cpu in $cpus; do
	oldfreq=${frequencies_backup[$index]}
	echo $oldfreq > $CPU_PATH/$cpu/cpufreq/scaling_setspeed
	index=$((index + 1))
    done
}

# give me detailed report
report_stats()
{
    local num_cpus=`get_num_cpus`
    report "============================================="
    report " $*"
    report "OMAP STATS: "
    report "$DEBUGFS_LOCATION/pm_debug/count"
    cat $DEBUGFS_LOCATION/pm_debug/count
    report "$DEBUGFS_LOCATION/pm_debug/time"
    cat $DEBUGFS_LOCATION/pm_debug/time
    report "$DEBUGFS_LOCATION/wakeup_sources"
    cat $DEBUGFS_LOCATION/wakeup_sources
    report "Core domain stats:"
    cat $DEBUGFS_LOCATION/pm_debug/count | grep "^core_pwrdm"
    if [ -f $DEBUGFS_LOCATION/suspend_time ]; then
        report "Suspend times:"
        cat $DEBUGFS_LOCATION/suspend_time
    fi
    report "CPUFREQ STATS: "
    report "/sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state"
    cat /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state
    report "/sys/devices/system/cpu/cpu0/cpufreq/stats/total_trans"
    cat /sys/devices/system/cpu/cpu0/cpufreq/stats/total_trans
    report "/sys/devices/system/cpu/cpu0/cpufreq/stats/trans_table"
    cat /sys/devices/system/cpu/cpu0/cpufreq/stats/trans_table
    report "CPUIDLE STATS: "

    for cpu in `seq 0 $(($num_cpus - 1))`;
    do
        cpuidledir=/sys/devices/system/cpu/cpu$cpu/cpuidle
        if [ -d "$cpuidledir" ]; then
            report "CPU$cpu IDLE STATS: "
            k=`pwd`
            cd $cpuidledir
            report "NAME | DESCRIPTION | USAGE (number of entry)  | TIME | POWER | LATENCY"
            for state in *
            do
                DESC=`cat $state/desc`
                NAME=`cat $state/name`
                POWER=`cat $state/power`
                TIME=`cat $state/time`
                USAGE=`cat $state/usage`
                LATENCY=`cat $state/usage`
                report "$NAME | $DESC | $USAGE | $TIME | $POWER | $LATENCY"
            done
            cd $k
        fi
    done
    report "============================================="
}

# Get the power domain name for peripheral
# Input
#   $1: platform name
#   $2: peripheral
# Output
#   pwrdm_name
#
get_pwrdm_name()
{
  platform=$1
  per=$2

  case $platform in
    dra7xx*|dra72x*|am57xx*)
      case $per in
        i2c) rtn="l4per_pwrdm" ;;
      esac
    ;;
    am335x*)
      case $per in
        i2c) rtn="per_pwrdm" ;;
      esac
    ;;
  esac
 
  if [ -z "$rtn" ]; then
    die "Could not get pwrdm name for $platform $per"
  fi

  echo "$rtn"
}

# write pm counters into log file. The log will have something like "RET:0 \n RET-LOGIC-OFF:6"
# $1: power domain
# $2: power states seperated by delimiter Ex, "OFF:RET:INA","RET:RET-LOGIC-OFF" etc showing in pm count stat
# $3: power states delimiter
# $4: log name to save the counter
log_pm_count()
{
  local pwrdm=$1
  local pwr_states=$2
  local states_delimiter=$3
  local log_name=$4
  local tmp_ifs="$IFS"
  IFS=$states_delimiter
  for pwr_state in $pwr_states; do
    pwrdm_stat=`cat ${DEBUGFS_LOCATION}pm_debug/count | grep ^$pwrdm`
    pwrdm_stat=`expr match "$pwrdm_stat" ".*,\($pwr_state:[0-9]*\)"`
    report "Power domain stats requested: ${pwrdm}: $pwrdm_stat==========="
    echo "$pwrdm_stat" >> ${TMPDIR}/"$log_name"
  done
  IFS="$tmp_ifs"
}

# Compare two counters from two logs for pwrdm and pwr-state
#  The log contains something like "RET:0 \n RET-LOGIC-OFF:6 \n"
#  $1: pwrdm
#  $2: power states 
#  $3: power states delimiter; 
#  $4: log name before
#  $5: log name after  
compare_pm_count()
{
  local pwrdm=$1
  local pwr_states=$2
  local state_delimiter=$3
  local log_name_before=$4
  local log_name_after=$5

  local log_before=${TMPDIR}/"$log_name_before"
  local log_after=${TMPDIR}/"$log_name_after"

  local num_lines_1=`cat "$log_before" | wc -l`
  local num_lines_2=`cat "$log_after" | wc -l`
  if [ $num_lines_1 -ne $num_lines_2 ]; then
    die "There is differnt number of pairs between log file $log_name_before and log file $log_name_after; can not compare these two logs" 
  fi

  local tmp_ifs="$IFS"
  IFS=$state_delimiter
  for pwr_state in $pwr_states; do
    val_before=`get_value_for_key_from_file "$log_before" "$pwr_state" ":"` || die "Error getting value from $log_before for ${pwr_state}: $val_before"
    val_after=`get_value_for_key_from_file "$log_after" "$pwr_state" ":"` || die "Error getting value from $log_after for ${pwr_state}: $val_after"

    report "$pwrdm: Initial Value -> $pwr_state: $val_before"
    report "$pwrdm: Final Value -> $pwr_state: $val_after"

    # Verify the power domain counter increases
    report "Verifying $pwrdm: $pwr_state counter increases ..."
    sleep 1

    if [ "$val_after" -gt "$val_before" ]; then
      report "SUCCESS: $pwrdm: $pwr_state counters increased"
    else
      die "ERROR: $pwrdm: $pwr_state counters did not increase. Please review power states counters"
    fi

  done
  IFS="$tmp_ifs"

}

sigtrap() {
    exit 255
}

# execute on exit - cleanup actions
on_exit()
{
    stop_cpu_load
    kill_memtest
}

#Function to validate a condition, takes the
# following parameters
#    $1: Condition to assert, i.e [ 1 -ne 2 ]
#If the conditions is not true the function exits the program and prints
#the backtrace
assert() {
  eval "${@}"
  if [ $? -ne 0 ]
  then
    echo "Assertion ${@} failed"
    i=0
    while caller $i
    do
      i=$((i+1))
    done 
    exit 2
  fi
}

#Funtion to parse text into sections.
#Inputs:
#  $1: pattern to match for a start of section
#  $2: text to parse
#  $3: separator to use for the elements returned in $4
#  $4: variable to assign the result list that will contain
#Output:
#A list named $4 whose element are text that match
#<text that matched $1><$3><section text>
get_sections() {
  assert [ ${#} -eq 4 ]
  local key_val_indexer=$3
  local current_section
  local old_IFS=$IFS
  local sections_dict
  IFS=$'\n'
  i=0
  for line in $2
  do
    if [[ "$line" =~ $1 ]]
    then
      if [[ -n "$current_section" ]]
      then
        eval "$4[$i]=\"$current_section\""
        i=$((i+1))
      fi
      current_section="${BASH_REMATCH[0]}${key_val_indexer}"
      if [[ ${#BASH_REMATCH[@]} -gt 1 ]]
      then
        current_section="${BASH_REMATCH[1]}${key_val_indexer}"
      fi
    elif [[ -n "$current_section" ]]
    then
      current_section="${current_section}${line}"'\n'
    fi
  done
  if [[ -n "$current_section" ]]
  then
    eval "$4[$i]=\"$current_section\""
  fi
  IFS=$old_IFS
}

#Function to obtain the value referenced by a key from a
#sections list returned by get_sections.
#Inputs:
#  $1: key whose value will be returned
#  $2: the list to search in, i.e sections_dict[@]
#  $3: the separator used when creating the elements in
#      list $2
#Output:
#The text associated with the key if any
get_section_val() {
  assert [ ${#} -eq 3 ]
  local key="$1"
  local dict=("${!2}")
  local current_tuple
  local old_IFS=$IFS
  for idx in $(seq 0 $((${#dict[@]}-1)))
  do
    IFS=$3
    current_tuple=( ${dict[$idx]} )
    if [ "$key" == "${current_tuple[0]}" ]
    then
       echo -e ${current_tuple[@]:1}
       break
    fi
  done
  IFS=$old_IFS
}


#Function to obtain a list of keys from a
#sections_dict like list returned by get_sections.
#Inputs:
#  $1: the list to search in, i.e sections_dict[@]
#  $2: the separator used when creating the elements in
#      list $1
#  $3: name of the result list
#  $4: (optional) pattern to match in keys, when this
#      parameters is set only the keys that match $4 are
#      included in $3. If $4 has a grouping construct
#      then only the captured group is included in $3
#Output:
#a list named $3 with all the keys found in $1
get_sections_keys() {
  assert [ ${#} -eq 3 -o ${#} -eq 4 ]
  local dict=("${!1}")
  local current_tuple
  local old_IFS=$IFS
  local filter_idx=0
  for idx in $(seq 0 $((${#dict[@]}-1)))
  do
    IFS=$2
    current_tuple=( ${dict[$idx]} )
    if [ ${#} -eq 4 ]
    then
      if [[ "${current_tuple[0]}" =~ $4 ]]
      then
        if [[ ${#BASH_REMATCH[@]} -gt 1 ]]
        then
          eval "$3[$filter_idx]=\"${BASH_REMATCH[1]}\""
        else
          eval "$3[$filter_idx]=\"${BASH_REMATCH[0]}\""
        fi
      fi
      filter_idx=$((filter_idx+1))
    else
      eval "$3[$idx]=\"${current_tuple[0]}\""
    fi
  done
  IFS=$old_IFS
}


#================================================================== 
# run_memtest_var() is designed to test memory modules larger than 2000 MBytes
# by running memtester() function multiple times in 2000 MBytes or smaller segments.  
# All inputs variables must be integers in MBytes, except the last one for iterations.
# Syntax: run_memtest_var [Memory_Size] [Memory_Headroom] [Iterations] 
# $1: Memory size to test in MBytes.  
# $2: Headroom memory for the Kernel's operation in MBytes. (Recommended >= 350 MB)
# $3: Number of test iterations.
# The program terminates with exit code 1 if the input variables are missing, or
# insufficient memory is available to conduct the test based on user inputs.   

run_memtest_var()
{ 
  declare -a procs
  trap on_exit EXIT
  if [ -z $3 ]; then 
  echo "ERROR: incorrect number of input parameters."
  echo "Example: run_memtest_var 3000 350 1"
  exit 1;
  fi
  Start_time=$(date "+%Y-%m-%d %H:%M:%S")
  mem_per_proc=`expr 2000 \* 1000`
  headroom=`expr $2 \* 1000`
  Mem_Size=`expr $1 \* 1000`
  iterations=$3
  killall memtester 2>/dev/null; sleep 5;
 
  mem_free=`free|cut -d ":" -f2| sed -e "s/\s\+/ /g"|head -2|tail -1|cut -d ' ' -f4`
  mem_free=`expr $mem_free \- $headroom`   #leave memory headroom for kernel operation
  
  if [ $Mem_Size -gt $mem_free ]; then 
    echo "ERROR: Insufficient free memory available for your test."
    exit 1;
  else  
    # if user specifies smaller memory size than available free memory, then only run what is requested.
    mem_free=$Mem_Size
  fi
  num_proc=`expr $mem_free \/ $mem_per_proc`
  i=0
  while [ $i -lt $num_proc ]; do
     procs[$i]="memtester ${mem_per_proc}K $iterations  "
     i=$((i+1))
  done
  left_over_mem=`expr $mem_free \- $num_proc \* $mem_per_proc`
  CMD=`join \# "${procs[@]}"`
  if [ $left_over_mem -gt 0 ]; then 
  CMD+="#memtester ${left_over_mem}K $iterations"
  fi
  run_processes.sh -c "$CMD"
  rc=$?
  End_time=$(date "+%Y-%m-%d %H:%M:%S") 
  echo "Test Start time:" $Start_time
  echo "Test End   time:" $End_time
  exit $rc
}

#==================================================================
join ()
{ 
local IFS="$1"; shift; echo "$*";
}

# Run cyclictest and compare max latency agains $1 pass criteria
run_cyclictest()
{
    local passcriteria=$1
    shift 1
    cyclictest $@  | awk -v passcriteria=$passcriteria '
      BEGIN {max=0; FS="Max:"};
      {print $0};
      /^T:.+Max:\s+[[:digit:]]+/ {if ($2 > max) max=$2};
      END {print "max_latency=" max};
      END {if (max > passcriteria) {print "TEST:FAILED"; exit 1;} else {print "TEST:PASSED"; exit 0}}'
}

mount_cgroup()
{
    ls /sys/fs/cgroup/tasks &> /dev/null || mount -t cgroup -ocpuset cpuset /sys/fs/cgroup/
}

# $1: name
# $2: cpuset
# $3: memset (default 0)
create_cgroup()
{
    local memset=0
    if [ -z $1 -o -z $2 ]; then
        die "create_cgroup requires name and cpuset"
    fi
    if [ $3"x" != "x" ]; then
        memset=$3
    fi
    mount_cgroup
    ls /sys/fs/cgroup/$1 &> /dev/null || mkdir /sys/fs/cgroup/$1
    echo $2 > /sys/fs/cgroup/$1/cpuset.cpus
    echo $memset > /sys/fs/cgroup/$1/cpuset.mems
    echo 1 > /sys/fs/cgroup/$1/cpuset.cpu_exclusive
}

# $1: 0 to disable, 1 to enable
set_cgroup_load_balance()
{
    mount_cgroup
    cat /sys/fs/cgroup/cpuset.sched_load_balance | grep $1 &> /dev/null || echo $1 > /sys/fs/cgroup/cpuset.sched_load_balance
    cat /sys/fs/cgroup/rt/cpuset.sched_load_balance | grep $1 &> /dev/null || echo $1 > /sys/fs/cgroup/rt/cpuset.sched_load_balance
    cat /sys/fs/cgroup/nonrt/cpuset.sched_load_balance | grep $1 &> /dev/null || echo $1 > /sys/fs/cgroup/nonrt/cpuset.sched_load_balance
}

# Run shell and subsequent Processes started from it on shielded (i.e. separate) CPU
shield_shell()
{
    local max_id=`cat /sys/devices/system/cpu/online | cut -d '-' -f 2`
    if [ $max_id == "1" ]; then
        create_cgroup nonrt 0
        create_cgroup rt 1
    else
        create_cgroup nonrt "0-$((max_id-1))"
        create_cgroup rt $max_id
    fi
    set_cgroup_load_balance 0
    for pid in $(cat /sys/fs/cgroup/tasks); do /bin/echo $pid > /sys/fs/cgroup/nonrt/tasks; done
    /bin/echo $$ > /sys/fs/cgroup/rt/tasks
}

unshield_shell()
{
    for pid in $(cat /sys/fs/cgroup/nonrt/tasks); do /bin/echo $pid > /sys/fs/cgroup/tasks; done
    for pid in $(cat /sys/fs/cgroup/rt/tasks); do /bin/echo $pid > /sys/fs/cgroup/tasks; done
    set_cgroup_load_balance 1
}

# Run a command and capture one or more values into an array
# $1: Command to execute
# $2: sed command to capture and print values, e.g. 's/.+myprefix([[:digit:]]+)mysuffix.*/\1 /p'
# $3: Array to save values into
run_and_capture_values() {
    local __arrayvalues=$3
    eval $__arrayvalues="($($1 2>&1 | sed -rn $2))"
}

check_jailhouse()
{
    which jailhouse || die "jailhouse is not in the filesystem"
    lsmod |grep jailhouse || die "jailhouse kernel module is not available"
}

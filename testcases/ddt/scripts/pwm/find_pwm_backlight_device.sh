#! /bin/bash

backlight_device=$(find /sys/class/backlight/ -mindepth 1 -maxdepth 1 -name '*backlight*' -exec basename {} \;)
pwm_backlight_device=$(udevadm info -a --path=/sys/class/backlight/"$backlight_device"|grep DRIVERS|grep pwm-backlight)
#echo "PWM Backlight device is $pwm_backlight_device"
if [ -z "$pwm_backlight_device" ];
then 
  echo "Not found device"
  exit 1
fi 
echo "$backlight_device"

#!/bin/sh

VAR=`cat /proc/interrupts | grep 'timer' | awk -F '[:I]' '{print $2}' |awk '{print $1}' |head -1`
cat /proc/interrupts | grep 'timer'
echo $VAR
sleep 10
VAR10=`cat /proc/interrupts | grep 'timer' | awk -F '[:I]' '{print $2}'|awk '{print $1}' |head -1`
echo $VAR10
EXP=`zcat /proc/config.gz | grep 'CONFIG_HZ=' | awk -F '[:=]' '{print $2}'`
echo $EXP
EXP=`echo "($EXP * 10)" | bc` # Calculating expected ticks in 10 seconds
EXPPER=`echo "($EXP * 0.95)" | bc` #Calculating 95% of expected increase w/out Dynamic Ticks
EXPPER=${EXPPER%.*} # Convert to integer

ACTPER=$(($VAR10-$VAR))

echo "The difference is $ACTPER"

if [ $ACTPER -lt $EXPPER ]; then
   exit 0
fi
exit 1

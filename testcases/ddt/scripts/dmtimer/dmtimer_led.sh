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
# @desc LED helpers for the dmtimer. Only LEDs whose LED function (the part
# of the name after the last ':', e.g. heartbeat) starts with the given
# <led_function> are touched. Can be sourced to use the functions, or run
# with an action.
# @params check_leds | check_led_function <led_function> | set_function <led_function> <trigger> | set_brightness <led_function> | setup <led_function> <trigger> | verify <led_function> <trigger>

source "common.sh"

LEDS_DIR="/sys/class/leds"
TARGET_LEDS=()

############################# Functions #######################################
usage()
{
        echo "dmtimer_led.sh <action>"
        echo "  check_leds                           die if there are no LEDs on the board"
        echo "  check_led_function <lf>              die if no LED has an LED function starting with <lf>, e.g. heartbeat"
        echo "  set_function <lf> <trigger>          set the trigger of matching LEDs to <trigger>, e.g. none"
        echo "  set_brightness <lf>                  set the brightness of matching LEDs to 1"
        echo "  setup <lf> <trigger>                 check_leds, check_led_function, set_function, set_brightness"
        echo "  verify <lf> <trigger>                die unless matching LEDs still have <trigger> and brightness 1"
        exit 1
}

dmtimer_led_check_leds()
{
        local led
        for led in "$LEDS_DIR"/*; do
                [ -e "$led" ] && { echo "Found LED: ${led##*/}"; return 0; }
        done
        die "No LEDs found in $LEDS_DIR"
}

dmtimer_led_check_led_function()
{
        local led_function="$1" led name
        [ -n "$led_function" ] || die "an LED function name (e.g. heartbeat) is required"
        TARGET_LEDS=()
        for led in "$LEDS_DIR"/*; do
                [ -e "$led" ] || continue
                name=${led##*/}
                case "${name##*:}" in
                        "$led_function"*) TARGET_LEDS+=("$led"); echo "Found $led_function LED: $name" ;;
                esac
        done
        [ ${#TARGET_LEDS[@]} -gt 0 ] || die "No LED with a function starting with $led_function found"
}

dmtimer_led_set_function()
{
        local led_function="$1" trigger="$2" led
        [ -n "$trigger" ] || die "set_function requires a trigger name"
        dmtimer_led_check_led_function "$led_function"
        for led in "${TARGET_LEDS[@]}"; do
                grep -qw "$trigger" "$led/trigger" || die "${led##*/}: '$trigger' is not an available trigger: $(cat "$led/trigger")"
                do_cmd "echo $trigger > $led/trigger"
        done
}

dmtimer_led_set_brightness()
{
        local led_function="$1" led
        dmtimer_led_check_led_function "$led_function"
        for led in "${TARGET_LEDS[@]}"; do
                do_cmd "echo 1 > $led/brightness"
        done
}

dmtimer_led_setup()
{
        dmtimer_led_check_leds
        dmtimer_led_set_function "$1" "$2"
        dmtimer_led_set_brightness "$1"
}

dmtimer_led_verify()
{
        local led_function="$1" expected="$2" led name trigger brightness
        [ -n "$expected" ] || die "verify requires the expected trigger name"
        dmtimer_led_check_led_function "$led_function"
        for led in "${TARGET_LEDS[@]}"; do
                name=${led##*/}
                trigger=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$led/trigger")
                brightness=$(cat "$led/brightness")
                [ "$trigger" = "$expected" ] || die "$name: trigger is '$trigger', expected '$expected'"
                [ "$brightness" = "1" ] || die "$name: brightness is '$brightness', expected '1'"
                echo "$name: trigger=$expected brightness=1"
        done
}

########################### REUSABLE TEST LOGIC ###############################
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        case "$1" in
                check_leds)          dmtimer_led_check_leds ;;
                check_led_function)  dmtimer_led_check_led_function "$2" ;;
                set_function)        dmtimer_led_set_function "$2" "$3" ;;
                set_brightness)      dmtimer_led_set_brightness "$2" ;;
                setup)               dmtimer_led_setup "$2" "$3" ;;
                verify)              dmtimer_led_verify "$2" "$3" ;;
                *)                   usage ;;
        esac
fi

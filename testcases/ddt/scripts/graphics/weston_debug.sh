#!/bin/sh
#
# Copyright (C) 2019 Texas Instruments Incorporated - http://www.ti.com/
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

# Start weston in debug mode 
# Input: None
# Output: None

source "common.sh"

usage()
{
cat <<-EOF >&2
        usage: ./${0##*/} [-s START_OPTIONS]
        -s START_OPTIONS weston command line options --drm-device=.. --idle-time=.. ...
        -h Help         print this usage
EOF
exit 0
}

default_weston_options()
{
  case $MACHINE in
    j7*)
      echo "--idle-time=0 --backend=drm-backend.so"
    ;;
    *)
      echo "--idle-time=0"
    ;;
  esac
}

START_OPTIONS=$(default_weston_options)

OPTIND=1
while getopts :s: arg
    do case $arg in
            s)
                    START_OPTIONS=$OPTARG ;;
            \?)
                    echo "Invalid Option -$OPTARG ignored." >&2
                    usage
                    exit 1
                    ;;
    esac
done

stop_daemon emptty && sleep 3
unset WAYLAND_DISPLAY
weston --debug ${START_OPTIONS} &
sleep 3

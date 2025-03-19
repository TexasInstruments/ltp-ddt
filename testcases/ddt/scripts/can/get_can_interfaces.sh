#!/bin/sh

platform=$1

case $platform in
    j721e*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan0 main_mcan2"
        ;;
    j7200*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan3"
        ;;
    j721s2*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan3 main_mcan5 main_mcan16"
        ;;
    j784s4*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan4 main_mcan16"
        ;;
    j742s2*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan4 main_mcan16"
        ;;
    j722s*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan0"
        ;;
    am68*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan6 main_mcan7"
        ;;
    am69*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan6 main_mcan7"
        ;;
    am62p)
        candata="mcu_mcan0 mcu_mcan1 main_mcan0 main_mcan1"
        ;;
    am62*)
        candata="mcu_mcan0 mcu_mcan1 main_mcan0"
        ;;
    am64*)
        candata="main_mcan0 main_mcan1"
        ;;
    am65*)
        candata="mcu_mcan0 mcu_mcan1"
        ;;
    *)
        candata=""
        ;;
esac

echo "$candata"

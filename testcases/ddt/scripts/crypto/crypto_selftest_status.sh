#!/bin/bash
#
# Copyright (C) 2024 Texas Instruments Incorporated - https://www.ti.com/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation version 2.
#
# This program is distributed "as is" WITHOUT ANY WARRANTY of any
# kind, whether express or implied; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#

# crypto_selftest_status.sh
# Parses /proc/crypto and displays self-test status for all crypto algorithms
# Also shows the source of each algorithm (built-in, kernel module, hardware driver)
#
# Usage: crypto_selftest_status.sh [-v] [-f]
#   -v: Verbose output (show all fields)
#   -f: Filter to show only failed/unknown tests

source "common.sh"

PROC_CRYPTO="/proc/crypto"
VERBOSE=0
FILTER_FAILED=0

# Parse command line arguments
while getopts "vfh" opt; do
    case $opt in
        v) VERBOSE=1 ;;
        f) FILTER_FAILED=1 ;;
        h)
            echo "Usage: $0 [-v] [-f]"
            echo "  -v: Verbose output"
            echo "  -f: Filter to show only failed/unknown tests"
            exit 0
            ;;
        *) die "Invalid option: -$OPTARG" ;;
    esac
done

# Check if /proc/crypto exists
if [ ! -f "$PROC_CRYPTO" ]; then
    die "/proc/crypto not found. Crypto subsystem may not be available."
fi

# Check kernel config for crypto self-tests
# Returns: "<selftests>:<selftests_full>" where each is y/m/n/unknown
check_crypto_selftest_config() {
    local selftests_enabled="unknown"
    local selftests_full="unknown"
    local config_cmd=""

    # Determine how to read kernel config
    if [ -f /proc/config.gz ]; then
        config_cmd="zcat /proc/config.gz"
    elif [ -f "/boot/config-$(uname -r)" ]; then
        config_cmd="cat /boot/config-$(uname -r)"
    else
        test_print_wrg "Cannot find kernel config. Self-test status may be unreliable."
        echo "unknown:unknown"
        return
    fi

    # Check CONFIG_CRYPTO_SELFTESTS
    if $config_cmd | grep -q "CONFIG_CRYPTO_SELFTESTS=y"; then
        selftests_enabled="y"
    elif $config_cmd | grep -q "CONFIG_CRYPTO_SELFTESTS=m"; then
        selftests_enabled="m"
    elif $config_cmd | grep -q "# CONFIG_CRYPTO_SELFTESTS is not set"; then
        selftests_enabled="n"
    fi

    # Check CONFIG_CRYPTO_SELFTESTS_FULL
    if $config_cmd | grep -q "CONFIG_CRYPTO_SELFTESTS_FULL=y"; then
        selftests_full="y"
    elif $config_cmd | grep -q "# CONFIG_CRYPTO_SELFTESTS_FULL is not set"; then
        selftests_full="n"
    fi

    echo "${selftests_enabled}:${selftests_full}"
}

# Determine the source type of the crypto algorithm
# Returns: "built-in", "kernel-module:<name>", or "hardware:<driver-hint>"
get_algo_source() {
    local module="$1"
    local driver="$2"

    # Check if it's built into kernel
    if [ "$module" = "kernel" ]; then
        # Check if driver name suggests hardware acceleration
        # Common hardware driver patterns for TI platforms
        case "$driver" in
            *-omap*|*omap-*|*-sa2ul*|*sa2ul*|*-ce|*-neon|*-hw|*_hw|*-accel*)
                echo "hardware:$driver"
                return
                ;;
            *-generic|*_generic)
                echo "built-in:software"
                return
                ;;
            *)
                echo "built-in:$driver"
                return
                ;;
        esac
    else
        # It's a loadable module
        # Check if module name suggests hardware
        case "$module" in
            *omap*|*sa2ul*|*crypto_engine*|*caam*|*ccree*|*hisi*|*qce*|*sun*|*rockchip*)
                echo "hardware-module:$module"
                return
                ;;
            *)
                echo "kernel-module:$module"
                return
                ;;
        esac
    fi
}

# Parse /proc/crypto and display results
parse_proc_crypto() {
    local selftest_config="$1"
    local config_selftests="${selftest_config%%:*}"
    local config_full="${selftest_config##*:}"

    local name=""
    local driver=""
    local module=""
    local selftest=""
    local type=""
    local priority=""

    local total_count=0
    local passed_count=0
    local failed_count=0
    local unknown_count=0

    echo "============================================================"
    echo "        CRYPTO ALGORITHM SELF-TEST STATUS REPORT"
    echo "============================================================"
    echo ""
    echo "Kernel Config:"
    echo "  CONFIG_CRYPTO_SELFTESTS      : $config_selftests"
    echo "  CONFIG_CRYPTO_SELFTESTS_FULL : $config_full"
    echo ""

    if [ "$config_selftests" = "n" ] || [ "$config_selftests" = "unknown" ]; then
        test_print_wrg "Crypto self-tests not enabled in kernel config."
        test_print_wrg "Self-test results may show as 'unknown'."
        echo ""
    fi

    echo "------------------------------------------------------------"
    printf "%-30s %-12s %-25s %s\n" "ALGORITHM" "SELF-TEST" "SOURCE" "TYPE"
    echo "------------------------------------------------------------"

    # Read /proc/crypto line by line
    while IFS=: read -r key value; do
        # Trim whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        case "$key" in
            "name")
                name="$value"
                ;;
            "driver")
                driver="$value"
                ;;
            "module")
                module="$value"
                ;;
            "selftest")
                selftest="$value"
                ;;
            "type")
                type="$value"
                ;;
            "priority")
                priority="$value"
                ;;
            "")
                # Empty line marks end of an algorithm entry
                if [ -n "$name" ]; then
                    total_count=$((total_count + 1))

                    # Get source information
                    local source_info
                    source_info=$(get_algo_source "$module" "$driver")

                    # Count by status
                    case "$selftest" in
                        "passed")
                            passed_count=$((passed_count + 1))
                            ;;
                        "failed")
                            failed_count=$((failed_count + 1))
                            ;;
                        *)
                            unknown_count=$((unknown_count + 1))
                            ;;
                    esac

                    # Apply filter if requested
                    local show=1
                    if [ "$FILTER_FAILED" -eq 1 ]; then
                        if [ "$selftest" = "passed" ]; then
                            show=0
                        fi
                    fi

                    if [ "$show" -eq 1 ]; then
                        local status_display=""
                        case "$selftest" in
                            "passed")
                                status_display="PASSED"
                                ;;
                            "failed")
                                status_display="FAILED"
                                ;;
                            *)
                                status_display="UNKNOWN"
                                ;;
                        esac

                        printf "%-30s %-12s %-25s %s\n" "$name" "$status_display" "$source_info" "$type"

                        if [ "$VERBOSE" -eq 1 ]; then
                            echo "    Driver: $driver"
                            echo "    Module: $module"
                            echo "    Priority: $priority"
                            echo ""
                        fi
                    fi
                fi

                # Reset for next entry
                name=""
                driver=""
                module=""
                selftest=""
                type=""
                priority=""
                ;;
        esac
    done < "$PROC_CRYPTO"

    # Handle last entry if file doesn't end with empty line
    if [ -n "$name" ]; then
        total_count=$((total_count + 1))
        local source_info
        source_info=$(get_algo_source "$module" "$driver")

        case "$selftest" in
            "passed") passed_count=$((passed_count + 1)) ;;
            "failed") failed_count=$((failed_count + 1)) ;;
            *) unknown_count=$((unknown_count + 1)) ;;
        esac

        local show=1
        if [ "$FILTER_FAILED" -eq 1 ] && [ "$selftest" = "passed" ]; then
            show=0
        fi

        if [ "$show" -eq 1 ]; then
            local status_display=""
            case "$selftest" in
                "passed") status_display="PASSED" ;;
                "failed") status_display="FAILED" ;;
                *) status_display="UNKNOWN" ;;
            esac
            printf "%-30s %-12s %-25s %s\n" "$name" "$status_display" "$source_info" "$type"
        fi
    fi

    echo "------------------------------------------------------------"
    echo ""
    echo "SUMMARY:"
    echo "  Total Algorithms : $total_count"
    echo "  Passed           : $passed_count"
    echo "  Failed           : $failed_count"
    echo "  Unknown          : $unknown_count"
    echo ""

    # Return appropriate exit code
    if [ "$failed_count" -gt 0 ]; then
        test_print_err "Some crypto algorithms failed self-tests!"
        return 1
    elif [ "$unknown_count" -gt 0 ] && [ "$config_selftests" = "y" ]; then
        test_print_wrg "Some algorithms have unknown self-test status despite selftests being enabled."
        return 1 
    else
        test_print_trc "All crypto algorithms passed self-tests."
        return 0
    fi
}

# Main execution
test_print_trc "Starting crypto self-test status check..."

selftest_config=$(check_crypto_selftest_config)
parse_proc_crypto "$selftest_config"
exit_code=$?

exit $exit_code

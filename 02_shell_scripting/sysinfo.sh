#!/bin/bash
#
# sysinfo.sh - collects basic information about the machine it runs on.
#
# Author : Dhruv Davda (24BCS10203)
# Course : DevOps - Assignment 1, Shell Scripting
#
# The script prints a short report on the terminal, then stores a snapshot
# of the running processes inside a directory it creates itself.

set -u

REPORT_DIR="system_info"
PROCESS_LOG="$REPORT_DIR/process.log"

# --- a small helper so every section is printed the same way -------------
section() {
    echo ""
    echo "===================================================="
    echo " $1"
    echo "===================================================="
}

section "HOST"
echo "Hostname      : $(hostname)"
echo "Kernel        : $(uname -s) $(uname -r)"
echo "Architecture  : $(uname -m)"
echo "Current user  : $(whoami)"
echo "Date and time : $(date '+%Y-%m-%d %H:%M:%S')"

section "OPERATING SYSTEM"
if [ -f /etc/os-release ]; then
    # PRETTY_NAME is the human readable distribution name
    grep 'PRETTY_NAME' /etc/os-release | cut -d '"' -f 2
else
    echo "/etc/os-release not found on this system"
fi

section "UPTIME AND LOAD"
uptime

section "CPU"
if [ -f /proc/cpuinfo ]; then
    echo "Cores         : $(grep -c '^processor' /proc/cpuinfo)"
    # x86 exposes "model name", ARM exposes "Model" or only the implementer id,
    # so fall back through the options instead of printing an empty line.
    CPU_MODEL=$(grep -m 1 -E '^(model name|Model)[[:space:]]*:' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //')
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(grep -m 1 'CPU implementer' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //')
        [ -n "$CPU_MODEL" ] && CPU_MODEL="ARM implementer $CPU_MODEL ($(uname -m))"
    fi
    echo "Model         : ${CPU_MODEL:-not reported by this kernel}"
else
    echo "Cores         : $(nproc 2>/dev/null || echo unknown)"
    echo "Model         : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
fi

section "MEMORY"
free -h 2>/dev/null || echo "free is not available on this system"

section "DISK USAGE"
df -h / 2>/dev/null

section "TOP 5 PROCESSES BY MEMORY"
# --sort=-%mem puts the heaviest process first, head -6 keeps the header row
ps -eo pid,user,%cpu,%mem,comm --sort=-%mem 2>/dev/null | head -6

# --- store a full process snapshot on disk -------------------------------
if [ ! -d "$REPORT_DIR" ]; then
    mkdir -p "$REPORT_DIR"
    echo ""
    echo "Created directory: $REPORT_DIR"
fi

{
    echo "Process snapshot taken on $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo ""
    ps -ef
} > "$PROCESS_LOG"

echo "Saved process list to: $PROCESS_LOG ($(wc -l < "$PROCESS_LOG") lines)"
echo ""
echo "Report finished."

#!/bin/bash

# Ubuntu / Linux Server Health Check
# Read-only system information collection

set -u
export LC_ALL=C

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT="/tmp/${HOSTNAME}_health_${TIMESTAMP}.txt"

# Capture all report output in a file and display it on screen.
exec > >(tee "$REPORT") 2>&1

section() {
    echo
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

section "SERVER INFORMATION"
echo "Hostname       : $HOSTNAME"
echo "Date           : $(date)"
echo "Uptime         : $(uptime -p 2>/dev/null || uptime)"
echo "OS             : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Unknown}")"
echo "Kernel         : $(uname -r)"
echo "Architecture   : $(uname -m)"
echo "Logged-in user : $(whoami)"
echo "IP addresses   : $(hostname -I 2>/dev/null || echo N/A)"

section "CPU INFORMATION"
if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Thread|Core|Socket|CPU MHz):'
fi
echo
echo "Load average:"
uptime
echo
echo "CPU usage snapshot (1-second sample):"
if command -v mpstat >/dev/null 2>&1; then
    mpstat 1 1 | tail -n 1
elif command -v vmstat >/dev/null 2>&1; then
    vmstat 1 2 | tail -n 1
else
    echo "Install sysstat for mpstat; vmstat fallback shown above if available."
fi

section "MEMORY / RAM"
free -h
echo
echo "Swap usage:"
swapon --show 2>/dev/null || true

section "DISK SPACE"
df -hT -x tmpfs -x devtmpfs -x squashfs
echo
echo "Filesystems above 80% usage:"
df -P -x tmpfs -x devtmpfs -x squashfs |
awk 'NR > 1 {
    gsub(/%/, "", $5)
    if ($5 >= 80)
        printf "WARNING: %s is %s%% full (mounted on %s)\n", $6, $5, $6
}'

section "INODE USAGE"
df -ih -x tmpfs -x devtmpfs -x squashfs

section "BLOCK DEVICES"
if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
fi

section "TOP CPU-CONSUMING PROCESSES"
ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu | head -n 11

section "TOP MEMORY-CONSUMING PROCESSES"
ps -eo pid,ppid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n 11

section "NETWORK INFORMATION"
ip -brief address 2>/dev/null || ip addr
echo
echo "Listening TCP/UDP ports:"
if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>/dev/null | head -n 30
else
    echo "ss command not available"
fi

section "FAILED SYSTEMD SERVICES"
if command -v systemctl >/dev/null 2>&1; then
    systemctl --failed --no-pager 2>/dev/null || true
fi

section "RECENT SYSTEM ERRORS"
if command -v journalctl >/dev/null 2>&1; then
    journalctl -p err -n 20 --no-pager 2>/dev/null || true
else
    echo "journalctl not available"
fi

section "RECENT REBOOTS"
last -x reboot 2>/dev/null | head -n 5 || true

section "CHECK SUMMARY"
echo "CPU cores       : $(nproc 2>/dev/null || echo N/A)"
echo "Memory          : $(awk '/MemTotal/ {printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
echo "Root filesystem : $(df -hP / | awk 'NR==2 {print $5 " used, " $4 " available"}')"
echo
echo "Health report saved to: $REPORT"

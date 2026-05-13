#!/bin/bash

echo "=========================================="
echo "  Linux System Health Check"
echo "=========================================="
echo ""

echo "[1] CPU Usage:"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1 "%, Idle: " $1 "%"}'

echo ""
echo "[2] Memory Usage:"
free -h | grep Mem | awk '{print "Total: " $2 ", Used: " $3 ", Free: " $4 ", Used%: " $3/$2*100 "%"}'

echo ""
echo "[3] Disk Usage:"
df -h / | grep / | awk '{print "Mount: " $6 ", Total: " $2 ", Used: " $3 ", Free: " $4 ", Used%: " $5}'

echo ""
echo "[4] Load Average:"
uptime | awk '{print "1min: " $10 ", 5min: " $11 ", 15min: " $12}'

echo ""
echo "[5] Running Processes:"
echo "Total processes: $(ps aux | wc -l)"

echo ""
echo "[6] Network Status:"
echo "IP Address: $(hostname -I | awk '{print $1}')"

echo ""
echo "=========================================="
echo "  Health Check Completed"
echo "=========================================="
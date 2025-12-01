#!/bin/bash

# Configuration
# This file is shared between the Host (Windows) and Container (Linux)
METRICS_FILE="/data/real_metrics.txt"
REPORT_FILE="/data/system_report.html"

# Function: Get CPU Usage
# Logic: Reads the text file written by the Windows PowerShell script
get_cpu() {
    if [ -f "$METRICS_FILE" ]; then
        # File content format: CPU:15%|RAM:4GB/16GB
        # Cut splits by '|', takes 1st part. Sed removes "CPU:"
        cat "$METRICS_FILE" | cut -d'|' -f1 | sed 's/CPU://'
    else
        echo "Waiting for Host Data..."
    fi
}

# Function: Get RAM Usage
# Logic: Reads the text file written by the Windows PowerShell script
get_ram() {
    if [ -f "$METRICS_FILE" ]; then
        # Cut splits by '|', takes 2nd part. Sed removes "RAM:"
        cat "$METRICS_FILE" | cut -d'|' -f2 | sed 's/RAM://'
    else
        echo "0/0"
    fi
}

# Function: Get Network Usage
# Logic: Reads the text file written by the Windows PowerShell script
get_network() {
    if [ -f "$METRICS_FILE" ]; then
        # Cut splits by '|', takes 3rd part. Sed removes "NET:"
        # If the file doesn't have the 3rd part yet (old format), handle gracefully
        NET_DATA=$(cat "$METRICS_FILE" | cut -d'|' -f3)
        if [[ "$NET_DATA" == *"NET:"* ]]; then
            echo "$NET_DATA" | sed 's/NET://'
        else
            echo "Waiting for Data..."
        fi
    else
        echo "0 KB/s"
    fi
}

# Function: Get Disk Usage (C: Drive)
# Logic: Checks the specific mount point for the Windows C drive
get_disk() {
    # Check if the volume is mounted at /host_c (defined in docker-compose)
    if [ -d "/host_c" ]; then
        # df -h output usually looks like: Filesystem Size Used Avail Use% Mounted
        # We grab Size ($2), Used ($3), and Percentage ($5)
        df -h /host_c | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}'
    else
        echo "C: Drive Not Mounted"
    fi
}

# Function: Get GPU Usage
# Logic: Uses nvidia-smi command passed through from host
# Function: Get GPU Usage & Health
# Logic: Uses nvidia-smi command passed through from host
get_gpu() {
    # 1. Check if the command exists
    if command -v nvidia-smi &> /dev/null; then
        # 2. Try to run it. Hide errors (2> /dev/null) to prevent spam.
        # Query: Utilization, Temperature, Power Draw
        STATS=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2> /dev/null)
        
        # 3. Check if we got data back
        if [ -n "$STATS" ]; then
            # Format comes as: 15, 45, 25.5
            # We parse it to make it readable
            UTIL=$(echo "$STATS" | cut -d',' -f1)
            TEMP=$(echo "$STATS" | cut -d',' -f2)
            POWER=$(echo "$STATS" | cut -d',' -f3)
            echo "Load: ${UTIL}% | Temp: ${TEMP}°C | Power: ${POWER}W"
        else
            echo "Not Available (Check Driver/Container)"
        fi
    else
        echo "No GPU Tool Found"
    fi
}

# Function: Generate HTML Report
# Logic: Creates a simple webpage updated every cycle
generate_report() {
    echo "<html><head><title>System Monitor</title>" > $REPORT_FILE
    # Add auto-refresh every 3 seconds so you can watch it live in browser
    echo "<meta http-equiv='refresh' content='3'></head>" >> $REPORT_FILE
    echo "<body style='font-family: sans-serif; padding: 20px;'>" >> $REPORT_FILE
    echo "<h1>System Health Dashboard</h1>" >> $REPORT_FILE
    echo "<h3>Last Update: $(date '+%H:%M:%S')</h3>" >> $REPORT_FILE
    echo "<hr>" >> $REPORT_FILE
    echo "<ul>" >> $REPORT_FILE
    echo "<li><b>Real CPU Load:</b> $(get_cpu)</li>" >> $REPORT_FILE
    echo "<li><b>Real RAM Usage:</b> $(get_ram)</li>" >> $REPORT_FILE
    echo "<li><b>Network I/O:</b> $(get_network)</li>" >> $REPORT_FILE
    echo "<li><b>Disk (C:):</b> $(get_disk)</li>" >> $REPORT_FILE
    echo "<li><b>GPU Health:</b> $(get_gpu)</li>" >> $REPORT_FILE
    echo "</ul>" >> $REPORT_FILE
    echo "<p><i>Data provided by Hybrid Docker Agent</i></p>" >> $REPORT_FILE
    echo "</body></html>" >> $REPORT_FILE
}

# --- Main Execution Loop ---
echo "Starting Hybrid Monitor..."
echo "Reading metrics from: $METRICS_FILE"

while true; do
    # Print to the console (Docker Logs)
    echo "======================================"
    echo "Timestamp:  $(date '+%H:%M:%S')"
    echo "--------------------------------------"
    echo "Real CPU:   $(get_cpu)"
    echo "Real RAM:   $(get_ram)"
    echo "Network:    $(get_network)"
    echo "Disk (C:):  $(get_disk)"
    echo "Real GPU:   $(get_gpu)"
    echo "======================================"
    
    # Update the HTML file
    generate_report
    
    # Wait 2 seconds before next update
    sleep 2
done
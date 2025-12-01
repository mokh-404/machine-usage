#!/bin/bash

REPORT_FILE="/data/system_report.html"

# Function to safely get GPU
get_gpu() {
    # 1. Check if the command exists
    if command -v nvidia-smi &> /dev/null; then
        # 2. Try to run it. 
        # "2> /dev/null" sends the ugly error message to the trash (void)
        # We store the result in a variable
        USAGE=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2> /dev/null)
        
        # 3. Check if we got a number back (Success) or nothing (Failure)
        if [ -n "$USAGE" ]; then
            echo "${USAGE}%"
        else
            echo "Not Available (Driver Error)"
        fi
    else
        echo "No GPU Tool Found"
    fi
}

# Function to get Disk C: specifically
get_disk() {
    # We look at the mount point /host_c defined in docker-compose
    if [ -d "/host_c" ]; then
        # df -h output usually looks like: Filesystem Size Used Avail Use% Mounted
        # We grab the Size (2) and Used (3) and Percentage (5)
        df -h /host_c | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}'
    else
        echo "Mount Error (C: not found)"
    fi
}

get_cpu() {
    # Get the load of the Docker VM
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'
}

get_ram() {
    # Get the RAM allocated to Docker
    free -h | grep Mem | awk '{print $3 " / " $2}'
}

# Generate Report Function
generate_report() {
    echo "<html><body><h1>System Report</h1><ul>" > $REPORT_FILE
    echo "<li><b>Date:</b> $(date)</li>" >> $REPORT_FILE
    echo "<li><b>CPU (Docker VM):</b> $(get_cpu)</li>" >> $REPORT_FILE
    echo "<li><b>RAM (Docker VM):</b> $(get_ram)</li>" >> $REPORT_FILE
    echo "<li><b>Disk (Host C:):</b> $(get_disk)</li>" >> $REPORT_FILE
    echo "<li><b>GPU:</b> $(get_gpu)</li>" >> $REPORT_FILE
    echo "</ul></body></html>" >> $REPORT_FILE
}

# Main Loop - Removed 'clear' to fix TERM error
echo "Starting Monitoring..."
while true; do
    echo "======================================"
    echo "Timestamp:  $(date '+%H:%M:%S')"
    echo "--------------------------------------"
    echo "CPU Load:   $(get_cpu)"
    echo "RAM Usage:  $(get_ram)"
    echo "Disk (C:):  $(get_disk)"
    echo "GPU Usage:  $(get_gpu)"
    echo "======================================"
    
    generate_report
    sleep 3
done
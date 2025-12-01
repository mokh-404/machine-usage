#!/bin/bash
# dashboard.sh
# Docker Container Dashboard - Displays system metrics using Whiptail
# Reads metrics from shared /data/metrics.json file

METRICS_FILE="/data/metrics.json"
REFRESH_INTERVAL=2

# Colors for terminal (fallback if whiptail not available)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to parse JSON using jq (preferred) or fallback to grep
parse_json() {
    local json_file="$1"
    local key="$2"
    
    if [ ! -f "$json_file" ]; then
        echo ""
        return
    fi
    
    # Try jq first (installed in Dockerfile)
    if command -v jq &> /dev/null; then
        jq -r "$key" "$json_file" 2>/dev/null || echo ""
    else
        # Fallback: Simple JSON value extraction using grep
        case "$key" in
            ".cpu.percent")
                grep -o '"percent":[0-9.]*' "$json_file" | head -1 | cut -d':' -f2
                ;;
            ".ram.total_gb")
                grep -o '"total_gb":[0-9.]*' "$json_file" | head -1 | cut -d':' -f2
                ;;
            ".ram.used_gb")
                grep -o '"used_gb":[0-9.]*' "$json_file" | head -1 | cut -d':' -f2
                ;;
            ".ram.percent")
                grep -o '"percent":[0-9.]*' "$json_file" | head -2 | tail -1 | cut -d':' -f2
                ;;
            ".disk.total_gb")
                grep -o '"total_gb":[0-9.]*' "$json_file" | tail -1 | cut -d':' -f2
                ;;
            ".disk.used_gb")
                grep -o '"used_gb":[0-9.]*' "$json_file" | tail -1 | cut -d':' -f2
                ;;
            ".disk.percent")
                grep -o '"percent":[0-9.]*' "$json_file" | tail -1 | cut -d':' -f2
                ;;
            ".gpu.vendor")
                grep -o '"vendor":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".gpu.model")
                grep -o '"model":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".gpu.usage_percent")
                grep -o '"usage_percent":[0-9.]*' "$json_file" | cut -d':' -f2
                ;;
            ".gpu.status")
                grep -o '"status":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".timestamp")
                grep -o '"timestamp":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            *)
                echo ""
                ;;
        esac
    fi
}

# Function to get integer value (for whiptail gauge)
get_int() {
    local val="$1"
    if [ -z "$val" ] || [ "$val" = "" ]; then
        echo "0"
    else
        # Round to nearest integer
        echo "$val" | awk '{printf "%.0f", $1}'
    fi
}

# Function to format value with default
format_value() {
    local val="$1"
    local default="$2"
    if [ -z "$val" ] || [ "$val" = "" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

# Function to create progress bar
create_progress_bar() {
    local percent="$1"
    local width=50
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    printf "["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$percent"
}

# Function to display dashboard using whiptail
show_dashboard() {
    local cpu=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.percent")" "0")
    local ram_total=$(format_value "$(parse_json "$METRICS_FILE" ".ram.total_gb")" "0")
    local ram_used=$(format_value "$(parse_json "$METRICS_FILE" ".ram.used_gb")" "0")
    local ram_percent=$(format_value "$(parse_json "$METRICS_FILE" ".ram.percent")" "0")
    local disk_total=$(format_value "$(parse_json "$METRICS_FILE" ".disk.total_gb")" "0")
    local disk_used=$(format_value "$(parse_json "$METRICS_FILE" ".disk.used_gb")" "0")
    local disk_percent=$(format_value "$(parse_json "$METRICS_FILE" ".disk.percent")" "0")
    local gpu_vendor=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.vendor")" "Unknown")
    local gpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.model")" "Not Detected")
    local gpu_usage=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.usage_percent")" "0")
    local gpu_status=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.status")" "Not Available")
    local timestamp=$(format_value "$(parse_json "$METRICS_FILE" ".timestamp")" "Waiting...")
    
    # Convert to integers for progress bars
    local cpu_int=$(get_int "$cpu")
    local ram_int=$(get_int "$ram_percent")
    local disk_int=$(get_int "$disk_percent")
    local gpu_int=$(get_int "$gpu_usage")
    
    # Build info text with progress bars
    local info_text=""
    info_text+="═══════════════════════════════════════════════════════\n"
    info_text+="     SYSTEM MONITORING DASHBOARD\n"
    info_text+="═══════════════════════════════════════════════════════\n\n"
    info_text+="Last Update: $timestamp\n\n"
    info_text+="CPU Usage: ${cpu}%\n"
    info_text+="$(create_progress_bar $cpu_int)\n\n"
    info_text+="RAM: ${ram_used} GB / ${ram_total} GB (${ram_percent}%)\n"
    info_text+="$(create_progress_bar $ram_int)\n\n"
    info_text+="Disk: ${disk_used} GB / ${disk_total} GB (${disk_percent}%)\n"
    info_text+="$(create_progress_bar $disk_int)\n\n"
    info_text+="GPU: $gpu_vendor $gpu_model\n"
    if [ "$gpu_status" != "Not Available" ] && [ "$gpu_status" != "Not Detected" ]; then
        info_text+="GPU Usage: ${gpu_usage}% ($gpu_status)\n"
        info_text+="$(create_progress_bar $gpu_int)\n"
    else
        info_text+="GPU Status: $gpu_status\n"
    fi
    info_text+="\nPress Ctrl+C to exit"
    
    # Display using whiptail info box
    whiptail --title "System Monitor Dashboard" \
        --backtitle "Real-Time System Metrics" \
        --infobox "$info_text" \
        25 70 2>/dev/null || true
}

# Function to display simple text dashboard (fallback)
show_text_dashboard() {
    clear
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║     SYSTEM MONITORING DASHBOARD                      ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    if [ ! -f "$METRICS_FILE" ]; then
        echo "Waiting for host agent to provide metrics..."
        echo "Metrics file: $METRICS_FILE"
        sleep "$REFRESH_INTERVAL"
        return
    fi
    
    local cpu=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.percent")" "0")
    local ram_total=$(format_value "$(parse_json "$METRICS_FILE" ".ram.total_gb")" "0")
    local ram_used=$(format_value "$(parse_json "$METRICS_FILE" ".ram.used_gb")" "0")
    local ram_percent=$(format_value "$(parse_json "$METRICS_FILE" ".ram.percent")" "0")
    local disk_total=$(format_value "$(parse_json "$METRICS_FILE" ".disk.total_gb")" "0")
    local disk_used=$(format_value "$(parse_json "$METRICS_FILE" ".disk.used_gb")" "0")
    local disk_percent=$(format_value "$(parse_json "$METRICS_FILE" ".disk.percent")" "0")
    local gpu_vendor=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.vendor")" "Unknown")
    local gpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.model")" "Not Detected")
    local gpu_usage=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.usage_percent")" "0")
    local gpu_status=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.status")" "Not Available")
    local timestamp=$(format_value "$(parse_json "$METRICS_FILE" ".timestamp")" "Waiting...")
    
    local cpu_int=$(get_int "$cpu")
    local ram_int=$(get_int "$ram_percent")
    local disk_int=$(get_int "$disk_percent")
    local gpu_int=$(get_int "$gpu_usage")
    
    echo "Last Update: $timestamp"
    echo ""
    echo -e "CPU Usage:  ${GREEN}${cpu}%${NC}"
    echo "$(create_progress_bar $cpu_int)"
    echo ""
    echo -e "RAM Usage:  ${BLUE}${ram_used} GB / ${ram_total} GB${NC} (${ram_percent}%)"
    echo "$(create_progress_bar $ram_int)"
    echo ""
    echo -e "Disk Usage: ${YELLOW}${disk_used} GB / ${disk_total} GB${NC} (${disk_percent}%)"
    echo "$(create_progress_bar $disk_int)"
    echo ""
    echo "GPU:        ${gpu_vendor} ${gpu_model}"
    if [ "$gpu_status" != "Not Available" ] && [ "$gpu_status" != "Not Detected" ]; then
        echo -e "GPU Usage:  ${gpu_usage}% (${gpu_status})"
        echo "$(create_progress_bar $gpu_int)"
    else
        echo "GPU Status: $gpu_status"
    fi
    echo ""
    echo "Press Ctrl+C to exit"
}

# Main loop
echo "Starting System Monitor Dashboard..."
echo "Reading metrics from: $METRICS_FILE"
echo ""

# Check if whiptail is available and if we're in a TTY
if command -v whiptail &> /dev/null && [ -t 0 ]; then
    echo "Using Whiptail GUI mode"
    while true; do
        show_dashboard
        sleep "$REFRESH_INTERVAL"
    done
else
    echo "Using text mode (whiptail not available or not in TTY)"
    while true; do
        show_text_dashboard
        sleep "$REFRESH_INTERVAL"
    done
fi


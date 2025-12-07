#!/bin/bash
# dashboard.sh
# Docker Container Dashboard - Displays system metrics using Whiptail
# Reads metrics from shared /data/metrics.json file

if [ -f "/data/metrics.json" ]; then
    METRICS_FILE="/data/metrics.json"
else
    METRICS_FILE="./metrics/metrics.json"
fi
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
    # echo "DEBUG: key=$key file=$json_file" >> debug.log
    
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
            ".cpu.model")
                grep -o '"cpu_model_name":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".cpu.temperature_c")
                grep -o '"temperature_c":[0-9.]*' "$json_file" | cut -d':' -f2
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
            ".disk.smart_status")
                grep -o '"smart_status":"[^"]*"' "$json_file" | cut -d'"' -f4
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
            ".gpu.temperature_c")
                grep -o '"temperature_c":[0-9.]*' "$json_file" | cut -d':' -f2
                ;;
            ".gpu.power_w")
                grep -o '"power_w":[0-9.]*' "$json_file" | cut -d':' -f2
                ;;
            ".gpu.fan_speed_percent")
                grep -o '"fan_speed_percent":[0-9.]*' "$json_file" | cut -d':' -f2
                ;;
            ".network.total_kb_sec")
                grep -o '"total_kb_sec":[0-9.]*' "$json_file" | cut -d':' -f2
                ;;
            ".network.lan_speed")
                # Use sed for more robust extraction
                grep -o '"lan_speed":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".network.wifi_speed")
                grep -o '"wifi_speed":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".network.wifi_type")
                grep -o '"wifi_type":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".network.wifi_model")
                grep -o '"wifi_model":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".timestamp")
                grep -o '"timestamp":"[^"]*"' "$json_file" | cut -d'"' -f4
                ;;
            ".alerts")
                # Grep hack for array (very basic)
                grep -o '"alerts":\[[^]]*\]' "$json_file" | sed 's/"alerts":\[//;s/\]//'
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
# Function to display dashboard using whiptail
show_dashboard() {
    local cpu=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.percent")" "0")
    local cpu_temp=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.temperature_c")" "0")
    local ram_total=$(format_value "$(parse_json "$METRICS_FILE" ".ram.total_gb")" "0")
    local ram_used=$(format_value "$(parse_json "$METRICS_FILE" ".ram.used_gb")" "0")
    local ram_percent=$(format_value "$(parse_json "$METRICS_FILE" ".ram.percent")" "0")
    local smart_status=$(format_value "$(parse_json "$METRICS_FILE" ".disk.smart_status")" "Unknown")
    local gpu_vendor=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.vendor")" "Unknown")
    local gpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.model")" "Not Detected")
    local gpu_usage=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.usage_percent")" "0")
    local gpu_status=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.status")" "Not Available")
    local gpu_temp=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.temperature_c")" "0")
    local gpu_power=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.power_w")" "0")
    local gpu_fan=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.fan_speed_percent")" "0")
    local net_kb=$(format_value "$(parse_json "$METRICS_FILE" ".network.total_kb_sec")" "0")
    local lan_speed=$(format_value "$(parse_json "$METRICS_FILE" ".network.lan_speed")" "Not Connected")
    local wifi_speed=$(format_value "$(parse_json "$METRICS_FILE" ".network.wifi_speed")" "Not Connected")
    local wifi_type=$(format_value "$(parse_json "$METRICS_FILE" ".network.wifi_type")" "Unknown")
    local wifi_model=$(format_value "$(parse_json "$METRICS_FILE" ".network.wifi_model")" "")
    local timestamp=$(format_value "$(parse_json "$METRICS_FILE" ".timestamp")" "Waiting...")
    
    # Convert to integers for progress bars
    local cpu_int=$(get_int "$cpu")
    local ram_int=$(get_int "$ram_percent")
    local gpu_int=$(get_int "$gpu_usage")
    
    # Build info text with progress bars
    local info_text=""
    
    # Alerts Section (Top Priority)
    local alerts=""
    if command -v jq &> /dev/null; then
        local alert_type=$(jq -r '.alerts | type' "$METRICS_FILE" 2>/dev/null)
        
        if [ "$alert_type" == "array" ]; then
            local alert_count=$(jq '.alerts | length' "$METRICS_FILE" 2>/dev/null)
            for ((i=0; i<alert_count; i++)); do
                local msg=$(jq -r ".alerts[$i]" "$METRICS_FILE")
                alerts+="!!! $msg !!!\n"
            done
        elif [ "$alert_type" == "string" ]; then
            local msg=$(jq -r ".alerts" "$METRICS_FILE")
            alerts+="!!! $msg !!!\n"
        fi
    else
        # Fallback
        local raw_alerts=$(parse_json "$METRICS_FILE" ".alerts")
        if [ -n "$raw_alerts" ] && [ "$raw_alerts" != "" ]; then
             # Remove quotes and split by comma
             IFS=',' read -ra ADDR <<< "$raw_alerts"
             for i in "${!ADDR[@]}"; do
                 local msg=$(echo "${ADDR[$i]}" | sed 's/"//g')
                 if [ -n "$msg" ]; then
                    alerts+="!!! $msg !!!\n"
                 fi
             done
        fi
    fi
    
    if [ -n "$alerts" ]; then
        info_text+="\n$alerts\n"
    fi

    info_text+="═══════════════════════════════════════════════════════\n"
    info_text+="     SYSTEM MONITORING DASHBOARD\n"
    info_text+="═══════════════════════════════════════════════════════\n\n"
    info_text+="Last Update: $timestamp\n"
    
    # History check
    local history_file="${METRICS_FILE%/*}/history.csv"
    local history_count=0
    if [ -f "$history_file" ]; then
        history_count=$(wc -l < "$history_file")
        # Subtract header
        if [ "$history_count" -gt 0 ]; then history_count=$((history_count - 1)); fi
    fi
    info_text+="History Points: $history_count\n\n"
    
    local cpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.model")" "Unknown CPU")
    info_text+="CPU: $cpu_model\n"
    info_text+="Usage: ${cpu}% (${cpu_temp}°C)\n"
    info_text+="$(create_progress_bar $cpu_int)\n\n"
    info_text+="RAM: ${ram_used} GB / ${ram_total} GB (${ram_percent}%)\n"
    info_text+="$(create_progress_bar $ram_int)\n\n"
    
    # Disk Section (Multi-Disk)
    info_text+="Disks (SMART: $smart_status):\n"
    
    # Extract disk info
    # We need to handle array parsing carefully without jq if possible, but assuming jq is available for complex structures
    # or using grep hack for now
    if command -v jq &> /dev/null; then
        # Use jq to iterate
        local drive_count=$(jq '.disk.drives | length' "$METRICS_FILE" 2>/dev/null)
        if [ -z "$drive_count" ]; then drive_count=0; fi
        
        for ((i=0; i<drive_count; i++)); do
            local name=$(jq -r ".disk.drives[$i].Name" "$METRICS_FILE")
            local used=$(jq -r ".disk.drives[$i].Used" "$METRICS_FILE")
            local total=$(jq -r ".disk.drives[$i].Total" "$METRICS_FILE")
            local percent=$(jq -r ".disk.drives[$i].Percent" "$METRICS_FILE")
            local percent_int=$(get_int "$percent")
            
            info_text+="$name ${used}GB/${total}GB ($percent%)\n"
            info_text+="$(create_progress_bar $percent_int)\n"
        done
    else
        # Fallback using grep/cut for simple array extraction (assumes compressed JSON)
        # This is a bit fragile but works for the specific format
        local names=$(grep -o '"Name":"[^"]*"' "$METRICS_FILE" | cut -d'"' -f4)
        local useds=$(grep -o '"Used":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        local totals=$(grep -o '"Total":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        local percents=$(grep -o '"Percent":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        
        # Convert to arrays
        IFS=$'\n' read -rd '' -a name_arr <<< "$names"
        IFS=$'\n' read -rd '' -a used_arr <<< "$useds"
        IFS=$'\n' read -rd '' -a total_arr <<< "$totals"
        IFS=$'\n' read -rd '' -a percent_arr <<< "$percents"
        
        for ((i=0; i<${#name_arr[@]}; i++)); do
            local percent_int=$(get_int "${percent_arr[$i]}")
            info_text+="${name_arr[$i]} ${used_arr[$i]}GB/${total_arr[$i]}GB (${percent_arr[$i]}%)\n"
            info_text+="$(create_progress_bar $percent_int)\n"
        done
    fi
    info_text+="\n"

    info_text+="Network I/O: ${net_kb} KB/s\n"
    info_text+="LAN Speed: ${lan_speed}\n"
    if [ "$wifi_speed" != "Not Connected" ]; then
        info_text+="WiFi: ${wifi_speed} (${wifi_type})\n"
        if [ "$wifi_model" != "" ]; then
            info_text+="      $wifi_model\n"
        fi
    fi
    info_text+="\n"
    info_text+="GPU: $gpu_vendor $gpu_model\n"
    if [ "$gpu_status" != "Not Available" ] && [ "$gpu_status" != "Not Detected" ]; then
        info_text+="GPU Usage: ${gpu_usage}% ($gpu_status)\n"
        info_text+="$(create_progress_bar $gpu_int)\n"
        info_text+="Temp: ${gpu_temp}°C | Power: ${gpu_power}W | Fan: ${gpu_fan}%\n"
    else
        info_text+="GPU Status: $gpu_status\n"
    fi
    info_text+="\nPress Ctrl+C to exit"
    
    # Display using whiptail info box
    whiptail --title "System Monitor Dashboard" \
        --backtitle "Real-Time System Metrics" \
        --infobox "$info_text" \
        25 76 2>/dev/null || true
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
    local cpu_temp=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.temperature_c")" "0")
    local ram_total=$(format_value "$(parse_json "$METRICS_FILE" ".ram.total_gb")" "0")
    local ram_used=$(format_value "$(parse_json "$METRICS_FILE" ".ram.used_gb")" "0")
    local ram_percent=$(format_value "$(parse_json "$METRICS_FILE" ".ram.percent")" "0")
    local disk_total=$(format_value "$(parse_json "$METRICS_FILE" ".disk.total_gb")" "0")
    local disk_used=$(format_value "$(parse_json "$METRICS_FILE" ".disk.used_gb")" "0")
    local disk_percent=$(format_value "$(parse_json "$METRICS_FILE" ".disk.percent")" "0")
    local smart_status=$(format_value "$(parse_json "$METRICS_FILE" ".disk.smart_status")" "Unknown")
    local gpu_vendor=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.vendor")" "Unknown")
    local gpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.model")" "Not Detected")
    local gpu_usage=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.usage_percent")" "0")
    local gpu_status=$(format_value "$(parse_json "$METRICS_FILE" ".gpu.status")" "Not Available")
    local net_kb=$(format_value "$(parse_json "$METRICS_FILE" ".network.total_kb_sec")" "0")
    local lan_speed=$(format_value "$(parse_json "$METRICS_FILE" ".network.lan_speed")" "Not Connected")
    local wifi_speed=$(format_value "$(parse_json "$METRICS_FILE" ".network.wifi_speed")" "Not Connected")
    local wifi_type=$(format_value "$(parse_json "$METRICS_FILE" ".network.wifi_type")" "Unknown")
    local timestamp=$(format_value "$(parse_json "$METRICS_FILE" ".timestamp")" "Waiting...")
    
    local cpu_int=$(get_int "$cpu")
    local ram_int=$(get_int "$ram_percent")
    local gpu_int=$(get_int "$gpu_usage")
    
    echo "Last Update: $timestamp"
    
    # Alerts Section
    local alerts=""
    if command -v jq &> /dev/null; then
        local alert_type=$(jq -r '.alerts | type' "$METRICS_FILE" 2>/dev/null)
        
        if [ "$alert_type" == "array" ]; then
            local alert_count=$(jq '.alerts | length' "$METRICS_FILE" 2>/dev/null)
            if [ -n "$alert_count" ] && [ "$alert_count" -gt 0 ]; then
                echo ""
                echo -e "${RED}!!! CRITICAL ALERTS !!!${NC}"
                for ((i=0; i<alert_count; i++)); do
                    local msg=$(jq -r ".alerts[$i]" "$METRICS_FILE")
                    echo -e "${RED}$msg${NC}"
                done
                echo ""
            fi
        elif [ "$alert_type" == "string" ]; then
            local msg=$(jq -r ".alerts" "$METRICS_FILE")
            echo ""
            echo -e "${RED}!!! CRITICAL ALERTS !!!${NC}"
            echo -e "${RED}$msg${NC}"
            echo ""
        fi
    else
        local raw_alerts=$(parse_json "$METRICS_FILE" ".alerts")
        if [ -n "$raw_alerts" ] && [ "$raw_alerts" != "" ]; then
             echo ""
             echo -e "${RED}!!! CRITICAL ALERTS !!!${NC}"
             IFS=',' read -ra ADDR <<< "$raw_alerts"
             for i in "${!ADDR[@]}"; do
                 local msg=$(echo "${ADDR[$i]}" | sed 's/"//g')
                 if [ -n "$msg" ]; then
                    echo -e "${RED}$msg${NC}"
                 fi
             done
             echo ""
        fi
    fi
    
    # History check
    local history_file="${METRICS_FILE%/*}/history.csv"
    local history_count=0
    if [ -f "$history_file" ]; then
        history_count=$(wc -l < "$history_file")
        if [ "$history_count" -gt 0 ]; then history_count=$((history_count - 1)); fi
    fi
    echo "History Points: $history_count"
    echo ""
    local cpu_model=$(format_value "$(parse_json "$METRICS_FILE" ".cpu.model")" "Unknown CPU")
    echo "CPU:        $cpu_model"
    echo -e "Usage:      ${GREEN}${cpu}%${NC} (${cpu_temp}°C)"
    echo "$(create_progress_bar $cpu_int)"
    echo ""
    echo -e "RAM Usage:  ${BLUE}${ram_used} GB / ${ram_total} GB${NC} (${ram_percent}%)"
    echo "$(create_progress_bar $ram_int)"
    echo ""
    echo "Disks (SMART: $smart_status):"
    
    # Extract disk info (same logic as above)
    if command -v jq &> /dev/null; then
        local drive_count=$(jq '.disk.drives | length' "$METRICS_FILE" 2>/dev/null)
        if [ -z "$drive_count" ]; then drive_count=0; fi
        
        for ((i=0; i<drive_count; i++)); do
            local name=$(jq -r ".disk.drives[$i].Name" "$METRICS_FILE")
            local used=$(jq -r ".disk.drives[$i].Used" "$METRICS_FILE")
            local total=$(jq -r ".disk.drives[$i].Total" "$METRICS_FILE")
            local percent=$(jq -r ".disk.drives[$i].Percent" "$METRICS_FILE")
            local percent_int=$(get_int "$percent")
            
            echo -e "${YELLOW}${name} ${used}GB/${total}GB${NC} (${percent}%)"
            echo "$(create_progress_bar $percent_int)"
        done
    else
        local names=$(grep -o '"Name":"[^"]*"' "$METRICS_FILE" | cut -d'"' -f4)
        local useds=$(grep -o '"Used":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        local totals=$(grep -o '"Total":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        local percents=$(grep -o '"Percent":[0-9.]*' "$METRICS_FILE" | cut -d':' -f2)
        
        IFS=$'\n' read -rd '' -a name_arr <<< "$names"
        IFS=$'\n' read -rd '' -a used_arr <<< "$useds"
        IFS=$'\n' read -rd '' -a total_arr <<< "$totals"
        IFS=$'\n' read -rd '' -a percent_arr <<< "$percents"
        
        for ((i=0; i<${#name_arr[@]}; i++)); do
            local percent_int=$(get_int "${percent_arr[$i]}")
            echo -e "${YELLOW}${name_arr[$i]} ${used_arr[$i]}GB/${total_arr[$i]}GB${NC} (${percent_arr[$i]}%)"
            echo "$(create_progress_bar $percent_int)"
        done
    fi
    echo ""
    echo -e "Network I/O: ${net_kb} KB/s"
    echo -e "LAN Speed:   ${lan_speed}"
    if [ "$wifi_speed" != "Not Connected" ]; then
        echo -e "WiFi:        ${wifi_speed} (${wifi_type})"
    fi
    echo ""
    echo "GPU:        ${gpu_vendor} ${gpu_model}"
    if [ "$gpu_status" != "Not Available" ] && [ "$gpu_status" != "Not Detected" ]; then
        echo -e "GPU Usage:  ${gpu_usage}% (${gpu_status})"
        echo "$(create_progress_bar $gpu_int)"
        echo -e "GPU Health: Temp: ${gpu_temp}°C | Power: ${gpu_power}W | Fan: ${gpu_fan}%"
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
# Determine Mode
if [ -t 0 ] && [ "$FORCE_GUI" == "1" ] && command -v whiptail &> /dev/null; then
    # Interactive GUI
    export TERM=xterm-256color
    echo "Using Whiptail GUI mode"
    MODE_FUNC="show_dashboard"
elif [ -t 0 ]; then
    # Interactive Text
    echo "Using Text Mode (More reliable for Windows)"
    MODE_FUNC="show_text_dashboard"
else
    # Background
    echo "============================================================"
    echo " System Monitor Dashboard is Running"
    echo "============================================================"
    echo "Mode: Background / Non-Interactive"
    echo ""
    echo "To view the dashboard, please attach to the container:"
    echo "  docker attach system-monitor-dashboard"
    echo ""
    MODE_FUNC="background_loop"
fi

if [ "$MODE_FUNC" == "background_loop" ]; then
    while true; do
        if [ -f "$METRICS_FILE" ]; then
            timestamp=$(parse_json "$METRICS_FILE" ".timestamp")
            echo "[$timestamp] System Monitor Active - Metrics Updated"
        else
            echo "Waiting for metrics..."
        fi
        sleep 10
    done
else
    # Run the selected interactive function
    sleep 1
    while true; do
        $MODE_FUNC
        sleep "$REFRESH_INTERVAL"
    done
fi


#!/bin/bash
# host_agent_unix.sh
# Unix/Linux/macOS Host Agent - Collects Real Physical System Metrics
# Writes to shared metrics.json file for Docker container consumption

METRICS_FILE="${1:-./metrics/metrics.json}"
INTERVAL="${2:-2}"

# Ensure metrics directory exists
METRICS_DIR=$(dirname "$METRICS_FILE")
mkdir -p "$METRICS_DIR"

echo "Unix Host Agent Started"
echo "Metrics file: $METRICS_FILE"
echo "Update interval: ${INTERVAL} seconds"
echo "Press Ctrl+C to stop"
echo ""

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Linux"
    else
        echo "Unknown"
    fi
}

OS_TYPE=$(detect_os)

# Function to calculate with bc or awk fallback
calc() {
    local expr="$1"
    if command -v bc &> /dev/null; then
        echo "$expr" | bc
    else
        # Fallback to awk for basic calculations
        awk "BEGIN {printf \"%.2f\", $expr}"
    fi
}

# Function to get CPU Model
get_cpu_model() {
    if [[ "$OS_TYPE" == "Linux" ]]; then
        local model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
        echo "${model:-Unknown CPU}"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        local model=$(sysctl -n machdep.cpu.brand_string)
        echo "${model:-Unknown CPU}"
    else
        echo "Unknown CPU"
    fi
}

# Function to get CPU Temperature
get_cpu_temp() {
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Try to find a valid thermal zone
        # Prioritize x86_pkg_temp (package temperature)
        local temp_path=$(grep -l "x86_pkg_temp" /sys/class/thermal/thermal_zone*/type 2>/dev/null | sed 's/type/temp/')
        
        if [ -z "$temp_path" ]; then
            # Fallback to first thermal zone
            temp_path="/sys/class/thermal/thermal_zone0/temp"
        fi
        
        if [ -f "$temp_path" ]; then
            local temp_millideg=$(cat "$temp_path")
            # Convert to degrees Celsius
            calc "$temp_millideg / 1000"
        else
            echo "0"
        fi
    else
        # macOS requires sudo/powermetrics, return 0 for now
        echo "0"
    fi
}

# Function to get CPU usage (works on both Linux and macOS)
get_cpu_usage() {
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux: Use /proc/stat
        local cpu_line=$(grep '^cpu ' /proc/stat)
        local idle=$(echo $cpu_line | awk '{print $5}')
        local total=0
        for val in $cpu_line; do
            total=$((total + val))
        done
        
        # Calculate percentage (simplified, for more accuracy need previous values)
        if [ -f /tmp/cpu_prev ]; then
            local prev=$(cat /tmp/cpu_prev)
            local diff=$((total - prev))
            local idle_diff=$((idle - $(echo $prev | awk '{print $5}')))
            if [ $diff -gt 0 ]; then
                local usage=$((100 - (idle_diff * 100 / diff)))
                echo "$usage"
            else
                echo "0"
            fi
        else
            echo "0"
        fi
        echo "$cpu_line" > /tmp/cpu_prev
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        # macOS: Use top command
        local usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
        echo "${usage:-0}"
    else
        echo "0"
    fi
}

# Function to get RAM usage
get_ram_usage() {
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux: Parse /proc/meminfo
        local total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        if [ -z "$free_kb" ]; then
            free_kb=$(grep MemFree /proc/meminfo | awk '{print $2}')
        fi
        local total_gb=$(calc "$total_kb / 1024 / 1024")
        local free_gb=$(calc "$free_kb / 1024 / 1024")
        local used_gb=$(calc "$total_gb - $free_gb")
        local percent=$(calc "($used_gb / $total_gb) * 100")
        echo "$used_gb|$total_gb|$free_gb|$percent"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        # macOS: Use vm_stat
        local total_bytes=$(sysctl -n hw.memsize)
        local total_gb=$(calc "$total_bytes / 1024 / 1024 / 1024")
        
        local vm_stat=$(vm_stat)
        local free_pages=$(echo "$vm_stat" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local inactive_pages=$(echo "$vm_stat" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local page_size=$(sysctl -n vm.page_size)
        local free_bytes=$((free_pages * page_size))
        local free_gb=$(calc "$free_bytes / 1024 / 1024 / 1024")
        local used_gb=$(calc "$total_gb - $free_gb")
        local percent=$(calc "($used_gb / $total_gb) * 100")
        echo "$used_gb|$total_gb|$free_gb|$percent"
    else
        echo "0|0|0|0"
    fi
}

# Function to get Disk usage
# Function to get Disk usage (Multi-disk)
# Function to get Disk usage (Multi-disk)
get_disk_usage() {
    local drives=""
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux: Use df, exclude pseudo-filesystems
        # Output format: Size Used Avail Use% Mounted
        # We use -P for portability (no line breaks) and -B G for Gigabytes
        while read -r line; do
            local total=$(echo "$line" | awk '{print $2}' | sed 's/G//')
            local used=$(echo "$line" | awk '{print $3}' | sed 's/G//')
            local free=$(echo "$line" | awk '{print $4}' | sed 's/G//')
            local percent=$(echo "$line" | awk '{print $5}' | sed 's/%//')
            local mount=$(echo "$line" | awk '{print $6}')
            local device=$(echo "$line" | awk '{print $1}')
            
            # Determine Disk Type (SSD/HDD)
            local type="Unknown"
            
            # Try to resolve device to block name (e.g., /dev/sda1 -> sda)
            if [[ "$device" == "/dev/"* ]]; then
                local dev_name=$(basename "$device")
                # Remove partition digits (sda1 -> sda, nvme0n1p1 -> nvme0n1)
                local parent_dev=$(lsblk -no pkname "/dev/$dev_name" 2>/dev/null)
                if [ -z "$parent_dev" ]; then
                     # Fallback regex if lsblk fails or returns empty
                     parent_dev=$(echo "$dev_name" | sed 's/[0-9]*$//')
                fi
                
                # Check rotational status in /sys/block
                if [ -f "/sys/block/$parent_dev/queue/rotational" ]; then
                    local rota=$(cat "/sys/block/$parent_dev/queue/rotational")
                    if [ "$rota" -eq 0 ]; then
                        type="SSD"
                    elif [ "$rota" -eq 1 ]; then
                        type="HDD"
                    fi
                elif [ -f "/sys/block/$dev_name/queue/rotational" ]; then
                     # Sometimes the partition itself might be listed (rare)
                    local rota=$(cat "/sys/block/$dev_name/queue/rotational")
                    if [ "$rota" -eq 0 ]; then
                        type="SSD"
                    elif [ "$rota" -eq 1 ]; then
                        type="HDD"
                    fi
                else
                    # Fallback to lsblk
                    local rota=$(lsblk -d -o rota "/dev/$parent_dev" 2>/dev/null | tail -1)
                    if [ "$rota" == "0" ]; then
                        type="SSD"
                    elif [ "$rota" == "1" ]; then
                        type="HDD"
                    fi
                fi
            fi
            
            if [ -n "$drives" ]; then drives="${drives};"; fi
            drives="${drives}${mount},${used},${total},${percent},${type}"
        done < <(df -BG -P | grep -vE '^Filesystem|tmpfs|devtmpfs|overlay|none|udev|run|shm')
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        # macOS
        while read -r line; do
            local total=$(echo "$line" | awk '{print $2}' | sed 's/Gi//')
            local used=$(echo "$line" | awk '{print $3}' | sed 's/Gi//')
            local free=$(echo "$line" | awk '{print $4}' | sed 's/Gi//')
            local percent=$(echo "$line" | awk '{print $5}' | sed 's/%//')
            local mount=$(echo "$line" | awk '{print $9}')
            
            # macOS disk type detection is complex, defaulting to SSD for now as most Macs are SSD
            local type="SSD"
            # Attempt to check system_profiler (slow, so maybe skip or cache)
            # For now, we'll leave it as "SSD" or "Unknown" to match Windows "Unknown" fallback
            
            if [ -n "$drives" ]; then drives="${drives};"; fi
            drives="${drives}${mount},${used},${total},${percent},${type}"
        done < <(df -g | grep -vE '^Filesystem|devfs|map|com.apple')
    fi
    echo "$drives"
}

# Function to get SMART Status
get_smart_status() {
    if ! command -v smartctl &> /dev/null; then
        echo "Unknown (smartctl missing)"
        return
    fi
    
    local healthy_count=0
    local unhealthy_count=0
    
    # Scan for devices (requires permissions, might fail if not root)
    local devices=$(smartctl --scan 2>/dev/null | awk '{print $1}')
    
    if [ -z "$devices" ]; then
        echo "Unknown (No devices found/Permission denied)"
        return
    fi
    
    for dev in $devices; do
        local health=$(smartctl -H "$dev" 2>/dev/null | grep "result" | awk '{print $NF}')
        if [ "$health" == "PASSED" ] || [ "$health" == "OK" ]; then
            ((healthy_count++))
        else
            ((unhealthy_count++))
        fi
    done
    
    if [ $unhealthy_count -gt 0 ]; then
        echo "Warning ($unhealthy_count Unhealthy)"
    else
        echo "Healthy ($healthy_count Drives)"
    fi
}

# Function to get Network usage (Total KB/s)
get_network_usage() {
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Linux: Read /proc/net/dev
        # Get sum of bytes for all non-loopback interfaces
        local curr_bytes=$(awk '/:/ {if ($1 !~ /lo/) sum+=$2+$10} END {print sum}' /proc/net/dev)
        
        if [ -f /tmp/net_prev ]; then
            local prev_bytes=$(cat /tmp/net_prev)
            local diff_bytes=$((curr_bytes - prev_bytes))
            
            # Handle counter wrap-around or restart
            if [ $diff_bytes -lt 0 ]; then
                diff_bytes=0
            fi
            
            # Calculate KB/s (assuming INTERVAL seconds)
            local kb_sec=$(calc "$diff_bytes / 1024 / $INTERVAL")
            echo "$kb_sec"
        else
            echo "0"
        fi
        echo "$curr_bytes" > /tmp/net_prev
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        # macOS: Use netstat
        local curr_bytes=$(netstat -ib | grep -v "lo0" | grep "Link#" | awk '{sum+=$7+$10} END {print sum}')
        
        if [ -f /tmp/net_prev ]; then
            local prev_bytes=$(cat /tmp/net_prev)
            local diff_bytes=$((curr_bytes - prev_bytes))
            
            if [ $diff_bytes -lt 0 ]; then
                diff_bytes=0
            fi
            
            local kb_sec=$(calc "$diff_bytes / 1024 / $INTERVAL")
            echo "$kb_sec"
        else
            echo "0"
        fi
        echo "$curr_bytes" > /tmp/net_prev
    else
        echo "0"
    fi
}

# Function to get Network Details (LAN Speed, WiFi Info)
get_network_details() {
    local lan_speed="Not Connected"
    local wifi_speed="Not Connected"
    local wifi_type="Unknown"
    local wifi_model="Unknown"
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        # Find default interface
        local default_iface=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
        
        if [ -n "$default_iface" ]; then
            # Check if it's wireless
            if [ -d "/sys/class/net/$default_iface/wireless" ] || [ -e "/proc/net/wireless" ] && grep -q "$default_iface" /proc/net/wireless; then
                # WiFi
                if command -v iwconfig &> /dev/null; then
                    local iw_out=$(iwconfig "$default_iface" 2>/dev/null)
                    wifi_speed=$(echo "$iw_out" | grep "Bit Rate" | awk -F'=' '{print $2}' | awk '{print $1 " " $2}')
                    wifi_type="802.11" # Generic, hard to get specific generation without 'iw'
                    if [[ "$iw_out" == *"IEEE 802.11"* ]]; then
                         wifi_type=$(echo "$iw_out" | grep -o "IEEE 802.11[^ ]*")
                    fi
                fi
                # Try to get model from lspci or lsusb
                # Simplified: just say "Wireless Interface"
                wifi_model="Wireless Interface ($default_iface)"
            else
                # Wired
                if [ -f "/sys/class/net/$default_iface/speed" ]; then
                    local speed=$(cat "/sys/class/net/$default_iface/speed" 2>/dev/null)
                    if [ -n "$speed" ]; then
                        lan_speed="${speed} Mbps"
                    fi
                fi
            fi
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        # macOS WiFi
        local wifi_info=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null)
        if [ -n "$wifi_info" ] && echo "$wifi_info" | grep -q "SSID"; then
             local rate=$(echo "$wifi_info" | grep "lastTxRate" | awk '{print $2}')
             wifi_speed="${rate} Mbps"
             wifi_type="802.11"
             wifi_model="AirPort"
        else
             # Wired check (simplified)
             lan_speed="Unknown (macOS)"
        fi
    fi
    
    echo "$lan_speed|$wifi_speed|$wifi_type|$wifi_model"
}

# Function to detect and get GPU info
get_gpu_info() {
    local vendor="Unknown"
    local model="Not Detected"
    local usage=0
    local memory_used=0
    local memory_total=0
    local temperature=0
    local status="Not Available"
    
    # Try NVIDIA first
    if command -v nvidia-smi &> /dev/null; then
        # Use CSV format and parse carefully (GPU name might contain commas)
        local nvidia_output=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
        if [ -n "$nvidia_output" ] && [ "$nvidia_output" != "" ]; then
            vendor="NVIDIA"
            # Parse CSV - handle potential commas in GPU name by using awk
            model=$(echo "$nvidia_output" | awk -F', ' '{for(i=1;i<NF-4;i++){if(i>1)printf ", "; printf "%s", $i}}')
            if [ -z "$model" ]; then
                # Fallback: simple cut if awk fails
                model=$(echo "$nvidia_output" | cut -d',' -f1 | xargs)
            fi
            # Get the last 4 fields (usage, mem_used, mem_total, temp)
            usage=$(echo "$nvidia_output" | awk -F', ' '{print $(NF-3)}' | xargs)
            local mem_used_mb=$(echo "$nvidia_output" | awk -F', ' '{print $(NF-2)}' | xargs)
            local mem_total_mb=$(echo "$nvidia_output" | awk -F', ' '{print $(NF-1)}' | xargs)
            temperature=$(echo "$nvidia_output" | awk -F', ' '{print $NF}' | xargs)
            
            # Validate we got numbers
            if [ -n "$usage" ] && [ "$usage" -ge 0 ] 2>/dev/null; then
                memory_used=$(calc "$mem_used_mb / 1024" 2>/dev/null || echo "0")
                memory_total=$(calc "$mem_total_mb / 1024" 2>/dev/null || echo "0")
                status="Active"
                echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
                return
            fi
        fi
    fi
    
    # Try AMD (ROCm)
    if command -v rocm-smi &> /dev/null; then
        local amd_output=$(rocm-smi --showid --showtemp --showuse --showmemuse --showmeminfo vram 2>/dev/null)
        if [ -n "$amd_output" ]; then
            vendor="AMD"
            # Try to extract GPU name
            model=$(echo "$amd_output" | grep -i "card\|device" | head -1 | awk -F: '{print $NF}' | xargs || echo "AMD GPU")
            # Extract GPU usage percentage
            usage=$(echo "$amd_output" | grep -i "GPU use\|utilization" | head -1 | awk '{print $NF}' | sed 's/%//' || echo "0")
            # Extract memory usage (in MB, convert to GB)
            local mem_line=$(echo "$amd_output" | grep -i "memory use\|vram" | head -1)
            if [ -n "$mem_line" ]; then
                local mem_used_mb=$(echo "$mem_line" | grep -oE '[0-9]+' | head -1)
                if [ -n "$mem_used_mb" ]; then
                    memory_used=$(calc "$mem_used_mb / 1024")
                fi
            fi
            # Extract temperature
            temperature=$(echo "$amd_output" | grep -i "temperature\|temp" | head -1 | awk '{print $NF}' | sed 's/[^0-9]//g' || echo "0")
            status="Active"
            echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
            return
        fi
    fi
    
    # Try radeontop for AMD (if available, provides real-time stats)
    if command -v radeontop &> /dev/null; then
        # radeontop outputs to stdout, we need to parse it
        local radeon_output=$(timeout 1 radeontop -d - -l 1 2>/dev/null | tail -1)
        if [ -n "$radeon_output" ]; then
            vendor="AMD"
            model="AMD Radeon GPU"
            # radeontop format: gpu: XX%, vram: XX%
            usage=$(echo "$radeon_output" | grep -oE 'gpu:[0-9]+%' | grep -oE '[0-9]+' || echo "0")
            local vram_usage=$(echo "$radeon_output" | grep -oE 'vram:[0-9]+%' | grep -oE '[0-9]+' || echo "0")
            status="Active"
            echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
            return
        fi
    fi
    
    # Try Intel GPU tools
    if command -v intel_gpu_top &> /dev/null; then
        # intel_gpu_top requires root or specific permissions, try a quick check
        local intel_output=$(timeout 1 intel_gpu_top -l 1 2>/dev/null | head -20)
        if [ -n "$intel_output" ]; then
            vendor="Intel"
            model="Intel GPU"
            # Try to extract usage from intel_gpu_top output
            usage=$(echo "$intel_output" | grep -i "render\|rcs" | awk '{print $NF}' | head -1 | sed 's/%//' || echo "0")
            status="Active"
            echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
            return
        fi
    fi
    
    # Try reading Intel GPU stats from sysfs (Linux)
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if [ -d /sys/class/drm ]; then
            for card in /sys/class/drm/card*/device; do
                if [ -d "$card" ]; then
                    local vendor_id=$(cat "$card/vendor" 2>/dev/null)
                    if [ "$vendor_id" == "0x8086" ]; then
                        vendor="Intel"
                        model="Intel GPU"
                        # Try to get memory info from sysfs
                        if [ -f "$card/gt/gt0/meminfo_vram_total" ]; then
                            local mem_bytes=$(cat "$card/gt/gt0/meminfo_vram_total" 2>/dev/null)
                            if [ -n "$mem_bytes" ]; then
                                memory_total=$(calc "$mem_bytes / 1024 / 1024 / 1024")
                            fi
                        fi
                        # Try to get usage from power/energy
                        if [ -f "$card/power/energy_uj" ]; then
                            status="Detected (Power Monitoring Available)"
                        else
                            status="Detected (Limited Stats)"
                        fi
                        echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
                        return
                    fi
                fi
            done
        fi
    fi
    
    # Try to detect via system (Linux) and get basic memory info
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if [ -d /sys/class/drm ]; then
            for card_path in /sys/class/drm/card*/device; do
                if [ -d "$card_path" ]; then
                    local vendor_id=$(cat "$card_path/vendor" 2>/dev/null)
                    local card_name=$(basename $(dirname "$card_path"))
                    
                    if [ "$vendor_id" == "0x10de" ]; then
                        vendor="NVIDIA"
                        model="NVIDIA GPU"
                        # Try to get memory from sysfs (if available)
                        if [ -f "$card_path/uevent" ]; then
                            local mem_info=$(grep -i "memory" "$card_path/uevent" 2>/dev/null)
                        fi
                    elif [ "$vendor_id" == "0x1002" ] || [ "$vendor_id" == "0x1022" ]; then
                        vendor="AMD"
                        model="AMD GPU"
                        # Try to get memory info from AMD sysfs
                        if [ -f "$card_path/mem_info_vram_total" ]; then
                            local mem_bytes=$(cat "$card_path/mem_info_vram_total" 2>/dev/null)
                            if [ -n "$mem_bytes" ]; then
                                memory_total=$(calc "$mem_bytes / 1024 / 1024 / 1024")
                            fi
                        fi
                    elif [ "$vendor_id" == "0x8086" ]; then
                        vendor="Intel"
                        model="Intel GPU"
                    fi
                    
                    if [ "$vendor" != "Unknown" ]; then
                        status="Detected (No Driver Stats)"
                        break
                    fi
                fi
            done
        fi
    fi
    
    # macOS GPU detection
    if [[ "$OS_TYPE" == "macOS" ]]; then
        local gpu_name=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | cut -d':' -f2 | xargs)
        if [ -n "$gpu_name" ]; then
            if echo "$gpu_name" | grep -qi "nvidia"; then
                vendor="NVIDIA"
            elif echo "$gpu_name" | grep -qi "amd\|radeon"; then
                vendor="AMD"
            elif echo "$gpu_name" | grep -qi "intel"; then
                vendor="Intel"
            else
                vendor="Unknown"
            fi
            model="$gpu_name"
            status="Detected (No Driver Stats)"
        fi
    fi
    
    echo "$vendor|$model|$usage|$memory_used|$memory_total|$temperature|$status"
}

# Function to generate alerts
get_alerts() {
    local cpu="$1"
    local cpu_temp="$2"
    local ram_percent="$3"
    local disk_str="$4"
    local smart_status="$5"
    local gpu_usage="$6"
    local gpu_temp="$7"
    
    local alerts="["
    local count=0
    
    # CPU Alerts
    if [ $(echo "$cpu > 90" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: High CPU Usage (${cpu}%)\""
        ((count++))
    fi
    if [ $(echo "$cpu_temp > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: High CPU Temperature (${cpu_temp} C)\""
        ((count++))
    fi
    
    # RAM Alerts
    if [ $(echo "$ram_percent > 90" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: High RAM Usage (${ram_percent}%)\""
        ((count++))
    fi
    
    # Disk Alerts
    IFS=';' read -ra ADDR <<< "$disk_str"
    for i in "${!ADDR[@]}"; do
        IFS=',' read -r name used total percent type <<< "${ADDR[$i]}"
        if [ $(echo "$percent > 90" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
            if [ $count -gt 0 ]; then alerts="${alerts},"; fi
            alerts="${alerts}\"CRITICAL: Low Disk Space on ${name} (${percent}% Used)\""
            ((count++))
        fi
    done
    
    if [[ "$smart_status" == *"Unhealthy"* ]] || [[ "$smart_status" == *"Warning"* ]]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: Disk SMART Status Warning\""
        ((count++))
    fi
    
    # GPU Alerts
    if [ $(echo "$gpu_usage > 90" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: High GPU Usage (${gpu_usage}%)\""
        ((count++))
    fi
    if [ $(echo "$gpu_temp > 85" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
        if [ $count -gt 0 ]; then alerts="${alerts},"; fi
        alerts="${alerts}\"CRITICAL: High GPU Temperature (${gpu_temp} C)\""
        ((count++))
    fi
    
    alerts="${alerts}]"
    echo "$alerts"
}

# Function to create JSON
create_json() {
    local timestamp="$1"
    local cpu="$2"
    local cpu_temp="$3"
    local cpu_model="$4"
    local ram_used="$5"
    local ram_total="$6"
    local ram_free="$7"
    local ram_percent="$8"
    local disk_str="$9"
    local smart_status="${10}"
    local gpu_vendor="${11}"
    local gpu_model="${12}"
    local gpu_usage="${13}"
    local gpu_mem_used="${14}"
    local gpu_mem_total="${15}"
    local gpu_temp="${16}"
    local gpu_status="${17}"
    local net_kb="${18}"
    local lan_speed="${19}"
    local wifi_speed="${20}"
    local wifi_type="${21}"
    local wifi_model="${22}"
    local alerts="${23}"
    
    # Construct drives JSON array
    local drives_json="["
    IFS=';' read -ra ADDR <<< "$disk_str"
    for i in "${!ADDR[@]}"; do
        IFS=',' read -r name used total percent type <<< "${ADDR[$i]}"
        if [ "$i" -gt 0 ]; then drives_json="${drives_json},"; fi
        drives_json="${drives_json}{\"Name\":\"$name\",\"Used\":$used,\"Total\":$total,\"Percent\":$percent,\"Type\":\"${type:-Unknown}\"}"
    done
    drives_json="${drives_json}]"
    
    cat <<EOF
{"timestamp":"$timestamp","cpu":{"percent":$cpu,"temperature_c":$cpu_temp,"cpu_model_name":"$cpu_model"},"ram":{"total_gb":$ram_total,"used_gb":$ram_used,"free_gb":$ram_free,"percent":$ram_percent},"disk":{"smart_status":"$smart_status","drives":$drives_json},"network":{"total_kb_sec":$net_kb,"lan_speed":"$lan_speed","wifi_speed":"$wifi_speed","wifi_type":"$wifi_type","wifi_model":"$wifi_model"},"gpu":{"vendor":"$gpu_vendor","model":"$gpu_model","usage_percent":$gpu_usage,"memory_used_gb":$gpu_mem_used,"memory_total_gb":$gpu_mem_total,"temperature_c":$gpu_temp,"status":"$gpu_status"},"alerts":$alerts}
EOF
}

# Function to write history
write_history() {
    local timestamp="$1"
    local cpu="$2"
    local cpu_temp="$3"
    local ram_percent="$4"
    local ram_used="$5"
    local ram_total="$6"
    local disk_str="$7"
    local net="$8"
    local lan_speed="$9"
    local wifi_speed="${10}"
    local gpu_usage="${11}"
    local gpu_temp="${12}"
    local gpu_mem_used="${13}"
    local gpu_mem_total="${14}"
    local alerts="${15}"
    
    local history_file="${METRICS_DIR}/history.csv"
    local max_lines=1440
    
    # Calculate aggregated disk stats
    local total_disk_used=0
    local total_disk_size=0
    
    IFS=';' read -ra ADDR <<< "$disk_str"
    for i in "${!ADDR[@]}"; do
        IFS=',' read -r name used total percent type <<< "${ADDR[$i]}"
        # Remove any non-numeric chars
        used=$(echo "$used" | sed 's/[^0-9.]//g')
        total=$(echo "$total" | sed 's/[^0-9.]//g')
        
        if [ -n "$used" ]; then total_disk_used=$(echo "$total_disk_used + $used" | bc); fi
        if [ -n "$total" ]; then total_disk_size=$(echo "$total_disk_size + $total" | bc); fi
    done
    
    local disk_percent=0
    if [ $(echo "$total_disk_size > 0" | bc) -eq 1 ]; then
        disk_percent=$(echo "scale=2; ($total_disk_used / $total_disk_size) * 100" | bc)
    fi
    

    
    # Format alerts (remove brackets/quotes, replace comma with pipe)
    local alert_str=""
    if [ "$alerts" != "[]" ] && [ "$alerts" != "" ]; then
        alert_str=$(echo "$alerts" | sed 's/[\[\]""]//g' | sed 's/,/ | /g')
    fi
    
    # Columns: Timestamp,CPU_%,CPU_Temp,RAM_%,RAM_Used,RAM_Total,Disk_%,Disk_Used,Disk_Total,Net_KB_s,LAN_Speed,WiFi_Speed,GPU_%,GPU_Temp,GPU_Mem_Used,GPU_Mem_Total,Alerts
    local line="$timestamp,$cpu,$cpu_temp,$ram_percent,$ram_used,$ram_total,$disk_percent,$total_disk_used,$total_disk_size,$net,$lan_speed,$wifi_speed,$gpu_usage,$gpu_temp,$gpu_mem_used,$gpu_mem_total,$alert_str"
    
    # Create header if missing
    if [ ! -f "$history_file" ]; then
        echo "Timestamp,CPU_%,CPU_Temp,RAM_%,RAM_Used,RAM_Total,Disk_%,Disk_Used,Disk_Total,Net_KB_s,LAN_Speed,WiFi_Speed,GPU_%,GPU_Temp,GPU_Mem_Used,GPU_Mem_Total,Alerts" > "$history_file"
    fi
    
    # Append line
    echo "$line" >> "$history_file"
    
    # Rotate (keep header + max_lines)
    local lines=$(wc -l < "$history_file")
    if [ "$lines" -gt $((max_lines + 100)) ]; then
        local header=$(head -n 1 "$history_file")
        local content=$(tail -n "$max_lines" "$history_file")
        echo "$header" > "$history_file"
        echo "$content" >> "$history_file"
    fi
}

# Main loop
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Collect metrics
    cpu=$(get_cpu_usage)
    cpu_temp=$(get_cpu_temp)
    cpu_model=$(get_cpu_model)
    ram_data=$(get_ram_usage)
    disk_str=$(get_disk_usage)
    smart_status=$(get_smart_status)
    gpu_data=$(get_gpu_info)
    net_kb=$(get_network_usage)
    net_details=$(get_network_details)
    
    # Parse Network Details
    lan_speed=$(echo "$net_details" | cut -d'|' -f1)
    wifi_speed=$(echo "$net_details" | cut -d'|' -f2)
    wifi_type=$(echo "$net_details" | cut -d'|' -f3)
    wifi_model=$(echo "$net_details" | cut -d'|' -f4)
    
    # Parse RAM data
    ram_used=$(echo "$ram_data" | cut -d'|' -f1)
    ram_total=$(echo "$ram_data" | cut -d'|' -f2)
    ram_free=$(echo "$ram_data" | cut -d'|' -f3)
    ram_percent=$(echo "$ram_data" | cut -d'|' -f4)
    
    # Parse GPU data
    gpu_vendor=$(echo "$gpu_data" | cut -d'|' -f1)
    gpu_model=$(echo "$gpu_data" | cut -d'|' -f2)
    gpu_usage=$(echo "$gpu_data" | cut -d'|' -f3)
    gpu_mem_used=$(echo "$gpu_data" | cut -d'|' -f4)
    gpu_mem_total=$(echo "$gpu_data" | cut -d'|' -f5)
    gpu_temp=$(echo "$gpu_data" | cut -d'|' -f6)
    gpu_status=$(echo "$gpu_data" | cut -d'|' -f7)
    
    # Get Alerts
    alerts=$(get_alerts "$cpu" "$cpu_temp" "$ram_percent" "$disk_str" "$smart_status" "$gpu_usage" "$gpu_temp")
    
    # Create JSON
    json=$(create_json "$timestamp" "$cpu" "$cpu_temp" "$cpu_model" \
                      "$ram_used" "$ram_total" "$ram_free" "$ram_percent" \
                      "$disk_str" "$smart_status" \
                      "$gpu_vendor" "$gpu_model" "$gpu_usage" "$gpu_mem_used" "$gpu_mem_total" "$gpu_temp" "$gpu_status" \
                      "$net_kb" "$lan_speed" "$wifi_speed" "$wifi_type" "$wifi_model" "$alerts")
    
    
    # Write to file (Atomic Write)
    echo "DEBUG: Writing JSON to $METRICS_FILE" >&2
    echo "$json" > "${METRICS_FILE}.tmp"
    chmod 666 "${METRICS_FILE}.tmp"
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
    # Ensure final file is readable even if mv behaved oddly
    chmod 666 "$METRICS_FILE"
    
    # Write History
    write_history "$timestamp" "$cpu" "$cpu_temp" "$ram_percent" "$ram_used" "$ram_total" "$disk_str" "$net_kb" "$lan_speed" "$wifi_speed" "$gpu_usage" "$gpu_temp" "$gpu_mem_used" "$gpu_mem_total" "$alerts"
    
    # Format disk info for console
    disk_console=""
    IFS=';' read -ra ADDR <<< "$disk_str"
    for i in "${!ADDR[@]}"; do
        IFS=',' read -r name used total percent type <<< "${ADDR[$i]}"
        disk_console="${disk_console}${name} [${type}] ${used}GB/${total}GB "
    done
    
    # Optional: Log to console
    # Print Alerts if any (parsing the JSON array string)
    if [ "$alerts" != "[]" ] && [ "$alerts" != "" ]; then
        # Remove brackets and quotes for cleaner output
        clean_alerts=$(echo "$alerts" | sed 's/[\[\]""]//g')
        IFS=',' read -ra ALERT_ADDR <<< "$clean_alerts"
        for alert in "${ALERT_ADDR[@]}"; do
            # Red color for alerts
            echo -e "\033[0;31m[$timestamp] $alert\033[0m" >&2
        done
    fi
    
    echo "[$timestamp] CPU: $cpu_model | ${cpu}% (${cpu_temp}C) | RAM: ${ram_used}GB/${ram_total}GB | Disk: $disk_console[$smart_status] | Net: ${net_kb}KB/s | LAN: $lan_speed | WiFi: $wifi_speed | GPU: $gpu_vendor $gpu_model" >&2
    
    sleep "$INTERVAL"
done


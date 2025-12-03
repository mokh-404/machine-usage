# host_agent_windows.ps1
# Windows Host Agent - Collects Real Physical System Metrics
# Writes to shared metrics.json file for Docker container consumption

param(
    [string]$MetricsFile = ".\metrics\metrics.json",
    [int]$Interval = 2
)

# Ensure metrics directory exists
$MetricsDir = Split-Path -Parent $MetricsFile
if (-not (Test-Path $MetricsDir)) {
    New-Item -ItemType Directory -Path $MetricsDir -Force | Out-Null
}

Write-Host "Windows Host Agent Started" -ForegroundColor Green
Write-Host "Metrics file: $MetricsFile" -ForegroundColor Cyan
Write-Host "Update interval: $Interval seconds" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

# Function to get CPU usage
function Get-CpuUsage {
    try {
        $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
        return [math]::Round($cpu.Average, 2)
    }
    catch {
        return 0
    }
}

# Function to get CPU Temperature (Windows Native)
function Get-CpuTemperature {
    # Method 1: Performance Counters (Works without Admin)
    try {
        $t = Get-WmiObject Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($t -and $t.Temperature -gt 0) {
            # Temperature is usually in Kelvin
            $currentTempCelsius = $t.Temperature - 273.15
            return [math]::Round($currentTempCelsius, 2)
        }
    }
    catch {
        # Continue to next method
    }

    # Method 2: MSAcpi_ThermalZoneTemperature (Requires Admin)
    try {
        $t = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue
        if ($t) {
            # Just take the first reading if multiple exist
            $temp = $t | Select-Object -First 1
            $currentTempKelvin = $temp.CurrentTemperature / 10
            $currentTempCelsius = $currentTempKelvin - 273.15
            return [math]::Round($currentTempCelsius, 2)
        }
    }
    catch {
        # Continue
    }

    return 0
}

# Function to get RAM usage
function Get-RamUsage {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalRamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedRamGB = [math]::Round($totalRamGB - $freeRamGB, 2)
        $ramPercent = [math]::Round(($usedRamGB / $totalRamGB) * 100, 2)
        
        return @{
            Total   = $totalRamGB
            Used    = $usedRamGB
            Free    = $freeRamGB
            Percent = $ramPercent
        }
    }
    catch {
        return @{
            Total   = 0
            Used    = 0
            Free    = 0
            Percent = 0
        }
    }
}

# Function to get Disk usage
function Get-DiskUsage {
    try {
        # Get all local disks (DriveType=3)
        $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $diskData = @()
        
        foreach ($d in $disks) {
            $totalGB = [math]::Round($d.Size / 1GB, 2)
            $freeGB = [math]::Round($d.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round($totalGB - $freeGB, 2)
            
            $percent = 0
            if ($totalGB -gt 0) {
                $percent = [math]::Round(($usedGB / $totalGB) * 100, 2)
            }
            
            # Determine Disk Type (SSD/HDD)
            $type = "Unknown"
            try {
                $driveLetter = $d.DeviceID.TrimEnd(':')
                $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                if ($partition) {
                    $diskObj = Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue
                    if ($diskObj) {
                        # Get-PhysicalDisk might return multiple for RAID/Storage Spaces, take the first unique type
                        $physDisks = $diskObj | Get-PhysicalDisk -ErrorAction SilentlyContinue
                        $mediaTypes = $physDisks.MediaType | Select-Object -Unique
                        if ($mediaTypes -contains "SSD") { $type = "SSD" }
                        elseif ($mediaTypes -contains "HDD") { $type = "HDD" }
                        elseif ($mediaTypes -contains "Unspecified") { $type = "Unspecified" }
                    }
                }
            }
            catch {
                # Fallback or permission issue
            }
            
            $diskData += @{
                Name    = $d.DeviceID
                Total   = $totalGB
                Used    = $usedGB
                Free    = $freeGB
                Percent = $percent
                Type    = $type
            }
        }
        
        return $diskData
    }
    catch {
        return @()
    }
}


# Function to get SMART Status
function Get-SmartStatus {
    try {
        $disks = Get-PhysicalDisk | Select-Object FriendlyName, HealthStatus
        $unhealthy = $disks | Where-Object { $_.HealthStatus -ne "Healthy" }
        $count = $disks.Count
        
        if ($unhealthy) {
            $status = "Warning ($($unhealthy.Count) Unhealthy)"
        }
        else {
            $status = "Healthy ($count Drives)"
        }
        return $status
    }
    catch {
        return "Unknown"
    }
}

# Function to get Network Details (LAN Speed, WiFi Info)
function Get-NetworkDetails {
    $info = @{
        LanSpeed  = "Not Connected"
        WifiSpeed = "Not Connected"
        WifiType  = "Unknown"
        WifiModel = "Unknown"
    }

    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        
        # WiFi
        $wifi = $adapters | Where-Object { $_.MediaType -like "*802.11*" -or $_.Name -like "*Wi-Fi*" } | Select-Object -First 1
        if ($wifi) {
            $info.WifiSpeed = $wifi.LinkSpeed
            $info.WifiModel = $wifi.InterfaceDescription
            # Try to determine type from name/description if MediaType is generic
            if ($wifi.Name -match "Wi-Fi 6") { $info.WifiType = "Wi-Fi 6" }
            elseif ($wifi.Name -match "Wi-Fi 5") { $info.WifiType = "Wi-Fi 5" }
            elseif ($wifi.Name -match "AC") { $info.WifiType = "Wi-Fi 5 (AC)" }
            elseif ($wifi.Name -match "AX") { $info.WifiType = "Wi-Fi 6 (AX)" }
            else { $info.WifiType = $wifi.MediaType }
        }

        # LAN (Wired) - Exclude WiFi and Loopback
        # We prioritize physical Ethernet if possible, but will take vEthernet if it's the only one active
        $lan = $adapters | Where-Object { 
            $_.MediaType -notlike "*802.11*" -and 
            $_.Name -notlike "*Wi-Fi*" -and 
            $_.InterfaceDescription -notlike "*Loopback*" 
        } | Sort-Object LinkSpeed -Descending | Select-Object -First 1
        
        if ($lan) {
            $info.LanSpeed = $lan.LinkSpeed
        }
    }
    catch {
        # Keep defaults
    }

    return $info
}

# Function to get Network usage
function Get-NetworkUsage {
    try {
        $net = Get-Counter "\Network Interface(*)\Bytes Total/sec" -ErrorAction SilentlyContinue
        $totalBytes = ($net.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
        $totalKb = [math]::Round($totalBytes / 1KB, 2)
        return $totalKb
    }
    catch {
        return 0
    }
}

# Function to write metrics with retry logic to handle file locking
function Write-MetricsWithRetry {
    param (
        [string]$Path,
        [string]$Content
    )
    $maxRetries = 5
    $retryDelayMs = 100
    
    # Use a temp file for atomic write
    $tempFile = "$Path.tmp"
    
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            # Write to temp file first
            $Content | Set-Content -Path $tempFile -Force -ErrorAction Stop
            
            # Move temp file to actual file (atomic operation)
            Move-Item -Path $tempFile -Destination $Path -Force -ErrorAction Stop
            return $true
        }
        catch {
            if ($i -eq $maxRetries - 1) {
                # Clean up temp file if it exists
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
                # Log error but don't throw to keep agent running
                Write-Host "Error writing metrics: $_" -ForegroundColor Red
                return $false
            }
            Start-Sleep -Milliseconds $retryDelayMs
        }
    }
    return $false
}

# Function to detect and get GPU info
function Get-GpuInfo {
    $gpuInfo = @{
        Vendor      = "Unknown"
        Model       = "Not Detected"
        Usage       = 0
        MemoryUsed  = 0
        MemoryTotal = 0
        Temperature = 0
        PowerW      = 0
        FanSpeed    = 0
        Status      = "Not Available"
    }
    
    # Try NVIDIA first
    try {
        # Try to find nvidia-smi in PATH or common locations
        $nvidiaSmiPath = $null
        $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvidiaSmi) {
            $nvidiaSmiPath = $nvidiaSmi.Path
        }
        else {
            # Try common installation paths
            $commonPaths = @(
                "${env:ProgramFiles}\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
                "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
                "C:\Windows\System32\nvidia-smi.exe"
            )
            foreach ($path in $commonPaths) {
                if (Test-Path $path) {
                    $nvidiaSmiPath = $path
                    break
                }
            }
        }
        
        if ($nvidiaSmiPath) {
            # Execute nvidia-smi and capture output
            try {
                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $nvidiaSmiPath
                $processInfo.Arguments = "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,fan.speed --format=csv,noheader,nounits"
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true
                
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                $process.Start() | Out-Null
                $nvidiaOutput = $process.StandardOutput.ReadToEnd()
                $process.WaitForExit()
                
                # Clean up the output - remove any header lines or extra text
                $nvidiaOutput = ($nvidiaOutput -split "`n" | Where-Object { 
                        $_ -match ',' -and $_ -notmatch '^name,' -and $_.Trim() -ne '' 
                    } | Select-Object -First 1).Trim()
            }
            catch {
                # Fallback to simple execution
                $nvidiaOutput = & $nvidiaSmiPath --query-gpu = name, utilization.gpu, memory.used, memory.total, temperature.gpu, power.draw, fan.speed --format = csv, noheader, nounits 2>$null
            }
            
            if ($nvidiaOutput -and $nvidiaOutput.Trim() -ne "") {
                # nvidia-smi CSV uses ", " (comma-space) as delimiter
                # Handle both ", " and "," delimiters
                $parts = $nvidiaOutput -split ', '
                if ($parts.Count -lt 5) {
                    # Try with just comma
                    $parts = $nvidiaOutput -split ','
                }
                
                if ($parts.Count -ge 5) {
                    $gpuInfo.Vendor = "NVIDIA"
                    $rawModel = ($parts[0] -replace '\s+', ' ').Trim()
                    # Remove Vendor from Model if present to avoid "NVIDIA NVIDIA..."
                    if ($rawModel -match "^NVIDIA\s+(.*)") {
                        $gpuInfo.Model = $matches[1]
                    }
                    else {
                        $gpuInfo.Model = $rawModel
                    }
                    
                    # Parse usage (remove any whitespace and non-numeric)
                    $usageStr = ($parts[1] -replace '[^\d]', '').Trim()
                    $usageVal = 0
                    if ([int]::TryParse($usageStr, [ref]$usageVal)) {
                        $gpuInfo.Usage = $usageVal
                    }
                    
                    # Parse memory used (in MB, convert to GB)
                    $memUsedStr = ($parts[2] -replace '[^\d.]', '').Trim()
                    $memUsedVal = 0.0
                    if ([double]::TryParse($memUsedStr, [ref]$memUsedVal)) {
                        $gpuInfo.MemoryUsed = [math]::Round($memUsedVal / 1024, 2)
                    }
                    
                    # Parse memory total (in MB, convert to GB)
                    $memTotalStr = ($parts[3] -replace '[^\d.]', '').Trim()
                    $memTotalVal = 0.0
                    if ([double]::TryParse($memTotalStr, [ref]$memTotalVal)) {
                        $gpuInfo.MemoryTotal = [math]::Round($memTotalVal / 1024, 2)
                    }
                    
                    # Parse temperature
                    $tempStr = ($parts[4] -replace '[^\d]', '').Trim()
                    $tempVal = 0
                    if ([int]::TryParse($tempStr, [ref]$tempVal)) {
                        $gpuInfo.Temperature = $tempVal
                    }

                    # Parse power (if available)
                    if ($parts.Count -ge 6) {
                        $powerStr = ($parts[5] -replace '[^\d.]', '').Trim()
                        $powerVal = 0.0
                        if ([double]::TryParse($powerStr, [ref]$powerVal)) {
                            $gpuInfo.PowerW = [math]::Round($powerVal, 1)
                        }
                    }

                    # Parse fan speed (if available)
                    if ($parts.Count -ge 7) {
                        $fanStr = ($parts[6] -replace '[^\d]', '').Trim()
                        $fanVal = 0
                        if ([int]::TryParse($fanStr, [ref]$fanVal)) {
                            $gpuInfo.FanSpeed = $fanVal
                        }
                    }
                    
                    # If we successfully parsed nvidia-smi output, return it
                    # Usage can be 0 (idle GPU), so we check if we got valid data
                    if ($gpuInfo.Model -ne "" -and ($gpuInfo.MemoryTotal -gt 0 -or $gpuInfo.Usage -ge 0)) {
                        $gpuInfo.Status = "Active"
                        return $gpuInfo
                    }
                }
            }
        }
    }
    catch {
        # NVIDIA not available, continue
        # Uncomment for debugging: Write-Host "NVIDIA-SMI Error: $_" -ForegroundColor Yellow
    }
    
    # Try AMD tools
    try {
        # Try amd-smi (AMD's equivalent to nvidia-smi)
        $amdSmi = Get-Command amd-smi -ErrorAction SilentlyContinue
        if ($amdSmi) {
            $amdOutput = amd-smi --query-gpu = name, utilization.gpu, memory.used, memory.total, temperature.gpu --format = csv, noheader, nounits 2>$null
            if ($amdOutput -and $amdOutput.Trim() -ne "") {
                $parts = $amdOutput -split ','
                if ($parts.Count -ge 5) {
                    $gpuInfo.Vendor = "AMD"
                    $gpuInfo.Model = ($parts[0] -replace '\s+', ' ').Trim()
                    $gpuInfo.Usage = [int]$parts[1]
                    $gpuInfo.MemoryUsed = [math]::Round([double]$parts[2] / 1024, 2)
                    $gpuInfo.MemoryTotal = [math]::Round([double]$parts[3] / 1024, 2)
                    $gpuInfo.Temperature = [int]$parts[4]
                    $gpuInfo.Status = "Active"
                    return $gpuInfo
                }
            }
        }
    }
    catch {
        # AMD tools not available
    }
    
    # Try to detect via WMI and get memory info first
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" } | Select-Object -First 1
        if ($gpu) {
            if ($gpu.Name -like "*NVIDIA*") {
                $gpuInfo.Vendor = "NVIDIA"
            }
            elseif ($gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
                $gpuInfo.Vendor = "AMD"
            }
            elseif ($gpu.Name -like "*Intel*") {
                $gpuInfo.Vendor = "Intel"
            }
            $gpuInfo.Model = $gpu.Name
            
            # Try to get GPU memory from WMI (AdapterRAM is in bytes)
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $gpuInfo.MemoryTotal = [math]::Round($gpu.AdapterRAM / 1GB, 2)
            }
        }
    }
    catch {
        # WMI query failed
    }
    
    # Try Performance Counters for GPU usage (Windows 10+) - works for any GPU
    if ($gpuInfo.Vendor -ne "Unknown") {
        try {
            $gpuCounter = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue
            if ($gpuCounter -and $gpuCounter.CounterSamples) {
                $gpuUsage = ($gpuCounter.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Measure-Object -Property CookedValue -Average).Average
                if ($gpuUsage -and $gpuUsage -gt 0) {
                    $gpuInfo.Usage = [math]::Round($gpuUsage, 0)
                    if ($gpuInfo.Status -eq "Not Available") {
                        $gpuInfo.Status = "Active (Performance Counter)"
                    }
                }
            }
        }
        catch {
            # Performance counters not available
        }
        
        # Set status if we have some info but no usage
        if ($gpuInfo.Status -eq "Not Available") {
            if ($gpuInfo.MemoryTotal -gt 0) {
                $gpuInfo.Status = "Detected (Memory: $($gpuInfo.MemoryTotal)GB Total)"
            }
            else {
                $gpuInfo.Status = "Detected (No Stats Available)"
            }
        }
    }
    
    return $gpuInfo
}

# Function to write historical data to CSV
function Write-History {
    param (
        [string]$Timestamp,
        [double]$Cpu,
        [double]$CpuTemp,
        [object]$Ram,
        [array]$Disks,
        [double]$Net,
        [string]$LanSpeed,
        [string]$WifiSpeed,
        [object]$Gpu
    )
    
    $HistoryFile = Join-Path $MetricsDir "history.csv"
    $MaxLines = 1440 # Approx 1 hour at 2s interval
    
    # Calculate aggregated disk stats
    $totalDiskUsed = 0
    $totalDiskSize = 0
    foreach ($d in $Disks) {
        $totalDiskUsed += $d.Used
        $totalDiskSize += $d.Total
    }
    
    $diskPercent = 0
    if ($totalDiskSize -gt 0) {
        $diskPercent = [math]::Round(($totalDiskUsed / $totalDiskSize) * 100, 2)
    }
    
    # Prepare CSV line
    # Columns: Timestamp,CPU_%,CPU_Temp,RAM_%,RAM_Used,RAM_Total,Disk_%,Disk_Used,Disk_Total,Net_KB_s,LAN_Speed,WiFi_Speed,GPU_%,GPU_Temp,GPU_Mem_Used,GPU_Mem_Total
    $line = "$Timestamp,$Cpu,$CpuTemp,$($Ram.Percent),$($Ram.Used),$($Ram.Total),$diskPercent,$totalDiskUsed,$totalDiskSize,$Net,$LanSpeed,$WifiSpeed,$($Gpu.Usage),$($Gpu.Temperature),$($Gpu.MemoryUsed),$($Gpu.MemoryTotal)"
    
    try {
        # Create header if file doesn't exist
        if (-not (Test-Path $HistoryFile)) {
            "Timestamp,CPU_%,CPU_Temp,RAM_%,RAM_Used,RAM_Total,Disk_%,Disk_Used,Disk_Total,Net_KB_s,LAN_Speed,WiFi_Speed,GPU_%,GPU_Temp,GPU_Mem_Used,GPU_Mem_Total" | Out-File -FilePath $HistoryFile -Encoding ascii
        }
        
        # Append new line
        $line | Out-File -FilePath $HistoryFile -Append -Encoding ascii
        
        # Rotate file if too large (simple check every 10 updates to save I/O)
        if ((Get-Random -Minimum 0 -Maximum 10) -eq 0) {
            $content = Get-Content $HistoryFile
            if ($content.Count -gt $MaxLines) {
                $header = $content[0]
                $keep = $content | Select-Object -Last $MaxLines
                $newContent = @($header) + $keep
                $newContent | Out-File -FilePath $HistoryFile -Encoding ascii
            }
        }
    }
    catch {
        # Ignore history write errors
    }
}

# Main loop
$ErrorActionPreference = "SilentlyContinue"
while ($true) {
    $loopStartTime = Get-Date
    try {
        $timestamp = $loopStartTime.ToString("yyyy-MM-dd HH:mm:ss")
        
        # Collect metrics
        $cpuPercent = Get-CpuUsage
        $cpuTemp = Get-CpuTemperature
        $ram = Get-RamUsage
        $disk = Get-DiskUsage
        $smartStatus = Get-SmartStatus
        $netKb = Get-NetworkUsage
        $netDetails = Get-NetworkDetails
        $gpu = Get-GpuInfo
        
        # Build JSON object
        $metrics = @{
            timestamp = $timestamp
            cpu       = @{
                percent        = $cpuPercent
                temperature_c  = $cpuTemp
                cpu_model_name = (Get-CimInstance Win32_Processor).Name
            }
            ram       = @{
                total_gb = $ram.Total
                used_gb  = $ram.Used
                free_gb  = $ram.Free
                percent  = $ram.Percent
            }
            disk      = @{
                drives       = $disk
                smart_status = $smartStatus
            }
            network   = @{
                total_kb_sec = $netKb
                lan_speed    = $netDetails.LanSpeed
                wifi_speed   = $netDetails.WifiSpeed
                wifi_type    = $netDetails.WifiType
                wifi_model   = $netDetails.WifiModel
            }
            gpu       = @{
                vendor            = $gpu.Vendor
                model             = $gpu.Model
                usage_percent     = $gpu.Usage
                memory_used_gb    = $gpu.MemoryUsed
                memory_total_gb   = $gpu.MemoryTotal
                temperature_c     = $gpu.Temperature
                fan_speed_percent = $gpu.FanSpeed
                status            = $gpu.Status
            }
        }
        
        # Convert to JSON
        $json = $metrics | ConvertTo-Json -Depth 5 -Compress
        
        # Write to file with retry
        Write-MetricsWithRetry -Path $metricsFile -Content $json | Out-Null
        
        # Write History
        Write-History -Timestamp $timestamp -Cpu $cpuPercent -CpuTemp $cpuTemp -Ram $ram -Disks $disk -Net $netKb -LanSpeed $netDetails.LanSpeed -WifiSpeed $netDetails.WifiSpeed -Gpu $gpu
        
        # Optional: Write status to console (can be hidden)
        $gpuInfo = "$($gpu.Vendor) $($gpu.Model)"
        
        # Always show usage to prevent flickering
        $gpuInfo += " [$($gpu.Usage)%]"
        
        if ($gpu.MemoryUsed -gt 0 -and $gpu.MemoryTotal -gt 0) {
            $gpuInfo += " [$($gpu.MemoryUsed)GB/$($gpu.MemoryTotal)GB]"
        }
        if ($gpu.Temperature -gt 0) {
            $gpuInfo += " Temp: $($gpu.Temperature)C"
        }
        if ($gpu.PowerW -gt 0) {
            $gpuInfo += " Pwr: $($gpu.PowerW)W"
        }

        # Format disk info for console
        $diskInfo = ($disk | ForEach-Object { "$($_.Name) [$($_.Type)] $($_.Used)GB/$($_.Total)GB" }) -join " "

        $cpuModel = (Get-CimInstance Win32_Processor).Name
        Write-Host "[$timestamp] CPU: $cpuModel | $cpuPercent% (${cpuTemp}C) | RAM: $($ram.Used)GB/$($ram.Total)GB | Disk: $diskInfo [$smartStatus] | Net: ${netKb}KB/s | LAN: $($netDetails.LanSpeed) | WiFi: $($netDetails.WifiSpeed) ($($netDetails.WifiType)) | GPU: $gpuInfo" -ForegroundColor Gray

    }
    catch {
        # Suppress error output
    }

    # Dynamic Sleep: Calculate how long to sleep to maintain the interval
    $elapsed = (Get-Date) - $loopStartTime
    $sleepSeconds = $Interval - $elapsed.TotalSeconds

    if ($sleepSeconds -gt 0) {
        Start-Sleep -Seconds $sleepSeconds
    }
}


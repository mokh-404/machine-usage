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
    } catch {
        return 0
    }
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
            Total = $totalRamGB
            Used = $usedRamGB
            Free = $freeRamGB
            Percent = $ramPercent
        }
    } catch {
        return @{
            Total = 0
            Used = 0
            Free = 0
            Percent = 0
        }
    }
}

# Function to get Disk usage
function Get-DiskUsage {
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $usedGB = [math]::Round($totalGB - $freeGB, 2)
        $percent = [math]::Round(($usedGB / $totalGB) * 100, 2)
        
        return @{
            Total = $totalGB
            Used = $usedGB
            Free = $freeGB
            Percent = $percent
        }
    } catch {
        return @{
            Total = 0
            Used = 0
            Free = 0
            Percent = 0
        }
    }
}

# Function to detect and get GPU info
function Get-GpuInfo {
    $gpuInfo = @{
        Vendor = "Unknown"
        Model = "Not Detected"
        Usage = 0
        MemoryUsed = 0
        MemoryTotal = 0
        Temperature = 0
        Status = "Not Available"
    }
    
    # Try NVIDIA first
    try {
        # Try to find nvidia-smi in PATH or common locations
        $nvidiaSmiPath = $null
        $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($nvidiaSmi) {
            $nvidiaSmiPath = $nvidiaSmi.Path
        } else {
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
                $processInfo.Arguments = "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits"
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
            } catch {
                # Fallback to simple execution
                $nvidiaOutput = & $nvidiaSmiPath --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>$null
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
                    $gpuInfo.Model = ($parts[0] -replace '\s+', ' ').Trim()
                    
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
                    
                    # If we successfully parsed nvidia-smi output, return it
                    # Usage can be 0 (idle GPU), so we check if we got valid data
                    if ($gpuInfo.Model -ne "" -and ($gpuInfo.MemoryTotal -gt 0 -or $gpuInfo.Usage -ge 0)) {
                        $gpuInfo.Status = "Active"
                        return $gpuInfo
                    }
                }
            }
        }
    } catch {
        # NVIDIA not available, continue
        # Uncomment for debugging: Write-Host "NVIDIA-SMI Error: $_" -ForegroundColor Yellow
    }
    
    # Try AMD tools
    try {
        # Try amd-smi (AMD's equivalent to nvidia-smi)
        $amdSmi = Get-Command amd-smi -ErrorAction SilentlyContinue
        if ($amdSmi) {
            $amdOutput = amd-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>$null
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
    } catch {
        # AMD tools not available
    }
    
    # Try to detect via WMI and get memory info first
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" } | Select-Object -First 1
        if ($gpu) {
            if ($gpu.Name -like "*NVIDIA*") {
                $gpuInfo.Vendor = "NVIDIA"
            } elseif ($gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*") {
                $gpuInfo.Vendor = "AMD"
            } elseif ($gpu.Name -like "*Intel*") {
                $gpuInfo.Vendor = "Intel"
            }
            $gpuInfo.Model = $gpu.Name
            
            # Try to get GPU memory from WMI (AdapterRAM is in bytes)
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $gpuInfo.MemoryTotal = [math]::Round($gpu.AdapterRAM / 1GB, 2)
            }
        }
    } catch {
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
        } catch {
            # Performance counters not available
        }
        
        # Set status if we have some info but no usage
        if ($gpuInfo.Status -eq "Not Available") {
            if ($gpuInfo.MemoryTotal -gt 0) {
                $gpuInfo.Status = "Detected (Memory: $($gpuInfo.MemoryTotal)GB Total)"
            } else {
                $gpuInfo.Status = "Detected (No Stats Available)"
            }
        }
    }
    
    return $gpuInfo
}

# Main loop
$ErrorActionPreference = "SilentlyContinue"
while ($true) {
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Collect metrics
        $cpuPercent = Get-CpuUsage
        $ram = Get-RamUsage
        $disk = Get-DiskUsage
        $gpu = Get-GpuInfo
        
        # Build JSON object
        $metrics = @{
            timestamp = $timestamp
            cpu = @{
                percent = $cpuPercent
            }
            ram = @{
                total_gb = $ram.Total
                used_gb = $ram.Used
                free_gb = $ram.Free
                percent = $ram.Percent
            }
            disk = @{
                total_gb = $disk.Total
                used_gb = $disk.Used
                free_gb = $disk.Free
                percent = $disk.Percent
            }
            gpu = @{
                vendor = $gpu.Vendor
                model = $gpu.Model
                usage_percent = $gpu.Usage
                memory_used_gb = $gpu.MemoryUsed
                memory_total_gb = $gpu.MemoryTotal
                temperature_c = $gpu.Temperature
                status = $gpu.Status
            }
        }
        
        # Convert to JSON and write to file
        $json = $metrics | ConvertTo-Json -Compress
        $json | Set-Content -Path $MetricsFile -Force
        
        # Optional: Write status to console (can be hidden)
        $gpuInfo = "$($gpu.Vendor) $($gpu.Model)"
        if ($gpu.Usage -gt 0) {
            $gpuInfo += " ($($gpu.Usage)%)"
        }
        if ($gpu.MemoryUsed -gt 0 -and $gpu.MemoryTotal -gt 0) {
            $gpuInfo += " [$($gpu.MemoryUsed)GB/$($gpu.MemoryTotal)GB]"
        }
        Write-Host "[$timestamp] CPU: $cpuPercent% | RAM: $($ram.Used)GB/$($ram.Total)GB | Disk: $($disk.Used)GB/$($disk.Total)GB | GPU: $gpuInfo" -ForegroundColor Gray
        
    } catch {
        Write-Host "Error collecting metrics: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds $Interval
}


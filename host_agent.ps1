# host_agent.ps1
$OutputFile = ".\reports\real_metrics.txt"

Write-Host "Starting Host Agent... (Press Ctrl+C to stop)"
Write-Host "Writing real Windows metrics to $OutputFile"

while ($true) {
    # 1. Get Real CPU Load
    $Cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    
# host_agent.ps1
$OutputFile = ".\reports\real_metrics.txt"

Write-Host "Starting Host Agent... (Press Ctrl+C to stop)"
Write-Host "Writing real Windows metrics to $OutputFile"

while ($true) {
    # 1. Get Real CPU Load
    $Cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    
    # 2. Get Real RAM Usage
    $Os = Get-CimInstance Win32_OperatingSystem
    $TotalRam = [math]::Round($Os.TotalVisibleMemorySize / 1MB, 2)
    $FreeRam = [math]::Round($Os.FreePhysicalMemory / 1MB, 2)
    $UsedRam = [math]::Round($TotalRam - $FreeRam, 2)
    
    # 3. Get Network Traffic (Total across all interfaces)
    # We use Get-Counter for real-time network I/O
    try {
        $NetStats = Get-Counter "\Network Interface(*)\Bytes Total/sec" -ErrorAction SilentlyContinue
        $TotalBytesSec = ($NetStats.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
        $TotalKbSec = [math]::Round($TotalBytesSec / 1KB, 2)
    } catch {
        $TotalKbSec = 0
    }

    # 4. Write to file (Format: CPU:X%|RAM:Y/ZGB|NET:ZKBs)
    $Output = "CPU:$Cpu%|RAM:${UsedRam}GB / ${TotalRam}GB|NET:${TotalKbSec}KB/s"
    Set-Content -Path $OutputFile -Value $Output
    
    Start-Sleep -Seconds 2
}
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
    
    # 3. Write to file (Format: CPU:X%|RAM:Y/ZGB)
    $Output = "CPU:$Cpu%|RAM:${UsedRam}GB / ${TotalRam}GB"
    Set-Content -Path $OutputFile -Value $Output
    
    Start-Sleep -Seconds 2
}
# install_windows_service.ps1
# Installs the Host Agent as a background Scheduled Task
# Run as Administrator

$ErrorActionPreference = "Stop"

# Get absolute path to the agent script
$ScriptPath = Join-Path $PSScriptRoot "host_agent_windows.ps1"
$TaskName = "SystemMonitorAgent"

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Could not find host_agent_windows.ps1 at $ScriptPath"
    exit 1
}

Write-Host "Installing $TaskName..." -ForegroundColor Cyan

# Create the Scheduled Task Action
# We use wscript to run it completely hidden (no console window)
$VbsPath = Join-Path $PSScriptRoot "run_hidden.vbs"
$VbsContent = "CreateObject(""Wscript.Shell"").Run ""powershell.exe -ExecutionPolicy Bypass -File """"$ScriptPath"""""", 0, False"
$VbsContent | Out-File -FilePath $VbsPath -Encoding ascii

$Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument """$VbsPath"""

# Create Trigger (At Logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn

# Create Settings (Allow running on demand, don't stop if on battery)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 365)

# Register the Task
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Background Host Agent for System Monitor" | Out-Null
    
    Write-Host "Task registered successfully!" -ForegroundColor Green
    Write-Host "Starting task now..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Agent is running in the background." -ForegroundColor Green
    Write-Host "You can now run Docker without manually starting the agent." -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to register task. Please run as Administrator."
    Write-Error $_
}

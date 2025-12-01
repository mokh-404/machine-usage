# test_nvidia.ps1
# Quick test script to check if nvidia-smi is working

Write-Host "Testing NVIDIA GPU Detection..." -ForegroundColor Cyan
Write-Host ""

# Try to find nvidia-smi
$nvidiaSmiPath = $null
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $nvidiaSmiPath = $nvidiaSmi.Path
    Write-Host "Found nvidia-smi in PATH: $nvidiaSmiPath" -ForegroundColor Green
} else {
    Write-Host "nvidia-smi not found in PATH, checking common locations..." -ForegroundColor Yellow
    $commonPaths = @(
        "${env:ProgramFiles}\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $nvidiaSmiPath = $path
            Write-Host "Found nvidia-smi at: $path" -ForegroundColor Green
            break
        }
    }
}

if (-not $nvidiaSmiPath) {
    Write-Host "ERROR: nvidia-smi not found!" -ForegroundColor Red
    Write-Host "Please ensure NVIDIA drivers are installed." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Testing nvidia-smi query..." -ForegroundColor Cyan
$query = "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits"
Write-Host "Command: $nvidiaSmiPath $query" -ForegroundColor Gray
Write-Host ""

try {
    $output = & $nvidiaSmiPath --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS! Output:" -ForegroundColor Green
        Write-Host $output -ForegroundColor White
        Write-Host ""
        
        # Try to parse
        $parts = $output -split ', '
        if ($parts.Count -lt 5) {
            $parts = $output -split ','
        }
        
        Write-Host "Parsed values:" -ForegroundColor Cyan
        Write-Host "  GPU Name: $($parts[0])" -ForegroundColor White
        Write-Host "  Usage: $($parts[1])%" -ForegroundColor White
        Write-Host "  Memory Used: $($parts[2]) MB" -ForegroundColor White
        Write-Host "  Memory Total: $($parts[3]) MB" -ForegroundColor White
        Write-Host "  Temperature: $($parts[4]) C" -ForegroundColor White
    } else {
        Write-Host "ERROR: nvidia-smi returned exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Output: $output" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Exception occurred" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""
Write-Host "Test complete." -ForegroundColor Cyan


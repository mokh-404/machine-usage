# System Monitoring Solution

A robust, cross-platform system monitoring solution using **Bash** and **Docker** with a Host-Agent pattern to collect real physical hardware metrics.

## Architecture

This solution uses a **Host-Agent Pattern**:

1. **Host Side**: Native scripts (PowerShell for Windows, Bash for Linux/macOS) that gather real physical metrics and write them to a shared JSON file (`metrics/metrics.json`).

2. **Container Side**: A Docker container that mounts the shared metrics file and displays the data using a Bash script with a GUI (using `whiptail` or text fallback).

## Features

- ✅ **Real Physical Metrics**: Reports actual CPU, RAM, and Disk usage of the host machine (not Docker VM stats)
- ✅ **Multi-Disk Support**: Monitors all mounted logical drives (C:, D:, /home, etc.)
- ✅ **Disk Type Detection**: Identifies whether drives are SSD or HDD (Windows 8+ / Linux)
- ✅ **SMART Health Monitoring**: Checks physical disk health status (Requires `smartmontools` on Linux/macOS)
- ✅ **Detailed Hardware Info**: Displays CPU Model Name and Real-Time Temperature
- ✅ **Cross-Platform**: Works on Windows, Linux, and macOS
- ✅ **Network & LAN Monitoring**: Real-time network I/O, LAN Link Speed, and WiFi Speed/Type
- ✅ **Universal GPU Support**: Automatically detects NVIDIA, AMD, or Intel GPUs
- ✅ **One-Click Execution**: Single entry point scripts that handle everything
- ✅ **Error Handling**: Robust error handling for missing drivers or configurations
- ✅ **Auto-Refresh Dashboard**: Real-time updating dashboard with progress bars

## Requirements

- **Docker** (Docker Desktop for Windows/macOS, Docker Engine for Linux)
- **PowerShell** (Windows - usually pre-installed)
- **Bash** (Linux/macOS - usually pre-installed)
- **smartmontools** (Linux/macOS - required for SMART status)
- **bc** (Unix systems - usually pre-installed, fallback to awk if not available)

## Quick Start

### Windows

1. Open PowerShell or Command Prompt
2. Navigate to the project directory
3. Run:
   ```batch
   run_windows.bat
   ```

### Linux/macOS

1. Open Terminal
2. Navigate to the project directory
3. Run:
   ```bash
   ./run_unix.sh
   ```

The launcher will:
1. Start the Host Agent in the background
2. Build and start the Docker container
3. Display the dashboard
4. Clean up everything when you exit (Ctrl+C)

## Files Overview

### Core Files

- **`docker-compose.yml`**: Docker Compose configuration
- **`Dockerfile`**: Container image definition with whiptail and utilities
- **`dashboard.sh`**: Main dashboard script running inside the container

### Host Agents

- **`host_agent_windows.ps1`**: Windows metrics collector (PowerShell)
- **`host_agent_unix.sh`**: Linux/macOS metrics collector (Bash)

### Launchers

- **`run_windows.bat`**: One-click Windows launcher
- **`run_unix.sh`**: One-click Unix launcher

## GPU Detection

The system automatically detects GPU vendors and collects usage statistics:

- **NVIDIA**: Uses `nvidia-smi` to get usage, memory, temperature, power, and fan speed (requires NVIDIA drivers)
- **AMD**: 
  - Primary: `rocm-smi` (ROCm drivers)
  - Fallback: `radeontop` (for older AMD GPUs)
  - Detects usage, memory, and temperature when available
- **Intel**: 
  - Uses `intel_gpu_top` if available
  - Reads from `/sys/class/drm` on Linux for basic info
- **Windows Performance Counters**: On Windows 10+, uses Performance Counters to get GPU usage for any GPU
- **WMI Detection**: Falls back to WMI to detect GPU model and total memory
- **Fallback**: If no GPU driver/tools are found, displays GPU model but shows "No Stats Available"

## Metrics Collected

- **CPU**: Model Name, Usage percentage, Temperature (°C)
- **RAM**: Total, Used, Free (GB) and percentage
- **Disk**: Usage (Used/Total/Free/Percent) for all mounted drives, Disk Type (SSD/HDD), and SMART Health Status
- **Network**: Total I/O (KB/s), LAN Link Speed, WiFi Speed, WiFi Type (e.g., 802.11ax)
- **GPU**: Vendor, Model, Usage percentage, Memory usage, Temperature, Power Usage (W), Fan Speed (%), Status

## Troubleshooting

### Docker not running
- **Windows/macOS**: Start Docker Desktop
- **Linux**: Start Docker service: `sudo systemctl start docker`

### Host Agent not collecting data
- Check that the `metrics` directory exists and is writable
- Verify the host agent script has execute permissions (Unix)
- Check PowerShell execution policy (Windows): `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

### GPU not detected
- Install appropriate GPU drivers
- For NVIDIA: Ensure `nvidia-smi` is available
- The system will gracefully handle missing GPU drivers

### SMART Status Unknown (Linux/macOS)
- Install `smartmontools` to enable disk health monitoring:
  - Linux: `sudo apt-get install smartmontools`
  - macOS: `brew install smartmontools`

### GPU shows model but no usage readings
This is normal in certain scenarios:
- **Integrated GPUs (Intel/AMD APU)**: May only show model and total memory without usage stats
- **Missing vendor tools**: Without `nvidia-smi`, `rocm-smi`, or `radeontop`, usage stats aren't available
- **Windows**: Performance Counters may provide usage for some GPUs (Windows 10+)
- **Linux**: Some GPUs require root permissions or specific kernel modules

**To get full GPU stats:**
- **NVIDIA**: Install NVIDIA drivers (includes `nvidia-smi`)
- **AMD**: Install ROCm drivers (includes `rocm-smi`) or use `radeontop`
- **Intel**: Install Intel GPU tools or use `intel_gpu_top` (may require root)

### Dashboard not showing
- Ensure Docker container is running: `docker ps`
- Check container logs: `docker logs system-monitor-dashboard`
- Verify metrics file exists: `cat metrics/metrics.json`

## Manual Operation

If you prefer to run components manually:

### Start Host Agent Only

**Windows:**
```powershell
powershell -ExecutionPolicy Bypass -File .\host_agent_windows.ps1
```

**Unix:**
```bash
./host_agent_unix.sh
```

### Start Docker Only

```bash
docker-compose up -d --build
```

### View Dashboard

```bash
docker exec -it system-monitor-dashboard /app/dashboard.sh
```

### Stop Everything

```bash
docker-compose down
# Then stop the host agent (Ctrl+C or kill process)
```

## Notes

- The metrics file is written to `metrics/metrics.json` (created automatically)
- The dashboard refreshes every 2 seconds
- All scripts include comprehensive error handling
- The system is designed to be non-intrusive and won't crash on missing components

## License

This is a professional DevOps solution for system monitoring.


# System Monitor V2

A comprehensive, hybrid system monitoring solution that breaks Docker's virtualization limits to show **real hardware stats** (CPU Temp, Disk Health, Ghost-free Network) on a modern Web Dashboard.

![Dashboard Preview](web/preview.png)

## Features
- **Real Hardware Metrics**: Bypasses Docker isolation to read actual CPU Temps, SMART status, and physical RAM/GPU usage.
- **Modern Web Dashboard**: Premium Dark Mode, Glassmorphism, Responsive Design.
- **Hybrid Architecture**:
    - **Windows**: PowerShell Agent (Background Service) + Docker (Web Server).
    - **Linux**: Native Docker Container (Privileged Mode).
- **One-Click Launchers**: Automated setup scripts for both OSs.

## Quick Start (Recommended)

The easiest way to run the system with full hardware monitoring is to use the included launchers. They handle all configuration automatically.

### Windows 🪟
Double-click **`run_windows.bat`**.
- Starts the **Host Agent** (Background data collector).
- Starts **Docker** (Web Dashboard).
- Opens your browser to `http://localhost:8085`.
*Note: If you only run Docker, you must also run `host_agent_windows.ps1` separately to see data.*

### Linux / macOS 🐧
Run the launcher script:
```bash
./run_unix.sh
```
- **Auto-Detects** your hardware.
- Creates the necessary Docker Native configuration.
- Starts the container with hardware access enabled.

---

## Power Users (Docker Compose) 🐳

You CAN run `docker compose up -d --build` directly, but behavior differs by OS:

| OS | Command | Result |
|----|---------|--------|
| **Windows** | `docker compose up` | **Viewer Mode**. Dashboard runs, but waits for you to run `host_agent_windows.ps1` to see data. |
| **Linux** | `docker compose up` | **Viewer Mode** (Default). To get Native Monitoring, you must use the override: `docker compose -f docker-compose.yml -f docker-compose.linux.yml up` |


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

## Quick Start (New Device)

### Windows
1.  **Install Docker Desktop** and ensure it's running.
2.  Open the project folder.
3.  Double-click **`run_windows.bat`**.
    - *This will start the background data collector, build the container, and open your browser to `http://localhost:8085`.*

### Linux / macOS
1.  **Install Docker** and adds your user to the `docker` group.
2.  Open terminal in project folder.
3.  Run:
    ```bash
    chmod +x run_unix.sh
    ./run_unix.sh
    ```
4.  Open `http://localhost:8085` in your browser.

## Architecture Explained

| Component | Responsibility | Tech Stack |
|-----------|----------------|------------|
| **Host Agent** | Collects raw metrics from hardware (WMI/Sysfs) | PowerShell (Win) / Bash (Linux) |
| **Shared Volume** | Bridges data between Host and Docker | `metrics/metrics.json` |
| **Web Container** | Serves the frontend UI | Nginx, HTML5, CSS3, JS |
| **Monitor Container** | (Optional) Terminal Dashboard (TUI) | Bash, fast processing |

## Troubleshooting

### "CPU Name is Null" or "Network shows Ghost Adapters"
- We have fixed this in the latest agent using strict filtering.
- **Action**: Restart the agent using the launcher script (`run_windows.bat`) or kill the `powershell.exe` background process manually.

### "Port 8085 is in use"
- Edit `docker-compose.yml` and change `"8085:80"` to another port (e.g., `"9090:80"`).
- Update `run_windows.bat` to match.

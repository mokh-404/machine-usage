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

## Pro Tip: "One Command" Setup (Windows)

If you want to just run `docker compose up` without worrying about the host agent:

1.  **Install the Agent as a Service** (Run once as Admin):
    ```powershell
    .\install_windows_service.ps1
    ```
    *Now the agent runs automatically when you log in.*

2.  **Run Docker**:
    Simply run `docker compose up-d` (or use Docker Desktop Dashboard).
    The data will just be there!

## Manual Execution (Advanced)

If you prefer to run commands yourself (or if `docker compose up` didn't open the browser):

### Windows
1.  **Start Data Collector** (keep window open):
    ```powershell
    .\host_agent_windows.ps1
    ```
2.  **Start Dashboard** (new window):
    ```powershell
    docker compose up --build
    ```
3.  **Open Browser**: Go to [http://localhost:8085](http://localhost:8085).

### Linux
1.  **Run with Native Mode**:
    ```bash
    export HOST_MONITORING_MODE=native
    docker compose -f docker-compose.yml -f docker-compose.linux.yml up --build
    ```
2.  **Open Browser**: Go to [http://localhost:8085](http://localhost:8085).

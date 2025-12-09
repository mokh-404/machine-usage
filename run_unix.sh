#!/bin/bash
# run_unix.sh
# One-Click Launcher for Linux/macOS
# Starts System Monitor in Native Docker Mode

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/metrics"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "============================================================"
echo "  System Monitoring Solution - Unix Launcher"
echo "============================================================"
echo ""

# Create metrics directory
mkdir -p "$METRICS_DIR"
# Clean old metrics to prevent stale data from previous sessions/machines
rm -f "$METRICS_DIR"/*.json "$METRICS_DIR"/*.csv

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker is not running or not installed.${NC}"
    echo "Please start Docker and try again."
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    cd "$SCRIPT_DIR"
    docker-compose down 2>/dev/null || true
    echo -e "${GREEN}System Monitor stopped successfully.${NC}"
}

# Check if running in WSL
if grep -qE "(Microsoft|WSL)" /proc/version &> /dev/null; then
    IS_WSL=true
    echo -e "${GREEN}WSL Environment Detected!${NC}"
else
    IS_WSL=false
fi

if [ "$IS_WSL" = true ]; then
    # In WSL, we run the agent LOCALLY on the host so it can access powershell.exe
    # The container will just run the dashboard
    export HOST_MONITORING_MODE=agent
    
    echo "Starting Host Agent on WSL Host..."
    chmod +x "$SCRIPT_DIR/host_agent_unix.sh"
    "$SCRIPT_DIR/host_agent_unix.sh" "$METRICS_DIR/metrics.json" 2 &
    AGENT_PID=$!
    echo "Host Agent started (PID: $AGENT_PID)"
    
    # Add agent kill to cleanup trap
    trap "kill $AGENT_PID 2>/dev/null; cleanup" EXIT INT TERM
else
    # Standard Linux: Run everything in Docker (Native Mode)
    export HOST_MONITORING_MODE=native
    trap cleanup EXIT INT TERM
fi

# Ensure Linux Docker Override exists
if [ ! -f "docker-compose.linux.yml" ]; then
    echo "Creating missing docker-compose.linux.yml..."
    cat > docker-compose.linux.yml <<EOF
version: '3.8'

services:
  system-monitor:
    volumes:
      # Mounts for Native Linux Monitoring
      - /proc:/proc:ro
      - /sys:/sys:ro
      - /dev:/dev:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    privileged: true
    network_mode: "host"
    environment:
      - IS_LINUX_NATIVE=true
EOF
fi

echo -e "${GREEN}[1/3] Starting System Monitor in Native Docker Mode...${NC}"
echo "Note: This requires sudo permissions for hardware access."

# Build and start container
cd "$SCRIPT_DIR"

# We use sudo for docker-compose to ensure privileged access works if user isn't in docker group
# If in WSL, we might not need sudo for docker if configured correctly, but we'll stick to standard check
if groups | grep -q "docker"; then
    docker-compose -f docker-compose.yml -f docker-compose.linux.yml up -d --build
else
    # Check if we have sudo
    if command -v sudo &> /dev/null; then
        sudo -E docker-compose -f docker-compose.yml -f docker-compose.linux.yml up -d --build
    else
        echo "Warning: 'sudo' not found. Trying without it..."
        docker-compose -f docker-compose.yml -f docker-compose.linux.yml up -d --build
    fi
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Docker start failed.${NC}"
    exit 1
fi

sleep 2

echo -e "${GREEN}[2/3] Dashboard is running.${NC}"
echo -e "${GREEN}[3/3] Streaming logs (Press Ctrl+C to stop)...${NC}"
echo ""
echo "============================================================"
echo "  Web Dashboard: http://localhost:8085"
echo "  Press Ctrl+C to stop."
echo "============================================================"
echo ""

# Use logs -f instead of attach
docker compose logs -f system-monitor

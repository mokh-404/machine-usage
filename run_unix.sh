#!/bin/bash
# run_unix.sh
# One-Click Launcher for Linux/macOS
# Starts Host Agent, Docker, and Dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="$SCRIPT_DIR/metrics"
METRICS_FILE="$METRICS_DIR/metrics.json"
HOST_AGENT_SCRIPT="$SCRIPT_DIR/host_agent_unix.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================================"
echo "  System Monitoring Solution - Unix Launcher"
echo "============================================================"
echo ""

# Create metrics directory
mkdir -p "$METRICS_DIR"

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
    
    # Stop Docker container
    echo "Stopping Docker container..."
    cd "$SCRIPT_DIR"
    docker-compose down 2>/dev/null || true
    
    # Kill host agent
    echo "Stopping Host Agent..."
    if [ -n "$HOST_AGENT_PID" ]; then
        kill "$HOST_AGENT_PID" 2>/dev/null || true
        wait "$HOST_AGENT_PID" 2>/dev/null || true
    fi
    
    # Also try to find and kill any remaining host agent processes
    pkill -f "host_agent_unix.sh" 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}System Monitor stopped successfully.${NC}"
}

# Set trap for cleanup on script exit
trap cleanup EXIT INT TERM

# Make host agent executable
chmod +x "$HOST_AGENT_SCRIPT"

echo -e "${GREEN}[1/4] Starting Host Agent in background...${NC}"
"$HOST_AGENT_SCRIPT" "$METRICS_FILE" 2 &
HOST_AGENT_PID=$!
sleep 2

# Verify host agent is running
if ! kill -0 "$HOST_AGENT_PID" 2>/dev/null; then
    echo -e "${RED}[ERROR] Host Agent failed to start.${NC}"
    exit 1
fi

echo -e "${GREEN}[2/4] Building Docker container...${NC}"
cd "$SCRIPT_DIR"
docker-compose build
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Docker build failed.${NC}"
    kill "$HOST_AGENT_PID" 2>/dev/null || true
    exit 1
fi

echo -e "${GREEN}[3/4] Starting Docker container...${NC}"
docker-compose up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Docker start failed.${NC}"
    kill "$HOST_AGENT_PID" 2>/dev/null || true
    exit 1
fi

sleep 3

echo -e "${GREEN}[4/4] Attaching to dashboard...${NC}"
echo ""
echo "============================================================"
echo "  Dashboard is now running."
echo "  Press Ctrl+C to stop and cleanup."
echo "============================================================"
echo ""

# Attach to container and show dashboard
docker exec -it system-monitor-dashboard /app/dashboard.sh


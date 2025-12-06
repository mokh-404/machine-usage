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

# Set trap for cleanup on script exit
trap cleanup EXIT INT TERM

# Set mode to native for Linux
export HOST_MONITORING_MODE=native

echo -e "${GREEN}[1/3] Starting System Monitor in Native Docker Mode...${NC}"
echo "Note: This requires sudo permissions for hardware access."

# Build and start container
cd "$SCRIPT_DIR"

# We use sudo for docker-compose to ensure privileged access works if user isn't in docker group
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
echo -e "${GREEN}[3/3] Attaching to dashboard...${NC}"
echo ""
echo "============================================================"
echo "  Press Ctrl+C to stop and cleanup."
echo "============================================================"
echo ""

# Attach to container and show dashboard
docker attach system-monitor-dashboard

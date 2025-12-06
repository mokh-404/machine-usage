#!/bin/bash
# entrypoint.sh

# Default to "agent" mode (external agent)
MODE="${HOST_MONITORING_MODE:-agent}"

echo "Starting System Monitor Container..."
echo "Mode: $MODE"

# Wipe old metrics to prevent stale data from previous sessions/machines
rm -f /data/metrics.json /data/metrics.csv

if [ "$MODE" == "native" ]; then
    echo "Native Mode detected. Starting internal Host Agent..."
    
    # Check for privileged access/mounts
    if [ ! -d "/host/proc" ] && [ ! -d "/proc" ]; then
        echo "WARNING: Native mode requires /proc access. Ensure --privileged or volume mounts are set."
    fi

    # Start the host agent in the background
    # We pass the metrics file path. The agent writes to it, dashboard reads from it.
    /app/host_agent_unix.sh "/data/metrics.json" 2 &
    AGENT_PID=$!
    echo "Internal Host Agent started (PID: $AGENT_PID)"
    
    # Trap to kill agent on exit
    trap "kill $AGENT_PID" EXIT
fi

# Start the dashboard
# Pass arguments to dashboard if needed
/app/dashboard.sh "$@"

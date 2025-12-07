#!/bin/bash
# entrypoint.sh

# Auto-Detect Detection
# If the user didn't explicitly set a mode, we try to guess it.
if [ -z "$HOST_MONITORING_MODE" ]; then
    echo "Detecting environment..."
    # Check for explicit Native flag (injected by docker-compose.linux.yml)
    if [ "$IS_LINUX_NATIVE" == "true" ]; then
         echo "Auto-detected: NATIVE (via IS_LINUX_NATIVE)"
         MODE="native"
    else
         echo "Auto-detected: AGENT (Default)"
         MODE="agent"
    fi
else
    MODE="$HOST_MONITORING_MODE"
fi
    echo "Native Mode detected. Starting internal Host Agent..."
    
    # Check for privileged access/mounts
    if [ ! -d "/host/proc" ] && [ ! -d "/proc" ]; then
        echo "WARNING: Native mode requires /proc access. Ensure --privileged or volume mounts are set."
    fi

    # Start the host agent in the background
    # We pass the metrics file path. The agent writes to it, dashboard reads from it.
    chmod +x /app/host_agent_unix.sh
    /app/host_agent_unix.sh "/data/metrics.json" 2 &
    AGENT_PID=$!
    echo "Internal Host Agent started (PID: $AGENT_PID)"
    
    # Trap to kill agent on exit
    trap "kill $AGENT_PID" EXIT
fi

# Start the dashboard
# Pass arguments to dashboard if needed
/app/dashboard.sh "$@"

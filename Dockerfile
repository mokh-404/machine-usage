FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    bc \
    whiptail \
    dialog \
    procps \
    curl \
    jq \
    smartmontools \
    lm-sensors \
    pciutils \
    net-tools \
    wireless-tools \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy host agent for native monitoring
COPY host_agent_unix.sh /app/host_agent_unix.sh
RUN dos2unix /app/host_agent_unix.sh && chmod +x /app/host_agent_unix.sh

# Copy dashboard script
COPY dashboard.sh /app/dashboard.sh
RUN dos2unix /app/dashboard.sh && chmod +x /app/dashboard.sh

# Create data directory
RUN mkdir -p /data

# Copy entrypoint
COPY entrypoint.sh /app/entrypoint.sh
RUN dos2unix /app/entrypoint.sh && chmod +x /app/entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

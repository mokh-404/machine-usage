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
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy dashboard script
COPY dashboard.sh /app/dashboard.sh
RUN chmod +x /app/dashboard.sh

# Create data directory
RUN mkdir -p /data

# Set entrypoint
CMD ["/app/dashboard.sh"]

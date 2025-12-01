FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    procps \
    net-tools \
    bc \
    nvidia-utils-535-server \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY monitor.sh /app/monitor.sh
RUN chmod +x /app/monitor.sh
RUN mkdir /data
CMD ["./monitor.sh"]
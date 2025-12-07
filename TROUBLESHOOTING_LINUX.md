# Linux Troubleshooting Guide

## 1. NVIDIA Driver Error / `libnvidia-ml.so.1` Missing
**Error:** `could not select device driver "nvidia"` OR `initialization error: load library failed`.
**Cause:** The `docker-compose.yml` requests an NVIDIA GPU, but your machine either has no GPU or is missing `nvidia-container-toolkit` drivers.
**Solution:**
- **Option A (Remove GPU Requirement):**
  Edit `docker-compose.yml` and **delete** the entire `deploy:` section (lines 24-31).
- **Option B (Install Drivers):**
  Install `nvidia-container-toolkit` and `nvidia-utils` (Arch) or `nvidia-driver` (Ubuntu).

## 2. "Bad interpreter" or "Command not found"
**Error:** `/bin/bash^M: bad interpreter: No such file or directory`
**Cause:** The file was saved with Windows line endings (CRLF) instead of Linux ones (LF).
**Solution:**
- Run this command to fix all scripts:
  ```bash
  sed -i 's/\r$//' *.sh
  ```

## 2. Dashboard Shows Zeros / "Legacy Mode"
**Cause:** You ran `docker compose up` without the Linux overrides, so the container is isolated from the hardware.
**Solution:**
- Use the launcher: `./run_unix.sh`
- OR Rename the config file to auto-load it:
  ```bash
  mv docker-compose.linux.yml docker-compose.override.yml
  docker compose up -d
  ```

## 3. "Connection Refused"
**Cause:** `web` folder missing or Nginx crash.
**Solution:**
- Check logs: `docker compose logs system-monitor-web`.
- Ensure you copied the entire project directory.

## 4. Stale Data
**Cause:** Copied `metrics.json` from another machine.
**Solution:**
- Run: `rm -rf metrics/`
- Restart: `docker compose up -d` (The container auto-wipes old data on startup now).

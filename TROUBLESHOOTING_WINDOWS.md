# Windows Troubleshooting Guide

## 1. "Connection Refused" (localhost refuses to connect)
**Symptoms:** Browser shows `ERR_CONNECTION_REFUSED` when visiting `http://localhost:8085`.
**Causes:**
- Docker containers are not running.
- The `web` folder was not copied to the machine (Nginx crash).
**Solution:**
1. Ensure the `web` folder exists.
2. Run `docker compose logs system-monitor-web` to check for errors.
3. Start the system: `docker compose up -d --build`.

## 2. Old / Stale Data (from another PC)
**Symptoms:** Dashboard shows readings from a different computer immediately after starting.
**Cause:** The `metrics/metrics.json` file was copied over. (Note: These files are now ignored by git to prevent this).
**Solution:**
1. Stop Docker: `docker compose down`.
2. **Delete the `metrics` folder** manually.
3. Run `.\run_windows.bat` (checks `host_agent.log` if data doesn't appear).

## 3. Dashboard Showing Zeros / "Connecting..."
**Cause:** The **Host Agent** is not running or failed to start.
**Solution:**
- Check **`host_agent.log`** in the project directory for errors.
- Run `.\install_windows_service.ps1` (Once, as Admin) to install it as a background service.

## 4. UI Not Updating (Stuck)
**Cause:** Docker file caching issue on Windows.
**Solution:**
- We have fixed this by setting `sendfile off;` in `nginx.conf`.
- If issues persist, try **Hard Refresh** (Ctrl+F5) in browser.

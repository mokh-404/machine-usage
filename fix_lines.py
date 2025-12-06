import os

files = ['entrypoint.sh', 'dashboard.sh', 'host_agent_unix.sh', 'run_unix.sh']

for filename in files:
    if os.path.exists(filename):
        print(f"Fixing {filename}...")
        with open(filename, 'rb') as f:
            content = f.read()
        
        # Replace CRLF with LF
        content = content.replace(b'\r\n', b'\n')
        
        with open(filename, 'wb') as f:
            f.write(content)
        print(f"Fixed {filename}")
    else:
        print(f"Skipping {filename} (not found)")

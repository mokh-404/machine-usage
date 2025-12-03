#!/bin/bash
json_file="./metrics/metrics.json"

echo "Content:"
cat "$json_file"
echo ""

echo "Testing grep lan_speed:"
grep -o '"lan_speed":"[^"]*"' "$json_file"

echo "Testing cut:"
grep -o '"lan_speed":"[^"]*"' "$json_file" | cut -d'"' -f4

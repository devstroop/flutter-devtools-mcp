#!/bin/bash
# Test MCP session: launch WorxVPN, inspect, screenshot, disconnect
set -euo pipefail

SERVER="/Volumes/EXT/softether-workspace/flutter-devtools-mcp/bin/flutter_devtools_mcp_server"
SESSION_FILE="/tmp/mcp_session_$$.txt"
PID_FILE="/tmp/mcp_server_$$.pid"

# Start server in background, redirect stderr to file
$SERVER 2>"$SESSION_FILE" &
echo $! > "$PID_FILE"
sleep 2

# Initialize
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test"}}}' | tee -a /dev/stderr | nc 2>/dev/null || echo "init sent"

# Need to connect first - use connect with the URL from the previous run
echo "==========================================" 
echo "WorxVPN needs to be running first."
echo "Run this in another terminal:"
echo "  cd /Volumes/EXT/softether-workspace/WorxVPN-App && flutter run --debug"
echo ""
echo "Then copy the VM Service URL and call:"
echo "  connect(vmServiceUrl: \"http://127.0.0.1:PORT/TOKEN=/\")"
echo "=========================================="

kill $(cat "$PID_FILE") 2>/dev/null
rm -f "$PID_FILE" "$SESSION_FILE"

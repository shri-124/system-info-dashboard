#!/usr/bin/env bash
set -Eeuo pipefail

RUN_ID="${1:-}"
SERVER="${SERVER_URL:-}"

if [[ -z "${RUN_ID}" ]]; then
  echo "Usage: curl -sL <server>/client.sh | bash -s -- <RUN_ID>" >&2
  exit 1
fi

# Detect server from referer if not set (works in most cases)
if [[ -z "${SERVER}" ]]; then
  # If user pasted from the site, origin will match their page.
  # Fallback to http://localhost:5000
  SERVER="http://localhost:5000"
fi

# Collect minimal info (portable)
HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
OS="$(uname -srmo 2>/dev/null || sw_vers 2>/dev/null || echo unknown)"
UPTIME="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
IP_ADDRS="$(hostname -I 2>/dev/null || ipconfig getifaddr en0 2>/dev/null || echo unknown)"

CPU_MODEL="$(awk -F: "/^model name/{print \$2; exit}" /proc/cpuinfo 2>/dev/null | sed "s/^ *//" || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
CORES="$( (command -v nproc >/dev/null && nproc) || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo unknown)"

MEM="$( (free -h | awk "/^Mem:/ {print \$2\" total, \"\$3\" used, \"\$4\" free\"}") 2>/dev/null || vm_stat 2>/dev/null || echo unknown )"


# Build JSON safely
json_escape() { 
python3 - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
}

read -r -d '' PAYLOAD <<EOF || true
{
  "hostname": "$HOSTNAME",
  "os": "$OS",
  "uptime": "$UPTIME",
  "ip_addrs": "$IP_ADDRS",
  "cpu_model": "$CPU_MODEL",
  "cores": "$CORES",
  "memory": "$MEM",
  "ts": "$(date -Is)"
}
EOF

# Post to server
curl -s -X POST "$SERVER/api/ingest/$RUN_ID" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null \
  || { echo "Failed to send data to $SERVER" >&2; exit 2; }

echo "✅ Sent system info to $SERVER (run_id=$RUN_ID). Return to your browser tab."

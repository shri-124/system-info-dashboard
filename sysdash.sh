#!/usr/bin/env bash
set -Eeuo pipefail

PROCS=10
OUTPUT=""
NO_COLOR=0
REPEAT=0

usage() { cat <<'EOF'
Usage: sysdash.sh [options]
  -p, --processes N   Number of processes to show (default: 10)
  -o, --output PATH   Write/append results to PATH. If PATH is a directory or ends with '/', a timestamped .log is created inside it.
      --no-color      Disable ANSI colors
  -r, --repeat SEC    Refresh every SEC seconds (like watch)
  -h, --help          Show this help
Examples:
  ./sysdash.sh
  ./sysdash.sh -p 15 -o ~/logs/
  ./sysdash.sh -o sysdash.log --no-color
  ./sysdash.sh -r 2
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--processes) PROCS="${2:?}"; shift 2;;
    -o|--output) OUTPUT="${2:?}"; shift 2;;
    --no-color) NO_COLOR=1; shift;;
    -r|--repeat) REPEAT="${2:?}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# colors
bold=""; reset=""; red=""; green=""; yellow=""; blue=""; magenta=""; cyan="";
if [[ -t 1 && "$NO_COLOR" -eq 0 ]]; then
  if command -v tput >/dev/null 2>&1; then
    bold=$(tput bold); reset=$(tput sgr0)
    red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3)
    blue=$(tput setaf 4); magenta=$(tput setaf 5); cyan=$(tput setaf 6)
  else
    bold=$'\e[1m'; reset=$'\e[0m'
    red=$'\e[31m'; green=$'\e[32m'; yellow=$'\e[33m'
    blue=$'\e[34m'; magenta=$'\e[35m'; cyan=$'\e[36m'
  fi
fi

hr(){ printf '%s\n' '------------------------------------------------------------'; }

resolve_logfile() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  if [[ -d "$p" || "$p" == */ ]]; then
    mkdir -p "$p"
    printf '%s/%s.log\n' "${p%/}" "sysdash_$(date +%F_%H-%M-%S)"
  else
    mkdir -p "$(dirname -- "$p")"
    printf '%s\n' "$p"
  fi
}

cpu_model() {
  if [[ -r /proc/cpuinfo ]]; then
    awk -F: '/^model name/{print $2; exit}' /proc/cpuinfo | sed 's/^[[:space:]]*//'
  fi
}
cpu_cores(){ command -v nproc >/dev/null && nproc || getconf _NPROCESSORS_ONLN; }
cpu_usage(){
  if CPU_LINE=$(LC_ALL=C top -bn1 2>/dev/null | grep -m1 "Cpu(s)"); then
    idle=$(printf '%s' "$CPU_LINE" | sed 's/,/ /g' | awk '{for(i=1;i<=NF;i++){if($i ~ /^id/){print $(i-1); exit}}}')
    awk -v id="${idle:-0}" 'BEGIN{printf "%.1f", (100-id)}'
  else
    awk '
      NR==FNR && /^cpu /{for(i=2;i<=NF;i++) a[i]=$i; next}
      /^cpu /{
        total=idle=0
        for(i=2;i<=NF;i++){total+=($i-a[i])}
        idle=($5-a[5])+($6-a[6])
        if(total>0) printf("%.1f", (100*(total-idle))/total); else print "0.0"
      }' /proc/stat <(sleep 0.5; cat /proc/stat)
  fi
}
load_avg(){ awk '{printf "%s %s %s", $1,$2,$3}' /proc/loadavg 2>/dev/null || sysctl -n vm.loadavg 2>/dev/null; }

mem_line_h(){ free -h | awk '/^Mem:/ {printf "%s total, %s used, %s free, %s buff/cache\n",$2,$3,$4,$6}'; }
mem_pct(){ free | awk '/^Mem:/ {printf "%.1f", ($3/$2)*100}'; }

disk_table(){
  df -h --output=source,fstype,size,used,avail,pcent,target -x squashfs -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR==1 || $1 ~ /^\//{printf "%-22s %-6s %6s %6s %6s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7}'
}

net_info(){
  local def dev src
  if command -v ip >/dev/null 2>&1; then
    def=$(ip route get 1.1.1.1 2>/dev/null | head -1)
    dev=$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1)}}' <<<"$def")
    src=$(awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1)}}' <<<"$def")
  fi
  local ips
  if command -v hostname >/dev/null 2>&1; then
    ips=$(hostname -I 2>/dev/null || true)
  fi
  printf "Default iface: %s  IP: %s\n" "${dev:-unknown}" "${src:-unknown}"
  [[ -n "$ips" ]] && printf "All IPs: %s\n" "$ips"
}

top_procs_cpu(){
  ps -eo pid,comm,%cpu,%mem,etime --sort=-%cpu | awk -v n="$PROCS" 'NR==1{printf "%-6s %-20s %6s %6s %10s\n",$1,$2,$3,$4,$5; next} NR<=n+1{printf "%-6s %-20s %6s %6s %10s\n",$1,$2,$3,$4,$5}'
}
top_procs_mem(){
  ps -eo pid,comm,%cpu,%mem,etime --sort=-%mem | awk -v n="$PROCS" 'NR==1{printf "%-6s %-20s %6s %6s %10s\n",$1,$2,$3,$4,$5; next} NR<=n+1{printf "%-6s %-20s %6s %6s %10s\n",$1,$2,$3,$4,$5}'
}

render_once(){
  printf "%s%sSystem Info Dashboard%s  %s\n" "$bold" "$cyan" "$reset" "$(date)"
  hr
  printf "%sCPU%s   %s\n" "$bold" "$reset" "$(cpu_model)"
  printf "Cores: %s   Usage: %s%%   Load (1/5/15m): %s\n" "$(cpu_cores)" "$(cpu_usage)" "$(load_avg)"
  hr
  printf "%sMemory%s\n" "$bold" "$reset"
  printf "%s (%.1f%% used)\n" "$(mem_line_h)" "$(mem_pct)"
  hr
  printf "%sDisk%s  (filesystem type, size used avail use%% mount)\n" "$bold" "$reset"
  disk_table
  hr
  printf "%sNetwork%s\n" "$bold" "$reset"
  net_info
  hr
  printf "%sTop %d processes by CPU%s\n" "$bold" "$PROCS" "$reset"
  top_procs_cpu
  hr
  printf "%sTop %d processes by MEM%s\n" "$bold" "$PROCS" "$reset"
  top_procs_mem
  hr
}

main_loop(){
  local logfile=""
  if [[ -n "$OUTPUT" ]]; then
    logfile=$(resolve_logfile "$OUTPUT")
    printf "Writing output to: %s\n" "$logfile" >&2
  fi
  while :; do
    if [[ -t 1 && "$REPEAT" -gt 0 ]]; then clear || tput clear || true; fi
    if [[ -n "$logfile" ]]; then
      { render_once; } | tee -a -- "$logfile"
    else
      render_once
    fi
    [[ "$REPEAT" -gt 0 ]] || break
    sleep "$REPEAT"
  done
}

main_loop


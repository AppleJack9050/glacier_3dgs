#!/usr/bin/env bash
#
# monitor_runner.sh: Run workload (default: stress-ng with 8 CPU cores, 60s)
#                    while monitoring CPU, RAM, GPU usage.
#                    Log results in CSV-like format (.log).
#
# Columns:
#   timestamp, cpu_percent, mem_used_mb, gpu_util_percent, vram_used_mb
#
# Example:
#   ./monitor_runner.sh -i 5 -o run.log -c "python train.py --epochs 10"
#

set -euo pipefail

# ---- Defaults ----
INTERVAL=30
OUTFILE="monitor.log"
VERBOSE=0
QUIET=0
TIMEOUT_SECS=0
CUSTOM_CMD=""

# ---- Logging helper ----
log() {
  local level="$1"; shift
  local msg="$*"
  if [[ "$QUIET" -eq 1 && "$level" == "INFO" ]]; then
    return
  fi
  if [[ "$VERBOSE" -eq 1 || "$level" != "INFO" ]]; then
    echo "[$level] $msg"
  fi
}

# ---- Help ----
show_help() {
  cat << EOF
Usage: $0 [-i interval_in_seconds] [-o logfile] [-c "command"] [-v|-q] [-t timeout_seconds] [-h]

Options:
  -i    Sampling interval (default: 30s)
  -o    Output log file (default: monitor.log)
  -c    Custom command to run (default: stress-ng --cpu 8 --timeout 60s)
  -v    Verbose logging
  -q    Quiet mode (suppress info logs)
  -t    Timeout in seconds (kill workload if exceeded, requires timeout)
  -h    Show this help
EOF
  exit 1
}

# ---- Parse options ----
while getopts ":i:o:c:vqt:h" opt; do
  case $opt in
    i) INTERVAL="$OPTARG" ;;
    o) OUTFILE="$OPTARG" ;;
    c) CUSTOM_CMD="$OPTARG" ;;
    v) VERBOSE=1 ;;
    q) QUIET=1 ;;
    t) TIMEOUT_SECS="$OPTARG" ;;
    h) show_help ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_help ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; show_help ;;
  esac
done

# ---- Define workload ----
run_workload() {
  if [[ -n "$CUSTOM_CMD" ]]; then
    log INFO "Running custom command: $CUSTOM_CMD"
    eval "$CUSTOM_CMD"
  else
    if ! command -v stress-ng >/dev/null 2>&1; then
      echo "[ERR] 'stress-ng' not found. Install it (e.g., 'sudo apt install stress-ng')." >&2
      exit 127
    fi
    log INFO "Running default workload: stress-ng --cpu 8 --timeout 60s"
    stress-ng --cpu 8 --timeout 60s
  fi
}

# ---- Start time ----
START_TS=$(date +%s)

# ---- Init log file with header ----
if [[ ! -f "$OUTFILE" ]]; then
  echo "timestamp, cpu_percent, mem_used_mb, gpu_util_percent, vram_used_mb" > "$OUTFILE"
  log INFO "Created new log file: $OUTFILE"
else
  log INFO "Appending to existing log file: $OUTFILE"
fi

# ---- Launch workload in background ----
if (( TIMEOUT_SECS > 0 )) && command -v timeout >/dev/null 2>&1; then
  log INFO "Applying timeout: ${TIMEOUT_SECS}s"
  ( timeout "${TIMEOUT_SECS}s" bash -c run_workload ) &
else
  if (( TIMEOUT_SECS > 0 )); then
    log WARN "timeout command not found; proceeding without enforcing -t"
  fi
  ( run_workload ) &
fi
PID=$!

# ---- Detect GPU availability ----
GPU_AVAIL=0
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_AVAIL=1
fi

# ---- CPU usage helper ----
cpu_percent() {
  if command -v mpstat >/dev/null 2>&1; then
    local idle
    idle=$(mpstat 1 1 | awk '/Average:/ && $2 ~ /all/ {print $(NF)}')
    if [[ -z "$idle" ]]; then
      idle=$(mpstat 1 1 | awk '/all/ {v=$NF} END{print v}')
    fi
    awk -v idle="$idle" 'BEGIN { if (idle ~ /^[0-9.]+$/) { printf "%.1f", (100 - idle) } else { print "N/A" } }'
  else
    echo "N/A"
  fi
}

# ---- RAM used (MB) ----
mem_used_mb() {
  if command -v free >/dev/null 2>&1; then
    free -m | awk '/Mem:/ {print $3}'
  else
    echo "N/A"
  fi
}

# ---- Monitoring loop ----
while kill -0 "$PID" 2>/dev/null; do
  TS=$(date +%s)
  CPU=$(cpu_percent)
  MEM_MB=$(mem_used_mb)

  if [[ "$GPU_AVAIL" -eq 1 ]]; then
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1 2>/dev/null || echo "N/A")
    VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -n1 2>/dev/null || echo "0")
  else
    GPU_UTIL="N/A"
    VRAM_USED="0"
  fi

  echo "${TS}, ${CPU}, ${MEM_MB}, ${GPU_UTIL}, ${VRAM_USED}" >> "$OUTFILE"

  sleep "$INTERVAL"
done

# ---- Wrap up ----
set +e
wait "$PID"
EXIT_STATUS=$?
set -e
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
HMS=$(printf '%02d:%02d:%02d' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))

log INFO "Workload exited with status: $EXIT_STATUS"
echo "# exit_status=${EXIT_STATUS}, duration_s=${DURATION}, duration_hms=${HMS}" >> "$OUTFILE"
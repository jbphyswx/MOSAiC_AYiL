# shellcheck shell=bash
# Progress lines for long DALES runs (local and Slurm). Source after run_status.sh.

# Append timestamped progress to stdout or a log file while .ayil_running exists.
ayil_monitor_run() {
  local run_dir="$1"
  local log="$2"
  local runtime="$3"
  local interval="${AYiL_PROGRESS_INTERVAL:-30}"
  local start_bytes last_bytes now_bytes sim pct disk_h delta

  start_bytes="$(ayil_dir_size_bytes "${run_dir}")"
  last_bytes="${start_bytes}"

  while [[ -f "${run_dir}/${AYiL_STATUS_RUNNING}" ]]; do
    sleep "${interval}"
    [[ -f "${log}" ]] || continue
    now_bytes="$(ayil_dir_size_bytes "${run_dir}")"
    sim="$(ayil_last_sim_time "${log}" 2>/dev/null || echo "?")"
    if [[ "${sim}" != "?" && -n "${runtime}" ]]; then
      pct=$(awk -v s="${sim}" -v r="${runtime}" 'BEGIN { if (r>0) printf "%.1f", 100*s/r; else print "?" }')
    else
      pct="?"
    fi
    disk_h="$(du -sh "${run_dir}" 2>/dev/null | awk '{print $1}')"
    delta=$(( now_bytes - last_bytes ))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] progress  sim=${sim}/${runtime}s (${pct}%)  disk=${disk_h} (+$(ayil_human_bytes "${delta}") since last)"
    last_bytes="${now_bytes}"
  done
}

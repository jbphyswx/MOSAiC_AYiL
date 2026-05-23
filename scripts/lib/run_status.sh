# shellcheck shell=bash
# Status helpers for local/batch runs. Source from other scripts; do not execute directly.

AYIL_STATUS_COMPLETE=".ayil_complete"
AYIL_STATUS_RUNNING=".ayil_running"
AYIL_STATUS_INTERRUPTED=".ayil_interrupted"
AYIL_STATUS_FAILED=".ayil_failed"

ayil_read_runtime() {
  local namoptions="$1"
  awk '
    /^[[:space:]]*runtime[[:space:]]*=/ {
      gsub(/[^0-9.]/, "", $0)
      if ($0 != "") print $0
      exit
    }
  ' "${namoptions}"
}

ayil_last_sim_time() {
  local log="$1"
  [[ -f "${log}" ]] || return 1
  awk '
    /Time of Simulation:/ {
      pos = index($0, "Time of Simulation:")
      rest = substr($0, pos + 19)
      if (match(rest, /[0-9]+\.?[0-9]*/)) {
        t = substr(rest, RSTART, RLENGTH) + 0
      }
    }
    END { if (t > 0) printf "%.2f", t }
  ' "${log}"
}

# True when dales.log sim time reached the target (seconds).
ayil_sim_reached_target() {
  local log="$1"
  local target_sec="$2"
  local sim
  sim="$(ayil_last_sim_time "${log}")"
  [[ -n "${target_sec}" && -n "${sim}" ]] || return 1
  awk -v s="${sim}" -v r="${target_sec}" 'BEGIN { exit (s >= r - 2.0) ? 0 : 1 }'
}

ayil_sim_complete() {
  local log="$1"
  local namoptions="$2"
  local runtime
  runtime="$(ayil_read_runtime "${namoptions}")"
  ayil_sim_reached_target "${log}" "${runtime}"
}

ayil_run_state() {
  local run_dir="$1"
  if [[ -f "${run_dir}/${AYIL_STATUS_COMPLETE}" ]]; then
    echo "complete"
  elif compgen -G "${run_dir}/.ayil_chunk_*_complete" >/dev/null 2>&1; then
    echo "partial"
  elif [[ -f "${run_dir}/${AYIL_STATUS_FAILED}" ]]; then
    echo "failed"
  elif [[ -f "${run_dir}/${AYIL_STATUS_INTERRUPTED}" ]]; then
    echo "interrupted"
  elif [[ -f "${run_dir}/${AYIL_STATUS_RUNNING}" ]]; then
    echo "running"
  elif [[ -d "${run_dir}" && -f "${run_dir}/namoptions" ]]; then
    echo "prepared"
  else
    echo "missing"
  fi
}

# Slurm TIMEOUT often leaves .ayil_running with sacct ExitCode 0:0; clear so submit can resume.
ayil_recover_stale_run_state() {
  local run_dir="$1"
  local pid
  [[ -d "${run_dir}" ]] || return 0
  if [[ -f "${run_dir}/${AYIL_STATUS_COMPLETE}" ]]; then
    return 0
  fi
  if [[ ! -f "${run_dir}/${AYIL_STATUS_RUNNING}" ]]; then
    return 0
  fi
  pid="$(grep -E '^pid=' "${run_dir}/${AYIL_STATUS_RUNNING}" 2>/dev/null | cut -d= -f2- || true)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  if [[ -f "${run_dir}/${AYIL_STATUS_FAILED}" || -f "${run_dir}/${AYIL_STATUS_INTERRUPTED}" ]]; then
    rm -f "${run_dir}/${AYIL_STATUS_RUNNING}"
    return 0
  fi
  echo "WARN: clearing stale ${AYIL_STATUS_RUNNING} on ${run_dir} (job ended without complete markers)" >&2
  rm -f "${run_dir}/${AYIL_STATUS_RUNNING}"
  if [[ ! -f "${run_dir}/${AYIL_STATUS_FAILED}" ]]; then
    echo "failed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${run_dir}/${AYIL_STATUS_FAILED}"
    echo "exit_code=stale_running" >> "${run_dir}/${AYIL_STATUS_FAILED}"
  fi
}

ayil_mark_running() {
  local run_dir="$1"
  local date="$2"
  local nproc="$3"
  local log="${4:-}"
  local sim_at_start="0"
  if [[ -n "${log}" && -f "${log}" ]]; then
    sim_at_start="$(ayil_last_sim_time "${log}" 2>/dev/null || echo 0)"
  fi
  rm -f "${run_dir}/${AYIL_STATUS_INTERRUPTED}" "${run_dir}/${AYIL_STATUS_FAILED}"
  cat > "${run_dir}/${AYIL_STATUS_RUNNING}" <<EOF
date=${date}
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
nproc=${nproc}
pid=$$
sim_at_start=${sim_at_start}
EOF
}

ayil_mark_complete() {
  local run_dir="$1"
  local log="$2"
  local nproc="$3"
  rm -f "${run_dir}/${AYIL_STATUS_RUNNING}"
  {
    echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "nproc=${nproc}"
    echo "disk_bytes=$(du -sb "${run_dir}" | awk '{print $1}')"
    echo "disk_human=$(du -sh "${run_dir}" | awk '{print $1}')"
    echo "sim_time_last=$(ayil_last_sim_time "${log}")"
    echo "runtime_target=$(ayil_read_runtime "${run_dir}/namoptions")"
  } > "${run_dir}/${AYIL_STATUS_COMPLETE}"
}

ayil_mark_interrupted() {
  local run_dir="$1"
  local log="$2"
  rm -f "${run_dir}/${AYIL_STATUS_RUNNING}"
  {
    echo "interrupted_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "sim_time_last=$(ayil_last_sim_time "${log}" 2>/dev/null || echo unknown)"
    echo "disk_human=$(du -sh "${run_dir}" 2>/dev/null | awk '{print $1}' || echo unknown)"
  } > "${run_dir}/${AYIL_STATUS_INTERRUPTED}"
}

ayil_mark_failed() {
  local run_dir="$1"
  local exit_code="$2"
  rm -f "${run_dir}/${AYIL_STATUS_RUNNING}"
  {
    echo "failed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "exit_code=${exit_code}"
  } > "${run_dir}/${AYIL_STATUS_FAILED}"
}

ayil_human_bytes() {
  numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "${1} bytes"
}

ayil_dir_size_bytes() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

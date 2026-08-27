# shellcheck shell=bash
# Slurm chunk chains: split one MOSAiC day into short DALES segments with restart handoff.
# Source after config.sh and run_status.sh.

# Seconds of simulation per day (JAMES paper: 3 h). Zenodo archives used 7200 s.
export AYiL_DAY_RUNTIME_SEC="${AYiL_DAY_RUNTIME_SEC:-10800}"
# Chunk length (30 min); must divide day runtime evenly for equal chunks.
export AYiL_CHUNK_SIM_SEC="${AYiL_CHUNK_SIM_SEC:-1800}"

# Warm-start template for chunked Slurm (not in Zenodo cold-start namoptions).
# Must match do_writerestartfiles linkname + readrestartfiles; see scripts/lib/restart_naming.sh.
AYiL_RESTART_STARTFILE="${AYiL_RESTART_STARTFILE:-initdlatestm00000001.001}"

# Cumulative simulation end time (s since cold start) for chunk index k.
# Used with ltotruntime=.true. in namoptions (DALES modstartup readinitfiles).
ayil_chunk_cumulative_runtime_sec() {
  local chunk_idx="$1"
  local chunk_sec="${2:-${AYiL_CHUNK_SIM_SEC}}"
  echo $(( (chunk_idx + 1) * chunk_sec ))
}

ayil_n_chunks() {
  local day="${1:-${AYiL_DAY_RUNTIME_SEC}}"
  local chunk="${2:-${AYiL_CHUNK_SIM_SEC}}"
  if (( chunk <= 0 )); then
    echo "ERROR: AYiL_CHUNK_SIM_SEC must be positive" >&2
    return 1
  fi
  if (( day % chunk != 0 )); then
    echo "ERROR: AYiL_DAY_RUNTIME_SEC=${day} must be divisible by AYiL_CHUNK_SIM_SEC=${chunk}" >&2
    return 1
  fi
  echo $(( day / chunk ))
}

ayil_chunk_marker() {
  local run_dir="$1"
  local chunk_idx="$2"
  echo "${run_dir}/.ayil_chunk_${chunk_idx}_complete"
}

ayil_mark_chunk_complete() {
  local run_dir="$1"
  local chunk_idx="$2"
  local log="$3"
  local nproc="$4"
  {
    echo "chunk=${chunk_idx}"
    echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "nproc=${nproc}"
    echo "sim_time_last=$(ayil_last_sim_time "${log}" 2>/dev/null || echo unknown)"
    echo "runtime_target=$(ayil_read_runtime "${run_dir}/namoptions")"
  } > "$(ayil_chunk_marker "${run_dir}" "${chunk_idx}")"
}

ayil_chunk_is_complete() {
  local run_dir="$1"
  local chunk_idx="$2"
  [[ -f "$(ayil_chunk_marker "${run_dir}" "${chunk_idx}")" ]]
}

# First chunk index that still needs a Slurm job (0..n-1), or -1 if all done.
ayil_first_incomplete_chunk() {
  local run_dir="$1"
  local n_chunks="$2"
  local c
  for ((c = 0; c < n_chunks; c++)); do
    if ! ayil_chunk_is_complete "${run_dir}" "${c}"; then
      echo "${c}"
      return 0
    fi
  done
  echo -1
}

ayil_clear_chunk_markers() {
  local run_dir="$1"
  find "${run_dir}" -maxdepth 1 -name '.ayil_chunk_*_complete' -delete 2>/dev/null || true
}

# Delete timed restart files; keep initdlatest*/initslatest* for the next chunk.
ayil_prune_timed_restart_files() {
  local run_dir="$1"
  find "${run_dir}" -maxdepth 1 \( \
    -name 'initd[0-9]*h*m*.001' -o -name 'inits[0-9]*h*m*.001' \
    \) ! -name 'initdlatest*.001' ! -name 'initslatest*.001' -delete 2>/dev/null || true
}

ayil_prune_all_restart_files() {
  local run_dir="$1"
  find "${run_dir}" -maxdepth 1 \( -name 'initd*.001' -o -name 'inits*.001' \) -delete 2>/dev/null || true
}

ayil_all_chunks_complete() {
  local run_dir="$1"
  local n_chunks="$2"
  local c
  for ((c = 0; c < n_chunks; c++)); do
    if ! ayil_chunk_is_complete "${run_dir}" "${c}"; then
      return 1
    fi
  done
  return 0
}

# Return 0 if generated outputs should be removed before this job runs.
#
# Without --force: wipe only when (re)starting chunk 0 of an incomplete day — removes
# garbage from crashed old single-job runs; resume chunk k>0 keeps fielddump + restarts.
# With --force: same wipe on chunk 0 only (not chunk 1..N — avoids deleting prior chunks).
# Completed days (.ayil_complete) are never cleaned unless --force and this is chunk 0.
ayil_should_clean_run_outputs() {
  local run_dir="$1"
  local force="${2:-0}"
  local chunk_mode="${3:-0}"
  local chunk_idx="${4:-0}"

  if [[ -f "${run_dir}/.ayil_complete" ]] && (( force != 1 )); then
    return 1
  fi

  if (( force == 1 )); then
    if [[ "${chunk_mode}" == "1" ]] && (( chunk_idx > 0 )); then
      return 1
    fi
    return 0
  fi

  if [[ "${chunk_mode}" == "1" ]]; then
    (( chunk_idx == 0 )) || return 1
    if ayil_chunk_is_complete "${run_dir}" 0; then
      return 1
    fi
    return 0
  fi

  return 0
}

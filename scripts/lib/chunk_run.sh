# shellcheck shell=bash
# Slurm chunk chains: split one MOSAiC day into short DALES segments with restart handoff.
# Source after config.sh and run_status.sh.

# Seconds of simulation per day (JAMES paper: 3 h). Zenodo archives used 7200 s.
export AYIL_DAY_RUNTIME_SEC="${AYIL_DAY_RUNTIME_SEC:-10800}"
# Chunk length (30 min); must divide day runtime evenly for equal chunks.
export AYIL_CHUNK_SIM_SEC="${AYIL_CHUNK_SIM_SEC:-1800}"

# DALES warm-start template; MPI replaces chars 13:20 with cmyid per rank.
AYIL_RESTART_STARTFILE="${AYIL_RESTART_STARTFILE:-initdlatestx000y000.001}"

ayil_n_chunks() {
  local day="${1:-${AYIL_DAY_RUNTIME_SEC}}"
  local chunk="${2:-${AYIL_CHUNK_SIM_SEC}}"
  if (( chunk <= 0 )); then
    echo "ERROR: AYIL_CHUNK_SIM_SEC must be positive" >&2
    return 1
  fi
  if (( day % chunk != 0 )); then
    echo "ERROR: AYIL_DAY_RUNTIME_SEC=${day} must be divisible by AYIL_CHUNK_SIM_SEC=${chunk}" >&2
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

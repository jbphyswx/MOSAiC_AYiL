# shellcheck shell=bash
# MOSAiC_AYiL overrides applied to per-day ``namoptions`` when staging or running DALES.

# Replace one namelist assignment (whole line).
ayil_namoptions_replace() {
  local namoptions="$1"
  local key="$2"
  local new_line="$3"
  if [[ ! -f "${namoptions}" ]]; then
    echo "ERROR: namoptions not found: ${namoptions}" >&2
    return 1
  fi
  if ! grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${namoptions}"; then
    echo "ERROR: ${key} not found in ${namoptions}" >&2
    return 1
  fi
  sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${new_line}|" "${namoptions}"
}

# Set &run runtime (seconds).
ayil_set_runtime() {
  local namoptions="$1"
  local runtime_sec="$2"
  ayil_namoptions_replace "${namoptions}" runtime \
    "    runtime = ${runtime_sec}    ! AYiL: simulation length (s)"
}

# Insert or replace a namelist key in namoptions.
ayil_namoptions_ensure() {
  local namoptions="$1"
  local key="$2"
  local new_line="$3"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${namoptions}"; then
    ayil_namoptions_replace "${namoptions}" "${key}" "${new_line}"
  else
    sed -i -E "/^[[:space:]]*runtime[[:space:]]*=/a\\
${new_line}" "${namoptions}"
  fi
}

# DALES default ltotruntime=.false. adds btime to runtime (segment since warm start).
# Chunk chains use cumulative runtime since the cold start of the day.
ayil_set_ltotruntime() {
  local namoptions="$1"
  local flag="${2:-true}" # true | false
  ayil_namoptions_ensure "${namoptions}" ltotruntime \
    "    ltotruntime = .${flag}.    ! AYiL: runtime is total since cold start"
}

# DALES modstartup: trestart < 0 disables all restart file output (initd/inits).
ayil_disable_restart_writes() {
  ayil_namoptions_replace "$1" trestart \
    '    trestart = -1    ! AYiL: no restart checkpoints (DALES trestart < 0)'
}

# trestart = 0: write restart only at end of this segment's runtime.
ayil_enable_restart_at_segment_end() {
  ayil_namoptions_replace "$1" trestart \
    '    trestart = 0    ! AYiL: restart at end of this segment only'
}

ayil_set_lwarmstart() {
  local namoptions="$1"
  local flag="$2" # true | false
  ayil_namoptions_replace "${namoptions}" lwarmstart "    lwarmstart = .${flag}."
}

ayil_set_startfile() {
  local namoptions="$1"
  local startfile="$2"
  ayil_namoptions_replace "${namoptions}" startfile \
    "    startfile = '${startfile}'"
}

# Apply namoptions for one Slurm chunk (see scripts/lib/chunk_run.sh).
# chunk_idx: 0 .. n_chunks-1; n_chunks = day_runtime / chunk_sec (must divide evenly).
ayil_apply_chunk_namoptions() {
  local namoptions="$1"
  local chunk_idx="$2"
  local n_chunks="$3"
  local chunk_sec="${4:-${AYiL_CHUNK_SIM_SEC}}"
  local day_sec="${5:-${AYiL_DAY_RUNTIME_SEC}}"
  local startfile="${6:-${AYiL_RESTART_STARTFILE}}"

  if (( chunk_idx < 0 || chunk_idx >= n_chunks )); then
    echo "ERROR: chunk_idx=${chunk_idx} out of range for n_chunks=${n_chunks}" >&2
    return 1
  fi
  if (( day_sec % chunk_sec != 0 || n_chunks != day_sec / chunk_sec )); then
    echo "ERROR: inconsistent chunking (day=${day_sec} chunk=${chunk_sec} n_chunks=${n_chunks})" >&2
    return 1
  fi

  local is_last=0
  if (( chunk_idx == n_chunks - 1 )); then
    is_last=1
  fi

  local cum_runtime
  cum_runtime="$(ayil_chunk_cumulative_runtime_sec "${chunk_idx}" "${chunk_sec}")"
  ayil_set_ltotruntime "${namoptions}" true
  ayil_set_runtime "${namoptions}" "${cum_runtime}"

  if (( chunk_idx == 0 )); then
    ayil_set_lwarmstart "${namoptions}" false
  else
    ayil_set_lwarmstart "${namoptions}" true
    ayil_set_startfile "${namoptions}" "${startfile}"
  fi

  if (( is_last )); then
    ayil_disable_restart_writes "${namoptions}"
  else
    ayil_enable_restart_at_segment_end "${namoptions}"
  fi
}

# Stage defaults: paper runtime; restarts only when chunk Slurm mode is enabled later.
ayil_apply_prepare_namoptions() {
  local namoptions="$1"
  ayil_set_runtime "${namoptions}" "${AYiL_DAY_RUNTIME_SEC:-10800}"
  if [[ "${AYiL_USE_RESTART_CHUNKS:-0}" != "1" ]]; then
    ayil_disable_restart_writes "${namoptions}"
  fi
}

# shellcheck shell=bash
# Slurm resource defaults for MOSAiC_AYIL. Source after config.sh.
#
# Tuned for Caltech Resnick HPC-style single-node MPI (64 ranks, 320 grid).
# Override in scripts/env.local on other systems.
#
# Memory: --mem is total job RAM = ntasks × GiB/rank + headroom (not per Slurm task).
# Walltime: unless AYIL_SLURM_TIME is set, --time scales with sim segment length
# (AYIL_CHUNK_SIM_SEC per chunk job, or AYIL_DAY_RUNTIME_SEC for --no-chunked).

export AYIL_SLURM_JOB_NAME="${AYIL_SLURM_JOB_NAME:-ayil_dales}"
export AYIL_SLURM_NODES="${AYIL_SLURM_NODES:-1}"
export AYIL_SLURM_NTASKS="${AYIL_SLURM_NTASKS:-64}"
export AYIL_SLURM_CPUS_PER_TASK="${AYIL_SLURM_CPUS_PER_TASK:-1}"
# 320×320 LES @ 32 ranks used ~102 GiB of a 104 GiB request (chunk 2 warm-start OOM); default 4 GiB/rank.
export AYIL_SLURM_MEM_PER_RANK_GIB="${AYIL_SLURM_MEM_PER_RANK_GIB:-4}"
export AYIL_SLURM_MEM_HEADROOM_GIB="${AYIL_SLURM_MEM_HEADROOM_GIB:-16}"
if [[ -z "${AYIL_SLURM_MEM:-}" ]]; then
  export AYIL_SLURM_MEM="$(( AYIL_SLURM_NTASKS * AYIL_SLURM_MEM_PER_RANK_GIB + AYIL_SLURM_MEM_HEADROOM_GIB ))G"
fi

# Wall/sim reference @ AYIL_SLURM_WALL_REF_NTASKS (default 64). Other rank counts are scaled
# automatically unless AYIL_SLURM_WALL_PER_SIM_SEC is set in env.local (manual override).
export AYIL_SLURM_WALL_REF_NTASKS="${AYIL_SLURM_WALL_REF_NTASKS:-64}"
export AYIL_SLURM_WALL_REF_PER_SIM_SEC="${AYIL_SLURM_WALL_REF_PER_SIM_SEC:-17}"
# Weak-scaling exponent: wall/sim ~ ref * (ref_ntasks/ntasks)^exp (0.55 fits 64→17, 32→~25).
export AYIL_SLURM_WALL_NTASKS_EXP="${AYIL_SLURM_WALL_NTASKS_EXP:-0.55}"
export AYIL_SLURM_WALL_HEADROOM_PCT="${AYIL_SLURM_WALL_HEADROOM_PCT:-15}"
# Partition hard cap (8 h on expansion); computed wall is min(this, estimate).
export AYIL_SLURM_WALL_MAX_SEC="${AYIL_SLURM_WALL_MAX_SEC:-28800}"
export AYIL_SLURM_WALL_MIN_SEC="${AYIL_SLURM_WALL_MIN_SEC:-1800}"

# Sim seconds used for wall estimate (slurm_submit sets for --no-chunked).
export AYIL_SLURM_WALL_SIM_SEC="${AYIL_SLURM_WALL_SIM_SEC:-${AYIL_CHUNK_SIM_SEC:-600}}"

# True if wall_per is high enough that sbatch --time would exceed AYIL_SLURM_WALL_MIN_SEC.
ayil_slurm_wall_per_sim_is_usable() {
  local wall_per="$1"
  local sim_sec="${2:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local headroom_pct="${AYIL_SLURM_WALL_HEADROOM_PCT}"
  local min_sec="${AYIL_SLURM_WALL_MIN_SEC}"
  awk -v p="${wall_per}" -v s="${sim_sec}" -v h="${headroom_pct}" -v m="${min_sec}" \
    'BEGIN {
      if (p <= 0 || s <= 0) exit 1
      wall = int(s * p * (100 + h) / 100 + 0.5)
      exit (wall >= m) ? 0 : 1
    }'
}

# Reference formula (no calibration file).
ayil_slurm_formula_wall_per_sim_sec() {
  local ntasks="${1:-${AYIL_SLURM_NTASKS:-64}}"
  awk -v ref="${AYIL_SLURM_WALL_REF_PER_SIM_SEC}" -v refn="${AYIL_SLURM_WALL_REF_NTASKS}" \
    -v n="${ntasks}" -v wexp="${AYIL_SLURM_WALL_NTASKS_EXP}" \
    'BEGIN {
      if (n <= 0 || refn <= 0) exit 1
      printf "%d\n", int(ref * (refn / n) ^ wexp + 0.5)
    }'
}

# Effective wall seconds per simulated second for current AYIL_SLURM_NTASKS.
# Optional: runs/.ayil_wall_calibration from the last successful chunk on this cluster.
# Bad cal files (old bug: wall/full-day sim) are ignored automatically.
ayil_slurm_effective_wall_per_sim_sec() {
  if [[ -n "${AYIL_SLURM_WALL_PER_SIM_SEC:-}" ]]; then
    echo "${AYIL_SLURM_WALL_PER_SIM_SEC}"
    return 0
  fi

  local ntasks="${AYIL_SLURM_NTASKS:-64}"
  local cal="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}/.ayil_wall_calibration"
  local scaled=""
  if [[ -f "${cal}" ]]; then
    # shellcheck source=/dev/null
    source "${cal}"
    if [[ -n "${AYIL_CALIB_WALL_PER_SIM_SEC:-}" && -n "${AYIL_CALIB_NTASKS:-}" ]]; then
      if [[ "${ntasks}" == "${AYIL_CALIB_NTASKS}" ]]; then
        scaled="${AYIL_CALIB_WALL_PER_SIM_SEC}"
      else
        scaled="$(awk -v ref="${AYIL_CALIB_WALL_PER_SIM_SEC}" -v refn="${AYIL_CALIB_NTASKS}" \
          -v n="${ntasks}" -v wexp="${AYIL_SLURM_WALL_NTASKS_EXP}" \
          'BEGIN {
            if (n <= 0 || refn <= 0) exit 1
            printf "%d\n", int(ref * (refn / n) ^ wexp + 0.5)
          }')"
      fi
      local formula
      formula="$(ayil_slurm_formula_wall_per_sim_sec "${ntasks}")"
      if [[ -n "${scaled}" && -n "${formula}" ]] \
        && ayil_slurm_wall_per_sim_is_usable "${scaled}" \
        && (( scaled >= formula )); then
        echo "${scaled}"
        return 0
      fi
      echo "WARN: ignoring runs/.ayil_wall_calibration (wall/sim=${scaled:-?}, formula=${formula:-?}, ntasks=${ntasks}; using formula)" >&2
    fi
  fi

  ayil_slurm_formula_wall_per_sim_sec "${ntasks}"
}

# After a successful chunk, record measured wall/sim for this site (overrides formula next submit).
ayil_slurm_record_wall_calibration() {
  local run_dir="$1"
  local log="$2"
  local namoptions="${3:-${run_dir}/namoptions}"
  local runs_root="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}"
  local cal="${runs_root}/.ayil_wall_calibration"
  # shellcheck source=run_status.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_status.sh"
  local marker="${run_dir}/${AYIL_STATUS_RUNNING}"

  [[ -f "${marker}" ]] || return 0
  local nproc started_utc sim sim_start target_runtime seg_sim
  nproc="$(grep -E '^nproc=' "${marker}" | cut -d= -f2-)"
  started_utc="$(grep -E '^started_utc=' "${marker}" | cut -d= -f2-)"
  sim="$(ayil_last_sim_time "${log}")"
  sim_start="$(grep -E '^sim_at_start=' "${marker}" 2>/dev/null | cut -d= -f2- || echo 0)"
  [[ -n "${nproc}" && -n "${started_utc}" && -n "${sim}" ]] || return 0

  target_runtime="$(ayil_read_runtime "${namoptions}")"
  [[ -n "${target_runtime}" ]] || return 0
  ayil_sim_reached_target "${log}" "${target_runtime}" || return 0

  if [[ "${AYIL_USE_RESTART_CHUNKS:-0}" == "1" ]]; then
    seg_sim="$(awk -v s="${sim}" -v ss="${sim_start}" 'BEGIN { d = s - ss; if (d > 1) print d; else exit 1 }')"
  else
    seg_sim="${target_runtime}"
  fi

  local start_epoch end_epoch wall_sec wall_per min_wall_per
  min_wall_per=$(( AYIL_SLURM_WALL_REF_PER_SIM_SEC / 3 ))
  (( min_wall_per < 8 )) && min_wall_per=8

  start_epoch="$(date -u -d "${started_utc}" +%s 2>/dev/null || echo 0)"
  end_epoch="$(date -u +%s)"
  (( start_epoch > 0 && end_epoch > start_epoch )) || return 0
  wall_sec=$(( end_epoch - start_epoch ))
  wall_per="$(awk -v w="${wall_sec}" -v s="${seg_sim}" 'BEGIN { if (s > 0) printf "%.0f", w / s + 0.5; else exit 1 }')"
  [[ -n "${wall_per}" && "${wall_per}" -ge "${min_wall_per}" ]] 2>/dev/null || return 0

  mkdir -p "${runs_root}"
  cat > "${cal}" <<EOF
# Auto-written by MOSAiC_AYIL from last successful chunk (do not hand-edit unless needed).
AYIL_CALIB_NTASKS=${nproc}
AYIL_CALIB_WALL_PER_SIM_SEC=${wall_per}
AYIL_CALIB_RECORDED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AYIL_CALIB_SIM_SEC=${sim}
AYIL_CALIB_WALL_SEC=${wall_sec}
EOF
}

# Return HH:MM:00 for sbatch --time from simulated seconds in one job/chunk.
ayil_slurm_compute_walltime() {
  local sim_sec="${1:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local wall_per_sim
  wall_per_sim="$(ayil_slurm_effective_wall_per_sim_sec)"
  local headroom_pct="${AYIL_SLURM_WALL_HEADROOM_PCT}"
  local max_sec="${AYIL_SLURM_WALL_MAX_SEC}"
  local min_sec="${AYIL_SLURM_WALL_MIN_SEC}"
  local wall_sec=$(( sim_sec * wall_per_sim * (100 + headroom_pct) / 100 ))

  if (( wall_sec > max_sec )); then
    wall_sec="${max_sec}"
  fi
  if (( wall_sec < min_sec )); then
    wall_sec="${min_sec}"
  fi

  local total_min=$(( (wall_sec + 59) / 60 ))
  local h=$(( total_min / 60 ))
  local m=$(( total_min % 60 ))
  printf '%02d:%02d:00' "${h}" "${m}"
}

# Explicit AYIL_SLURM_TIME in env.local overrides the formula.
ayil_slurm_resolve_time() {
  if [[ -n "${AYIL_SLURM_TIME:-}" ]]; then
    echo "${AYIL_SLURM_TIME}"
  else
    ayil_slurm_compute_walltime
  fi
}

# Optional cap on simultaneous array tasks (Slurm --array=0-N%M). Unset = no cap.
# export AYIL_SLURM_ARRAY_MAX=8

ayil_slurm_array_spec() {
  local last="$1"
  if [[ -n "${AYIL_SLURM_ARRAY_MAX:-}" ]]; then
    echo "0-${last}%${AYIL_SLURM_ARRAY_MAX}"
  else
    echo "0-${last}"
  fi
}

export AYIL_SLURM_PARTITION="${AYIL_SLURM_PARTITION:-}"
export AYIL_SLURM_ACCOUNT="${AYIL_SLURM_ACCOUNT:-}"
export AYIL_SLURM_EXTRA="${AYIL_SLURM_EXTRA:-}"
export AYIL_SLURM_BUILD="${AYIL_SLURM_BUILD:-0}"

ayil_slurm_sbatch_opts() {
  local -n _out="$1"
  local wall_time
  wall_time="$(ayil_slurm_resolve_time)"
  _out=(
    --job-name="${AYIL_SLURM_JOB_NAME}"
    --chdir="${MOSAiC_AYIL_ROOT}"
    --nodes="${AYIL_SLURM_NODES}"
    --ntasks="${AYIL_SLURM_NTASKS}"
    --cpus-per-task="${AYIL_SLURM_CPUS_PER_TASK}"
    --time="${wall_time}"
    --mem="${AYIL_SLURM_MEM}"
  )
  if [[ -n "${AYIL_SLURM_PARTITION}" ]]; then
    _out+=(--partition="${AYIL_SLURM_PARTITION}")
  fi
  if [[ -n "${AYIL_SLURM_ACCOUNT}" ]]; then
    _out+=(--account="${AYIL_SLURM_ACCOUNT}")
  fi
  if [[ -n "${AYIL_SLURM_EXTRA}" ]]; then
    # shellcheck disable=SC2206
    _out+=(${AYIL_SLURM_EXTRA})
  fi
}

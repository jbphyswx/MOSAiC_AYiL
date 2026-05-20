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
export AYIL_SLURM_MEM_PER_RANK_GIB="${AYIL_SLURM_MEM_PER_RANK_GIB:-3}"
export AYIL_SLURM_MEM_HEADROOM_GIB="${AYIL_SLURM_MEM_HEADROOM_GIB:-8}"
if [[ -z "${AYIL_SLURM_MEM:-}" ]]; then
  export AYIL_SLURM_MEM="$(( AYIL_SLURM_NTASKS * AYIL_SLURM_MEM_PER_RANK_GIB + AYIL_SLURM_MEM_HEADROOM_GIB ))G"
fi

# Observed slow HPC rate ~1537 s sim in 7 h wall → ~16.4 s wall / s sim; default 17 + 15% headroom.
export AYIL_SLURM_WALL_PER_SIM_SEC="${AYIL_SLURM_WALL_PER_SIM_SEC:-17}"
export AYIL_SLURM_WALL_HEADROOM_PCT="${AYIL_SLURM_WALL_HEADROOM_PCT:-15}"
# Partition hard cap (8 h on expansion); computed wall is min(this, estimate).
export AYIL_SLURM_WALL_MAX_SEC="${AYIL_SLURM_WALL_MAX_SEC:-28800}"
export AYIL_SLURM_WALL_MIN_SEC="${AYIL_SLURM_WALL_MIN_SEC:-1800}"

# Sim seconds used for wall estimate (slurm_submit sets for --no-chunked).
export AYIL_SLURM_WALL_SIM_SEC="${AYIL_SLURM_WALL_SIM_SEC:-${AYIL_CHUNK_SIM_SEC:-600}}"

# Return HH:MM:00 for sbatch --time from simulated seconds in one job/chunk.
ayil_slurm_compute_walltime() {
  local sim_sec="${1:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local wall_per_sim="${AYIL_SLURM_WALL_PER_SIM_SEC}"
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

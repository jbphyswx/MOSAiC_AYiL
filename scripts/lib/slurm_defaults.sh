# shellcheck shell=bash
# Slurm resource defaults for MOSAiC_AYIL. Source after config.sh and sim_dt.sh.
#
# Walltime model (unless AYIL_SLURM_TIME is set):
#   T_wall = T_fixed + T_sim × (R_ref × N_ref / N_mpi) × f_dt
# R_ref = wall seconds per sim second at N_ref ranks (integration only, no I/O lump).
# Default R_ref=17 is a conservative placeholder — NOT tied to a logged dt@64 calibration.
# Set AYIL_SLURM_WALL_REF_PER_SIM_SEC from a finished run:
#   ./scripts/dev/estimate_wall_ref.sh YYYYMMDD --ntasks N
# f_dt ≈ ⟨dt_ref/dt⟩ from sim_dt/YYYYMMDD.csv (dt_ref is the pivot for scaling, not “the dt of 17”).
# Missing sim_dt → pessimistic dt_ref/min_dt; known date → can request less wall.
# Halving MPI tasks doubles the parallel term (ideal strong scaling).
#
# Memory: --mem = ntasks × GiB/rank + headroom.

_SIM_DT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sim_dt.sh"
# shellcheck source=sim_dt.sh
source "${_SIM_DT_LIB}"

export AYIL_SLURM_JOB_NAME="${AYIL_SLURM_JOB_NAME:-ayil_dales}"
export AYIL_SLURM_NODES="${AYIL_SLURM_NODES:-1}"
export AYIL_SLURM_NTASKS="${AYIL_SLURM_NTASKS:-64}"
export AYIL_SLURM_CPUS_PER_TASK="${AYIL_SLURM_CPUS_PER_TASK:-1}"
export AYIL_SLURM_MEM_PER_RANK_GIB="${AYIL_SLURM_MEM_PER_RANK_GIB:-4}"
export AYIL_SLURM_MEM_HEADROOM_GIB="${AYIL_SLURM_MEM_HEADROOM_GIB:-16}"
if [[ -z "${AYIL_SLURM_MEM:-}" ]]; then
  export AYIL_SLURM_MEM="$(( AYIL_SLURM_NTASKS * AYIL_SLURM_MEM_PER_RANK_GIB + AYIL_SLURM_MEM_HEADROOM_GIB ))G"
fi

# Reference point: R_ref wall/sim at N_ref ranks at dt ≈ AYIL_SIM_DT_REF_SEC (see sim_dt.sh).
export AYIL_SLURM_WALL_REF_NTASKS="${AYIL_SLURM_WALL_REF_NTASKS:-64}"
export AYIL_SLURM_WALL_REF_PER_SIM_SEC="${AYIL_SLURM_WALL_REF_PER_SIM_SEC:-17}"
# Per-job fixed overhead (init, I/O, cold start) — not divided by N_mpi or sim length.
export AYIL_SLURM_WALL_FIXED_SEC="${AYIL_SLURM_WALL_FIXED_SEC:-0}"
export AYIL_SLURM_WALL_HEADROOM_PCT="${AYIL_SLURM_WALL_HEADROOM_PCT:-15}"
export AYIL_SLURM_WALL_MAX_SEC="${AYIL_SLURM_WALL_MAX_SEC:-28800}"
export AYIL_SLURM_WALL_MIN_SEC="${AYIL_SLURM_WALL_MIN_SEC:-1800}"

export AYIL_SLURM_WALL_SIM_SEC="${AYIL_SLURM_WALL_SIM_SEC:-${AYIL_CHUNK_SIM_SEC:-600}}"

# T_wall = fixed + sim × (R_ref × N_ref / n). Integer bash arithmetic.
ayil_slurm_formula_wall_sec() {
  local sim_sec="${1:?sim_sec required}"
  local ntasks="${2:-${AYIL_SLURM_NTASKS:-64}}"
  local fixed="${AYIL_SLURM_WALL_FIXED_SEC:-0}"
  local ref_r="${AYIL_SLURM_WALL_REF_PER_SIM_SEC}"
  local ref_n="${AYIL_SLURM_WALL_REF_NTASKS}"
  if (( sim_sec <= 0 || ntasks <= 0 || ref_n <= 0 || ref_r <= 0 )); then
    return 1
  fi
  echo $(( fixed + sim_sec * ref_r * ref_n / ntasks ))
}

# Apply headroom and min/max partition caps.
ayil_slurm_clamp_wall_sec() {
  local wall_sec="$1"
  local headroom_pct="${AYIL_SLURM_WALL_HEADROOM_PCT}"
  local max_sec="${AYIL_SLURM_WALL_MAX_SEC}"
  local min_sec="${AYIL_SLURM_WALL_MIN_SEC}"
  wall_sec=$(( wall_sec * (100 + headroom_pct) / 100 ))
  if (( wall_sec > max_sec )); then
    wall_sec="${max_sec}"
  fi
  if (( wall_sec < min_sec )); then
    wall_sec="${min_sec}"
  fi
  echo "${wall_sec}"
}

# Scale a measured chunk-0 wall to another (ntasks, sim_sec); parallel term ∝ sim/n.
ayil_slurm_scale_calibrated_wall_sec() {
  local cal_wall="$1"
  local cal_n="$2"
  local cal_seg="$3"
  local submit_n="$4"
  local submit_sim="$5"
  local fixed="${AYIL_SLURM_WALL_FIXED_SEC:-0}"
  if (( cal_n <= 0 || cal_seg <= 0 || submit_n <= 0 || submit_sim <= 0 )); then
    return 1
  fi
  awk -v w="${cal_wall}" -v f="${fixed}" -v cn="${cal_n}" -v cs="${cal_seg}" \
    -v sn="${submit_n}" -v ss="${submit_sim}" \
    'BEGIN {
      parallel = w - f
      if (parallel < 0) parallel = 0
      printf "%d\n", int(f + parallel * (cn / sn) * (ss / cs) + 0.5)
    }'
}

# Scale parallel term by sim_dt table for DATE / [sim_lo,sim_hi) when set (see sim_dt.sh).
ayil_slurm_apply_dt_cost_to_wall() {
  local base_wall="$1"
  local date="${AYIL_WALL_DATE:-}"
  local sim_lo="${AYIL_WALL_SIM_LO:-0}"
  local sim_hi="${AYIL_WALL_SIM_HI:-}"
  local fixed="${AYIL_SLURM_WALL_FIXED_SEC:-0}"
  local factor parallel
  if [[ -z "${date}" || -z "${sim_hi}" ]]; then
    echo "${base_wall}"
    return 0
  fi
  factor="$(ayil_sim_dt_segment_cost_factor "${date}" "${sim_lo}" "${sim_hi}")"
  parallel=$(( base_wall - fixed ))
  if (( parallel < 0 )); then
    parallel=0
  fi
  awk -v f="${fixed}" -v p="${parallel}" -v k="${factor}" \
    'BEGIN { printf "%d\n", int(f + p * k + 0.5) }'
}

# Resolve base wall (before headroom) for one chunk: max(formula, scaled cold-start cal), × sim_dt factor.
ayil_slurm_resolve_base_wall_sec() {
  local sim_sec="${1:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local ntasks="${AYIL_SLURM_NTASKS:-64}"

  if [[ -n "${AYIL_SLURM_WALL_PER_SIM_SEC:-}" ]]; then
    # Legacy override: pure rate × sim (no fixed term, no 1/n).
    echo $(( sim_sec * AYIL_SLURM_WALL_PER_SIM_SEC ))
    return 0
  fi

  local formula scaled cal cal_n cal_seg cal_wall base
  formula="$(ayil_slurm_formula_wall_sec "${sim_sec}" "${ntasks}")" || return 1
  base="${formula}"

  local cal_file="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}/.ayil_wall_calibration"
  if [[ -f "${cal_file}" ]]; then
    # shellcheck source=/dev/null
    source "${cal_file}"
    if [[ -n "${AYIL_CALIB_SEGMENT:-}" && "${AYIL_CALIB_SEGMENT}" != "cold_start" ]]; then
      echo "WARN: ignoring runs/.ayil_wall_calibration (segment=${AYIL_CALIB_SEGMENT}; need cold_start)" >&2
    elif [[ -n "${AYIL_CALIB_WALL_SEC:-}" && -n "${AYIL_CALIB_SEG_SIM_SEC:-}" && -n "${AYIL_CALIB_NTASKS:-}" ]]; then
      cal_wall="${AYIL_CALIB_WALL_SEC}"
      cal_n="${AYIL_CALIB_NTASKS}"
      cal_seg="${AYIL_CALIB_SEG_SIM_SEC}"
      scaled="$(ayil_slurm_scale_calibrated_wall_sec "${cal_wall}" "${cal_n}" "${cal_seg}" \
        "${ntasks}" "${sim_sec}" 2>/dev/null || true)"
      if [[ -n "${scaled}" ]] && (( scaled > base )); then
        base="${scaled}"
      fi
    fi
  fi

  ayil_slurm_apply_dt_cost_to_wall "${base}"
}

# Effective wall/sim for logging (equivalent average rate for this segment length).
ayil_slurm_effective_wall_per_sim_sec() {
  local sim_sec="${1:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local wall_sec
  wall_sec="$(ayil_slurm_resolve_base_wall_sec "${sim_sec}")" || return 1
  if (( sim_sec <= 0 )); then
    return 1
  fi
  echo $(( (wall_sec + sim_sec - 1) / sim_sec ))
}

# Return HH:MM:00 for sbatch --time.
ayil_slurm_compute_walltime() {
  local sim_sec="${1:-${AYIL_SLURM_WALL_SIM_SEC}}"
  local wall_sec
  wall_sec="$(ayil_slurm_resolve_base_wall_sec "${sim_sec}")" || return 1
  wall_sec="$(ayil_slurm_clamp_wall_sec "${wall_sec}")"
  local total_min=$(( (wall_sec + 59) / 60 ))
  local h=$(( total_min / 60 ))
  local m=$(( total_min % 60 ))
  printf '%02d:%02d:00' "${h}" "${m}"
}

ayil_slurm_resolve_time() {
  if [[ -n "${AYIL_SLURM_TIME:-}" ]]; then
    echo "${AYIL_SLURM_TIME}"
  else
    ayil_slurm_compute_walltime
  fi
}

# After successful chunk-0 only: record measured wall for scaling (parallel term ∝ sim/n).
ayil_slurm_record_wall_calibration() {
  if [[ "${AYIL_CHUNK_INDEX:-0}" != "0" ]]; then
    return 0
  fi
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

  local start_epoch end_epoch wall_sec wall_per formula_sec
  start_epoch="$(date -u -d "${started_utc}" +%s 2>/dev/null || echo 0)"
  end_epoch="$(date -u +%s)"
  (( start_epoch > 0 && end_epoch > start_epoch )) || return 0
  wall_sec=$(( end_epoch - start_epoch ))
  formula_sec="$(ayil_slurm_formula_wall_sec "${seg_sim}" "${nproc}" 2>/dev/null || echo 0)"
  # Reject measurements far below the 1/n model (bad segment time or clock).
  if [[ -z "${formula_sec}" ]] || (( wall_sec * 100 < formula_sec * 80 )); then
    return 0
  fi
  wall_per="$(awk -v w="${wall_sec}" -v s="${seg_sim}" 'BEGIN { if (s > 0) printf "%.0f", w / s + 0.5; else exit 1 }')"

  mkdir -p "${runs_root}"
  cat > "${cal}" <<EOF
# Auto-written from last successful chunk-0 (cold start). Submit uses max(formula, scaled cal).
AYIL_CALIB_SEGMENT=cold_start
AYIL_CALIB_CHUNK_INDEX=0
AYIL_CALIB_NTASKS=${nproc}
AYIL_CALIB_WALL_SEC=${wall_sec}
AYIL_CALIB_SEG_SIM_SEC=${seg_sim}
AYIL_CALIB_WALL_PER_SIM_SEC=${wall_per}
AYIL_CALIB_RECORDED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

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
  local wall_time="${2:-}"
  if [[ -z "${wall_time}" ]]; then
    wall_time="$(ayil_slurm_resolve_time)"
  fi
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

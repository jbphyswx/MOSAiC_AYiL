#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MOSAiC_AYiL_ROOT="${REPO_ROOT}"
export AYiL_CHUNK_SIM_SEC=600
export AYiL_SLURM_WALL_FIXED_SEC=0
export AYiL_SLURM_WALL_REF_PER_SIM_SEC=14
export AYiL_SLURM_WALL_REF_NTASKS=64
export AYiL_SLURM_WALL_HEADROOM_PCT=15
export AYiL_SLURM_WALL_MAX_SEC=28800
export AYiL_SIM_DT_USE=0
unset AYiL_SLURM_TIME
unset AYiL_SLURM_WALL_PER_SIM_SEC
unset AYiL_WALL_DATE AYiL_WALL_SIM_LO AYiL_WALL_SIM_HI
# shellcheck source=../../scripts/lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"

# T = sim × R_ref × N_ref / n  (fixed=0 here)
export AYiL_SLURM_NTASKS=64
t="$(ayil_slurm_compute_walltime 600)"
[[ "${t}" == "02:41:00" ]] || {
  echo "FAIL: 64 ranks 600s sim expected 02:41:00, got ${t}" >&2
  exit 1
}
w64="$(ayil_slurm_effective_wall_per_sim_sec 600)"
[[ "${w64}" == "14" ]] || {
  echo "FAIL: 64 ranks effective wall/sim expected 14, got ${w64}" >&2
  exit 1
}
echo "PASS: 600s @ 64 ranks -> ${t} (wall/sim=${w64})"

# Half ranks → double parallel term for same sim length
export AYiL_SLURM_NTASKS=32
w32="$(ayil_slurm_effective_wall_per_sim_sec 300)"
[[ "${w32}" == "28" ]] || {
  echo "FAIL: 32 ranks expected wall/sim=28 (2×14), got ${w32}" >&2
  exit 1
}
base32="$(ayil_slurm_formula_wall_sec 300 32)"
base64="$(ayil_slurm_formula_wall_sec 300 64)"
(( base32 == 2 * base64 )) || {
  echo "FAIL: 300s sim at 32 ranks should be 2× wall of 64 ranks; got ${base32} vs ${base64}" >&2
  exit 1
}
t32="$(ayil_slurm_compute_walltime 300)"
[[ "${t32}" == "02:41:00" ]] || {
  echo "FAIL: 32 ranks 300s expected 02:41:00 (same parallel term as 600@64), got ${t32}" >&2
  exit 1
}
echo "PASS: 300s @ 32 ranks -> ${t32} (wall/sim=${w32}, 2× vs 64 ranks)"

# Fixed overhead (startup) adds on top of parallel term
export AYiL_SLURM_WALL_FIXED_SEC=600
export AYiL_SLURM_NTASKS=32
base_fixed="$(ayil_slurm_formula_wall_sec 300 32)"
(( base_fixed == 600 + 300 * 14 * 64 / 32 )) || {
  echo "FAIL: fixed+parallel formula, got ${base_fixed}" >&2
  exit 1
}
echo "PASS: fixed overhead term"

export AYiL_SLURM_WALL_FIXED_SEC=0
export AYiL_SLURM_WALL_PER_SIM_SEC=99
export AYiL_SLURM_NTASKS=32
[[ "$(ayil_slurm_effective_wall_per_sim_sec 100)" == "99" ]] || {
  echo "FAIL: AYiL_SLURM_WALL_PER_SIM_SEC override" >&2
  exit 1
}
echo "PASS: AYiL_SLURM_WALL_PER_SIM_SEC override"

unset AYiL_SLURM_WALL_PER_SIM_SEC
export AYiL_SLURM_TIME=02:00:00
[[ "$(ayil_slurm_resolve_time)" == "02:00:00" ]] || {
  echo "FAIL: AYiL_SLURM_TIME override" >&2
  exit 1
}
echo "PASS: AYiL_SLURM_TIME override"

# Low calibrated wall must not shrink below formula
export AYiL_SLURM_NTASKS=32
export AYiL_SLURM_WALL_SIM_SEC=300
unset AYiL_SLURM_TIME
CAL_DIR="${REPO_ROOT}/test/tmp_cal"
mkdir -p "${CAL_DIR}"
export AYiL_RUNS="${CAL_DIR}"
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYiL_CALIB_SEGMENT=cold_start
AYiL_CALIB_NTASKS=32
AYiL_CALIB_WALL_SEC=2000
AYiL_CALIB_SEG_SIM_SEC=300
EOF
t_cal="$(ayil_slurm_compute_walltime 300)"
[[ "${t_cal}" == "02:41:00" ]] || {
  echo "FAIL: low cal must not beat formula, got ${t_cal}" >&2
  exit 1
}
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYiL_CALIB_SEGMENT=cold_start
AYiL_CALIB_NTASKS=32
AYiL_CALIB_WALL_SEC=15000
AYiL_CALIB_SEG_SIM_SEC=300
EOF
t_high="$(ayil_slurm_compute_walltime 300)"
# 15000 * 1.15 = 17250 -> 04:48:00 (ceil to minutes)
[[ "${t_high}" == "04:48:00" ]] || {
  echo "FAIL: high cal should raise walltime, got ${t_high}" >&2
  exit 1
}
rm -rf "${CAL_DIR}"
echo "PASS: calibration max(formula, scaled measurement)"

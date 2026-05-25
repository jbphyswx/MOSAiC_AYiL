#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
export AYIL_CHUNK_SIM_SEC=600
export AYIL_SLURM_WALL_FIXED_SEC=0
export AYIL_SLURM_WALL_REF_PER_SIM_SEC=17
export AYIL_SLURM_WALL_REF_NTASKS=64
export AYIL_SLURM_WALL_HEADROOM_PCT=15
export AYIL_SLURM_WALL_MAX_SEC=28800
unset AYIL_SLURM_TIME
unset AYIL_SLURM_WALL_PER_SIM_SEC
# shellcheck source=../../scripts/lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"

# T = sim × R_ref × N_ref / n  (fixed=0 here)
export AYIL_SLURM_NTASKS=64
t="$(ayil_slurm_compute_walltime 600)"
[[ "${t}" == "03:16:00" ]] || {
  echo "FAIL: 64 ranks 600s sim expected 03:16:00, got ${t}" >&2
  exit 1
}
w64="$(ayil_slurm_effective_wall_per_sim_sec 600)"
[[ "${w64}" == "17" ]] || {
  echo "FAIL: 64 ranks effective wall/sim expected 17, got ${w64}" >&2
  exit 1
}
echo "PASS: 600s @ 64 ranks -> ${t} (wall/sim=${w64})"

# Half ranks → double parallel term for same sim length
export AYIL_SLURM_NTASKS=32
w32="$(ayil_slurm_effective_wall_per_sim_sec 300)"
[[ "${w32}" == "34" ]] || {
  echo "FAIL: 32 ranks expected wall/sim=34 (2×17), got ${w32}" >&2
  exit 1
}
base32="$(ayil_slurm_formula_wall_sec 300 32)"
base64="$(ayil_slurm_formula_wall_sec 300 64)"
(( base32 == 2 * base64 )) || {
  echo "FAIL: 300s sim at 32 ranks should be 2× wall of 64 ranks; got ${base32} vs ${base64}" >&2
  exit 1
}
t32="$(ayil_slurm_compute_walltime 300)"
[[ "${t32}" == "03:16:00" ]] || {
  echo "FAIL: 32 ranks 300s expected 03:16:00 (same parallel term as 600@64), got ${t32}" >&2
  exit 1
}
echo "PASS: 300s @ 32 ranks -> ${t32} (wall/sim=${w32}, 2× vs 64 ranks)"

# Fixed overhead (startup) adds on top of parallel term
export AYIL_SLURM_WALL_FIXED_SEC=600
export AYIL_SLURM_NTASKS=32
base_fixed="$(ayil_slurm_formula_wall_sec 300 32)"
(( base_fixed == 600 + 300 * 17 * 64 / 32 )) || {
  echo "FAIL: fixed+parallel formula, got ${base_fixed}" >&2
  exit 1
}
echo "PASS: fixed overhead term"

export AYIL_SLURM_WALL_FIXED_SEC=0
export AYIL_SLURM_WALL_PER_SIM_SEC=99
export AYIL_SLURM_NTASKS=32
[[ "$(ayil_slurm_effective_wall_per_sim_sec 100)" == "99" ]] || {
  echo "FAIL: AYIL_SLURM_WALL_PER_SIM_SEC override" >&2
  exit 1
}
echo "PASS: AYIL_SLURM_WALL_PER_SIM_SEC override"

unset AYIL_SLURM_WALL_PER_SIM_SEC
export AYIL_SLURM_TIME=02:00:00
[[ "$(ayil_slurm_resolve_time)" == "02:00:00" ]] || {
  echo "FAIL: AYIL_SLURM_TIME override" >&2
  exit 1
}
echo "PASS: AYIL_SLURM_TIME override"

# Low calibrated wall must not shrink below formula
export AYIL_SLURM_NTASKS=32
export AYIL_SLURM_WALL_SIM_SEC=300
unset AYIL_SLURM_TIME
CAL_DIR="${REPO_ROOT}/test/tmp_cal"
mkdir -p "${CAL_DIR}"
export AYIL_RUNS="${CAL_DIR}"
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYIL_CALIB_SEGMENT=cold_start
AYIL_CALIB_NTASKS=32
AYIL_CALIB_WALL_SEC=2000
AYIL_CALIB_SEG_SIM_SEC=300
EOF
t_cal="$(ayil_slurm_compute_walltime 300)"
[[ "${t_cal}" == "03:16:00" ]] || {
  echo "FAIL: low cal must not beat formula, got ${t_cal}" >&2
  exit 1
}
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYIL_CALIB_SEGMENT=cold_start
AYIL_CALIB_NTASKS=32
AYIL_CALIB_WALL_SEC=15000
AYIL_CALIB_SEG_SIM_SEC=300
EOF
t_high="$(ayil_slurm_compute_walltime 300)"
# 15000 * 1.15 = 17250 -> 04:48:00 (ceil to minutes)
[[ "${t_high}" == "04:48:00" ]] || {
  echo "FAIL: high cal should raise walltime, got ${t_high}" >&2
  exit 1
}
rm -rf "${CAL_DIR}"
echo "PASS: calibration max(formula, scaled measurement)"

#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
export AYIL_CHUNK_SIM_SEC=600
export AYIL_SLURM_WALL_HEADROOM_PCT=15
export AYIL_SLURM_WALL_MAX_SEC=28800
unset AYIL_SLURM_TIME
unset AYIL_SLURM_WALL_PER_SIM_SEC
# shellcheck source=../../scripts/lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"

export AYIL_SLURM_NTASKS=64
t="$(ayil_slurm_compute_walltime 600)"
[[ "${t}" == "03:16:00" ]] || {
  echo "FAIL: 64 ranks expected 03:16:00, got ${t}" >&2
  exit 1
}
w64="$(ayil_slurm_effective_wall_per_sim_sec)"
[[ "${w64}" == "17" ]] || {
  echo "FAIL: 64 ranks wall/sim expected 17, got ${w64}" >&2
  exit 1
}
echo "PASS: walltime 600s @ 64 ranks -> ${t} (wall/sim=${w64})"

export AYIL_SLURM_NTASKS=32
w32="$(ayil_slurm_effective_wall_per_sim_sec)"
t32="$(ayil_slurm_compute_walltime 300)"
# 300 * 25 * 1.15 = 8625 s -> 02:24:00
[[ "${t32}" == "02:24:00" ]] || {
  echo "FAIL: 32 ranks 300s chunk expected 02:24:00, got ${t32} (wall/sim=${w32})" >&2
  exit 1
}
(( w32 >= 24 && w32 <= 26 )) || {
  echo "FAIL: 32 ranks wall/sim expected ~25, got ${w32}" >&2
  exit 1
}
echo "PASS: walltime 300s @ 32 ranks -> ${t32} (wall/sim=${w32})"

export AYIL_SLURM_WALL_PER_SIM_SEC=99
[[ "$(ayil_slurm_effective_wall_per_sim_sec)" == "99" ]] || {
  echo "FAIL: env.local override AYIL_SLURM_WALL_PER_SIM_SEC" >&2
  exit 1
}
echo "PASS: AYIL_SLURM_WALL_PER_SIM_SEC override"

export AYIL_SLURM_TIME=02:00:00
unset AYIL_SLURM_WALL_PER_SIM_SEC
[[ "$(ayil_slurm_resolve_time)" == "02:00:00" ]] || {
  echo "FAIL: explicit AYIL_SLURM_TIME override" >&2
  exit 1
}
echo "PASS: AYIL_SLURM_TIME override"

# Stale/bad auto-calibration must not force 30:00 wall (old bug: wall_sec / cumulative sim).
export AYIL_SLURM_NTASKS=32
export AYIL_SLURM_WALL_SIM_SEC=300
unset AYIL_SLURM_WALL_PER_SIM_SEC
CAL_DIR="${REPO_ROOT}/test/tmp_cal"
mkdir -p "${CAL_DIR}"
export AYIL_RUNS="${CAL_DIR}"
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYIL_CALIB_NTASKS=32
AYIL_CALIB_WALL_PER_SIM_SEC=3
EOF
w_bad="$(ayil_slurm_effective_wall_per_sim_sec 2>/dev/null)"
[[ "${w_bad}" == "25" ]] || {
  echo "FAIL: bad cal wall/sim=3 should be ignored, got ${w_bad}" >&2
  exit 1
}
t_bad="$(ayil_slurm_compute_walltime 300)"
[[ "${t_bad}" == "02:24:00" ]] || {
  echo "FAIL: with bad cal ignored, expected 02:24:00, got ${t_bad}" >&2
  exit 1
}
# wall/sim=20 still below formula (~25) — must not shorten walltime
mkdir -p "${CAL_DIR}"
cat > "${CAL_DIR}/.ayil_wall_calibration" <<'EOF'
AYIL_CALIB_NTASKS=32
AYIL_CALIB_WALL_PER_SIM_SEC=20
EOF
w20="$(ayil_slurm_effective_wall_per_sim_sec 2>/dev/null)"
[[ "${w20}" == "25" ]] || {
  echo "FAIL: cal 20 < formula 25 should be ignored, got ${w20}" >&2
  exit 1
}
rm -rf "${CAL_DIR}"
echo "PASS: ignore unusable .ayil_wall_calibration"

#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export AYIL_CHUNK_SIM_SEC=600
export AYIL_SLURM_WALL_PER_SIM_SEC=17
export AYIL_SLURM_WALL_HEADROOM_PCT=15
export AYIL_SLURM_WALL_MAX_SEC=28800
unset AYIL_SLURM_TIME
# shellcheck source=../../scripts/lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"

t="$(ayil_slurm_compute_walltime 600)"
[[ "${t}" == "03:16:00" ]] || {
  echo "FAIL: expected 03:16:00 for 600s chunk, got ${t}" >&2
  exit 1
}
echo "PASS: walltime 600s chunk -> ${t}"

export AYIL_SLURM_TIME=02:00:00
[[ "$(ayil_slurm_resolve_time)" == "02:00:00" ]] || {
  echo "FAIL: explicit AYIL_SLURM_TIME override" >&2
  exit 1
}
echo "PASS: AYIL_SLURM_TIME override"

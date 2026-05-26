#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
export AYIL_SIM_DT_DIR="$(mktemp -d)"
export AYIL_SIM_DT_BIN_SEC=60
export AYIL_SIM_DT_REF_SEC=2.0
export AYIL_SIM_DT_RECORD=1
trap 'rm -rf "${AYIL_SIM_DT_DIR}" "${AYIL_SIM_DT_FROZEN_DIR:-}"' EXIT
# shellcheck source=../../scripts/lib/sim_dt.sh
source "${REPO_ROOT}/scripts/lib/sim_dt.sh"

ayil_sim_dt_merge_log "FAST" "${REPO_ROOT}/test/fixtures/dales_log_dt_fast.txt" "64"
f_fast="$(ayil_sim_dt_segment_cost_factor FAST 0 120)"
awk -v f="${f_fast}" 'BEGIN { if (f < 0.95 || f > 1.05) exit 1 }' || {
  echo "FAIL: FAST factor expected ~1, got ${f_fast}" >&2
  exit 1
}
echo "PASS: FAST sim_dt factor=${f_fast}"

ayil_sim_dt_merge_log "SLOW" "${REPO_ROOT}/test/fixtures/dales_log_dt_slow.txt" "32"
f_slow="$(ayil_sim_dt_segment_cost_factor SLOW 0 120)"
awk -v f="${f_slow}" 'BEGIN { if (f < 2.5 || f > 3.0) exit 1 }' || {
  echo "FAIL: SLOW factor expected ~2.7, got ${f_slow}" >&2
  exit 1
}
echo "PASS: SLOW sim_dt factor=${f_slow}"

export AYIL_SLURM_WALL_FIXED_SEC=0
export AYIL_SLURM_WALL_REF_PER_SIM_SEC=17
export AYIL_SLURM_WALL_REF_NTASKS=64
export AYIL_SLURM_NTASKS=64
export AYIL_WALL_DATE=SLOW
export AYIL_WALL_SIM_LO=0
export AYIL_WALL_SIM_HI=120
# shellcheck source=../../scripts/lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"
base_slow="$(ayil_slurm_resolve_base_wall_sec 120)"
unset AYIL_WALL_DATE AYIL_WALL_SIM_LO AYIL_WALL_SIM_HI
base_plain="$(ayil_slurm_resolve_base_wall_sec 120)"
(( base_slow > base_plain )) || {
  echo "FAIL: SLOW wall base ${base_slow} should exceed plain ${base_plain}" >&2
  exit 1
}
echo "PASS: wall base with sim_dt ${base_slow} > ${base_plain}"

export AYIL_SIM_DT_FROZEN_DIR="$(mktemp -d)"
export AYIL_SIM_DT_DIR="${AYIL_SIM_DT_FROZEN_DIR}"
echo "20190101" > "${AYIL_SIM_DT_FROZEN_DIR}/.corpus_complete"
export AYIL_SIM_DT_RECORD=1
ayil_sim_dt_merge_log "X" "${REPO_ROOT}/test/fixtures/dales_log_dt_fast.txt" "1"
[[ ! -f "${AYIL_SIM_DT_FROZEN_DIR}/X.csv" ]] || {
  echo "FAIL: merge should no-op when .corpus_complete exists" >&2
  exit 1
}
echo "PASS: no runtime merge after corpus_complete"

f_unk="$(ayil_sim_dt_segment_cost_factor UNKNOWN_DATE 0 300)"
pess="$(ayil_sim_dt_pessimistic_cost_factor)"
[[ "${f_unk}" == "${pess}" ]] || {
  echo "FAIL: missing sim_dt must use pessimistic factor; got ${f_unk} expected ${pess}" >&2
  exit 1
}
echo "PASS: missing sim_dt uses pessimistic f_dt=${f_unk}"

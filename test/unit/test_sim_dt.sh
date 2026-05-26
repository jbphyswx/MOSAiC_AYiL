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

ayil_sim_dt_merge_log "ORDER" "${REPO_ROOT}/test/fixtures/dales_log_dt_bins_order.txt" "1"
awk -F, 'BEGIN { prev = -1; bad = 0 }
  /^#/ || /^sim_bin/ { next }
  {
    b = $1 + 0
    if (b < prev) bad = 1
    prev = b
  }
  END { exit bad }' "${AYIL_SIM_DT_DIR}/ORDER.csv" || {
  echo "FAIL: ORDER.csv rows must be ascending by sim_bin_s" >&2
  exit 1
}
echo "PASS: sim_dt CSV rows sorted by sim_bin_s"

# Cumulative-log merge: second pass must keep early bins and add later sim times.
LOG_MERGE="$(mktemp)"
cat > "${LOG_MERGE}" <<'EOF'
Time of Day: 090000.000    Time of Simulation:      0.00    dt:  2.000000000
Time of Day: 090016.000    Time of Simulation:     60.00    dt:  2.000000000
EOF
ayil_sim_dt_merge_log "MERGE2" "${LOG_MERGE}" "32"
cat >> "${LOG_MERGE}" <<'EOF'
Time of Day: 090032.000    Time of Simulation:    120.00    dt:  1.500000000
EOF
ayil_sim_dt_merge_log "MERGE2" "${LOG_MERGE}" "32"
rm -f "${LOG_MERGE}"
awk -F, 'BEGIN { want="0,60,120"; got="" }
  /^#/ || /^sim_bin/ { next }
  { got = (got == "" ? $1 : got "," $1) }
  END { exit (got != want) }' "${AYIL_SIM_DT_DIR}/MERGE2.csv" || {
  echo "FAIL: cumulative merge expected bins 0,60,120 got wrong order/content" >&2
  exit 1
}
awk -F, '$1==120 && $2+0==1.5 { ok=1 }
  END { exit !ok }' "${AYIL_SIM_DT_DIR}/MERGE2.csv" || {
  echo "FAIL: cumulative merge bin 120 dt_s" >&2
  exit 1
}
echo "PASS: cumulative log merge extends existing bins"

ayil_sim_dt_merge_log "BLIP" "${REPO_ROOT}/test/fixtures/dales_log_dt_sync_blip.txt" "32"
awk -F, '$1==60 && $2+0 > 1.9 && $2+0 < 2.2 { ok=1 }
  END { exit !ok }' "${AYIL_SIM_DT_DIR}/BLIP.csv" || {
  echo "FAIL: bin 60 dt_s should be ~2.07 effective, not min 0.005" >&2
  exit 1
}
ayil_sim_dt_merge_log "TWORATE" "${REPO_ROOT}/test/fixtures/dales_log_dt_two_rate.txt" "32"
awk -F, '$1==60 && $2+0 > 39.5 && $2+0 < 40.5 { ok=1 }
  END { exit !ok }' "${AYIL_SIM_DT_DIR}/TWORATE.csv" || {
  echo "FAIL: bin 60 dt_s should be 40 (60s at dt=30 + 30s at dt=60), not arithmetic mean 45" >&2
  exit 1
}
echo "PASS: effective dt_s from interval step_units (TWORATE bin60=40)"
f_blip="$(ayil_sim_dt_segment_cost_factor BLIP 0 120)"
awk -v f="${f_blip}" 'BEGIN { if (f < 0.9 || f > 1.15) exit 1 }' || {
  echo "FAIL: sync blip chunk f_dt should be ~1, got ${f_blip}" >&2
  exit 1
}
echo "PASS: effective dt ignores single sync blip (f_dt=${f_blip})"

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

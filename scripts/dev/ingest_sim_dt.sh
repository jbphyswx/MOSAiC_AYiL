#!/usr/bin/env bash
# Bootstrap: build or refresh checked-in sim_dt/*.csv from runs/*/logs/dales.log.
#
# Not used after sim_dt/.corpus_complete — see scripts/dev/README.md and sim_dt/README.md.
#
# Usage:
#   ./scripts/dev/ingest_sim_dt.sh
#   ./scripts/dev/ingest_sim_dt.sh 20191101 20191206
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.sh
source "${SCRIPT_DIR}/../config.sh"
# shellcheck source=../lib/sim_dt.sh
source "${SCRIPT_DIR}/../lib/sim_dt.sh"

export AYIL_SIM_DT_FORCE_RECORD=1

ingest_one() {
  local date="$1"
  local log="${AYIL_RUNS}/${date}/logs/dales.log"
  if [[ ! -f "${log}" ]]; then
    echo "SKIP ${date} (no ${log})" >&2
    return 0
  fi
  local nproc=""
  if [[ -f "${AYIL_RUNS}/${date}/.ayil_complete" ]]; then
    nproc="$(grep -E '^nproc=' "${AYIL_RUNS}/${date}/.ayil_complete" 2>/dev/null | cut -d= -f2- || true)"
  fi
  ayil_sim_dt_merge_log "${date}" "${log}" "${nproc}"
  echo "OK ${date} -> $(ayil_sim_dt_csv "${date}")"
}

if (("$#" > 0)); then
  for date in "$@"; do
    ingest_one "${date}"
  done
  exit 0
fi

shopt -s nullglob
for log in "${AYIL_RUNS}"/*/logs/dales.log; do
  date="$(basename "$(dirname "$(dirname "${log}")")")"
  [[ "${date}" =~ ^[0-9]{8}$ ]] || continue
  ingest_one "${date}"
done

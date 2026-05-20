#!/usr/bin/env bash
# List status of all (or selected) MOSAiC days.
#
# Usage: list_cases.sh [YYYYMMDD ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/run_status.sh
source "${SCRIPT_DIR}/lib/run_status.sh"

DATES=()
if [[ $# -ge 1 ]]; then
  DATES=("$@")
else
  mapfile -t DATES < <(find "${AYIL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

printf "%-12s %-12s %-10s %s\n" "DATE" "STATE" "DISK" "RUN_DIR"
for DATE in "${DATES[@]}"; do
  RUN_DIR="${AYIL_RUNS}/${DATE}"
  state="$(ayil_run_state "${RUN_DIR}")"
  disk="-"
  if [[ -d "${RUN_DIR}" ]]; then
    disk="$(du -sh "${RUN_DIR}" 2>/dev/null | awk '{print $1}')"
  fi
  printf "%-12s %-12s %-10s %s\n" "${DATE}" "${state}" "${disk}" "${RUN_DIR}"
done

echo ""
echo "States: missing | prepared | running | interrupted | failed | complete"
echo "Complete runs have ${AYIL_STATUS_COMPLETE} and are skipped by run_local.sh"
echo "Logs (when present): runs/YYYYMMDD/logs/{dales.log,progress.log,slurm.out,convert.log}"

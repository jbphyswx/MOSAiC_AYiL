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
# shellcheck source=lib/logging_paths.sh
source "${SCRIPT_DIR}/lib/logging_paths.sh"

DATES=()
if [[ $# -ge 1 ]]; then
  DATES=("$@")
else
  mapfile -t DATES < <(find "${AYiL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

printf "%-12s %-12s %-10s %-8s %s\n" "DATE" "STATE" "DISK" "LOGS" "NOTES"
for DATE in "${DATES[@]}"; do
  RUN_DIR="${AYiL_RUNS}/${DATE}"
  state="$(ayil_run_state "${RUN_DIR}")"
  disk="-"
  logs="-"
  notes=""
  if [[ -d "${RUN_DIR}" ]]; then
    disk="$(du -sh "${RUN_DIR}" 2>/dev/null | awk '{print $1}')"
    if [[ -f "$(ayil_slurm_log_out "${RUN_DIR}")" ]]; then
      logs="slurm"
    elif [[ -f "$(ayil_dales_log "${RUN_DIR}")" ]]; then
      logs="dales"
    fi
    for m in "${AYiL_STATUS_FAILED}" "${AYiL_STATUS_RUNNING}" "${AYiL_STATUS_INTERRUPTED}" \
      "${AYiL_STATUS_COMPLETE}"; do
      if [[ -f "${RUN_DIR}/${m}" ]]; then
        notes="${notes:+$notes,}${m}"
      fi
    done
    shopt -s nullglob
    chunks=("${RUN_DIR}"/.ayil_chunk_*_complete)
    shopt -u nullglob
    if ((${#chunks[@]} > 0)); then
      notes="${notes:+$notes,}${#chunks[@]}_chunks_done"
    fi
    if [[ -z "${notes}" && "${state}" == "prepared" ]]; then
      notes="inputs_only"
    fi
  fi
  printf "%-12s %-12s %-10s %-8s %s\n" "${DATE}" "${state}" "${disk}" "${logs}" "${notes}"
done

echo ""
echo "States: missing | prepared | running | interrupted | failed | partial | complete"
echo "Slurm/local logs: runs/YYYYMMDD/logs/slurm.out  (always check here first on HPC)"
echo "  backup: runs/.slurm_job_logs/job_<SLURM_JOB_ID>.out  (if slurm.out was wiped — fixed in repo)"
echo "  tail runs/YYYYMMDD/logs/slurm.out   dales: runs/YYYYMMDD/logs/dales.log"
echo "Complete runs have ${AYiL_STATUS_COMPLETE} and are skipped unless --force"

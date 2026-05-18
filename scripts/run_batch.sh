#!/usr/bin/env bash
# Run (or prepare) many MOSAiC days sequentially.
#
# Usage:
#   run_batch.sh prepare [DATE ...]          # only stage inputs
#   run_batch.sh run [NPROC] [DATE ...]      # run simulations
#   run_batch.sh run [NPROC]                 # all dates under AYIL_INPUTS
#
# For HPC, prefer a job array that calls run_case.sh per date instead of this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

MODE="${1:-}"
shift || true

if [[ "${MODE}" != "prepare" && "${MODE}" != "run" ]]; then
  echo "Usage: $0 prepare|run [NPROC] [YYYYMMDD ...]" >&2
  exit 1
fi

NPROC="${DALES_NPROC}"
DATES=()

if [[ "${MODE}" == "run" && $# -ge 1 && "$1" =~ ^[0-9]+$ ]]; then
  NPROC="$1"
  shift
fi

if [[ $# -ge 1 ]]; then
  DATES=("$@")
else
  mapfile -t DATES < <(find "${AYIL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

for DATE in "${DATES[@]}"; do
  echo "======== ${DATE} ========"
  if [[ "${MODE}" == "prepare" ]]; then
    "${SCRIPT_DIR}/prepare_case.sh" "${DATE}"
  else
    "${SCRIPT_DIR}/run_case.sh" "${DATE}" "${NPROC}"
  fi
done

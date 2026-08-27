#!/usr/bin/env bash
# Bootstrap: build or refresh checked-in sim_dt/*.csv from runs/*/logs/dales.log.
#
# Default: extend only — keep existing bins; add new sim bins from the log; refresh a
# bin only if the log has more diagnostic lines for it (partial chunk filled in).
# --recompute: refresh every bin the log covers (use after algorithm/version changes).
#
# Bins outside the log's sim range are always kept from the existing CSV.
# If data rows are unchanged, the CSV file is not rewritten (no timestamp/git noise).
#
# Not used after sim_dt/.corpus_complete — see scripts/dev/README.md and sim_dt/README.md.
#
# Usage:
#   ./scripts/dev/ingest_sim_dt.sh
#   ./scripts/dev/ingest_sim_dt.sh 20191101 20191206
#   ./scripts/dev/ingest_sim_dt.sh --recompute 20191101
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.sh
source "${SCRIPT_DIR}/../config.sh"
# shellcheck source=../lib/sim_dt.sh
source "${SCRIPT_DIR}/../lib/sim_dt.sh"

export AYiL_SIM_DT_FORCE_RECORD=1

INGEST_OK=0
INGEST_SKIP=0
INGEST_WARN=0
INGEST_UNCHANGED=0
RECOMPUTE=0
DATES=()

while (("$#" > 0)); do
  case "$1" in
    --recompute)
      RECOMPUTE=1
      shift
      ;;
    -h | --help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      DATES+=("$1")
      shift
      ;;
  esac
done

export AYiL_SIM_DT_RECOMPUTE="${RECOMPUTE}"

ingest_one() {
  local date="$1"
  local log="${AYiL_RUNS}/${date}/logs/dales.log"
  local csv nproc log_bytes log_stats old_stats new_stats action

  if [[ ! -f "${log}" ]]; then
    echo "SKIP ${date}  (no log: ${log})" >&2
    INGEST_SKIP=$((INGEST_SKIP + 1))
    return 0
  fi

  csv="$(ayil_sim_dt_csv "${date}")"
  nproc=""
  if [[ -f "${AYiL_RUNS}/${date}/.ayil_complete" ]]; then
    nproc="$(grep -E '^nproc=' "${AYiL_RUNS}/${date}/.ayil_complete" 2>/dev/null | cut -d= -f2- || true)"
  fi

  log_bytes="$(wc -c < "${log}" | tr -d ' ')"
  if ! log_stats="$(ayil_sim_dt_log_stats "${log}")"; then
    echo "WARN ${date}  no Time of Simulation / dt lines in ${log}" >&2
    INGEST_WARN=$((INGEST_WARN + 1))
    return 0
  fi

  if [[ -f "${csv}" ]]; then
    old_stats="$(ayil_sim_dt_csv_stats "${csv}")"
    if [[ "${RECOMPUTE}" == "1" ]]; then
      action="merge+recompute"
    else
      action="merge+extend"
    fi
  else
    old_stats=""
    action="create"
  fi

  ayil_sim_dt_merge_log "${date}" "${log}" "${nproc}" 2>&1 | grep -E '^ayil_sim_dt merge' || true

  if [[ ! -f "${csv}" ]]; then
    echo "WARN ${date}  merge wrote nothing (empty diagnostics?)" >&2
    INGEST_WARN=$((INGEST_WARN + 1))
    return 0
  fi

  new_stats="$(ayil_sim_dt_csv_stats "${csv}")"
  if [[ -n "${old_stats}" && "${old_stats}" == "${new_stats}" ]]; then
    INGEST_UNCHANGED=$((INGEST_UNCHANGED + 1))
    printf 'OK %s  unchanged  (%s)\n' "${date}" "${action}"
    printf '    log:  %s  (%s bytes)  %s\n' "${log}" "${log_bytes}" "${log_stats}"
    printf '    csv:  %s  (data rows identical; file not rewritten)\n' "${csv}"
    return 0
  fi

  INGEST_OK=$((INGEST_OK + 1))

  printf 'OK %s  %s\n' "${date}" "${action}"
  printf '    log:  %s  (%s bytes)  %s\n' "${log}" "${log_bytes}" "${log_stats}"
  if [[ -n "${nproc}" ]]; then
    printf '    nproc=%s  (from .ayil_complete)\n' "${nproc}"
  fi
  if [[ -n "${old_stats}" ]]; then
    printf '    was:  %s\n' "${old_stats}"
    ayil_sim_dt_stats_delta "${old_stats}" "${new_stats}"
  fi
  printf '    now:  %s\n' "${new_stats}"
  printf '    csv:  %s\n' "${csv}"
}

if (("${#DATES[@]}" > 0)); then
  for date in "${DATES[@]}"; do
    ingest_one "${date}"
  done
else
  shopt -s nullglob
  for log in "${AYiL_RUNS}"/*/logs/dales.log; do
    date="$(basename "$(dirname "$(dirname "${log}")")")"
    [[ "${date}" =~ ^[0-9]{8}$ ]] || continue
    ingest_one "${date}"
  done
fi

printf '\ningest_sim_dt summary: ok=%d unchanged=%d skip=%d warn=%d recompute=%s  out_dir=%s\n' \
  "${INGEST_OK}" "${INGEST_UNCHANGED}" "${INGEST_SKIP}" "${INGEST_WARN}" "${RECOMPUTE}" "$(ayil_sim_dt_root)"

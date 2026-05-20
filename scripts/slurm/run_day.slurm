#!/bin/bash
#SBATCH --job-name=ayil_dales
#SBATCH --nodes=1
#SBATCH --ntasks=64
#SBATCH --cpus-per-task=1
#SBATCH --time=03:15:00
#SBATCH --mem=200G
# Slurm must have a static --output path at submit time; we discard its copy and tee per-day below.
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#
# Run one MOSAiC day, or one day per array task (see scripts/slurm_submit.sh).
# SBATCH lines above are defaults; slurm_submit.sh overrides them via sbatch CLI.
#
# Single day:
#   sbatch --export=ALL,DATE=20200720 scripts/slurm/run_day.slurm
#
# Array (submit via slurm_submit.sh --pending instead of by hand).

set -euo pipefail

# Slurm executes a copy under /var/spool/slurmd/... — BASH_SOURCE is not the checkout.
_ayil_repo_root_sh=""
for _ayil_root in "${MOSAiC_AYIL_ROOT:-}" "${SLURM_SUBMIT_DIR:-}"; do
  if [[ -n "${_ayil_root}" && -f "${_ayil_root}/scripts/lib/repo_root.sh" ]]; then
    _ayil_repo_root_sh="${_ayil_root}/scripts/lib/repo_root.sh"
    break
  fi
done
if [[ -z "${_ayil_repo_root_sh}" ]]; then
  _ayil_slurm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${_ayil_slurm_dir}/../lib/repo_root.sh" ]]; then
    _ayil_repo_root_sh="${_ayil_slurm_dir}/../lib/repo_root.sh"
  fi
fi
if [[ -z "${_ayil_repo_root_sh}" ]]; then
  echo "ERROR: cannot find scripts/lib/repo_root.sh (set MOSAiC_AYIL_ROOT or sbatch from repo root)" >&2
  exit 1
fi
# shellcheck source=../lib/repo_root.sh
source "${_ayil_repo_root_sh}"
REPO_ROOT="$(ayil_resolve_repo_root)"
export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
cd "${REPO_ROOT}"

export DALES_NPROC="${SLURM_NTASKS:-64}"
export AYIL_FORCE="${AYIL_FORCE:-0}"
export AYIL_USE_RESTART_CHUNKS="${AYIL_USE_RESTART_CHUNKS:-1}"
export AYIL_CHUNK_INDEX="${AYIL_CHUNK_INDEX:-0}"
export AYIL_N_CHUNKS="${AYIL_N_CHUNKS:-}"

if [[ -n "${SLURM_ARRAY_TASK_ID:-}" && -z "${DATE:-}" ]]; then
  : "${AYIL_SLURM_DATE_LIST:?AYIL_SLURM_DATE_LIST must point to a date list file}"
  DATE="$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "${AYIL_SLURM_DATE_LIST}")"
fi

: "${DATE:?Set DATE=YYYYMMDD (sbatch --export=ALL,DATE=...) or use slurm_submit.sh --pending}"

RUN_DIR="${AYIL_RUNS:-${REPO_ROOT}/runs}/${DATE}"
# shellcheck source=../lib/logging_paths.sh
source "${REPO_ROOT}/scripts/lib/logging_paths.sh"
ayil_ensure_run_logs "${RUN_DIR}"
# Per-day log file (not /dev/null): redirect bash stdout/stderr before config/modules.
ayil_slurm_tee_to_run_logs "${RUN_DIR}"
echo "Slurm job_id=${SLURM_JOB_ID:-?} array_task=${SLURM_ARRAY_TASK_ID:-?} DATE=${DATE} chunk=${AYIL_CHUNK_INDEX:-?}/${AYIL_N_CHUNKS:-?}"
echo "Logs: $(ayil_slurm_log_out "${RUN_DIR}")  $(ayil_progress_log "${RUN_DIR}")  $(ayil_dales_log "${RUN_DIR}")"

# shellcheck source=../config.sh
source "${REPO_ROOT}/scripts/config.sh"
# shellcheck source=../lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"
export DALES_NPROC="${SLURM_NTASKS:-${AYIL_SLURM_NTASKS:-${DALES_NPROC}}}"

if [[ "${AYIL_SLURM_BUILD:-0}" == "1" ]] || [[ ! -x "${DALES_BIN:-${REPO_ROOT}/dales_ayil/build/src/dales4}" ]]; then
  "${REPO_ROOT}/scripts/build_dales.sh"
fi

"${REPO_ROOT}/scripts/run_slurm_day.sh" "${DATE}"

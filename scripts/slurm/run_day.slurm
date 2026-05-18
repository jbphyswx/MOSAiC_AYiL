#!/bin/bash
#SBATCH --job-name=ayil_dales
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --cpus-per-task=1
#SBATCH --time=08:00:00
#SBATCH --mem=128G
#SBATCH --output=runs/slurm_logs/%x-%A_%a.out
#SBATCH --error=runs/slurm_logs/%x-%A_%a.err
#
# Run one MOSAiC day, or one day per array task (see scripts/slurm_submit.sh).
# SBATCH lines above are defaults; slurm_submit.sh overrides them via sbatch CLI.
#
# Single day:
#   sbatch --export=ALL,DATE=20200720 scripts/slurm/run_day.slurm
#
# Array (submit via slurm_submit.sh --pending instead of by hand).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export MOSAiC_AYIL_ROOT="${REPO_ROOT}"

# shellcheck source=../config.sh
source "${REPO_ROOT}/scripts/config.sh"
# shellcheck source=../lib/slurm_defaults.sh
source "${REPO_ROOT}/scripts/lib/slurm_defaults.sh"

mkdir -p "${AYIL_SLURM_LOG_DIR:-${REPO_ROOT}/runs/slurm_logs}"

export DALES_NPROC="${SLURM_NTASKS:-${AYIL_SLURM_NTASKS}}"
export AYIL_FORCE="${AYIL_FORCE:-0}"

if [[ -n "${SLURM_ARRAY_TASK_ID:-}" && -z "${DATE:-}" ]]; then
  : "${AYIL_SLURM_DATE_LIST:?AYIL_SLURM_DATE_LIST must point to a date list file}"
  DATE="$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "${AYIL_SLURM_DATE_LIST}")"
fi

: "${DATE:?Set DATE=YYYYMMDD (sbatch --export=ALL,DATE=...) or use slurm_submit.sh --pending}"

if [[ "${AYIL_SLURM_BUILD:-0}" == "1" ]] || [[ ! -x "${DALES_BIN:-${REPO_ROOT}/dales_ayil/build/src/dales4}" ]]; then
  "${REPO_ROOT}/scripts/build_dales.sh"
fi

"${REPO_ROOT}/scripts/run_slurm_day.sh" "${DATE}"

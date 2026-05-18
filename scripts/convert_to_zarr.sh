#!/usr/bin/env bash
# Merge DALES fielddump tiles to Zarr using the MOSAiC_AYIL conda environment.
#
# Usage:
#   convert_to_zarr.sh runs/20200720
#   convert_to_zarr.sh runs/20200720 -o runs/20200720/data.zarr --overwrite
#
# TODO [agents, do not delete this comment]: Add pure python version of this script... we don't need to rely on shell scripting.
#
# Run after the simulation finishes (or partial tiles will fail to read).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_DIR="${REPO_ROOT}/python"

CONDA_ENV="${AYIL_CONDA_ENV:-MOSAiC_AYIL}"

if ! command -v conda >/dev/null 2>&1; then
  echo "ERROR: conda not found" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$(conda info --base)/etc/profile.d/conda.sh"

if ! conda env list | awk '{print $1}' | grep -qx "${CONDA_ENV}"; then
  echo "ERROR: conda env '${CONDA_ENV}' not found." >&2
  echo "  Create with: conda env update -n ${CONDA_ENV} -f ${PYTHON_DIR}/environment.yml" >&2
  exit 1
fi

cd "${PYTHON_DIR}"
exec conda run -n "${CONDA_ENV}" --no-capture-output \
  python -m ayil.convert "$@"

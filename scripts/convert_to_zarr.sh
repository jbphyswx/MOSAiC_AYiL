#!/usr/bin/env bash
# Thin launcher: run ``python -m ayil.convert`` in the MOSAiC_AYIL conda env.
# All path resolution, progress, and logging live in Python (see ayil/convert.py).
#
# Usage:
#   convert_to_zarr.sh runs/20200720
#   convert_to_zarr.sh runs/20200720 --overwrite -v
#
# Equivalent:
#   cd python && conda run -n MOSAiC_AYIL python -m ayil.convert runs/20200720
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
  echo "  conda env update -n ${CONDA_ENV} -f ${PYTHON_DIR}/environment.yml" >&2
  exit 1
fi

cd "${PYTHON_DIR}"
exec conda run -n "${CONDA_ENV}" --no-capture-output \
  python -m ayil.convert "$@"

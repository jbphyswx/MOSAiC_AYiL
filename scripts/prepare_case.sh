#!/usr/bin/env bash
# Stage one MOSAiC day into a run directory (inputs + scm_in.nc link).
#
# Usage: prepare_case.sh YYYYMMDD [RUN_DIR]
#
# RUN_DIR defaults to ${AYIL_RUNS}/YYYYMMDD
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/namoptions_patch.sh
source "${SCRIPT_DIR}/lib/namoptions_patch.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 YYYYMMDD [RUN_DIR]" >&2
  exit 1
fi

DATE="$1"
INPUT_DIR="${AYIL_INPUTS}/${DATE}"
RUN_DIR="${2:-${AYIL_RUNS}/${DATE}}"

if [[ ! -d "${INPUT_DIR}" ]]; then
  echo "ERROR: no input folder ${INPUT_DIR}" >&2
  exit 1
fi

mkdir -p "${RUN_DIR}"

# Copy all case inputs (text + NetCDF). Symlinks save space if you prefer.
rsync -a --exclude='fielddump.*' --exclude='profiles.*.nc' \
  "${INPUT_DIR}/" "${RUN_DIR}/"

SCM_SRC="scm_in.a_year_in_les.${DATE}.nc"
if [[ ! -f "${RUN_DIR}/${SCM_SRC}" ]]; then
  echo "ERROR: missing ${RUN_DIR}/${SCM_SRC}" >&2
  exit 1
fi

ln -sfn "${SCM_SRC}" "${RUN_DIR}/scm_in.nc"

if [[ ! -f "${RUN_DIR}/namoptions" ]]; then
  echo "ERROR: missing namoptions in ${RUN_DIR}" >&2
  exit 1
fi

# Zenodo configs use trestart=1800 (~77 GiB/day of initd/inits); AYIL does not warm-restart.
ayil_disable_restart_writes "${RUN_DIR}/namoptions"

echo "Prepared ${DATE} -> ${RUN_DIR}"
echo "  scm_in.nc -> ${SCM_SRC}"

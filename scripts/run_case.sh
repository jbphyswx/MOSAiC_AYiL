#!/usr/bin/env bash
# Run DALES for one MOSAiC day.
#
# Usage: run_case.sh YYYYMMDD [NPROC] [RUN_DIR]
#
# Prereqs: build_dales.sh; prepare_case.sh (or this script will prepare).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 YYYYMMDD [NPROC] [RUN_DIR]" >&2
  exit 1
fi

DATE="$1"
NPROC="${2:-${DALES_NPROC}}"
RUN_DIR="${3:-${AYIL_RUNS}/${DATE}}"

if [[ ! -x "${DALES_BIN}" ]]; then
  echo "ERROR: ${DALES_BIN} not found. Run scripts/build_dales.sh first." >&2
  exit 1
fi

if [[ ! -f "${RUN_DIR}/namoptions" ]]; then
  "${SCRIPT_DIR}/prepare_case.sh" "${DATE}" "${RUN_DIR}"
fi

# itot=jtot=320 from namoptions; MPI_Dims_create must yield factors of 320.
valid_factors=(1 2 4 5 8 10 16 20 32 40 64 80 160 320)
ok=0
for f in "${valid_factors[@]}"; do
  if (( NPROC == f )); then ok=1; break; fi
done
if (( ok == 0 )); then
  echo "WARNING: NPROC=${NPROC} is not a usual factor of 320; DALES may abort in initmpi." >&2
fi

cd "${RUN_DIR}"
LOG="dales_${DATE}.log"

echo "Running ${DATE} in ${RUN_DIR} with ${NPROC} MPI ranks"
echo "Log: ${LOG}"

"${MPIRUN}" -np "${NPROC}" "${DALES_BIN}" namoptions 2>&1 | tee "${LOG}"

echo "Finished ${DATE}. Check fielddump.*.*.001.nc for 3D fields (domain-decomposed)."

#!/usr/bin/env bash
# Source this in an interactive shell so mpirun/mpif90 match the pipeline:
#   source /path/to/MOSAiC_AYIL/scripts/setup_env.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
echo "MOSAiC_AYIL_ROOT=${MOSAiC_AYIL_ROOT}"
echo "MPIRUN=${MPIRUN}"
echo "MPIF90=${MPIF90}"
echo "DALES_NPROC=${DALES_NPROC} (recommended for this host)"
echo "DALES_BIN=${DALES_BIN}"

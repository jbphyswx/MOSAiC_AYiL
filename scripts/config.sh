# Shared paths and defaults for the MOSAiC AYIL pipeline.
# Sourced by every script under scripts/. Do not run directly.
#
# Optional machine overrides: copy scripts/env.example -> scripts/env.local

if [[ -z "${MOSAiC_AYIL_ROOT:-}" ]]; then
  MOSAiC_AYIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ -f "${MOSAiC_AYIL_ROOT}/scripts/env.local" ]]; then
  # shellcheck source=/dev/null
  source "${MOSAiC_AYIL_ROOT}/scripts/env.local"
fi

export MOSAiC_AYIL_ROOT
export DALES_SRC="${DALES_SRC:-${MOSAiC_AYIL_ROOT}/dales_ayil}"
export DALES_BUILD="${DALES_BUILD:-${DALES_SRC}/build}"
export DALES_BIN="${DALES_BIN:-${DALES_BUILD}/src/dales4}"

export AYIL_INPUTS="${AYIL_INPUTS:-${MOSAiC_AYIL_ROOT}/ayil_config_input_results}"
export AYIL_RUNS="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}"

_SCRIPT_LIB="${MOSAiC_AYIL_ROOT}/scripts/lib"
# shellcheck source=lib/mpi_env.sh
source "${_SCRIPT_LIB}/mpi_env.sh"
ayil_setup_mpi_env

# shellcheck source=lib/mpi_slots.sh
source "${_SCRIPT_LIB}/mpi_slots.sh"

export AYIL_PROGRESS_INTERVAL="${AYIL_PROGRESS_INTERVAL:-30}"

# Auto-detect rank count unless set in env.local or tests (AYIL_SKIP_MPI_AUTO=1).
if [[ -z "${DALES_NPROC:-}" && -z "${AYIL_SKIP_MPI_AUTO:-}" ]]; then
  export DALES_NPROC
  DALES_NPROC="$(ayil_resolve_nproc "${AYIL_DEFAULT_NPROC:-64}")"
fi

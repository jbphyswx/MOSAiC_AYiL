# Shared paths and defaults for the MOSAiC AYIL pipeline.
# Sourced by every script under scripts/. Do not run directly.
#
# Optional machine overrides: copy scripts/env.example -> scripts/env.local

if [[ -z "${MOSAiC_AYIL_ROOT:-}" ]]; then
  MOSAiC_AYIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Values already set in the parent shell (e.g. launch script exports) must survive env.local.
_ayil_cfg_chunk="${AYIL_CHUNK_SIM_SEC-}"
_ayil_cfg_ntasks="${AYIL_SLURM_NTASKS-}"
_ayil_cfg_day="${AYIL_DAY_RUNTIME_SEC-}"
if [[ -f "${MOSAiC_AYIL_ROOT}/scripts/env.local" && -z "${AYIL_ENV_LOCAL_LOADED:-}" ]]; then
  export AYIL_ENV_LOCAL_LOADED=1
  # shellcheck source=/dev/null
  source "${MOSAiC_AYIL_ROOT}/scripts/env.local"
fi
[[ -n "${_ayil_cfg_chunk}" ]] && export AYIL_CHUNK_SIM_SEC="${_ayil_cfg_chunk}"
[[ -n "${_ayil_cfg_ntasks}" ]] && export AYIL_SLURM_NTASKS="${_ayil_cfg_ntasks}"
[[ -n "${_ayil_cfg_day}" ]] && export AYIL_DAY_RUNTIME_SEC="${_ayil_cfg_day}"
unset _ayil_cfg_chunk _ayil_cfg_ntasks _ayil_cfg_day

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

# Simulation length (JAMES paper: 3 h). Slurm splits into AYIL_CHUNK_SIM_SEC segments.
export AYIL_DAY_RUNTIME_SEC="${AYIL_DAY_RUNTIME_SEC:-10800}"
# Must be >= namfielddump dtav (1800) unless dales_ayil modfielddump tnext patch is built; see docs/fielddump_and_chunking.md
export AYIL_CHUNK_SIM_SEC="${AYIL_CHUNK_SIM_SEC:-1800}"

# Auto-detect rank count unless set in env.local or tests (AYIL_SKIP_MPI_AUTO=1).
if [[ -z "${DALES_NPROC:-}" && -z "${AYIL_SKIP_MPI_AUTO:-}" ]]; then
  export DALES_NPROC
  DALES_NPROC="$(ayil_resolve_nproc "${AYIL_DEFAULT_NPROC:-64}")"
fi

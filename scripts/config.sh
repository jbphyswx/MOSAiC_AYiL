# Shared paths and defaults for the MOSAiC AYiL pipeline.
# Sourced by every script under scripts/. Do not run directly.
#
# Optional machine overrides: copy scripts/env.example -> scripts/env.local

if [[ -z "${MOSAiC_AYiL_ROOT:-}" ]]; then
  MOSAiC_AYiL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Values already set in the parent shell (e.g. launch script exports) must survive env.local.
_ayil_cfg_chunk="${AYiL_CHUNK_SIM_SEC-}"
_ayil_cfg_ntasks="${AYiL_SLURM_NTASKS-}"
_ayil_cfg_day="${AYiL_DAY_RUNTIME_SEC-}"
if [[ -f "${MOSAiC_AYiL_ROOT}/scripts/env.local" && -z "${AYiL_ENV_LOCAL_LOADED:-}" ]]; then
  export AYiL_ENV_LOCAL_LOADED=1
  # shellcheck source=/dev/null
  source "${MOSAiC_AYiL_ROOT}/scripts/env.local"
fi
[[ -n "${_ayil_cfg_chunk}" ]] && export AYiL_CHUNK_SIM_SEC="${_ayil_cfg_chunk}"
[[ -n "${_ayil_cfg_ntasks}" ]] && export AYiL_SLURM_NTASKS="${_ayil_cfg_ntasks}"
[[ -n "${_ayil_cfg_day}" ]] && export AYiL_DAY_RUNTIME_SEC="${_ayil_cfg_day}"
unset _ayil_cfg_chunk _ayil_cfg_ntasks _ayil_cfg_day

export MOSAiC_AYiL_ROOT
export DALES_SRC="${DALES_SRC:-${MOSAiC_AYiL_ROOT}/MOSAiC_AYiL}"
export DALES_BUILD="${DALES_BUILD:-${DALES_SRC}/build}"
export DALES_BIN="${DALES_BIN:-${DALES_BUILD}/src/dales4}"

export AYiL_INPUTS="${AYiL_INPUTS:-${MOSAiC_AYiL_ROOT}/ayil_config_input_results}"
export AYiL_RUNS="${AYiL_RUNS:-${MOSAiC_AYiL_ROOT}/runs}"

_SCRIPT_LIB="${MOSAiC_AYiL_ROOT}/scripts/lib"
# shellcheck source=lib/mpi_env.sh
source "${_SCRIPT_LIB}/mpi_env.sh"
ayil_setup_mpi_env

# shellcheck source=lib/mpi_slots.sh
source "${_SCRIPT_LIB}/mpi_slots.sh"

export AYiL_PROGRESS_INTERVAL="${AYiL_PROGRESS_INTERVAL:-30}"

# Simulation length (JAMES paper: 3 h). Slurm splits into AYiL_CHUNK_SIM_SEC segments.
export AYiL_DAY_RUNTIME_SEC="${AYiL_DAY_RUNTIME_SEC:-10800}"
# Must be >= namfielddump dtav (1800) unless MOSAiC_AYiL modfielddump tnext patch is built; see docs/fielddump_and_chunking.md
export AYiL_CHUNK_SIM_SEC="${AYiL_CHUNK_SIM_SEC:-1800}"

# Auto-detect rank count unless set in env.local or tests (AYiL_SKIP_MPI_AUTO=1).
if [[ -z "${DALES_NPROC:-}" && -z "${AYiL_SKIP_MPI_AUTO:-}" ]]; then
  export DALES_NPROC
  DALES_NPROC="$(ayil_resolve_nproc "${AYiL_DEFAULT_NPROC:-64}")"
fi

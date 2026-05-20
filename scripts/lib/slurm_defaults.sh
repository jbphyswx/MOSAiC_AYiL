# shellcheck shell=bash
# Slurm resource defaults for MOSAiC_AYIL. Source after config.sh.
#
# Defaults are tuned for the Caltech Resnick HPC cluster
# (https://www.hpc.caltech.edu/resources): single-node MPI jobs with ~40 ranks
# on 64-core Icelake nodes, 128G RAM, 8h walltime. Override in scripts/env.local
# on other systems — nothing here is cluster-specific except comments.

export AYIL_SLURM_JOB_NAME="${AYIL_SLURM_JOB_NAME:-ayil_dales}"
export AYIL_SLURM_NODES="${AYIL_SLURM_NODES:-1}"
export AYIL_SLURM_NTASKS="${AYIL_SLURM_NTASKS:-40}"
export AYIL_SLURM_CPUS_PER_TASK="${AYIL_SLURM_CPUS_PER_TASK:-1}"
export AYIL_SLURM_TIME="${AYIL_SLURM_TIME:-08:00:00}"
export AYIL_SLURM_MEM="${AYIL_SLURM_MEM:-128G}"
# Optional cap on simultaneous array tasks (Slurm --array=0-N%M). Unset = no cap;
# Slurm schedules tasks as partition/QOS/account limits allow.
# export AYIL_SLURM_ARRAY_MAX=8

# Return Slurm array spec for tasks 0..last (e.g. "0-189" or "0-189%8" if capped).
ayil_slurm_array_spec() {
  local last="$1"
  if [[ -n "${AYIL_SLURM_ARRAY_MAX:-}" ]]; then
    echo "0-${last}%${AYIL_SLURM_ARRAY_MAX}"
  else
    echo "0-${last}"
  fi
}
# Optional: partition, account, extra sbatch flags (e.g. --constraint=...)
export AYIL_SLURM_PARTITION="${AYIL_SLURM_PARTITION:-}"
export AYIL_SLURM_ACCOUNT="${AYIL_SLURM_ACCOUNT:-}"
export AYIL_SLURM_EXTRA="${AYIL_SLURM_EXTRA:-}"
# Build dales4 inside each job if missing (0 = expect login-node build).
export AYIL_SLURM_BUILD="${AYIL_SLURM_BUILD:-0}"
# Cluster-wide Slurm stdout copy (array jobs). Canonical per-day logs: runs/YYYYMMDD/logs/.
export AYIL_SLURM_LOG_DIR="${AYIL_SLURM_LOG_DIR:-${AYIL_RUNS}/slurm_logs}"

# Append sbatch arguments to an array variable name (nameref).
ayil_slurm_sbatch_opts() {
  local -n _out="$1"
  _out=(
    --job-name="${AYIL_SLURM_JOB_NAME}"
    --chdir="${MOSAiC_AYIL_ROOT}"
    --nodes="${AYIL_SLURM_NODES}"
    --ntasks="${AYIL_SLURM_NTASKS}"
    --cpus-per-task="${AYIL_SLURM_CPUS_PER_TASK}"
    --time="${AYIL_SLURM_TIME}"
    --mem="${AYIL_SLURM_MEM}"
  )
  if [[ -n "${AYIL_SLURM_PARTITION}" ]]; then
    _out+=(--partition="${AYIL_SLURM_PARTITION}")
  fi
  if [[ -n "${AYIL_SLURM_ACCOUNT}" ]]; then
    _out+=(--account="${AYIL_SLURM_ACCOUNT}")
  fi
  if [[ -n "${AYIL_SLURM_EXTRA}" ]]; then
    # shellcheck disable=SC2206
    _out+=(${AYIL_SLURM_EXTRA})
  fi
}

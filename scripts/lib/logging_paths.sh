# shellcheck shell=bash
# Canonical log paths under each run directory: runs/YYYYMMDD/logs/
#
#   dales.log      DALES MPI stdout/stderr (namoptions run)
#   progress.log   Local run_local.sh progress lines
#   slurm.out      Slurm job stdout + stderr (single file)
#   convert.log    python -m ayil.convert
#   smoke.log      smoke_test.sh
#
# Source after config.sh. Do not execute directly.

# Directory holding all logs for one simulation day.
ayil_run_logs_dir() {
  echo "${1}/logs"
}

ayil_ensure_run_logs() {
  mkdir -p "$(ayil_run_logs_dir "$1")"
}

ayil_dales_log() {
  echo "$(ayil_run_logs_dir "$1")/dales.log"
}

ayil_progress_log() {
  echo "$(ayil_run_logs_dir "$1")/progress.log"
}

ayil_slurm_log_out() {
  echo "$(ayil_run_logs_dir "$1")/slurm.out"
}

# Deprecated name: stderr is merged into slurm.out.
ayil_slurm_log_err() {
  ayil_slurm_log_out "$1"
}

ayil_convert_log() {
  echo "$(ayil_run_logs_dir "$1")/convert.log"
}

ayil_smoke_log() {
  echo "$(ayil_run_logs_dir "$1")/smoke.log"
}

# Remove generated simulation outputs (keeps inputs, namoptions, prof.inp).
# Does not delete logs/slurm.out — that file is written by the active Slurm job via tee.
ayil_clean_run_outputs() {
  local run_dir="$1"
  # shellcheck source=run_status.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_status.sh"
  find "${run_dir}" -maxdepth 1 \( \
    -name 'fielddump.*.nc' -o -name 'profiles.*.nc' -o -name 'cross*.nc' -o \
    -name 'tmser*.nc' -o -name 'initd*.001' -o -name 'inits*.001' -o \
    -name "${AYIL_STATUS_COMPLETE}" -o -name "${AYIL_STATUS_INTERRUPTED}" -o \
    -name "${AYIL_STATUS_FAILED}" -o -name "${AYIL_STATUS_RUNNING}" -o \
    -name '.ayil_chunk_*_complete' \
    \) -delete 2>/dev/null || true
  # Simulation logs only (never rm -rf logs/ — that deletes slurm.out mid-job).
  local logs_dir
  logs_dir="$(ayil_run_logs_dir "${run_dir}")"
  if [[ -d "${logs_dir}" ]]; then
    rm -f "${logs_dir}/dales.log" "${logs_dir}/progress.log" "${logs_dir}/convert.log" \
      "${logs_dir}/smoke.log" 2>/dev/null || true
  fi
  # Legacy logs at run root (before logs/ layout).
  find "${run_dir}" -maxdepth 1 -name '*.log' -delete 2>/dev/null || true
}

# Send all further bash output to runs/YYYYMMDD/logs/slurm.out.
# Also copies to runs/.slurm_job_logs/job_<id>.out when SLURM_JOB_ID is set (survives empty logs/ bugs).
# (#SBATCH --output=/dev/null only disables Slurm's spool copy; this tee is the primary log.)
ayil_slurm_tee_to_run_logs() {
  local run_dir="$1"
  ayil_ensure_run_logs "${run_dir}"
  local out job_log
  out="$(ayil_slurm_log_out "${run_dir}")"
  if [[ -n "${SLURM_JOB_ID:-}" && -n "${MOSAiC_AYIL_ROOT:-}" ]]; then
    job_log="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}/.slurm_job_logs/job_${SLURM_JOB_ID}.out"
    mkdir -p "$(dirname "${job_log}")"
    exec > >(tee -a "${out}" "${job_log}") 2>&1
  else
    exec > >(tee -a "${out}") 2>&1
  fi
}

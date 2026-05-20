# shellcheck shell=bash
# Canonical log paths under each run directory: runs/YYYYMMDD/logs/
#
#   dales.log      DALES MPI stdout/stderr (namoptions run)
#   progress.log   Local run_local.sh progress lines
#   slurm.out      Slurm job stdout (batch wrapper + echoes)
#   slurm.err      Slurm job stderr
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

ayil_slurm_log_err() {
  echo "$(ayil_run_logs_dir "$1")/slurm.err"
}

ayil_convert_log() {
  echo "$(ayil_run_logs_dir "$1")/convert.log"
}

ayil_smoke_log() {
  echo "$(ayil_run_logs_dir "$1")/smoke.log"
}

# Remove generated outputs and logs (keeps inputs, namoptions, prof.inp, status markers cleared separately).
ayil_clean_run_outputs() {
  local run_dir="$1"
  # shellcheck source=run_status.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_status.sh"
  find "${run_dir}" -maxdepth 1 \( \
    -name 'fielddump.*.nc' -o -name 'profiles.*.nc' -o -name 'cross*.nc' -o \
    -name 'tmser*.nc' -o -name 'initd*.001' -o -name 'inits*.001' -o \
    -name "${AYIL_STATUS_COMPLETE}" -o -name "${AYIL_STATUS_INTERRUPTED}" -o \
    -name "${AYIL_STATUS_FAILED}" -o -name "${AYIL_STATUS_RUNNING}" \
    \) -delete 2>/dev/null || true
  rm -rf "$(ayil_run_logs_dir "${run_dir}")"
  # Legacy logs at run root (before logs/ layout).
  find "${run_dir}" -maxdepth 1 -name '*.log' -delete 2>/dev/null || true
}

# Redirect remaining shell output to per-run Slurm logs (also see cluster copy under AYIL_SLURM_LOG_DIR).
ayil_slurm_tee_to_run_logs() {
  local run_dir="$1"
  ayil_ensure_run_logs "${run_dir}"
  local out err
  out="$(ayil_slurm_log_out "${run_dir}")"
  err="$(ayil_slurm_log_err "${run_dir}")"
  # Array jobs: SBATCH writes to runs/slurm_logs/; tee copies into this run's logs/.
  exec > >(tee -a "${out}") 2> >(tee -a "${err}" >&2)
}

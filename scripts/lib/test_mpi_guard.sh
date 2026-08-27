# shellcheck shell=bash
# Refuse heavy DALES MPI runs on cluster login nodes (OOM / policy).

# Return 0 if the current host looks like a batch/interactive compute session.
ayil_mpi_tests_allowed() {
  if [[ "${AYiL_ALLOW_LOGIN_MPI_TESTS:-0}" == "1" ]]; then
    return 0
  fi
  local host="${HOSTNAME:-$(hostname -s 2>/dev/null || hostname)}"
  host="${host%%.*}"
  case "${host}" in
    login*|*login*|head*)
      return 1
      ;;
  esac
  # Slurm job or explicit compute allocation → OK.
  if [[ -n "${SLURM_JOB_ID:-}" || -n "${PBS_JOBID:-}" ]]; then
    return 0
  fi
  return 0
}

ayil_refuse_login_mpi_tests() {
  local label="${1:-MPI test}"
  if ayil_mpi_tests_allowed; then
    return 0
  fi
  echo "ERROR: ${label} must not run on a login node (host=${HOSTNAME:-unknown})." >&2
  echo "  Build here: ./scripts/build_dales.sh" >&2
  echo "  Run MPI tests on a compute node, e.g.:" >&2
  echo "    srun --pty -n 1 -t 30 --mem=64G bash -lc './scripts/manual/smoke_test.sh'" >&2
  echo "  Override only if you accept the risk: AYiL_ALLOW_LOGIN_MPI_TESTS=1" >&2
  return 1
}

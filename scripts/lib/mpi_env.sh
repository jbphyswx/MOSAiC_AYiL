# shellcheck shell=bash
# Locate Open MPI (or compatible) launchers. Portable across Linux/HPC/macOS.

ayil_setup_mpi_env() {
  if [[ -n "${MPIRUN:-}" && -x "${MPIRUN}" ]]; then
    export PATH="$(dirname "${MPIRUN}"):${PATH}"
    return 0
  fi

  local dir cmd

  # Explicit prefix from env.local / modules
  if [[ -n "${OPENMPI_PREFIX:-}" && -x "${OPENMPI_PREFIX}/bin/mpirun" ]]; then
    export MPIRUN="${OPENMPI_PREFIX}/bin/mpirun"
    export MPIF90="${OPENMPI_PREFIX}/bin/mpif90"
    export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
    return 0
  fi

  # Already on PATH (modules, spack, conda-openmpi, etc.)
  if command -v mpirun >/dev/null 2>&1; then
    export MPIRUN="$(command -v mpirun)"
    export MPIF90="$(command -v mpif90 2>/dev/null || true)"
    return 0
  fi

  # Common install locations (first match wins)
  for dir in \
    "${MPI_ROOT:-}/bin" \
    /usr/lib64/openmpi/bin \
    /usr/local/openmpi/bin \
    /opt/openmpi/bin \
    /usr/lib/openmpi/bin \
    /opt/homebrew/opt/open-mpi/bin \
    /usr/local/bin; do
    [[ -n "${dir}" && -x "${dir}/mpirun" ]] || continue
    export MPIRUN="${dir}/mpirun"
    export MPIF90="${dir}/mpif90"
    export PATH="${dir}:${PATH}"
    return 0
  done

  return 1
}

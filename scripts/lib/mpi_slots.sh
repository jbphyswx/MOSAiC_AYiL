# shellcheck shell=bash
# Open MPI slot detection and rank sizing for DALES (grid must divide 320).

# Valid MPI task counts for itot=jtot=320 (descending).
AYiL_GRID_FACTORS=(320 160 80 64 40 32 20 16 10 8 5 4 2 1)

ayil_largest_grid_factor_le() {
  local cap="$1"
  local f
  for f in "${AYiL_GRID_FACTORS[@]}"; do
    if (( f <= cap )); then
      echo "${f}"
      return 0
    fi
  done
  echo 1
}

# Probe max ranks Open MPI accepts among valid DALES grid factors (divisors of 320).
ayil_mpi_probe_max_slots() {
  local cap="${AYiL_MPI_MAX_SLOTS:-${AYiL_MAX_SLOTS:-}}"
  if [[ -n "${cap}" ]]; then
    ayil_largest_grid_factor_le "${cap}"
    return 0
  fi
  if [[ -z "${MPIRUN:-}" ]]; then
    echo 1
    return 0
  fi
  local n
  for n in "${AYiL_GRID_FACTORS[@]}"; do
    # shellcheck disable=SC2086
    if "${MPIRUN}" ${AYiL_MPIRUN_EXTRA:-} -np "${n}" /bin/true &>/dev/null; then
      echo "${n}"
      return 0
    fi
  done
  echo 1
}

# Choose nproc: min(requested, env cap, probed slots), then largest factor of 320.
ayil_resolve_nproc() {
  local requested="${1:-64}"
  local cap
  cap="$(ayil_mpi_probe_max_slots)"
  if (( requested > cap )); then
    echo "${cap}"
    return 0
  fi
  ayil_largest_grid_factor_le "${requested}"
}

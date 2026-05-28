# shellcheck shell=bash
# Build argv for a single remote→local rsync of AYIL runs/ (one SSH session).
#
# Sourced by scripts/sync_runs_from_hpc.sh and unit tests.

# Return 0 if YYYYMMDD.
ayil_sync_validate_date() {
  [[ "${1:-}" =~ ^[0-9]{8}$ ]]
}

# Populate global array AYIL_SYNC_RSYNC_CMD with a complete rsync invocation.
# Options (env or caller):
#   AYIL_HPC_HOST, AYIL_HPC_USER, AYIL_HPC_ROOT, AYIL_RUNS
#   AYIL_SYNC_IGNORE_EXISTING=1 (default) — skip files that already exist locally
#   AYIL_SYNC_DRY_RUN=1 — pass -n
#   AYIL_SYNC_DATES — space-separated YYYYMMDD list (optional; empty = all runs/)
#   AYIL_RSYNC_EXTRA — extra rsync flags (quoted string split on whitespace)
#   AYIL_RSYNC_SSH — remote shell for rsync -e (default: multiplexed ssh -S socket)
ayil_sync_runs_build_rsync_cmd() {
  local host user remote_root local_runs dry ignore_existing dates extra rsync_ssh
  local -a cmd includes

  host="${AYIL_HPC_HOST:-login.hpc.caltech.edu}"
  user="${AYIL_HPC_USER:-${USER}}"
  remote_root="${AYIL_HPC_ROOT:-${MOSAiC_AYIL_ROOT}}"
  local_runs="${AYIL_RUNS:-${MOSAiC_AYIL_ROOT}/runs}"
  dry="${AYIL_SYNC_DRY_RUN:-0}"
  ignore_existing="${AYIL_SYNC_IGNORE_EXISTING:-1}"
  dates="${AYIL_SYNC_DATES:-}"

  if [[ -z "${remote_root}" || -z "${MOSAiC_AYIL_ROOT:-}" ]]; then
    echo "ERROR: MOSAiC_AYIL_ROOT must be set (source scripts/config.sh)." >&2
    return 1
  fi

  cmd=(rsync -a -h --info=progress2)

  if [[ "${dry}" == "1" ]]; then
    cmd+=(-n)
  fi

  if [[ "${ignore_existing}" == "1" ]]; then
    cmd+=(--ignore-existing)
  fi

  # Resume partial transfers without clobber policy change.
  cmd+=(--partial)

  # Git metadata under runs/ (should not appear, but never pull it).
  cmd+=(
    --exclude='.git/'
    --exclude='.git'
    --exclude='.gitattributes'
    --exclude='.gitmodules'
    --exclude='.gitignore'
  )

  extra="${AYIL_RSYNC_EXTRA:-}"
  if [[ -n "${extra}" ]]; then
    # shellcheck disable=SC2206
    cmd+=(${extra})
  fi

  if [[ -n "${dates}" ]]; then
    local d
    for d in ${dates}; do
      if ! ayil_sync_validate_date "${d}"; then
        echo "ERROR: invalid AYIL date '${d}' (expected YYYYMMDD)." >&2
        return 1
      fi
      includes+=(--include="${d}/***")
    done
    includes+=(--exclude='*')
    cmd+=("${includes[@]}")
  fi

  if [[ -z "${AYIL_RSYNC_SSH:-}" ]]; then
    echo "ERROR: AYIL_RSYNC_SSH unset; run ayil_hpc_control_ensure before building rsync cmd." >&2
    return 1
  fi
  rsync_ssh="${AYIL_RSYNC_SSH}"
  cmd+=(
    -e
    "${rsync_ssh}"
    "${user}@${host}:${remote_root}/runs/"
    "${local_runs}/"
  )

  AYIL_SYNC_RSYNC_CMD=("${cmd[@]}")
}

# Print one line per argument (safe for tests).
ayil_sync_runs_format_cmd() {
  local arg
  ayil_sync_runs_build_rsync_cmd || return 1
  for arg in "${AYIL_SYNC_RSYNC_CMD[@]}"; do
    printf '%s\n' "${arg}"
  done
}

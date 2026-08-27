# shellcheck shell=bash
# Build argv for a single remote→local rsync of AYiL runs/ (one SSH session).
#
# Sourced by scripts/sync_runs_from_hpc.sh and unit tests.

# Return 0 if YYYYMMDD.
ayil_sync_validate_date() {
  [[ "${1:-}" =~ ^[0-9]{8}$ ]]
}

# Populate global array AYiL_SYNC_RSYNC_CMD with a complete rsync invocation.
# Options (env or caller):
#   AYiL_HPC_HOST, AYiL_HPC_USER, AYiL_HPC_ROOT, AYiL_RUNS
#   AYiL_SYNC_IGNORE_EXISTING=1 (default) — skip files that already exist locally
#   AYiL_SYNC_DRY_RUN=1 — pass -n
#   AYiL_SYNC_DATES — space-separated YYYYMMDD list (optional; empty = all runs/)
#   AYiL_RSYNC_EXTRA — extra rsync flags (quoted string split on whitespace)
#   AYiL_RSYNC_SSH — remote shell for rsync -e (default: multiplexed ssh -S socket)
ayil_sync_runs_build_rsync_cmd() {
  local host user remote_root local_runs dry ignore_existing dates extra rsync_ssh
  local -a cmd includes

  host="${AYiL_HPC_HOST:-login.hpc.caltech.edu}"
  user="${AYiL_HPC_USER:-${USER}}"
  remote_root="${AYiL_HPC_ROOT:-${MOSAiC_AYiL_ROOT}}"
  local_runs="${AYiL_RUNS:-${MOSAiC_AYiL_ROOT}/runs}"
  dry="${AYiL_SYNC_DRY_RUN:-0}"
  ignore_existing="${AYiL_SYNC_IGNORE_EXISTING:-1}"
  dates="${AYiL_SYNC_DATES:-}"

  if [[ -z "${remote_root}" || -z "${MOSAiC_AYiL_ROOT:-}" ]]; then
    echo "ERROR: MOSAiC_AYiL_ROOT must be set (source scripts/config.sh)." >&2
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

  extra="${AYiL_RSYNC_EXTRA:-}"
  if [[ -n "${extra}" ]]; then
    # shellcheck disable=SC2206
    cmd+=(${extra})
  fi

  if [[ -n "${dates}" ]]; then
    local d
    for d in ${dates}; do
      if ! ayil_sync_validate_date "${d}"; then
        echo "ERROR: invalid AYiL date '${d}' (expected YYYYMMDD)." >&2
        return 1
      fi
      includes+=(--include="${d}/***")
    done
    includes+=(--exclude='*')
    cmd+=("${includes[@]}")
  fi

  if [[ -z "${AYiL_RSYNC_SSH:-}" ]]; then
    echo "ERROR: AYiL_RSYNC_SSH unset; run ayil_hpc_control_ensure before building rsync cmd." >&2
    return 1
  fi
  rsync_ssh="${AYiL_RSYNC_SSH}"
  cmd+=(
    -e
    "${rsync_ssh}"
    "${user}@${host}:${remote_root}/runs/"
    "${local_runs}/"
  )

  AYiL_SYNC_RSYNC_CMD=("${cmd[@]}")
}

# Print one line per argument (safe for tests).
ayil_sync_runs_format_cmd() {
  local arg
  ayil_sync_runs_build_rsync_cmd || return 1
  for arg in "${AYiL_SYNC_RSYNC_CMD[@]}"; do
    printf '%s\n' "${arg}"
  done
}

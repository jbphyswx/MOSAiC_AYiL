#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

(
  export MOSAiC_AYiL_ROOT="${REPO_ROOT}"
  export AYiL_RUNS="${REPO_ROOT}/runs"
  export AYiL_HPC_HOST=login.hpc.caltech.edu
  export AYiL_HPC_USER=testuser
  export AYiL_HPC_ROOT=/home/testuser/Research_Schneider/CliMA/MOSAiC_AYiL
  export AYiL_SYNC_DRY_RUN=0
  export AYiL_SYNC_IGNORE_EXISTING=1
  export AYiL_RSYNC_SSH="ssh -S ${HOME}/.ssh/ayil-hpc -o ControlMaster=no -o BatchMode=yes"
  unset AYiL_SYNC_DATES

  # shellcheck source=../../scripts/lib/sync_runs_from_hpc.sh
  source "${REPO_ROOT}/scripts/lib/sync_runs_from_hpc.sh"

  mapfile -t _argv < <(ayil_sync_runs_format_cmd)
  _joined=$(
    IFS=,
    echo "${_argv[*]}"
  )

  [[ "${_argv[0]}" == "rsync" ]] || {
    echo "FAIL: expected rsync, got ${_argv[0]}" >&2
    exit 1
  }
  [[ "${_joined}" == *"--ignore-existing"* ]] || {
    echo "FAIL: default should use --ignore-existing" >&2
    exit 1
  }
  [[ "${_joined}" == *"--exclude=.git/"* ]] || {
    echo "FAIL: should exclude .git/" >&2
    exit 1
  }
  [[ "${_joined}" == *"ControlMaster=no"* && "${_joined}" == *"BatchMode=yes"* ]] || {
    echo "FAIL: rsync -e should use multiplexed ssh" >&2
    exit 1
  }
  [[ "${_joined}" == *"testuser@login.hpc.caltech.edu:/home/testuser/Research_Schneider/CliMA/MOSAiC_AYiL/runs/"* ]] || {
    echo "FAIL: unexpected remote source: ${_joined}" >&2
    exit 1
  }
  [[ "${_argv[-1]}" == "${REPO_ROOT}/runs/" ]] || {
    echo "FAIL: unexpected local dest: ${_argv[-1]}" >&2
    exit 1
  }

  # One rsync, not a per-date loop.
  _rsync_count=0
  for _a in "${_argv[@]}"; do
    [[ "${_a}" == "rsync" ]] && _rsync_count=$((_rsync_count + 1))
  done
  [[ "${_rsync_count}" -eq 1 ]] || {
    echo "FAIL: expected exactly one rsync in argv, got ${_rsync_count}" >&2
    exit 1
  }

  export AYiL_SYNC_DATES="20200720 20200721"
  mapfile -t _argv2 < <(ayil_sync_runs_format_cmd)
  _joined2=$(
    IFS=,
    echo "${_argv2[*]}"
  )
  [[ "${_joined2}" == *"--include=20200720/***"* ]] || {
    echo "FAIL: missing include filter for 20200720" >&2
    exit 1
  }
  [[ "${_joined2}" == *"--include=20200721/***"* ]] || {
    echo "FAIL: missing include filter for 20200721" >&2
    exit 1
  }
  [[ "${_joined2}" == *"--exclude=*"* ]] || {
    echo "FAIL: missing trailing exclude for date filter" >&2
    exit 1
  }

  export AYiL_SYNC_IGNORE_EXISTING=0
  mapfile -t _argv3 < <(ayil_sync_runs_format_cmd)
  _joined3=$(
    IFS=,
    echo "${_argv3[*]}"
  )
  [[ "${_joined3}" != *"--ignore-existing"* ]] || {
    echo "FAIL: --replace should drop --ignore-existing" >&2
    exit 1
  }

  echo "PASS: sync_runs_from_hpc rsync argv"
)

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

(
  export MOSAiC_AYiL_ROOT="${REPO_ROOT}"
  export AYiL_HPC_HOST=login.hpc.caltech.edu
  export AYiL_HPC_USER=testuser

  # shellcheck source=../../scripts/lib/hpc_ssh.sh
  source "${REPO_ROOT}/scripts/lib/hpc_ssh.sh"

  _sock="$(ayil_hpc_control_socket)"
  [[ "${_sock}" == "${HOME}/.ssh/ayil-hpc" ]] || {
    echo "FAIL: unexpected control socket path: ${_sock}" >&2
    exit 1
  }
  [[ ${#_sock} -le 90 ]] || {
    echo "FAIL: socket path too long for Unix domain socket: ${_sock}" >&2
    exit 1
  }

  _rsync="$(ayil_hpc_rsync_ssh_cmd)"
  [[ "${_rsync}" == *"-S '${_sock}'"* || "${_rsync}" == *"-S ${_sock}"* ]] || {
    echo "FAIL: rsync ssh should reference socket: ${_rsync}" >&2
    exit 1
  }
  [[ "${_rsync}" == *"ControlMaster=no"* ]] || {
    echo "FAIL: rsync ssh should use ControlMaster=no" >&2
    exit 1
  }

  echo "PASS: hpc_ssh control socket paths"
)

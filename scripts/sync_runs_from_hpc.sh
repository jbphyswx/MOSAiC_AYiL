#!/usr/bin/env bash
# Pull HPC runs/ → local runs/ (one command: SSH login if needed, then one rsync).
#
#   ./scripts/sync_runs_from_hpc.sh
#   ./scripts/sync_runs_from_hpc.sh 20200720 20200721
#   ./scripts/sync_runs_from_hpc.sh --dry-run
#   ./scripts/sync_runs_from_hpc.sh --replace
#
# First run (or after ~2h): password + Duo once. Reuses ~/.ssh/ayil-hpc socket.
# Default: --ignore-existing (never overwrites local files). Git metadata excluded.
#
# Optional: scripts/env.local — AYIL_HPC_HOST, AYIL_HPC_USER, AYIL_HPC_ROOT, AYIL_RSYNC_EXTRA
# Advanced: ./scripts/hpc_ssh_master.sh {start|status|stop}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# No mpirun probe before SSH login (would run from config.sh otherwise).
export AYIL_SKIP_MPI_AUTO=1
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/hpc_ssh.sh
source "${SCRIPT_DIR}/lib/hpc_ssh.sh"
# shellcheck source=lib/sync_runs_from_hpc.sh
source "${SCRIPT_DIR}/lib/sync_runs_from_hpc.sh"

usage() {
  cat <<'EOF'
Pull runs/ from Caltech HPC to this machine.

  ./scripts/sync_runs_from_hpc.sh [options] [YYYYMMDD ...]

Does everything in one step:
  - Opens SSH master if needed (password + Duo once, socket ~/.ssh/ayil-hpc)
  - rsync from HPC runs/ to local runs/ (one transfer, one SSH session)

Options:
  -n, --dry-run     rsync trial run (still logs in if master is down)
  --print-cmd       show rsync argv only (no SSH, no rsync)
  --replace         update files that already exist locally
  -h, --help        this message

Default policy: --ignore-existing (add missing files only).
With dates: only those runs/YYYYMMDD/ subtrees (still one rsync).

Optional admin: ./scripts/hpc_ssh_master.sh status|stop
EOF
}

DRY_RUN=0
PRINT_CMD=0
declare -a DATES=()
export AYIL_SYNC_IGNORE_EXISTING=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --dry-run)
      DRY_RUN=1
      shift
      ;;
    --setup-ssh)
      # Accepted for old muscle memory; SSH setup is always automatic now.
      shift
      ;;
    --replace)
      export AYIL_SYNC_IGNORE_EXISTING=0
      shift
      ;;
    --print-cmd)
      PRINT_CMD=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      DATES+=("$@")
      break
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if ! ayil_sync_validate_date "$1"; then
        echo "ERROR: invalid date '$1' (expected YYYYMMDD)." >&2
        exit 1
      fi
      DATES+=("$1")
      shift
      ;;
  esac
done

export AYIL_SYNC_DRY_RUN="${DRY_RUN}"
export AYIL_HPC_ROOT="${AYIL_HPC_ROOT:-${MOSAiC_AYIL_ROOT}}"

if [[ ${#DATES[@]} -gt 0 ]]; then
  export AYIL_SYNC_DATES="${DATES[*]}"
else
  unset AYIL_SYNC_DATES
fi

mkdir -p "${AYIL_RUNS}"

host="${AYIL_HPC_HOST:-login.hpc.caltech.edu}"
user="${AYIL_HPC_USER:-${USER}}"
remote_root="${AYIL_HPC_ROOT}"

if [[ "${PRINT_CMD}" == "1" && -z "${AYIL_RSYNC_SSH:-}" ]]; then
  export AYIL_RSYNC_SSH
  AYIL_RSYNC_SSH="$(ayil_hpc_rsync_ssh_cmd)"
fi

if [[ "${PRINT_CMD}" != "1" ]]; then
  ayil_hpc_control_ensure
fi

ayil_sync_runs_build_rsync_cmd

echo "HPC:  ${user}@${host}:${remote_root}/runs/"
echo "Local: ${AYIL_RUNS}/"
if [[ "${AYIL_SYNC_IGNORE_EXISTING:-1}" == "1" ]]; then
  echo "Policy: --ignore-existing (will not overwrite existing local files)"
else
  echo "Policy: rsync may update existing local files (--replace)"
fi
if [[ -n "${AYIL_SYNC_DATES:-}" ]]; then
  echo "Dates: ${AYIL_SYNC_DATES}"
fi
echo

if [[ "${PRINT_CMD}" == "1" ]]; then
  printf '  %q' "${AYIL_SYNC_RSYNC_CMD[@]}"
  printf '\n'
  exit 0
fi

exec "${AYIL_SYNC_RSYNC_CMD[@]}"

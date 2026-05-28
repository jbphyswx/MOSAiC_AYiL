#!/usr/bin/env bash
# Optional SSH ControlMaster admin (normally use ./scripts/sync_runs_from_hpc.sh alone).
#
# Usage:
#   ./scripts/hpc_ssh_master.sh start | status | stop
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AYIL_SKIP_MPI_AUTO=1
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/hpc_ssh.sh
source "${SCRIPT_DIR}/lib/hpc_ssh.sh"

cmd="${1:-status}"
case "${cmd}" in
  start)
    ayil_hpc_control_start
    ayil_hpc_control_status
    ;;
  stop)
    ayil_hpc_control_stop
    ;;
  status)
    ayil_hpc_control_status
    ;;
  -h | --help | help)
    cat <<'EOF'
Optional: sync_runs_from_hpc.sh opens the master automatically.

  hpc_ssh_master.sh start | status | stop

Socket default: ~/.ssh/ayil-hpc
EOF
    ;;
  *)
    echo "ERROR: unknown command: ${cmd} (use start|status|stop)" >&2
    exit 1
    ;;
esac

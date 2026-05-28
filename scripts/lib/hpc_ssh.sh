# shellcheck shell=bash
# Caltech HPC SSH control master (one password/Duo, many rsync/scp calls).
#
# Password + Duo do not work reliably under `rsync -e ssh` (remote rsync --server).
# Open an SSH master socket first, then point rsync at it.

# Set AYIL_HPC_HOST, AYIL_HPC_USER from environment.
ayil_hpc_ssh_load_defaults() {
  AYIL_HPC_HOST="${AYIL_HPC_HOST:-login.hpc.caltech.edu}"
  AYIL_HPC_USER="${AYIL_HPC_USER:-${USER}}"
}

# Path to ControlMaster socket (must stay under ~90 chars; OpenSSH adds a short suffix).
ayil_hpc_control_socket() {
  local sock
  ayil_hpc_ssh_load_defaults
  if [[ -n "${AYIL_HPC_CONTROL_PATH:-}" ]]; then
    sock="${AYIL_HPC_CONTROL_PATH}"
  else
    sock="${HOME}/.ssh/ayil-hpc"
  fi
  if [[ ${#sock} -gt 90 ]]; then
    echo "ERROR: control socket path too long for Unix domain socket (${#sock} chars, max ~90)." >&2
    echo "  ${sock}" >&2
    echo "  Set AYIL_HPC_CONTROL_PATH to a short path, e.g. \${HOME}/.ssh/ayil-hpc" >&2
    return 1
  fi
  printf '%s\n' "${sock}"
}

# Return 0 if a control master is accepting multiplexed connections.
ayil_hpc_control_alive() {
  local sock host user
  sock="$(ayil_hpc_control_socket)" || return 1
  ayil_hpc_ssh_load_defaults
  host="${AYIL_HPC_HOST}"
  user="${AYIL_HPC_USER}"
  [[ -S "${sock}" ]] || return 1
  ssh -S "${sock}" -O check "${user}@${host}" &>/dev/null
}

# Remote shell command for rsync -e when using the control socket.
ayil_hpc_rsync_ssh_cmd() {
  local sock
  sock="$(ayil_hpc_control_socket)" || return 1
  # ControlMaster=no: this connection is a slave; BatchMode avoids re-prompting.
  printf 'ssh -S %q -o ControlMaster=no -o BatchMode=yes' "${sock}"
}

# Start master: password/Duo once, then background (-N) master for ControlPersist.
ayil_hpc_control_start() {
  local sock dir persist n
  ayil_hpc_ssh_load_defaults
  sock="$(ayil_hpc_control_socket)" || return 1
  dir="$(dirname "${sock}")"
  mkdir -p "${dir}"
  persist="${AYIL_HPC_CONTROL_PERSIST:-2h}"

  if ayil_hpc_control_alive; then
    echo "HPC SSH master already active: ${sock}"
    return 0
  fi

  if [[ ! -t 0 && ! -r /dev/tty ]]; then
    echo "ERROR: password/Duo needs an interactive terminal." >&2
    echo "  Run: ./scripts/sync_runs_from_hpc.sh" >&2
    return 1
  fi

  if ! ayil_hpc_control_alive; then
    rm -f "${sock}"
  fi

  echo "Opening SSH master to ${AYIL_HPC_USER}@${AYIL_HPC_HOST} (password + Duo once) ..."
  echo "Socket: ${sock} (persist ${persist})"

  # Do not run a remote command (avoids HPC .bashrc/modules); -fnNT keeps the master up.
  unset SSH_ASKPASS SSH_ASKPASS_REQUIRE
  if ! ssh \
    -o ControlMaster=yes \
    -o "ControlPath=${sock}" \
    -o "ControlPersist=${persist}" \
    -o BatchMode=no \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=keyboard-interactive \
    -o KbdInteractiveAuthentication=yes \
    -tt \
    -fnNT \
    "${AYIL_HPC_USER}@${AYIL_HPC_HOST}" \
    </dev/tty; then
    echo "ERROR: SSH login failed." >&2
    return 1
  fi

  for n in 1 2 3 4 5; do
    if ayil_hpc_control_alive; then
      echo "HPC SSH master ready."
      return 0
    fi
    sleep 1
  done

  echo "ERROR: SSH master did not stay open after login." >&2
  echo "  Check: ls -la ${sock}" >&2
  return 1
}

ayil_hpc_control_stop() {
  local sock
  sock="$(ayil_hpc_control_socket)" || return 1
  if [[ ! -S "${sock}" ]]; then
    echo "No HPC SSH master socket at ${sock}"
    return 0
  fi
  ssh -S "${sock}" -O exit 2>/dev/null || true
  echo "Closed HPC SSH master: ${sock}"
}

ayil_hpc_control_status() {
  local sock
  sock="$(ayil_hpc_control_socket)" || return 1
  ayil_hpc_ssh_load_defaults
  echo "Host:   ${AYIL_HPC_USER}@${AYIL_HPC_HOST}"
  echo "Socket: ${sock}"
  if ayil_hpc_control_alive; then
    echo "Status: active (rsync can use this connection without re-authenticating)"
    return 0
  fi
  echo "Status: not running"
  return 1
}

# Ensure master exists; start interactively if needed (password/Duo once per persist window).
ayil_hpc_control_ensure() {
  if [[ -n "${AYIL_RSYNC_SSH:-}" ]]; then
    return 0
  fi

  if ayil_hpc_control_alive; then
    export AYIL_RSYNC_SSH
    AYIL_RSYNC_SSH="$(ayil_hpc_rsync_ssh_cmd)"
    return 0
  fi

  if [[ "${AYIL_SKIP_SSH_SETUP:-0}" == "1" ]]; then
    echo "ERROR: no HPC SSH master and AYIL_SKIP_SSH_SETUP=1." >&2
    echo "  Socket: $(ayil_hpc_control_socket 2>/dev/null || echo '?')" >&2
    return 1
  fi

  ayil_hpc_control_start || return 1
  export AYIL_RSYNC_SSH
  AYIL_RSYNC_SSH="$(ayil_hpc_rsync_ssh_cmd)"
  ayil_hpc_control_alive || {
    echo "ERROR: SSH master did not start." >&2
    return 1
  }
}

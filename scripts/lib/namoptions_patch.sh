# shellcheck shell=bash
# MOSAiC_AYIL overrides applied to per-day ``namoptions`` when staging runs.

# DALES ``modstartup``: trestart < 0 disables all restart file output (initd/inits).
ayil_disable_restart_writes() {
  local namoptions="$1"
  if [[ ! -f "${namoptions}" ]]; then
    echo "ERROR: namoptions not found: ${namoptions}" >&2
    return 1
  fi
  if ! grep -qE '^[[:space:]]*trestart[[:space:]]*=' "${namoptions}"; then
    echo "ERROR: trestart not found in ${namoptions}" >&2
    return 1
  fi
  sed -i -E \
    's/^[[:space:]]*trestart[[:space:]]*=.*/    trestart = -1    ! AYIL: no restart checkpoints (DALES trestart < 0)/' \
    "${namoptions}"
}

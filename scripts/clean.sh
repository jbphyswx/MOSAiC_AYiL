#!/usr/bin/env bash
# Remove build and/or run artifacts (does not touch ayil_config_input_results).
#
# Usage:
#   clean.sh build          # remove MOSAiC_AYiL/build
#   clean.sh runs           # remove runs/
#   clean.sh all            # both
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

what="${1:-}"
if [[ -z "${what}" ]]; then
  echo "Usage: $0 build|runs|all" >&2
  exit 1
fi

rm_build() {
  if [[ -d "${DALES_BUILD}" ]]; then
    echo "Removing ${DALES_BUILD}"
    rm -rf "${DALES_BUILD}"
  fi
}

rm_runs() {
  if [[ -d "${AYiL_RUNS}" ]]; then
    echo "Removing ${AYiL_RUNS}"
    rm -rf "${AYiL_RUNS}"
  fi
}

case "${what}" in
  build) rm_build ;;
  runs)  rm_runs ;;
  all)   rm_build; rm_runs ;;
  *)
    echo "Usage: $0 build|runs|all" >&2
    exit 1
    ;;
esac

echo "Done."

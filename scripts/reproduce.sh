#!/usr/bin/env bash
# Canonical entry point: check tools, bootstrap build tree, compile dales4, run lightweight tests.
#
# Usage:
#   ./scripts/reproduce.sh           # build + ./test/run_tests.sh (mock LES only)
#   ./scripts/reproduce.sh --manual-smoke   # also run scripts/manual/smoke_test.sh on compute
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANUAL_SMOKE=0
for arg in "$@"; do
  case "${arg}" in
    --manual-smoke) MANUAL_SMOKE=1 ;;
    -h|--help)
      echo "Usage: $0 [--manual-smoke]"
      exit 0
      ;;
  esac
done

if [[ -f "${SCRIPT_DIR}/env.local" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/env.local"
fi

echo "======== 1/4 prerequisites ========"
"${SCRIPT_DIR}/check_prerequisites.sh"

echo ""
echo "======== 2/4 bootstrap build tree ========"
"${SCRIPT_DIR}/bootstrap_build_tree.sh"

echo ""
echo "======== 3/4 build dales4 ========"
"${SCRIPT_DIR}/build_dales.sh"

echo ""
echo "======== 4/4 lightweight tests (mock_dales4) ========"
"${SCRIPT_DIR}/../test/run_tests.sh"

if (( MANUAL_SMOKE == 1 )); then
  echo ""
  echo "======== optional manual LES smoke (compute node) ========"
  bash "${SCRIPT_DIR}/manual/smoke_test.sh"
fi

echo ""
echo "Reproduce pipeline completed."
echo "  Tests: mock orchestration only (safe for CI / login / laptop)."
echo "  Real LES: scripts/manual/ on a compute node with ample memory."

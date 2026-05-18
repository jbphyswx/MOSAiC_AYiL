#!/usr/bin/env bash
# Canonical entry point: check tools, bootstrap build tree, compile dales4, smoke test.
#
# Usage: ./scripts/reproduce.sh
#
# Override paths or rank count via scripts/env.local (see scripts/env.example).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
echo "======== 4/4 smoke test ========"
"${SCRIPT_DIR}/smoke_test.sh"

echo ""
echo "======== tests ========"
"${SCRIPT_DIR}/../test/run_tests.sh"

echo ""
echo "Reproduce pipeline completed successfully."
echo "Next: ./scripts/run_local.sh 20200720   # or run_case.sh on Slurm"

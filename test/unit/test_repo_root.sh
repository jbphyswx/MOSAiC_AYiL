#!/usr/bin/env bash
# Unit tests for scripts/lib/repo_root.sh (Slurm spool-safe root resolution).
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/repo_root.sh
source "${REPO_ROOT}/scripts/lib/repo_root.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

resolved="$(ayil_resolve_repo_root)"
[[ "${resolved}" == "${REPO_ROOT}" ]] || fail "expected ${REPO_ROOT}, got ${resolved}"
pass "default resolution"

export MOSAiC_AYIL_ROOT="${REPO_ROOT}"
unset SLURM_SUBMIT_DIR
resolved="$(ayil_resolve_repo_root)"
[[ "${resolved}" == "${REPO_ROOT}" ]] || fail "MOSAiC_AYIL_ROOT export"
pass "MOSAiC_AYIL_ROOT"

unset MOSAiC_AYIL_ROOT
export SLURM_SUBMIT_DIR="${REPO_ROOT}"
resolved="$(ayil_resolve_repo_root)"
[[ "${resolved}" == "${REPO_ROOT}" ]] || fail "SLURM_SUBMIT_DIR"
pass "SLURM_SUBMIT_DIR"

# Spool-like: repo_root.sh copied outside the checkout with no Slurm env hints.
tmpdir="$(mktemp -d)"
cp "${REPO_ROOT}/scripts/lib/repo_root.sh" "${tmpdir}/"
if (
  unset MOSAiC_AYIL_ROOT SLURM_SUBMIT_DIR
  # shellcheck source=/dev/null
  source "${tmpdir}/repo_root.sh"
  ayil_resolve_repo_root
) 2>/dev/null; then
  rm -rf "${tmpdir}"
  fail "expected failure when sourced outside checkout"
fi
rm -rf "${tmpdir}"
pass "fails outside checkout without env hints"

echo "All repo_root tests passed."

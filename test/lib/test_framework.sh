# shellcheck shell=bash
# Minimal test harness (no bats dependency).

TEST_PASS=${TEST_PASS:-0}
TEST_FAIL=${TEST_FAIL:-0}
TEST_SKIP=${TEST_SKIP:-0}

test_fail() {
  echo "FAIL: $*" >&2
  (( TEST_FAIL++ )) || true
}

test_pass() {
  (( TEST_PASS++ )) || true
}

test_skip() {
  echo "SKIP: $*"
  (( TEST_SKIP++ )) || true
}

assert_eq() {
  local got="$1" expected="$2" msg="${3:-}"
  if [[ "${got}" == "${expected}" ]]; then
    test_pass
  else
    test_fail "${msg} expected '${expected}', got '${got}'"
  fi
}

assert_ne() {
  local got="$1" not_expected="$2" msg="${3:-}"
  if [[ "${got}" != "${not_expected}" ]]; then
    test_pass
  else
    test_fail "${msg} did not expect '${not_expected}'"
  fi
}

assert_true() {
  local msg="${2:-}"
  if eval "$1"; then
    test_pass
  else
    test_fail "${msg} (${1})"
  fi
}

assert_file_exists() {
  [[ -f "$1" ]] && test_pass || test_fail "missing file: $1"
}

run_test_file() {
  local f="$1"
  echo ""
  echo "=== $(basename "${f}") ==="
  set +e
  # shellcheck source=/dev/null
  source "${f}"
  set -e
}

test_summary() {
  echo ""
  echo "========================================"
  echo "Passed: ${TEST_PASS}  Failed: ${TEST_FAIL}  Skipped: ${TEST_SKIP}"
  if (( TEST_FAIL > 0 )); then
    return 1
  fi
  return 0
}

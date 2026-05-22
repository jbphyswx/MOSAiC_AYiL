#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/run_status.sh
source "${REPO_ROOT}/scripts/lib/run_status.sh"
# shellcheck source=../../scripts/lib/pending_dates.sh
source "${REPO_ROOT}/scripts/lib/pending_dates.sh"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

if ayil_should_submit_date "${TMP}" 0; then
  test_pass "missing dir is submittable"
else
  test_fail "missing dir should be submittable"
fi

touch "${TMP}/${AYIL_STATUS_COMPLETE}"
if ! ayil_should_submit_date "${TMP}" 0; then
  test_pass "complete not submittable without force"
else
  test_fail "complete should not submit without force"
fi

if ayil_should_submit_date "${TMP}" 1; then
  test_pass "complete submittable with force"
else
  test_fail "complete should submit with force"
fi

printf 'date=20200720\nstarted_utc=2020-01-01T00:00:00Z\nnproc=4\npid=%s\n' "$$" > "${TMP}/${AYIL_STATUS_RUNNING}"
rm -f "${TMP}/${AYIL_STATUS_COMPLETE}" "${TMP}/${AYIL_STATUS_FAILED}"
if ! ayil_should_submit_date "${TMP}" 0; then
  test_pass "live running marker blocks submit"
else
  test_fail "running should not submit without force"
fi

printf 'pid=999999999\nstarted_utc=2020-01-01T00:00:00Z\n' > "${TMP}/${AYIL_STATUS_RUNNING}"
rm -f "${TMP}/${AYIL_STATUS_FAILED}"
if ayil_should_submit_date "${TMP}" 0; then
  test_pass "stale running (dead pid) is recovered and submittable"
else
  test_fail "stale running after TIMEOUT should submit"
fi

touch "${TMP}/.ayil_chunk_0_complete"
rm -f "${TMP}/${AYIL_STATUS_RUNNING}" "${TMP}/${AYIL_STATUS_COMPLETE}"
if ayil_should_submit_date "${TMP}" 0; then
  test_pass "partial chunk day is submittable"
else
  test_fail "partial chunk day should submit"
fi

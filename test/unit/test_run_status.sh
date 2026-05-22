#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/run_status.sh
source "${REPO_ROOT}/scripts/lib/run_status.sh"

FIX="${REPO_ROOT}/test/fixtures"
NAM="${FIX}/namoptions_minimal"

assert_eq "$(ayil_read_runtime "${NAM}")" "100" "read runtime"

assert_eq "$(ayil_last_sim_time "${FIX}/dales_log_complete.txt")" "100.00" "last sim time complete"

if ayil_sim_complete "${FIX}/dales_log_complete.txt" "${NAM}"; then
  test_pass
else
  test_fail "sim should be complete at 100s"
fi

if ! ayil_sim_complete "${FIX}/dales_log_partial.txt" "${NAM}"; then
  test_pass
else
  test_fail "sim should not be complete at 99.5s vs runtime 100"
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
assert_eq "$(ayil_run_state "${TMP}")" "missing" "empty dir"

cp "${NAM}" "${TMP}/namoptions"
assert_eq "$(ayil_run_state "${TMP}")" "prepared" "prepared state"

touch "${TMP}/${AYIL_STATUS_COMPLETE}"
assert_eq "$(ayil_run_state "${TMP}")" "complete" "complete state"

rm -f "${TMP}/${AYIL_STATUS_COMPLETE}"
touch "${TMP}/${AYIL_STATUS_RUNNING}" "${TMP}/${AYIL_STATUS_FAILED}"
assert_eq "$(ayil_run_state "${TMP}")" "failed" "failed beats stale running"

rm -f "${TMP}/${AYIL_STATUS_FAILED}"
printf 'pid=999999999\nstarted_utc=2020-01-01T00:00:00Z\n' > "${TMP}/${AYIL_STATUS_RUNNING}"
ayil_recover_stale_run_state "${TMP}"
assert_eq "$(ayil_run_state "${TMP}")" "failed" "stale running recovered to failed"
assert_true "[[ ! -f '${TMP}/${AYIL_STATUS_RUNNING}' ]]" "running marker removed"

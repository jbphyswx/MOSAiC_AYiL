#!/usr/bin/env bash
# Unit tests for canonical run log paths.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/logging_paths.sh
source "${REPO_ROOT}/scripts/lib/logging_paths.sh"

RUN="/tmp/ayil_test_logs_20990101"

assert_eq "$(ayil_dales_log "${RUN}")" "${RUN}/logs/dales.log" "dales log path"
assert_eq "$(ayil_slurm_log_out "${RUN}")" "${RUN}/logs/slurm.out" "slurm out path"
assert_eq "$(ayil_convert_log "${RUN}")" "${RUN}/logs/convert.log" "convert log path"

rm -rf "${RUN}"
ayil_ensure_run_logs "${RUN}"
assert_true "[[ -d \"${RUN}/logs\" ]]" "ensure_run_logs creates logs/"

echo "x" > "${RUN}/logs/slurm.out"
echo "y" > "${RUN}/logs/dales.log"
touch "${RUN}/.ayil_failed"
# shellcheck source=../../scripts/lib/run_status.sh
source "${REPO_ROOT}/scripts/lib/run_status.sh"
ayil_clean_run_outputs "${RUN}"
assert_true "[[ -f \"${RUN}/logs/slurm.out\" ]]" "clean keeps slurm.out"
assert_true "[[ ! -f \"${RUN}/logs/dales.log\" ]]" "clean removes dales.log"
assert_true "[[ ! -f \"${RUN}/.ayil_failed\" ]]" "clean removes status markers"
rm -rf "${RUN}"

test_summary

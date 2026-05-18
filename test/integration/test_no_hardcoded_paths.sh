#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

bad_re='sampo|jbenjami|/home/[a-z]+/'

while IFS= read -r -d '' f; do
  if grep -qE "${bad_re}" "${f}"; then
    test_fail "site-specific pattern in ${f}"
  fi
done < <(find "${REPO_ROOT}/scripts" -type f \( -name '*.sh' -o -name '*.slurm' \) -print0)

test_pass

assert_true "grep -q openmpi '${REPO_ROOT}/scripts/lib/mpi_env.sh'" \
  "mpi_env lists common paths as candidates"

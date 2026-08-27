#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/restart_naming.sh
source "${REPO_ROOT}/scripts/lib/restart_naming.sh"

# Regression: wrong template from Zenodo cold-start extrapolation (HPC chunk 1 failure).
WRONG_STARTFILE='initdlatestx000y000.001'
AYiL_STARTFILE='initdlatestm00000001.001'
RTIMEE=300
EXP='001'

fail=0

latest="$(ayil_dales_latest_initd_name "${RTIMEE}" 'x000y014' "${EXP}")"
[[ "${latest}" == 'initdlatestmx000y014.001' ]] || {
  echo "FAIL: latest name got ${latest}" >&2
  fail=1
}

resolved="$(ayil_dales_resolve_initd_startfile "${AYiL_STARTFILE}" 'x000y014')"
[[ "${resolved}" == "${latest}" ]] || {
  echo "FAIL: resolve(${AYiL_STARTFILE})=${resolved} != ${latest}" >&2
  fail=1
}

bad="$(ayil_dales_resolve_initd_startfile "${WRONG_STARTFILE}" 'x000y014')"
# Wrong Zenodo extrapolation (initdlatestx...) double-stacks x at char 13 vs cmyid x000y014.
[[ "${bad}" != "${latest}" ]] || {
  echo "FAIL: wrong template must not match on-disk latest name" >&2
  fail=1
}

# Position 12 must be 'm' (from write template), not 'x'.
[[ "${AYiL_STARTFILE:11:1}" == 'm' ]] || {
  echo "FAIL: warm startfile char 12 must be m" >&2
  fail=1
}

for nproc in 4 8 16 32 64; do
  while read -r cid; do
    lat="$(ayil_dales_latest_initd_name "${RTIMEE}" "${cid}" "${EXP}")"
    res="$(ayil_dales_resolve_initd_startfile "${AYiL_STARTFILE}" "${cid}")"
    if [[ "${res}" != "${lat}" ]]; then
      echo "FAIL: nproc=${nproc} cmyid=${cid}: resolve=${res} latest=${lat}" >&2
      fail=1
    fi
    bad_res="$(ayil_dales_resolve_initd_startfile "${WRONG_STARTFILE}" "${cid}")"
    if [[ "${bad_res}" == "${lat}" ]]; then
      echo "FAIL: wrong template matched latest for ${cid}" >&2
      fail=1
    fi
  done < <(ayil_dales_cmyids_for_nproc "${nproc}")
done

if (( fail != 0 )); then
  exit 1
fi
echo "PASS: restart naming matches modstartup.f90 (all ranks, regression on wrong template)"

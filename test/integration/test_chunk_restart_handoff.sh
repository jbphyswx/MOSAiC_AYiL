#!/usr/bin/env bash
# Offline end-to-end: chunk 0 writes latest restarts; chunk 1 namoptions must resolve to those paths.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"
# shellcheck source=../../scripts/lib/chunk_run.sh
source "${REPO_ROOT}/scripts/lib/chunk_run.sh"
# shellcheck source=../../scripts/lib/namoptions_patch.sh
source "${REPO_ROOT}/scripts/lib/namoptions_patch.sh"
# shellcheck source=../../scripts/lib/restart_naming.sh
source "${REPO_ROOT}/scripts/lib/restart_naming.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

RUN="${TMP}/20191101"
mkdir -p "${RUN}"
cp "${REPO_ROOT}/ayil_config_input_results/20191101/namoptions" "${RUN}/namoptions" 2>/dev/null \
  || cp "${REPO_ROOT}/ayil_config_input_results/20200720/namoptions" "${RUN}/namoptions"

CHUNK_SEC=300
DAY_SEC=10800
RTIMEE="${CHUNK_SEC}"
N_CHUNKS="$(ayil_n_chunks "${DAY_SEC}" "${CHUNK_SEC}")"
NPROC=32

ayil_apply_chunk_namoptions "${RUN}/namoptions" 0 "${N_CHUNKS}" "${CHUNK_SEC}" "${DAY_SEC}"
grep -q 'lwarmstart = .false.' "${RUN}/namoptions" || test_fail "chunk 0 cold start"

# Simulate chunk 0 completion: DALES wrote initdlatest* per rank.
while read -r cid; do
  lat="$(ayil_dales_latest_initd_name "${RTIMEE}" "${cid}" '001')"
  touch "${RUN}/${lat}"
done < <(ayil_dales_cmyids_for_nproc "${NPROC}")

ayil_apply_chunk_namoptions "${RUN}/namoptions" 1 "${N_CHUNKS}" "${CHUNK_SEC}" "${DAY_SEC}"
grep -q 'lwarmstart = .true.' "${RUN}/namoptions" || test_fail "chunk 1 warm start"

startfile="$(grep -E "^[[:space:]]*startfile" "${RUN}/namoptions" | sed -E "s/.*'([^']+)'.*/\1/")"
[[ "${startfile}" == "${AYIL_RESTART_STARTFILE}" ]] || test_fail "startfile not AYIL_RESTART_STARTFILE"

missing=0
while read -r cid; do
  path="$(ayil_dales_resolve_initd_startfile "${startfile}" "${cid}")"
  if [[ ! -f "${RUN}/${path}" ]]; then
    echo "missing restart: ${path} (cmyid=${cid})" >&2
    missing=1
  fi
done < <(ayil_dales_cmyids_for_nproc "${NPROC}")

if (( missing != 0 )); then
  test_fail "chunk 1 would fail Fortran open (restart files not found)"
fi

# Prune must keep latest for chunk 2.
touch "${RUN}/initd000h05mx000y000.001"
ayil_prune_timed_restart_files "${RUN}"
[[ -f "${RUN}/initdlatestmx000y000.001" ]] || test_fail "prune removed latest restart"
[[ ! -f "${RUN}/initd000h05mx000y000.001" ]] || test_fail "prune kept timed restart"

test_pass

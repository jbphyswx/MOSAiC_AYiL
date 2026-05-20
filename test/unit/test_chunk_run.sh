#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/chunk_run.sh
source "${REPO_ROOT}/scripts/lib/chunk_run.sh"
# shellcheck source=../../scripts/lib/namoptions_patch.sh
source "${REPO_ROOT}/scripts/lib/namoptions_patch.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

n="$(ayil_n_chunks 10800 600)"
[[ "${n}" == "18" ]] || {
  echo "FAIL: expected 18 chunks (600s), got ${n}" >&2
  exit 1
}
echo "PASS: ayil_n_chunks"

cat > "${TMP}/namoptions" <<'EOF'
&run
    lwarmstart = .false.
    startfile = 'initd002h00mx000y000.001'
    runtime = 7200
    trestart = -1
/
EOF

ayil_apply_chunk_namoptions "${TMP}/namoptions" 0 18
grep -q 'runtime = 600' "${TMP}/namoptions" || {
  echo "FAIL: chunk 0 runtime" >&2
  exit 1
}
grep -q 'lwarmstart = .false.' "${TMP}/namoptions" || {
  echo "FAIL: chunk 0 cold start" >&2
  exit 1
}
grep -q 'trestart = 0' "${TMP}/namoptions" || {
  echo "FAIL: chunk 0 trestart=0" >&2
  exit 1
}

ayil_apply_chunk_namoptions "${TMP}/namoptions" 2 18
grep -q 'lwarmstart = .true.' "${TMP}/namoptions" || {
  echo "FAIL: chunk 2 warm start" >&2
  exit 1
}
grep -q "startfile = 'initdlatestx000y000.001'" "${TMP}/namoptions" || {
  echo "FAIL: chunk 2 startfile" >&2
  exit 1
}

ayil_apply_chunk_namoptions "${TMP}/namoptions" 17 18
grep -q 'trestart = -1' "${TMP}/namoptions" || {
  echo "FAIL: last chunk no restart write" >&2
  exit 1
}
echo "PASS: ayil_apply_chunk_namoptions"

RUN="${TMP}/run"
mkdir -p "${RUN}"
touch "${RUN}/initd000h30m00000001.001" "${RUN}/initdlatestm00000001.001"
ayil_prune_timed_restart_files "${RUN}"
[[ -f "${RUN}/initdlatestm00000001.001" ]] || {
  echo "FAIL: latest restart removed" >&2
  exit 1
}
[[ ! -f "${RUN}/initd000h30m00000001.001" ]] || {
  echo "FAIL: timed restart not removed" >&2
  exit 1
}
echo "PASS: ayil_prune_timed_restart_files"

RUN2="${TMP}/run2"
mkdir -p "${RUN2}"
touch "${RUN2}/fielddump.001.001.001.nc"

# Failed old run: auto-clean on chunk 0 without force
ayil_should_clean_run_outputs "${RUN2}" 0 1 0 && echo "PASS: auto-clean chunk0 failed day" || {
  echo "FAIL: should clean chunk0 without force" >&2
  exit 1
}

touch "${RUN2}/.ayil_chunk_0_complete"
ayil_should_clean_run_outputs "${RUN2}" 0 1 1 && {
  echo "FAIL: should not clean resume chunk1" >&2
  exit 1
}
echo "PASS: no clean resume chunk1"

touch "${RUN2}/.ayil_complete"
ayil_should_clean_run_outputs "${RUN2}" 0 1 0 && {
  echo "FAIL: should not clean complete day without force" >&2
  exit 1
}
ayil_should_clean_run_outputs "${RUN2}" 1 1 0 || {
  echo "FAIL: force should clean complete day at chunk0" >&2
  exit 1
}
ayil_should_clean_run_outputs "${RUN2}" 1 1 2 && {
  echo "FAIL: force must not clean chunk2 mid-chain" >&2
  exit 1
}
echo "PASS: ayil_should_clean_run_outputs"

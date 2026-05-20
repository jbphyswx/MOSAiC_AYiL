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

n="$(ayil_n_chunks 10800 1800)"
[[ "${n}" == "6" ]] || {
  echo "FAIL: expected 6 chunks, got ${n}" >&2
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

ayil_apply_chunk_namoptions "${TMP}/namoptions" 0 6
grep -q 'runtime = 1800' "${TMP}/namoptions" || {
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

ayil_apply_chunk_namoptions "${TMP}/namoptions" 2 6
grep -q 'lwarmstart = .true.' "${TMP}/namoptions" || {
  echo "FAIL: chunk 2 warm start" >&2
  exit 1
}
grep -q "startfile = 'initdlatestx000y000.001'" "${TMP}/namoptions" || {
  echo "FAIL: chunk 2 startfile" >&2
  exit 1
}

ayil_apply_chunk_namoptions "${TMP}/namoptions" 5 6
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

#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
MOCK="${REPO_ROOT}/test/fixtures/bin/mock_dales4"
chmod +x "${MOCK}" 2>/dev/null || true

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
cd "${TMP}"

cat > namoptions <<'EOF'
&run
    lwarmstart = .false.
    startfile = 'initd002h00mx000y000.001'
    runtime = 60
    trestart = 0
/
EOF

export AYIL_MOCK_NPROC=4
out="$("${MOCK}" namoptions 2>&1)" || {
  echo "FAIL: cold+trestart mock run: ${out}" >&2
  exit 1
}
echo "${out}" | grep -q 'Time of Simulation: 60' || {
  echo "FAIL: missing sim line" >&2
  exit 1
}
[[ -f initdlatestmx000y000.001 ]] || {
  echo "FAIL: missing latest restart rank 0" >&2
  exit 1
}

cat > namoptions <<'EOF'
&run
    lwarmstart = .true.
    startfile = 'initdlatestx000y000.001'
    runtime = 60
    trestart = -1
/
EOF
if "${MOCK}" namoptions >/dev/null 2>&1; then
  echo "FAIL: wrong startfile should fail warm open" >&2
  exit 1
fi

cat > namoptions <<'EOF'
&run
    lwarmstart = .true.
    startfile = 'initdlatestm00000001.001'
    runtime = 60
    trestart = -1
/
EOF
touch initdlatestmx000y000.001 initdlatestmx000y001.001 initdlatestmx000y002.001 initdlatestmx000y003.001
"${MOCK}" namoptions >/dev/null || {
  echo "FAIL: correct warm start should pass" >&2
  exit 1
}

echo "PASS: mock_dales4"

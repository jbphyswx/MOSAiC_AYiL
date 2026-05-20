#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/namoptions_patch.sh
source "${REPO_ROOT}/scripts/lib/namoptions_patch.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/namoptions" <<'EOF'
&run
    runtime = 7200
    trestart = 1800
/
EOF

ayil_disable_restart_writes "${TMP}/namoptions"
grep -q 'trestart = -1' "${TMP}/namoptions" || {
  echo "FAIL: trestart not set to -1" >&2
  cat "${TMP}/namoptions"
  exit 1
}

ayil_set_runtime "${TMP}/namoptions" 10800
grep -q 'runtime = 10800' "${TMP}/namoptions" || {
  echo "FAIL: runtime not 10800" >&2
  exit 1
}

export AYIL_USE_RESTART_CHUNKS=0
ayil_apply_prepare_namoptions "${TMP}/namoptions"
grep -q 'trestart = -1' "${TMP}/namoptions" || {
  echo "FAIL: prepare disables restarts" >&2
  exit 1
}
echo "PASS: namoptions_patch"

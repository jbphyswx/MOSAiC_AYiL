#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/test_framework.sh
source "${REPO_ROOT}/test/lib/test_framework.sh"

(
  export MOSAiC_AYiL_ROOT="${REPO_ROOT}"
  export AYiL_SKIP_ZENODO_FETCH=1
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  export AYiL_INPUTS="${TMP}/inputs"
  # shellcheck source=../../scripts/lib/zenodo_inputs.sh
  source "${REPO_ROOT}/scripts/lib/zenodo_inputs.sh"

  mkdir -p "${AYiL_INPUTS}/20200720"
  touch "${AYiL_INPUTS}/20200720/namoptions"
  touch "${AYiL_INPUTS}/20200720/scm_in.a_year_in_les.20200720.nc"

  assert_true 'ayil_day_inputs_ready 20200720' "day ready when namoptions and scm_in exist"
  assert_true '! ayil_day_inputs_ready 20990101' "missing day not ready"

  if ayil_ensure_day_inputs 20990101 2>/dev/null; then
    echo "FAIL: ensure_day_inputs should fail when fetch disabled" >&2
    exit 1
  fi
  echo "PASS: ensure_day_inputs fails without fetch when day missing"
)

# rsync --ignore-existing must not replace an existing namoptions (git-tracked edits).
RSYNC_TMP="$(mktemp -d)"
trap 'rm -rf "${RSYNC_TMP}"' EXIT
mkdir -p "${RSYNC_TMP}/dest/20200720" "${RSYNC_TMP}/src/20200720"
echo "trestart = -1" > "${RSYNC_TMP}/dest/20200720/namoptions"
echo "trestart = 1800" > "${RSYNC_TMP}/src/20200720/namoptions"
echo "artifact" > "${RSYNC_TMP}/src/20200720/scm_in.a_year_in_les.20200720.nc"
rsync -a --ignore-existing "${RSYNC_TMP}/src/" "${RSYNC_TMP}/dest/"
grep -q 'trestart = -1' "${RSYNC_TMP}/dest/20200720/namoptions" || {
  echo "FAIL: rsync overwrote namoptions" >&2
  exit 1
}
[[ -f "${RSYNC_TMP}/dest/20200720/scm_in.a_year_in_les.20200720.nc" ]] || {
  echo "FAIL: rsync did not add missing artifact" >&2
  exit 1
}
echo "PASS: rsync ignore-existing keeps namoptions, adds artifacts"

test_summary

#!/usr/bin/env bash
# List YYYYMMDD folders under ayil_config_input_results that are ready for prepare_case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/zenodo_inputs.sh
source "${SCRIPT_DIR}/lib/zenodo_inputs.sh"

count=0
while IFS= read -r date; do
  if ayil_day_inputs_ready "${date}"; then
    echo "${date}"
    count=$(( count + 1 ))
  fi
done < <(find "${AYIL_INPUTS}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

echo "" >&2
echo "${count} ready day(s) under ${AYIL_INPUTS}" >&2

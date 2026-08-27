#!/usr/bin/env bash
# Prefetch Zenodo ayil_config_input_results.zip into AYiL_INPUTS (optional).
#
# Normal workflow: prepare_case / run_local / run_slurm fetch automatically.
# Use this to download on a login node before batch jobs.
#
# Usage: ./scripts/fetch_zenodo_inputs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/zenodo_inputs.sh
source "${SCRIPT_DIR}/lib/zenodo_inputs.sh"

ayil_ensure_zenodo_bundle
echo "Inputs ready: ${AYiL_INPUTS}"

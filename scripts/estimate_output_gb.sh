#!/usr/bin/env bash
# Rough order-of-magnitude output size for one full AYIL day (runtime=7200 s).
#
# Usage: estimate_output_gb.sh [NPROC]
#
# Uses namoptions in ayil_config_input_results/20200720 as reference.
# Extrapolates from smoke-run scaling when runs/smoke_* exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/run_status.sh
source "${SCRIPT_DIR}/lib/run_status.sh"

NPROC="${1:-${DALES_NPROC:-64}}"
REF_NAM="${AYIL_INPUTS}/20200720/namoptions"
RUNTIME="$(ayil_read_runtime "${REF_NAM}")"
FIELD_DTAV="$(awk '/^&namfielddump/,/^\/$/ { if ($1 ~ /^dtav/) { gsub(/[^0-9]/,"",$3); print $3; exit } }' "${REF_NAM}")"
KHIGH="$(awk '/^&namfielddump/,/^\/$/ { if ($1 ~ /^khigh/) { gsub(/[^0-9]/,"",$3); print $3; exit } }' "${REF_NAM}")"
FIELD_DTAV="${FIELD_DTAV:-1800}"
KHIGH="${KHIGH:-200}"
RUNTIME="${RUNTIME:-7200}"

ITOT=320
JTOT=320
NVAR=19
NDUMP=$(( RUNTIME / FIELD_DTAV ))

# Subdomain sizes for square MPI grid (approximate)
SIDE=$(awk -v n="${NPROC}" 'BEGIN { print int(sqrt(n)) }')
while (( ITOT % SIDE != 0 || JTOT % SIDE != 0 )); do
  SIDE=$(( SIDE - 1 ))
done
IMAX=$(( ITOT / SIDE ))
JMAX=$(( JTOT / SIDE ))

# Uncompressed 8-byte fields per rank per fielddump (upper bound)
BYTES_PER_DUMP=$(( IMAX * JMAX * KHIGH * NVAR * 8 ))
FIELD_GB=$(awk -v b="${BYTES_PER_DUMP}" -v d="${NDUMP}" -v n="${NPROC}" \
  'BEGIN { printf "%.1f", b * d * n / 1024^3 }')

echo "Reference case: 20200720 (runtime=${RUNTIME}s, fielddump every ${FIELD_DTAV}s, khigh=${KHIGH})"
echo "MPI ranks: ${NPROC} (approx ${SIDE}x${SIDE} -> ${IMAX}x${JMAX} horizontal per rank)"
echo ""
echo "fielddump.*.*.001.nc (uncompressed upper bound): ~${FIELD_GB} GB"
echo "All outputs (profiles, cross-sections, stats, logs): typically 1.5-3x fielddump alone"
echo "  => expect roughly $(awk -v f="${FIELD_GB}" 'BEGIN { printf "%.0f-%.0f", f*1.5, f*3 }') GB per completed day"
echo ""

SMOKE_DIR="${AYIL_RUNS}/smoke_20200720"
if [[ -d "${SMOKE_DIR}" ]]; then
  smoke_bytes=$(ayil_dir_size_bytes "${SMOKE_DIR}")
  # shellcheck source=lib/logging_paths.sh
  source "${SCRIPT_DIR}/lib/logging_paths.sh"
  smoke_sim=$(ayil_last_sim_time "$(ayil_smoke_log "${SMOKE_DIR}")" 2>/dev/null || \
              ayil_last_sim_time "$(ayil_dales_log "${SMOKE_DIR}")" 2>/dev/null || \
              ayil_last_sim_time "${SMOKE_DIR}/smoke_test.log" 2>/dev/null || echo "")
  if [[ -n "${smoke_sim}" && "${smoke_sim}" != "0.00" ]]; then
    proj=$(awk -v b="${smoke_bytes}" -v s="${smoke_sim}" -v r="${RUNTIME}" \
      'BEGIN { printf "%.1f", b * (r/s) / 1024^3 }')
    echo "Empirical (from smoke run): ${smoke_sim}s sim -> $(ayil_human_bytes "${smoke_bytes}")"
    echo "  linear extrapolation to ${RUNTIME}s: ~${proj} GB (very rough; fielddump weighted to end)"
  fi
fi

echo ""
echo "Inputs per day (scm_in + ancillary): ~$(du -sh "${AYIL_INPUTS}/20200720" 2>/dev/null | awk '{print $1}' || echo '?')"

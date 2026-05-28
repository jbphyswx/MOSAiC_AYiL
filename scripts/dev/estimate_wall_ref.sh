#!/usr/bin/env bash
# Estimate integration wall/sim from runs/YYYYMMDD/logs/progress.log (+ optional dales.log mean dt).
#
# Use the printed AYIL_SLURM_WALL_REF_* suggestion in env.local after a representative
# finished chunk (same ntasks and case as production). Replaces the repo default R_ref.
#
# Usage:
#   ./scripts/dev/estimate_wall_ref.sh 20191101
#   ./scripts/dev/estimate_wall_ref.sh 20191101 --ntasks 32 --sim-end 300
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.sh
source "${SCRIPT_DIR}/../config.sh"
# shellcheck source=../lib/run_status.sh
source "${SCRIPT_DIR}/../lib/run_status.sh"

DATE="${1:-}"
NTASKS="${DALES_NPROC:-32}"
SIM_END=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ntasks) NTASKS="$2"; shift 2 ;;
    --sim-end) SIM_END="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "${DATE}" ]]; then
        DATE="$1"
      fi
      shift
      ;;
  esac
done

[[ -n "${DATE}" ]] || {
  echo "Usage: $0 YYYYMMDD [--ntasks N] [--sim-end SEC]" >&2
  exit 1
}

PROGRESS="${AYIL_RUNS}/${DATE}/logs/progress.log"
DALES_LOG="${AYIL_RUNS}/${DATE}/logs/dales.log"
[[ -f "${PROGRESS}" ]] || {
  echo "ERROR: missing ${PROGRESS}" >&2
  exit 1
}

read -r t0 t1 s0 s1 <<<"$(
  awk -v end="${SIM_END}" '
    /progress[[:space:]]+sim=/ {
      if (match($0, /\[([0-9-]+ [0-9:]+)\]/, t)) ts = t[1]
      if (match($0, /sim=([0-9.]+)\//, s)) sim = s[1] + 0
      if (ts == "" || sim <= 0) next
      if (end != "" && sim > end + 0.5) next
      if (!have0) { t0 = ts; s0 = sim; have0 = 1 }
      t1 = ts; s1 = sim
    }
    END {
      if (!have0) exit 1
      printf "%s %s %.4f %.4f\n", t0, t1, s0, s1
    }
  ' "${PROGRESS}"
)"

wall_sec=$(( $(date -u -d "${t1}" +%s) - $(date -u -d "${t0}" +%s) ))
sim_sec="$(awk -v a="${s0}" -v b="${s1}" 'BEGIN { printf "%.2f", b - a }')"
rate="$(awk -v w="${wall_sec}" -v s="${sim_sec}" 'BEGIN { if (s > 0) printf "%.2f", w / s; else exit 1 }')"

mean_dt=""
if [[ -f "${DALES_LOG}" ]]; then
  mean_dt="$(awk '
    /Time of Simulation:/ && /[[:space:]]dt:/ {
      pos = index($0, "Time of Simulation:")
      rest = substr($0, pos + 19)
      if (match(rest, /[0-9]+\.?[0-9]*/)) sim = substr(rest, RSTART, RLENGTH) + 0; else next
      pos2 = index($0, "dt:")
      rest2 = substr($0, pos2 + 3)
      if (match(rest2, /[0-9]+\.?[0-9]*/)) dt = substr(rest2, RSTART, RLENGTH) + 0; else next
      if (sim >= s0 && sim <= s1) { sum += dt; n++ }
    }
    END { if (n > 0) printf "%.3f", sum / n }
  ' s0="${s0}" s1="${s1}" "${DALES_LOG}")"
fi

N_REF="${AYIL_SLURM_WALL_REF_NTASKS:-64}"
DT_REF="${AYIL_SIM_DT_REF_SEC:-2.0}"
# R_ref at N_REF: rate measured at NTASKS, scaled by 1/n to reference rank count.
r_ref="$(awk -v r="${rate}" -v n="${NTASKS}" -v nr="${N_REF}" \
  'BEGIN { printf "%.2f", r * n / nr }')"

echo "=== wall/sim estimate: ${DATE} ==="
echo "progress.log:  ${t0} .. ${t1}"
echo "sim window:    ${s0} .. ${s1} s  (${sim_sec} s integration)"
echo "wall elapsed:  ${wall_sec} s"
echo "wall/sim:      ${rate} s/s  @ ${NTASKS} MPI tasks (includes cold-start I/O in window)"
if [[ -n "${mean_dt}" ]]; then
  echo "mean dt:       ${mean_dt} s  (dales.log in same sim window)"
  f_dt="$(awk -v ref="${DT_REF}" -v dt="${mean_dt}" 'BEGIN { printf "%.3f", ref / dt }')"
  echo "f_dt pivot:    ${f_dt}  (if production dt differs, wall scales ~ proportionally)"
else
  echo "mean dt:       (no dales.log lines in window — ingest after run)"
  f_dt="?"
fi
echo ""
echo "Suggested env.local (measured @ ${NTASKS}; reference @ ${N_REF}):"
echo "  export AYIL_SLURM_NTASKS=${NTASKS}"
echo "  export AYIL_SLURM_WALL_REF_NTASKS=${N_REF}"
echo "  export AYIL_SLURM_WALL_REF_PER_SIM_SEC=${r_ref}"
if [[ -n "${mean_dt}" ]]; then
  echo "  export AYIL_SIM_DT_REF_SEC=${mean_dt}   # pivot f_dt to THIS run; or keep 2.0 and use sim_dt/"
fi
echo ""
echo "For another date with smaller dt, do NOT reuse R_ref alone — build sim_dt/YYYYMMDD.csv"
echo "or set AYIL_SIM_DT_PESSIMISTIC_MIN_DT_SEC for unknown dates."

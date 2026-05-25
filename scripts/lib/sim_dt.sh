# shellcheck shell=bash
# Per-AYIL-date DALES timestep vs simulation time (binned tables for Slurm wall scaling).
#
# Canonical store (versioned in git): ${MOSAiC_AYIL_ROOT}/sim_dt/YYYYMMDD.csv
# See sim_dt/README.md for bootstrap → corpus_complete → retire generation.
#
# Wall parallel term scales as mean(dt_ref/dt) over the segment — smaller dt ⇒ more steps/s.

export AYIL_SIM_DT_BIN_SEC="${AYIL_SIM_DT_BIN_SEC:-60}"
export AYIL_SIM_DT_REF_SEC="${AYIL_SIM_DT_REF_SEC:-2.0}"
export AYIL_SIM_DT_USE="${AYIL_SIM_DT_USE:-1}"
# 1 while bootstrap may write sim_dt/*.csv; set 0 after sim_dt/.corpus_complete
export AYIL_SIM_DT_RECORD="${AYIL_SIM_DT_RECORD:-1}"

ayil_sim_dt_root() {
  echo "${AYIL_SIM_DT_DIR:-${MOSAiC_AYIL_ROOT}/sim_dt}"
}

ayil_sim_dt_csv() {
  local date="$1"
  echo "$(ayil_sim_dt_root)/${date}.csv"
}

ayil_sim_dt_corpus_complete() {
  [[ -f "$(ayil_sim_dt_root)/.corpus_complete" ]]
}

# True when runtime may merge dales.log into sim_dt/ (bootstrap only).
ayil_sim_dt_may_record() {
  if [[ "${AYIL_SIM_DT_RECORD}" != "1" ]]; then
    return 1
  fi
  if ayil_sim_dt_corpus_complete; then
    return 1
  fi
  return 0
}

# Parse dales.log lines: sim_s dt_s [wall_hms]
ayil_sim_dt_parse_log_to_tsv() {
  local log="$1"
  [[ -f "${log}" ]] || return 1
  awk '
    /Time of Simulation:/ && /[[:space:]]dt:/ {
      line = $0
      pos = index(line, "Time of Simulation:")
      rest = substr(line, pos + 19)
      if (match(rest, /[0-9]+\.?[0-9]*/)) {
        sim = substr(rest, RSTART, RLENGTH) + 0
      } else {
        next
      }
      pos2 = index(line, "dt:")
      rest2 = substr(line, pos2 + 3)
      if (match(rest2, /[0-9]+\.?[0-9]*/)) {
        dt = substr(rest2, RSTART, RLENGTH) + 0
      } else {
        next
      }
      wall = ""
      if (match(line, /Time of Day:[[:space:]]+[0-9]+\.[0-9]+/)) {
        w = substr(line, RSTART, RLENGTH)
        sub(/^Time of Day:[[:space:]]+/, "", w)
        wall = w
      }
      if (sim > 0 && dt > 0) {
        printf "%.4f\t%.9f\t%s\n", sim, dt, wall
      }
    }
  ' "${log}"
}

# Merge log into binned CSV (bootstrap). No-op when recording is disabled or corpus is frozen.
ayil_sim_dt_merge_log() {
  local date="$1"
  local log="$2"
  local nproc="${3:-}"
  local bin_sec="${AYIL_SIM_DT_BIN_SEC}"
  local root csv
  if ! ayil_sim_dt_may_record && [[ "${AYIL_SIM_DT_FORCE_RECORD:-0}" != "1" ]]; then
    return 0
  fi
  root="$(ayil_sim_dt_root)"
  csv="$(ayil_sim_dt_csv "${date}")"
  mkdir -p "${root}"
  [[ -f "${log}" ]] || return 0

  awk -v bin="${bin_sec}" -v date="${date}" -v nproc="${nproc}" \
    -v ref="${AYIL_SIM_DT_REF_SEC}" \
    -v utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -v host="$(hostname -s 2>/dev/null || hostname)" \
    -v existing="${csv}" \
    '
    function bin_of(sim) { return int(sim / bin) * bin }

    BEGIN {
      if (existing != "" && (getline < existing) > 0) {
        do {
          if ($0 ~ /^#/) continue
          split($0, a, ",")
          if (length(a) >= 2) {
            b = a[1] + 0
            dt_min[b] = a[2] + 0
            n_lines[b] = (a[3] + 0)
            last_utc[b] = a[4]
          }
        } while ((getline < existing) > 0)
        close(existing)
      }
    }

    /Time of Simulation:/ && /[[:space:]]dt:/ {
      line = $0
      pos = index(line, "Time of Simulation:")
      rest = substr(line, pos + 19)
      if (match(rest, /[0-9]+\.?[0-9]*/)) {
        sim = substr(rest, RSTART, RLENGTH) + 0
      } else next
      pos2 = index(line, "dt:")
      rest2 = substr(line, pos2 + 3)
      if (match(rest2, /[0-9]+\.?[0-9]*/)) {
        dt = substr(rest2, RSTART, RLENGTH) + 0
      } else next
      if (sim <= 0 || dt <= 0) next
      b = bin_of(sim)
      if (!(b in dt_min) || dt < dt_min[b]) dt_min[b] = dt
      n_lines[b]++
      last_utc[b] = utc
    }

    END {
      printf "# ayil_sim_dt version=1\n"
      printf "# date=%s bin_sec=%d dt_ref_sec=%s host=%s nproc=%s updated_utc=%s\n", \
        date, bin, ref, host, nproc, utc
      printf "sim_bin_s,dt_s,n_lines,last_utc\n"
      nb = asorti(dt_min, sorted)
      for (i = 1; i <= nb; i++) {
        b = sorted[i]
        printf "%d,%.9f,%d,%s\n", b, dt_min[b], n_lines[b], last_utc[b]
      }
    }
  ' "${log}" > "${csv}.new"

  [[ -s "${csv}.new" ]] || { rm -f "${csv}.new"; return 0; }
  mv "${csv}.new" "${csv}"
}

# Mean(dt_ref/dt) over bins overlapping [sim_lo, sim_hi). Returns 1.0 if no data.
ayil_sim_dt_segment_cost_factor() {
  local date="$1"
  local sim_lo="${2:-0}"
  local sim_hi="${3:-${AYIL_DAY_RUNTIME_SEC:-10800}}"
  local csv ref
  if [[ "${AYIL_SIM_DT_USE}" != "1" ]]; then
    echo 1
    return 0
  fi
  csv="$(ayil_sim_dt_csv "${date}")"
  ref="${AYIL_SIM_DT_REF_SEC}"
  [[ -f "${csv}" ]] || { echo 1; return 0; }
  awk -v lo="${sim_lo}" -v hi="${sim_hi}" -v ref="${ref}" -v bin="${AYIL_SIM_DT_BIN_SEC}" '
    BEGIN { if (hi <= lo || ref <= 0) { print 1; exit } }
    /^#/ || /^sim_bin/ { next }
    {
      split($0, a, ",")
      b = a[1] + 0
      dt = a[2] + 0
      if (dt <= 0) next
      seg_lo = b
      seg_hi = b + bin
      if (seg_hi <= lo || seg_lo >= hi) next
      w_lo = (seg_lo < lo) ? lo : seg_lo
      w_hi = (seg_hi > hi) ? hi : seg_hi
      w = w_hi - w_lo
      if (w <= 0) next
      cost += w * (ref / dt)
      weight += w
    }
    END {
      if (weight > 0) printf "%.4f", cost / weight
      else print 1
    }
  ' "${csv}"
}

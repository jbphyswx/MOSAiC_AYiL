# shellcheck shell=bash
# Per-AYIL-date DALES timestep vs simulation time (binned tables for Slurm wall scaling).
#
# Canonical store (versioned in git): ${MOSAiC_AYIL_ROOT}/sim_dt/YYYYMMDD.csv
# See sim_dt/README.md for bootstrap → corpus_complete → retire generation.
#
# Wall parallel term: time-mean of dt_ref/dt over bins in the chunk.
# dt_s = effective timestep per bin: sim_seconds / step_units, with step_units = sum(delta_sim/dt)
# over diagnostic intervals (printed dt is mean rdt since previous line; modchecksim.f90).
# Pessimistic f_dt only when sim_dt/DATE.csv is missing or sparse for that chunk window.
# R_ref in slurm_defaults assumes dt ≈ dt_ref; f_dt adjusts per date and sim-time window.

export AYIL_SIM_DT_BIN_SEC="${AYIL_SIM_DT_BIN_SEC:-60}"
export AYIL_SIM_DT_REF_SEC="${AYIL_SIM_DT_REF_SEC:-2.0}"
# Pessimistic cap when sim_dt/DATE.csv is missing or does not cover the chunk window.
export AYIL_SIM_DT_PESSIMISTIC_MIN_DT_SEC="${AYIL_SIM_DT_PESSIMISTIC_MIN_DT_SEC:-0.6}"
export AYIL_SIM_DT_MIN_COVERAGE_FRAC="${AYIL_SIM_DT_MIN_COVERAGE_FRAC:-0.8}"
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
      if (sim >= 0 && dt > 0) {
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
    '
    function bin_of(sim) { return int(sim / bin) * bin }

    # Interval (lo, hi] used mean dt from the diagnostic line ending at hi.
    function add_interval(lo, hi, dt,    b, seg_lo, seg_hi, w) {
      if (hi <= lo || dt <= 0) return
      for (b = bin_of(lo); b <= bin_of(hi - 1e-9); b += bin) {
        seg_lo = (lo > b) ? lo : b
        seg_hi = (hi < b + bin) ? hi : b + bin
        w = seg_hi - seg_lo
        if (w <= 0) continue
        step_units[b] += w / dt
        sim_cover[b] += w
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
      if (sim < 0 || dt <= 0) next
      if (have_prev && sim > prev_sim) {
        add_interval(prev_sim, sim, dt)
      }
      b = bin_of(sim)
      n_lines[b]++
      last_dt[b] = dt
      last_utc[b] = utc
      prev_sim = sim
      have_prev = 1
    }

    END {
      printf "# ayil_sim_dt version=3\n"
      printf "# date=%s bin_sec=%d dt_ref_sec=%s host=%s nproc=%s updated_utc=%s\n", \
        date, bin, ref, host, nproc, utc
      printf "# dt_s = sim_cover/step_units per bin (step_units=sum delta_sim/dt over diagnostic intervals)\n"
      printf "sim_bin_s,dt_s,n_lines,last_utc\n"
      nb = 0
      for (b in step_units) seen[b] = 1
      for (b in n_lines) seen[b] = 1
      for (b in seen) {
        nb++
        bins[nb] = b + 0
      }
      for (i = 2; i <= nb; i++) {
        key = bins[i]
        j = i - 1
        while (j >= 1 && bins[j] > key) {
          bins[j + 1] = bins[j]
          j--
        }
        bins[j + 1] = key
      }
      for (i = 1; i <= nb; i++) {
        b = bins[i]
        if (step_units[b] > 0) {
          dt_eff = sim_cover[b] / step_units[b]
        } else if (b in last_dt) {
          dt_eff = last_dt[b]
        } else {
          continue
        }
        printf "%d,%.9f,%d,%s\n", b, dt_eff, n_lines[b], last_utc[b]
      }
    }
  ' "${log}" > "${csv}.new"

  [[ -s "${csv}.new" ]] || { rm -f "${csv}.new"; return 0; }
  # -f: required when login shells alias mv -i (otherwise chunk-2+ merge can prompt/hang).
  command mv -f "${csv}.new" "${csv}"
}

# f_dt = time-mean(dt_ref/dt) over bins in chunk. Pessimistic only if table missing or sparse.
ayil_sim_dt_pessimistic_cost_factor() {
  local ref="${AYIL_SIM_DT_REF_SEC}"
  local mindt="${AYIL_SIM_DT_PESSIMISTIC_MIN_DT_SEC}"
  awk -v ref="${ref}" -v mindt="${mindt}" \
    'BEGIN { if (ref <= 0 || mindt <= 0) print 1; else printf "%.4f", ref / mindt }'
}

# Mean(dt_ref/dt) over bins in [sim_lo, sim_hi); unknown/sparse → pessimistic factor.
ayil_sim_dt_segment_cost_factor() {
  local date="$1"
  local sim_lo="${2:-0}"
  local sim_hi="${3:-${AYIL_DAY_RUNTIME_SEC:-10800}}"
  local csv ref pess cov_frac
  if [[ "${AYIL_SIM_DT_USE}" != "1" ]]; then
    echo 1
    return 0
  fi
  pess="$(ayil_sim_dt_pessimistic_cost_factor)"
  csv="$(ayil_sim_dt_csv "${date}")"
  ref="${AYIL_SIM_DT_REF_SEC}"
  cov_frac="${AYIL_SIM_DT_MIN_COVERAGE_FRAC}"
  [[ -f "${csv}" ]] || {
    echo "${pess}"
    return 0
  }
  awk -v lo="${sim_lo}" -v hi="${sim_hi}" -v ref="${ref}" -v bin="${AYIL_SIM_DT_BIN_SEC}" \
    -v pess="${pess}" -v cov="${cov_frac}" \
    'BEGIN {
      if (hi <= lo || ref <= 0) { print pess; exit }
      seg_len = hi - lo
    }
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
      if (weight <= 0) {
        print pess
        exit
      }
      f = cost / weight
      if (weight < cov * seg_len && f < pess) {
        printf "%.4f", pess
      } else {
        printf "%.4f", f
      }
    }
  ' "${csv}"
}

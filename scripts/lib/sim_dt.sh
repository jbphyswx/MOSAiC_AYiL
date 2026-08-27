# shellcheck shell=bash
# Per-AYiL-date DALES timestep vs simulation time (binned tables for Slurm wall scaling).
#
# Canonical store (versioned in git): ${MOSAiC_AYiL_ROOT}/sim_dt/YYYYMMDD.csv
# See sim_dt/README.md for bootstrap → corpus_complete → retire generation.
#
# Wall parallel term: time-mean of dt_ref/dt over bins in the chunk.
# dt_s = effective timestep per bin: sim_seconds / step_units, with step_units = sum(delta_sim/dt)
# over diagnostic intervals (printed dt is mean rdt since previous line; modchecksim.f90).
# Pessimistic f_dt only when sim_dt/DATE.csv is missing or sparse for that chunk window.
# R_ref in slurm_defaults assumes dt ≈ dt_ref; f_dt adjusts per date and sim-time window.

export AYiL_SIM_DT_BIN_SEC="${AYiL_SIM_DT_BIN_SEC:-60}"
export AYiL_SIM_DT_REF_SEC="${AYiL_SIM_DT_REF_SEC:-2.0}"
# Pessimistic cap when sim_dt/DATE.csv is missing or does not cover the chunk window.
export AYiL_SIM_DT_PESSIMISTIC_MIN_DT_SEC="${AYiL_SIM_DT_PESSIMISTIC_MIN_DT_SEC:-0.6}"
export AYiL_SIM_DT_MIN_COVERAGE_FRAC="${AYiL_SIM_DT_MIN_COVERAGE_FRAC:-0.8}"
# Walltime: off by default — R_ref must be calibrated with estimate_wall_ref.sh first;
# enabling f_dt without matching AYiL_SIM_DT_REF_SEC to that run double-counts (see slurm_defaults.sh).
export AYiL_SIM_DT_USE="${AYiL_SIM_DT_USE:-0}"
# 1 while bootstrap may write sim_dt/*.csv; set 0 after sim_dt/.corpus_complete
export AYiL_SIM_DT_RECORD="${AYiL_SIM_DT_RECORD:-1}"
# 0 = keep existing bins unless log adds lines for that bin; 1 = recompute every bin the log covers
export AYiL_SIM_DT_RECOMPUTE="${AYiL_SIM_DT_RECOMPUTE:-0}"

ayil_sim_dt_root() {
  echo "${AYiL_SIM_DT_DIR:-${MOSAiC_AYiL_ROOT}/sim_dt}"
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
  if [[ "${AYiL_SIM_DT_RECORD}" != "1" ]]; then
    return 1
  fi
  if ayil_sim_dt_corpus_complete; then
    return 1
  fi
  return 0
}

# Stats from dales.log (diagnostic lines). Prints: diag_lines=N sim_log=LO-HIs
ayil_sim_dt_log_stats() {
  local log="$1"
  [[ -f "${log}" ]] || return 1
  awk '
    /Time of Simulation:/ && /[[:space:]]dt:/ {
      line = $0
      pos = index(line, "Time of Simulation:")
      rest = substr(line, pos + 19)
      if (match(rest, /[0-9]+\.?[0-9]*/)) {
        sim = substr(rest, RSTART, RLENGTH) + 0
      } else next
      n++
      if (n == 1 || sim < smin) smin = sim
      if (n == 1 || sim > smax) smax = sim
    }
    END {
      if (n == 0) exit 1
      printf "diag_lines=%d sim_log=%.2f-%.2fs", n, smin, smax
    }
  ' "${log}"
}

# Stats from sim_dt CSV. Prints: v3 bins=N sim_table=LO-HIs dt_eff=... partial|full_day
ayil_sim_dt_csv_stats() {
  local csv="$1"
  local bin_sec="${AYiL_SIM_DT_BIN_SEC}"
  local day_sec="${AYiL_DAY_RUNTIME_SEC:-10800}"
  [[ -f "${csv}" ]] || return 1
  awk -v bin="${bin_sec}" -v day="${day_sec}" '
    BEGIN { FS = "," }
    /^# ayil_sim_dt version=/ {
      ver = $0
      sub(/^# ayil_sim_dt version=/, "", ver)
      next
    }
    /^#/ { next }
    /^sim_bin/ { next }
    {
      b = $1 + 0
      dt = $2 + 0
      if (dt <= 0) next
      nb++
      if (nb == 1 || b < bmin) bmin = b
      if (nb == 1 || b > bmax) bmax = b
      if (nb == 1 || dt < dtmin) dtmin = dt
      if (nb == 1 || dt > dtmax) dtmax = dt
    }
    END {
      if (nb == 0) exit 1
      hi = bmax + bin
      status = (hi >= day - 1) ? "full_day" : "partial"
      printf "v%s bins=%d sim_table=%d-%ds dt_eff=%.3f-%.3fs %s", \
        ver, nb, bmin, hi, dtmin, dtmax, status
    }
  ' "${csv}"
}

# Compare prior vs new CSV one-liners (ingest logging).
ayil_sim_dt_stats_delta() {
  local old="$1"
  local new="$2"
  awk -v old="${old}" -v new="${new}" '
    function hi_span(s,   t, x) {
      if (!match(s, /sim_table=[0-9]+-[0-9]+/)) return -1
      t = substr(s, RSTART, RLENGTH)
      sub(/^sim_table=/, "", t)
      sub(/s$/, "", t)
      split(t, x, "-")
      return x[2] + 0
    }
  function lo_span(s,   t, x) {
      if (!match(s, /sim_table=[0-9]+-[0-9]+/)) return -1
      t = substr(s, RSTART, RLENGTH)
      sub(/^sim_table=/, "", t)
      sub(/s$/, "", t)
      split(t, x, "-")
      return x[1] + 0
    }
    BEGIN {
      olo = lo_span(old); ohi = hi_span(old)
      nlo = lo_span(new); nhi = hi_span(new)
      if (olo < 0 || nlo < 0) exit 0
      if (olo == nlo && ohi == nhi) {
        print "    delta: same sim_table span (CSV rebuilt from full dales.log; dt values may differ)"
      } else {
        printf "    delta: sim_table %d-%ds -> %d-%ds\n", olo, ohi, nlo, nhi
      }
    }
  '
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

# Compare data rows only (ignore header timestamps). Exit 0 if equal.
ayil_sim_dt_csv_body_equal() {
  local a="$1"
  local b="$2"
  diff -q <(awk '/^sim_bin_s,/{p=1} p' "${a}") <(awk '/^sim_bin_s,/{p=1} p' "${b}") >/dev/null 2>&1
}

# Merge log into binned CSV (bootstrap). No-op when recording is disabled or corpus is frozen.
ayil_sim_dt_merge_log() {
  local date="$1"
  local log="$2"
  local nproc="${3:-}"
  local bin_sec="${AYiL_SIM_DT_BIN_SEC}"
  local root csv
  if ! ayil_sim_dt_may_record && [[ "${AYiL_SIM_DT_FORCE_RECORD:-0}" != "1" ]]; then
    return 0
  fi
  root="$(ayil_sim_dt_root)"
  csv="$(ayil_sim_dt_csv "${date}")"
  mkdir -p "${root}"
  [[ -f "${log}" ]] || return 0

  awk -v bin="${bin_sec}" -v date="${date}" -v nproc="${nproc}" \
    -v ref="${AYiL_SIM_DT_REF_SEC}" \
    -v recompute_all="${AYiL_SIM_DT_RECOMPUTE:-0}" \
    -v utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -v host="$(hostname -s 2>/dev/null || hostname)" \
    -v existing="${csv}" \
    '
    function bin_of(sim) { return int(sim / bin) * bin }

    # Recompute from log only for new bins, denser log coverage, or explicit recompute_all.
    function should_recompute_from_log(b) {
      if (step_units[b] <= 0) return 0
      if (!(b in saved_dt)) return 1
      if (recompute_all + 0 == 1) return 1
      if ((b in n_lines) && n_lines[b] > saved_nlines[b]) return 1
      return 0
    }

    BEGIN {
      FS = ","
      saved_min_bin = -1
      saved_max_bin = -1
      if (existing != "" && (getline < existing) > 0) {
        while ((getline < existing) > 0) {
          if ($0 ~ /^#/ || $0 ~ /^sim_bin/) continue
          b = $1 + 0
          if ($2 + 0 <= 0) continue
          saved_dt[b] = $2 + 0
          saved_nlines[b] = ($3 + 0)
          saved_utc[b] = $4
          if (saved_min_bin < 0 || b < saved_min_bin) saved_min_bin = b
          if (b > saved_max_bin) saved_max_bin = b
        }
        close(existing)
      }
    }

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
      if (!have_log) {
        log_smin = sim
        log_smax = sim
        have_log = 1
      } else {
        if (sim < log_smin) log_smin = sim
        if (sim > log_smax) log_smax = sim
      }
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
      if (have_log && saved_max_bin >= 0) {
        if (log_smin > saved_min_bin + 0.001) {
          printf "WARN ayil_sim_dt %s: dales.log starts at sim %.2fs (table had from %ds); " \
            "keeping earlier bins from prior sim_dt/CSV\n", \
            date, log_smin, saved_min_bin > "/dev/stderr"
        }
        if (log_smax < saved_max_bin + bin - 1) {
          printf "WARN ayil_sim_dt %s: dales.log ends at sim %.2fs (table had to %ds); " \
            "keeping later bins from prior sim_dt/CSV\n", \
            date, log_smax, saved_max_bin + bin > "/dev/stderr"
        }
      }
      printf "# ayil_sim_dt version=3\n"
      printf "# date=%s bin_sec=%d dt_ref_sec=%s host=%s nproc=%s updated_utc=%s\n", \
        date, bin, ref, host, nproc, utc
      printf "# dt_s = sim_cover/step_units per bin (step_units=sum delta_sim/dt over diagnostic intervals)\n"
      printf "sim_bin_s,dt_s,n_lines,last_utc\n"
      nb = 0
      for (b in step_units) seen[b] = 1
      for (b in n_lines) seen[b] = 1
      for (b in saved_dt) seen[b] = 1
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
        out_nlines = 0
        out_utc = utc
        if (should_recompute_from_log(b)) {
          dt_eff = sim_cover[b] / step_units[b]
          out_nlines = n_lines[b] + 0
          if (b in last_utc) out_utc = last_utc[b]
          if (b in saved_dt) n_recomputed++
          else n_added++
        } else if (b in saved_dt) {
          dt_eff = saved_dt[b]
          out_nlines = saved_nlines[b]
          out_utc = (b in saved_utc) ? saved_utc[b] : utc
          n_preserved++
        } else if (b in last_dt) {
          dt_eff = last_dt[b]
          out_nlines = n_lines[b]
          out_utc = last_utc[b]
          n_added++
        } else {
          continue
        }
        printf "%d,%.9f,%d,%s\n", b, dt_eff, out_nlines, out_utc
      }
      if (n_preserved + n_recomputed + n_added > 0) {
        printf "ayil_sim_dt merge %s: preserved=%d recomputed=%d added=%d recompute_all=%s\n", \
          date, n_preserved, n_recomputed, n_added, recompute_all > "/dev/stderr"
      }
    }
  ' "${log}" > "${csv}.new"

  [[ -s "${csv}.new" ]] || { rm -f "${csv}.new"; return 0; }
  if [[ -f "${csv}" ]] && ayil_sim_dt_csv_body_equal "${csv}" "${csv}.new"; then
    rm -f "${csv}.new"
    return 0
  fi
  # -f: required when login shells alias mv -i (otherwise chunk-2+ merge can prompt/hang).
  command mv -f "${csv}.new" "${csv}"
}

# f_dt = time-mean(dt_ref/dt) over bins in chunk. Pessimistic only if table missing or sparse.
ayil_sim_dt_pessimistic_cost_factor() {
  local ref="${AYiL_SIM_DT_REF_SEC}"
  local mindt="${AYiL_SIM_DT_PESSIMISTIC_MIN_DT_SEC}"
  awk -v ref="${ref}" -v mindt="${mindt}" \
    'BEGIN { if (ref <= 0 || mindt <= 0) print 1; else printf "%.4f", ref / mindt }'
}

# Mean(dt_ref/dt) over bins in [sim_lo, sim_hi); unknown/sparse → pessimistic factor.
ayil_sim_dt_segment_cost_factor() {
  local date="$1"
  local sim_lo="${2:-0}"
  local sim_hi="${3:-${AYiL_DAY_RUNTIME_SEC:-10800}}"
  local csv ref pess cov_frac
  if [[ "${AYiL_SIM_DT_USE}" != "1" ]]; then
    echo 1
    return 0
  fi
  pess="$(ayil_sim_dt_pessimistic_cost_factor)"
  csv="$(ayil_sim_dt_csv "${date}")"
  ref="${AYiL_SIM_DT_REF_SEC}"
  cov_frac="${AYiL_SIM_DT_MIN_COVERAGE_FRAC}"
  [[ -f "${csv}" ]] || {
    echo "${pess}"
    return 0
  }
  awk -v lo="${sim_lo}" -v hi="${sim_hi}" -v ref="${ref}" -v bin="${AYiL_SIM_DT_BIN_SEC}" \
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

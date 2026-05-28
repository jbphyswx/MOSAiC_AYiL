# DALES timestep vs simulation time (per AYIL date)

Binned **`sim_time` → `dt`** tables used to scale Slurm walltime (`f_dt ∝ dt_ref/dt`). One file per MOSAiC day in this directory:

`sim_dt/YYYYMMDD.csv`

These files are **part of the MOSAiC_AYIL tree** (like `ayil_config_input_results/` namoptions), not under gitignored `runs/`. The pipeline **never runs git** — it only reads or writes plain CSV files on disk. You version them like any other repo file when you choose.

Not vertical **atmospheric profiles** — this is the model **timestep** `dt` vs **simulation clock** for each case (AYIL date). Header fields `host`, `nproc` are optional provenance; wall scaling uses `dt` only.

## Format

```text
# ayil_sim_dt version=1
# date=20191206 bin_sec=60 dt_ref_sec=2.0 host=... nproc=32 updated_utc=...
sim_bin_s,dt_s,n_lines,last_utc
0,0.728000000,42,2026-05-19T...
60,0.728000000,38,...
```

- **`sim_bin_s`**: start of bin (seconds since cold start; default **60 s** via `AYIL_SIM_DT_BIN_SEC`).
- **`dt_s`**: **effective** timestep for that bin: `sim_cover / step_units`, where `step_units = Σ (Δsim / dt)` over diagnostic intervals. Each printed `dt:` is the mean `rdt` since the previous line (`modchecksim.f90`); interval `(sim_prev, sim]` uses the `dt` on the line at `sim`. Matches `sim_seconds / n_steps` when step size is piecewise constant.
- **`n_lines`**: count of diagnostic lines whose `Time of Simulation` falls in the bin.
- Rows are written **ascending by `sim_bin_s`** (simulation time); scripts may scan linearly without re-sorting.
- Header `version=3`: interval-based effective `dt_s`. Re-ingest older tables after upgrading.

## Lifecycle

| Phase | Pipeline behavior |
|-------|-------------------|
| **Bootstrap** (incomplete corpus) | `AYIL_SIM_DT_RECORD=1` (default): after each chunk, merge `dales.log` into `sim_dt/YYYYMMDD.csv` — **add** new sim bins; **keep** existing bins unless the log has more lines for that bin; **keep** bins outside the log's sim range. Set `AYIL_SIM_DT_RECOMPUTE=1` (or `ingest_sim_dt.sh --recompute`) to refresh all bins the log covers. Skip file write if data rows unchanged. **Git** holds the durable record. |
| **Frozen** (corpus complete) | Add `sim_dt/.corpus_complete` and set `AYIL_SIM_DT_RECORD=0`. Slurm/local runs **only read** existing CSVs for walltime; **no** runtime writes from `dales.log`. Remove `ayil_sim_dt_merge_log` from production scripts and drop `scripts/dev/ingest_sim_dt.sh` in the same change. |

Until a date’s table covers the full day (default **10800 s** sim), that date’s CSV may keep growing across chunk jobs. After freeze, the tables are a **fixed reproducibility record** in the repo.

### Corpus completion

Create `sim_dt/.corpus_complete` (one `YYYYMMDD` per line) when every production day has a complete table (~190 lines). While that file is absent, recording stays allowed unless `AYIL_SIM_DT_RECORD=0`.

## Overrides

| Variable | Default | Role |
|----------|---------|------|
| `AYIL_SIM_DT_DIR` | `$MOSAiC_AYIL_ROOT/sim_dt` | Directory for CSVs |
| `AYIL_SIM_DT_RECORD` | `1` | `0` = production does not write CSVs |
| `AYIL_SIM_DT_USE` | `0` | `1` = multiply wall by ⟨dt_ref/dt⟩ from CSV (only after R_ref/dt_ref co-calibrated) |
| `AYIL_SIM_DT_REF_SEC` | `2.0` | Pivot for `f_dt = dt_ref/dt` (not “the dt when R_ref was measured” unless you set it from `estimate_wall_ref.sh`) |
| `AYIL_SIM_DT_PESSIMISTIC_MIN_DT_SEC` | `0.6` | Only when **no** table or **sparse** chunk coverage: assume effective `dt` this small → `f_dt = dt_ref / this` |
| `AYIL_SIM_DT_MIN_COVERAGE_FRAC` | `0.8` | Fraction of chunk sim window bins must be covered else bump to pessimistic `f_dt` |
| `AYIL_SIM_DT_RECOMPUTE` | `0` | `1` = recompute every bin the log covers (ingest: `--recompute`). Default keeps existing bins unless log adds diagnostic lines for that bin. |

Dev ingest sets `AYIL_SIM_DT_FORCE_RECORD=1` so it can refresh files even after `.corpus_complete` (manual maintenance only).

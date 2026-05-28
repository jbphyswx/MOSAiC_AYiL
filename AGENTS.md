# MOSAiC_AYIL Agent Guide

Repo for regenerating **full 3D DALES fielddump** output from the MOSAiC “A Year in LES” Zenodo bundle ([JAMES 10.1029/2024MS004296](https://doi.org/10.1029/2024MS004296), [Zenodo 10.5281/zenodo.10491362](https://zenodo.org/records/10491362)). Zenodo ships domain-averaged profiles; volumetric `fielddump.*.*.001.nc` tiles must be reproduced by running DALES.

**DALES is a fork:** all Fortran deltas from upstream are in [dales_ayil/MOSAiC_AYIL_FORK.md](dales_ayil/MOSAiC_AYIL_FORK.md). Slurm/fielddump rules: [docs/fielddump_and_chunking.md](docs/fielddump_and_chunking.md). Rebuild `dales4` after changing `dales_ayil/src/`.

Human-oriented overview: [README.md](README.md). Script details: [scripts/README.md](scripts/README.md). Zarr post-processing: [python/README.md](python/README.md).

## Repository layout

| Path | Role |
|------|------|
| `scripts/` | **Canonical pipeline** — build, prepare, run, Slurm submit, tests entry |
| `scripts/lib/` | Shared bash (`run_status.sh`, `mpi_env.sh`, `slurm_defaults.sh`, `pending_dates.sh`) |
| `scripts/slurm/run_day.slurm` | Slurm job body (one day or one array task) |
| `dales_ayil/` | AYIL DALES Fortran source; `build/src/dales4` after compile |
| `ayil_config_input_results/YYYYMMDD/` | **`namoptions` tracked in git** (edited pipeline settings). Large files (`scm_in.*.nc`, `prof.inp.*`, `*.001`, …) from [Zenodo 10.5281/zenodo.10491362](https://zenodo.org/records/10491362) on first `prepare_case`; install uses `rsync --ignore-existing` so Zenodo does not clobber existing/tracked files. Cache: `.cache/zenodo/`. |
| `runs/YYYYMMDD/` | Run working dirs (gitignored); outputs + status marker files |
| `sim_dt/` | Versioned **timestep vs sim time** CSVs per AYIL date (walltime); see `sim_dt/README.md` |
| `python/ayil/` | Merge fielddump tiles → Zarr (`convert`, `fielddump`, `zarr_store`) |
| `test/` | Bash unit/integration tests (`./test/run_tests.sh`) |

## Agent rules (read first)

- **Use pipeline scripts**, not ad-hoc one-off commands, for build/run/submit/convert unless the user explicitly asks otherwise.
- **Do not use git** to restore or overwrite tracked files (`git checkout`, `git restore`, etc.) unless the user names the exact command and paths.
- **Do not add** “legacy”, “back-compat”, or duplicate wrappers for code that has no prior users in this repo. Remove superseded paths in the same change.
- **Do not weaken tests** or relax tolerances without explicit user approval.
- **Do not claim** simulations or tests passed without running them when the change touches that path.
- **Do not convert to Zarr** while a run is in progress — partial `fielddump` NetCDF files cause HDF read errors.
- **Do not pip-install** Python dependencies; use the `MOSAiC_AYIL` conda env from `python/environment.yml` only.
- **Predetermined Zarr chunks** live in `python/ayil/zarr_store.py` as constants (`FIELDDUMP_CHUNKS_*`). Do not add runtime chunk-size heuristics under the same names.

## Conda environment (Python / Zarr)

- **Env name:** `MOSAiC_AYIL` (override with `AYIL_CONDA_ENV` only if documented for the user).
- **Definition:** [python/environment.yml](python/environment.yml) — **conda-forge only** (`nodefaults` channel). The `pip` entry is the conda meta-package, not permission to `pip install` packages.
- **Create/update:**
  ```bash
  conda env update -n MOSAiC_AYIL -f python/environment.yml
  ```
- **Run tools:**
  ```bash
  cd python && conda run -n MOSAiC_AYIL python -m ayil.convert runs/20200720
  # or: ./scripts/convert_to_zarr.sh runs/20200720  (conda wrapper only)
  cd python && conda run -n MOSAiC_AYIL pytest -v
  ```
- **Zarr conversion logic lives in Python** (`ayil.convert`, `ayil.paths`, `ayil.fielddump`). Do not add path-resolution or progress logic to bash.
- **Zarr format:** writes **Zarr v3** via `write_dataset_zarr(..., zarr_format=3)` (default); Blosc via `zarr.codecs.BloscCodec`; consolidated metadata on by default (`consolidated=True`). Merged winds (`u`, `v`, `w`) and physical microphysics names — no `u_tile_*` or raw `sv00N` in output.

## Site configuration

```bash
cp scripts/env.example scripts/env.local   # gitignored
```

`scripts/config.sh` sources `env.local` automatically. Use for modules, `NETCDF_INCLUDE`, `DALES_NPROC`, `OPENMPI_PREFIX`, and optional `AYIL_SLURM_*` overrides.

## DALES build and run

| Step | Command |
|------|---------|
| First-time verify | `./scripts/reproduce.sh` |
| Build | `./scripts/build_dales.sh` → `dales_ayil/build/src/dales4` |
| One day (login/interactive) | `./scripts/run_local.sh 20200720` |
| Pending days (local, serial) | `./scripts/run_local.sh --pending` |
| Status table | `./scripts/list_cases.sh` |
| MPI diagnosis | `./scripts/diagnose_mpi.sh` |

**MPI ranks** must be a **factor of 320** (`itot=jtot=320`). Valid examples: 40, 64, 80. Not every host slot count works (e.g. 48 slots ≠ valid grid decomposition). `config.sh` auto-picks a valid rank count unless `DALES_NPROC` is set in `env.local`.

**Local runs:** one simulation at a time (`run_local.sh`); logs in `runs/YYYYMMDD/logs/` (`dales.log`, `progress.log`).

## Run completion and overwrite policy

Status files under `runs/YYYYMMDD/` (see `scripts/lib/run_status.sh`):

| File | Meaning |
|------|---------|
| `.ayil_complete` | Finished successfully — **skipped** by default |
| `.ayil_running` | In progress or stale lock — **skipped** by default |
| `.ayil_interrupted` / `.ayil_failed` | Eligible to retry |

- `run_local.sh` and `slurm_submit.sh` **filter before run/submit**; they do not overwrite complete days unless `--force`. Incomplete/crashed days **auto-clean outputs when chunk 0 starts** (no `--force` needed). `--force` re-runs complete days; wipe happens on **chunk 0 only** (not chunk 1..5).
- Slurm: `./scripts/slurm_submit.sh --pending --dry-run` previews RUN vs SKIP without calling `sbatch`.

## Slurm (HPC)

Entry point: **`./scripts/slurm_submit.sh`** (not manual loops of `sbatch` unless debugging).

```bash
./scripts/build_dales.sh                              # login node, once
./scripts/slurm_submit.sh --pending --dry-run
./scripts/slurm_submit.sh --pending                 # 6 chained jobs/day (default chunked mode)
```

- Job script: `scripts/slurm/run_day.slurm` → `scripts/run_slurm_day.sh`.
- **Default Slurm mode:** chunked — jobs chained with `--dependency=afterok` (`AYIL_CHUNK_SIM_SEC` × chunks = `AYIL_DAY_RUNTIME_SEC`, default **10800 s**); restart handoff via `initdlatest*`. Use `--no-chunked` for one job/day only if walltime covers the full day.
- Per-day logs: `runs/YYYYMMDD/logs/{slurm.out,progress.log,dales.log,convert.log}`. Chunk progress: `.ayil_chunk_N_complete`; day done: `.ayil_complete`.
- **Walltime** (`scripts/lib/slurm_defaults.sh`): `T_wall = T_fixed + T_sim × (R_ref × N_ref / N_mpi) × f_dt` (+ 15% headroom). `f_dt` from repo `sim_dt/YYYYMMDD.csv` (plain files; pipeline never runs git). Bootstrap writes CSVs (`AYIL_SIM_DT_RECORD=1`); after `sim_dt/.corpus_complete` set `AYIL_SIM_DT_RECORD=0` and remove dev ingest / merge hooks (see `sim_dt/README.md`).
- **Memory:** `--mem = ntasks × 4 GiB + 16 GiB` (override `AYIL_SLURM_MEM` in `env.local`).
- Many **days** can run in parallel (each day = its own 6-job chain); there is no global “one job at a time” cap unless the partition/QOS limits you.
- Do not invent cluster-specific partition names in code; use optional `AYIL_SLURM_PARTITION` / `AYIL_SLURM_ACCOUNT`.

## Simulation config (important facts)

From Zenodo `namoptions` (all ~190 days use the same pattern):

| Setting | Value | Notes |
|---------|-------|--------|
| `runtime` | `10800` s | **3 h** per day (JAMES paper); `prepare_case.sh` patches staged `namoptions`. Zenodo zip still has `7200`. |
| `trestart` | `-1` local; `0`/`−1` chunked | Local/`--no-chunked`: no restarts. Slurm chunks: `trestart=0` writes `initdlatest*` at segment end; last chunk `−1`. |
| `namfielddump` `dtav` | `1800` s | 3D snapshots every **30 min** → **6** times per 3 h run |
| Chunked Slurm + fielddump | See [docs/fielddump_and_chunking.md](docs/fielddump_and_chunking.md) | Default `AYIL_CHUNK_SIM_SEC=1800` matches `dtav`. Shorter chunks need [modfielddump `tnext` patch](dales_ayil/MOSAiC_AYIL_FORK.md). Never claim fielddump works from mock chunk tests alone. |
| `namfielddump` `khigh` | `200` | Vertical levels in fielddump |
| Grid | `320×320×286` (`kmax`) | MPI tiles: `fielddump.III.JJJ.001.nc` |

**Paper vs Zenodo zip:** JAMES **3 h** is the pipeline default (`10800` s). Git `ayil_config_input_results/*/namoptions` may still show `7200` until refreshed; `prepare_case.sh` always sets `10800` in the run dir. `tb_taunudge = 10800` is nudging timescale, not run length.

Other outputs are **more frequent** than fielddump (e.g. `profiles.001.nc` via `namgenstat`: `dtav=60`, `timeav=300`).

## Zarr post-processing

After `.ayil_complete` exists for a day:

```bash
./scripts/convert_to_zarr.sh runs/20200720
```

- Merges MPI tiles to `runs/YYYYMMDD/data.zarr/`.
- Chunk preset **B** (fixed): `(time, z, y, x) = (6, 100, 80, 80)` — one time chunk = full 3 h run; x/y/z tile evenly into 320/320/200.
- CLI: `python -m ayil.convert` — `--overwrite`, `--no-staggered`; no runtime `--chunk-mb`.

## Tests

```bash
./test/run_tests.sh
cd python && conda run -n MOSAiC_AYIL pytest -v
./test/run_tests.sh                 # always mock_dales4 (CI / laptop / login safe)
# Real LES only via scripts/manual/ on a compute node — never part of run_tests.sh
```

Report failures honestly. After substantive script/python changes, run the relevant suite before claiming done.

## Common pitfalls

| Issue | Cause / fix |
|-------|-------------|
| `mpirun: command not found` | Use `./scripts/run_local.sh` or `source ./scripts/setup_env.sh`; don’t rely on bare `(base)` conda without MPI on PATH |
| “not enough slots” (Open MPI) | Lower `DALES_NPROC` to a valid factor ≤ slot limit (`diagnose_mpi.sh`) |
| Zarr convert HDF error | Run still writing `fielddump`; wait for completion |
| `xtime` / scm_in time decode | `scm_in.nc` may need `decode_times=False` for inspection |
| Slurm `8` concurrent tasks | **Removed** as default; was an arbitrary throttle, not a Caltech limit |
| Run dir ~80 GiB but Zarr ~3 GiB | Old runs with Zenodo `trestart=1800` wrote `initd*`/`inits*`; delete after `.ayil_complete` or re-`prepare_case` + `--force`. New runs omit them. |
| `curl: (60) SSL certificate problem` on fetch | Conda `base` curl often has no CA store on HPC. `export CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt` or `conda deactivate` before `fetch_zenodo_inputs.sh`. Script prefers `/usr/bin/curl`. |

## Self-correction

If the user corrects workflow, env, or cluster assumptions, update this file (or README / `scripts/README.md`) in the same session so later agents inherit it. Do not label new mistakes as “legacy.”

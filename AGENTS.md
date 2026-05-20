# MOSAiC_AYIL Agent Guide

Repo for regenerating **full 3D DALES fielddump** output from the MOSAiC “A Year in LES” Zenodo bundle ([JAMES 10.1029/2024MS004296](https://doi.org/10.1029/2024MS004296), [Zenodo 10.5281/zenodo.10491362](https://zenodo.org/records/10491362)). Zenodo ships domain-averaged profiles; volumetric `fielddump.*.*.001.nc` tiles must be reproduced by running DALES.

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

- `run_local.sh` and `slurm_submit.sh` **filter before run/submit**; they do not overwrite complete days unless `--force` / `AYIL_FORCE=1` (cleans outputs in the job).
- Slurm: `./scripts/slurm_submit.sh --pending --dry-run` previews RUN vs SKIP without calling `sbatch`.

## Slurm (HPC)

Entry point: **`./scripts/slurm_submit.sh`** (not manual loops of `sbatch` unless debugging).

```bash
./scripts/build_dales.sh                              # login node, once
./scripts/slurm_submit.sh --pending --dry-run
./scripts/slurm_submit.sh --pending                 # one job array: --array=0-N
```

- Job script: `scripts/slurm/run_day.slurm` → `scripts/run_slurm_day.sh`.
- Per-day logs: `runs/YYYYMMDD/logs/{slurm.out,dales.log,convert.log}` (Slurm stderr merged into `slurm.out`). Array cluster copy: `runs/slurm_logs/`. Date list: `runs/.slurm_pending_dates`.
- **Per-job defaults** in `scripts/lib/slurm_defaults.sh` are documented as aligned with [Caltech Resnick HPC](https://www.hpc.caltech.edu/resources) **resource shape** (1 node, 40 tasks, 128G, 8h) — override via `env.local` on other clusters.
- **No default array concurrency cap.** Slurm schedules array tasks as partition/QOS/limits allow. Set `AYIL_SLURM_ARRAY_MAX` only when an explicit `--array=0-N%M` throttle is desired.
- Do not invent cluster-specific partition names in code; use optional `AYIL_SLURM_PARTITION` / `AYIL_SLURM_ACCOUNT`.

## Simulation config (important facts)

From Zenodo `namoptions` (all ~190 days use the same pattern):

| Setting | Value | Notes |
|---------|-------|--------|
| `runtime` | `7200` s | **2 h** integration per day |
| `trestart` | `-1` | **No restart files** (`initd*`/`inits*`); Zenodo had `1800` (~77 GiB/day). Set by `prepare_case.sh` via `lib/namoptions_patch.sh`. DALES: `trestart < 0` disables writes. |
| `namfielddump` `dtav` | `1800` s | 3D snapshots every **30 min** → **4** times per run |
| `namfielddump` `khigh` | `200` | Vertical levels in fielddump |
| Grid | `320×320×286` (`kmax`) | MPI tiles: `fielddump.III.JJJ.001.nc` |

**Paper vs configs:** JAMES text says **3 h** simulations; Zenodo `namoptions` uniformly have **`runtime = 7200` (2 h)**. This repo reproduces the **archived configs**, not the paper paragraph. `tb_taunudge = 10800` is a nudging timescale, not run length. See README “Simulation length” section before changing runtime or Zarr time chunks.

Other outputs are **more frequent** than fielddump (e.g. `profiles.001.nc` via `namgenstat`: `dtav=60`, `timeav=300`).

## Zarr post-processing

After `.ayil_complete` exists for a day:

```bash
./scripts/convert_to_zarr.sh runs/20200720
```

- Merges MPI tiles to `runs/YYYYMMDD/data.zarr/`.
- Chunk preset **B** (fixed): `(time, z, y, x) = (4, 100, 80, 80)` — one time chunk = full 2 h run; x/y/z tile evenly into 320/320/200.
- CLI: `python -m ayil.convert` — `--overwrite`, `--no-staggered`; no runtime `--chunk-mb`.

## Tests

```bash
./test/run_tests.sh
cd python && conda run -n MOSAiC_AYIL pytest -v
./test/run_tests.sh --with-dales    # optional; needs built dales4
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

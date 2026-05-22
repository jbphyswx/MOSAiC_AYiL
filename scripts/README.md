# MOSAiC AYIL pipeline scripts

All build and run steps live here as version-controlled shell scripts. **Do not rely on ad-hoc terminal commands**—use these entry points so results are reproducible.

## First-time setup (from repo root)

```bash
# 1. Optional: site-specific modules and paths
cp scripts/env.example scripts/env.local
# edit scripts/env.local (modules, NETCDF_INCLUDE, DALES_NPROC)

# 2. Full verify + build + short smoke run (~2 min with 16 MPI tasks)
./scripts/reproduce.sh
```

`reproduce.sh` runs, in order:

| Step | Script | What it does |
|------|--------|----------------|
| 1 | `check_prerequisites.sh` | Checks `cmake`, `mpif90`, `mpirun`, `rsync`, NetCDF, repo layout |
| 2 | `bootstrap_build_tree.sh` | Ensures `CMakeLists.txt`, `findnetcdf`, `cases/standard/moduser.f90` exist |
| 3 | `build_dales.sh` | `cmake` + `make` → `dales_ayil/build/src/dales4` |
| 4 | `smoke_test.sh` | Stages `runs/smoke_20200720/`, runs 120 s, checks log for time steps |

## Script reference

| Script | Purpose |
|--------|---------|
| `config.sh` | Paths and defaults (sourced by others; loads `env.local`) |
| `env.example` | Template for `env.local` (gitignored) |
| `bootstrap_build_tree.sh` | Fix Zenodo-minimal tree before CMake |
| `build_dales.sh` | Compile `dales4` |
| `check_prerequisites.sh` | Pre-flight dependency check |
| `prepare_case.sh YYYYMMDD [RUN_DIR]` | Fetch Zenodo inputs if missing; copy + link `scm_in.nc`; `trestart = -1` |
| `fetch_zenodo_inputs.sh` | Optional prefetch of Zenodo zip; adds missing artifacts only (`rsync --ignore-existing`) |
| `run_case.sh YYYYMMDD [NPROC] [RUN_DIR]` | Full MPI simulation (single day) |
| **`run_local.sh`** | **Local workstation: progress logs, skip-complete, interrupts** |
| `diagnose_mpi.sh` | MPI paths, slot limits, recommended `DALES_NPROC` |
| `setup_env.sh` | `source` in interactive shell to match pipeline PATH |
| `list_cases.sh` | Table of complete / pending / failed days |
| `estimate_output_gb.sh [NPROC]` | Rough GB per completed day |
| `run_batch.sh prepare\|run ...` | Many dates (serial; prefer Slurm on HPC) |
| **`slurm_submit.sh`** | **Submit Slurm array or per-day jobs; skips complete days** |
| `run_slurm_day.sh YYYYMMDD` | One day inside a batch job (status markers) |
| `smoke_test.sh [DATE] [NPROC] [TIMEOUT]` | Short sanity run |
| `clean.sh build\|runs\|all` | Remove `dales_ayil/build` and/or `runs/` |
| `reproduce.sh` | Canonical chain: check → bootstrap → build → smoke |
| `slurm/run_day.slurm` | Slurm job body (single day or array task) |

## Local machine (no Slurm) — recommended

One simulation at a time on shared workstations (each case is heavy).

```bash
./scripts/estimate_output_gb.sh 64          # expected ~tens of GB per day
./scripts/list_cases.sh                     # what is done / pending
./scripts/run_local.sh --pending --limit 1  # next incomplete day
./scripts/run_local.sh 20200720 20200723    # specific dates (skips complete)
```

Features:

- Timestamped progress every 30 s: sim time / target runtime, disk usage, delta GB
- `runs/YYYYMMDD/.ayil_complete` — finished runs are never overwritten
- Ctrl+C → `.ayil_interrupted`; re-run same date to retry (or `--force` for clean restart)
- Logs: `runs/YYYYMMDD/logs/dales.log`, `progress.log`

MPI ranks must **divide 320** (not every host slot count is valid). Run `./scripts/diagnose_mpi.sh` on each machine; `config.sh` auto-picks the largest valid count unless `DALES_NPROC` is set in `env.local`.

Interactive shells without MPI on PATH: `source ./scripts/setup_env.sh`

## Tests

```bash
./test/run_tests.sh           # unit + integration (no DALES compile required)
./test/run_tests.sh --with-dales   # smoke + two-chunk warm-start if dales4 is built
```

### Chunked restart naming (Slurm only)

Zenodo `namoptions` use **cold start** (`lwarmstart = .false.`, `startfile = 'initd002h00mx000y000.001'`, `trestart = -1`). Chunked Slurm is **new orchestration**: after each segment DALES writes `initd000h05m{cmyid}.001` and copies to **`initdlatestm{cmyid}.001`** (`modstartup.f90`: `linkname(6:11)="latest"`, char 12 stays `m`). Warm chunks must use that pattern in `startfile` (chars 13–20 are replaced per rank), **not** a Zenodo string with `latest` swapped into the hour/min fields.

Offline checks: `test/unit/test_restart_naming.sh`, `test/integration/test_chunk_restart_handoff.sh`. With `dales4` built: `scripts/chunk_warmstart_smoke_test.sh`.

## Slurm (HPC batch)

Defaults in `lib/slurm_defaults.sh`: single node, **64** MPI tasks, **200G** RAM (`64×3 + 8` GiB headroom), 8h walltime. Override in `scripts/env.local`.

**Default submit mode is chunked:** each day → **6 jobs** of 1800 s sim (`--dependency=afterok`), so each job fits 8 h wall while the full day is 10800 s (3 h). Many days submit in parallel (one chain per day). Use `--no-chunked` for one job/day only if walltime allows the full 3 h run.

### First time on the cluster

```bash
cp scripts/env.example scripts/env.local
# Edit: module load gcc openmpi netcdf-fortran cmake  (see env.example)
./scripts/build_dales.sh
```

### Submit all pending days (recommended)

```bash
./scripts/list_cases.sh
./scripts/slurm_submit.sh --pending --dry-run    # lists RUN vs SKIP; no sbatch
./scripts/slurm_submit.sh --pending                # chunked chains (6 jobs/day)
```

Behavior:

| Situation | Without `--force` | With `--force` |
|-----------|-------------------|----------------|
| `runs/YYYYMMDD/.ayil_complete` | **Not submitted** | Submitted; outputs cleaned in job |
| `runs/YYYYMMDD/.ayil_running` | **Not submitted** | Submitted |
| failed / interrupted / missing | Submitted | Submitted |

The submit script filters **before** `sbatch`. Each chunk job runs `run_slurm_day.sh` with `AYIL_CHUNK_INDEX`; partial days resume from the first incomplete chunk.

```bash
./scripts/slurm_submit.sh --pending --limit 10           # first 10 eligible days
./scripts/slurm_submit.sh --pending --no-chunked         # one 3 h job per day (needs long walltime)
./scripts/slurm_submit.sh 20200720 20200721              # explicit dates
./scripts/slurm_submit.sh --status --pending             # table only
```

Monitor:

```bash
squeue -u "$USER"
tail -f runs/20200720/logs/progress.log   # sim time % every 30 s (Slurm + local)
tail -f runs/20200720/logs/dales.log      # DALES MPI output
tail -f runs/20200720/logs/slurm.out      # job wrapper (modules, START/DONE)
./scripts/list_cases.sh
```

Slurm copies `run_day.slurm` to `/var/spool/slurmd/...` on compute nodes. The job resolves the repo via **`MOSAiC_AYIL_ROOT`** (set by `slurm_submit.sh`), **`SLURM_SUBMIT_DIR`**, or `cd` to the checkout — not via `BASH_SOURCE` in the spool copy. Always submit from the repo (`./scripts/slurm_submit.sh`) or pass `MOSAiC_AYIL_ROOT` explicitly.

### Single day (manual `sbatch`)

```bash
sbatch --export=ALL,DATE=20200720,MOSAiC_AYIL_ROOT=$PWD scripts/slurm/run_day.slurm
# Or with explicit resources:
sbatch --ntasks=40 --time=08:00:00 --mem=128G \
  --export=ALL,DATE=20200720,MOSAiC_AYIL_ROOT=$PWD \
  scripts/slurm/run_day.slurm
```

### Slurm-related environment (`env.local`)

| Variable | Default | Role |
|----------|---------|------|
| `AYIL_SLURM_NTASKS` | `40` | MPI ranks (`#SBATCH --ntasks`) |
| `AYIL_SLURM_TIME` | `08:00:00` | Walltime |
| `AYIL_SLURM_MEM` | `200G` (64 ranks) | Total job RAM (`NTASKS×3 + 8` GiB if unset) |
| `AYIL_SLURM_ARRAY_MAX` | (unset) | Optional max concurrent array tasks (`--array=0-N%M`); unset = no `%` cap |
| `AYIL_SLURM_PARTITION` | (empty) | Optional partition |
| `AYIL_SLURM_BUILD` | `0` | Set `1` to compile in each job if binary missing |

**Logs** (all under `runs/YYYYMMDD/logs/` — see `lib/logging_paths.sh`):

| File | Written by |
|------|------------|
| `dales.log` | DALES MPI (`run_local.sh`, `run_slurm_day.sh`) |
| `progress.log` | `run_local.sh` / `run_slurm_day.sh` — sim time % every 30 s |
| `slurm.out` | Slurm job wrapper stdout + stderr (merged) |
| `convert.log` | `python -m ayil.convert` |
| `smoke.log` | `smoke_test.sh` |

Date list for arrays: `runs/.slurm_pending_dates`.

Outputs per day: `profiles.001.nc`, `fielddump.*.*.001.nc`, `.ayil_complete`, `data.zarr/`, …

## Paths (override in `env.local`)

| Variable | Default |
|----------|---------|
| `MOSAiC_AYIL_ROOT` | Parent of `scripts/` |
| `DALES_SRC` | `$MOSAiC_AYIL_ROOT/dales_ayil` |
| `DALES_BIN` | `$DALES_SRC/build/src/dales4` |
| `AYIL_INPUTS` | `$MOSAiC_AYIL_ROOT/ayil_config_input_results` |
| `AYIL_RUNS` | `$MOSAiC_AYIL_ROOT/runs` |
| `DALES_NPROC` | auto-detected (must divide 320) |
| `AYIL_SLURM_*` | see Slurm table above |

## Build tree files (committed under `dales_ayil/`)

Zenodo ships only `src/` and `config/`. This repo also commits:

- `CMakeLists.txt` — copy of `config/github_CMakeLists.txt`
- `findnetcdf` — NetCDF include helper for CMake
- `cases/standard/moduser.f90` — required by CMake case logic

`bootstrap_build_tree.sh` recreates any of these if missing, including `src/modversion.f90.in` (required by CMake; omitted from some Zenodo trees and previously gitignored via `*.in`).

## Clean rebuild

```bash
./scripts/clean.sh build
./scripts/build_dales.sh
```

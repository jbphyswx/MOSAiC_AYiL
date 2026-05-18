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
| `prepare_case.sh YYYYMMDD [RUN_DIR]` | Copy inputs + link `scm_in.nc` |
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

- Timestamped progress every 30 s: sim time / 7200 s, disk usage, delta GB
- `runs/YYYYMMDD/.ayil_complete` — finished runs are never overwritten
- Ctrl+C → `.ayil_interrupted`; re-run same date to retry (or `--force` for clean restart)
- Logs: `dales_YYYYMMDD.log`, `progress.log`

MPI ranks must **divide 320** (not every host slot count is valid). Run `./scripts/diagnose_mpi.sh` on each machine; `config.sh` auto-picks the largest valid count unless `DALES_NPROC` is set in `env.local`.

Interactive shells without MPI on PATH: `source ./scripts/setup_env.sh`

## Tests

```bash
./test/run_tests.sh           # unit + integration (no DALES compile required)
./test/run_tests.sh --with-dales   # optional smoke test if dales4 is built
```

## Slurm (HPC batch)

Defaults in `lib/slurm_defaults.sh` are aligned with the [Caltech Resnick HPC](https://www.hpc.caltech.edu/resources) for **per-job** resources (single node, 40 MPI tasks, 128G, 8h walltime). They are **environment variables**, not hardcoded cluster names — override in `scripts/env.local` on other systems.

By default there is **no** cap on how many array tasks run at once; Slurm queues and starts tasks according to partition, QOS, and your allocation. Set `AYIL_SLURM_ARRAY_MAX` only if you want an explicit throttle (e.g. `export AYIL_SLURM_ARRAY_MAX=8` → `--array=0-N%8`).

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
./scripts/slurm_submit.sh --pending                # one job array
```

Behavior:

| Situation | Without `--force` | With `--force` |
|-----------|-------------------|----------------|
| `runs/YYYYMMDD/.ayil_complete` | **Not submitted** | Submitted; outputs cleaned in job |
| `runs/YYYYMMDD/.ayil_running` | **Not submitted** | Submitted |
| failed / interrupted / missing | Submitted | Submitted |

The submit script filters **before** `sbatch`. Each array task runs `run_slurm_day.sh`, which skips again if the day completed between submit and start.

```bash
./scripts/slurm_submit.sh --pending --limit 10           # first 10 eligible days
./scripts/slurm_submit.sh --pending --separate           # one sbatch per day
./scripts/slurm_submit.sh 20200720 20200721              # explicit dates
./scripts/slurm_submit.sh --status --pending             # table only
```

Monitor:

```bash
squeue -u "$USER"
tail -f runs/slurm_logs/ayil_dales-<JOBID>_<TASK>.out
./scripts/list_cases.sh
```

### Single day (manual `sbatch`)

```bash
sbatch --export=ALL,DATE=20200720 scripts/slurm/run_day.slurm
# Or with explicit resources:
sbatch --ntasks=40 --time=08:00:00 --mem=128G \
  --export=ALL,DATE=20200720 \
  scripts/slurm/run_day.slurm
```

### Slurm-related environment (`env.local`)

| Variable | Default | Role |
|----------|---------|------|
| `AYIL_SLURM_NTASKS` | `40` | MPI ranks (`#SBATCH --ntasks`) |
| `AYIL_SLURM_TIME` | `08:00:00` | Walltime |
| `AYIL_SLURM_MEM` | `128G` | Memory per job |
| `AYIL_SLURM_ARRAY_MAX` | (unset) | Optional max concurrent array tasks (`--array=0-N%M`); unset = no `%` cap |
| `AYIL_SLURM_PARTITION` | (empty) | Optional partition |
| `AYIL_SLURM_BUILD` | `0` | Set `1` to compile in each job if binary missing |

Slurm stdout/stderr: `runs/slurm_logs/`. Date list for arrays: `runs/.slurm_pending_dates`.

Outputs per day: `runs/20200720/dales_20200720.log`, `profiles.001.nc`, `fielddump.*.*.001.nc`, `.ayil_complete`, …

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

`bootstrap_build_tree.sh` recreates any of these if missing.

## Clean rebuild

```bash
./scripts/clean.sh build
./scripts/build_dales.sh
```

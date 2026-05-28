# MOSAiC_AYIL

Regenerate full 3D/4D DALES output for [Schnierstein et al. 2024 (JAMES)](https://doi.org/10.1029/2024MS004296) / [Zenodo 10.5281/zenodo.10491362](https://zenodo.org/records/10491362).

Zenodo provides **profile-averaged** outputs; full horizontal fields require rerunning DALES with the archived inputs.

**Cursor / agents:** see [AGENTS.md](AGENTS.md) for pipeline entry points, conda env rules, Slurm, and known config facts.

## Simulation length and Slurm chunking

- **Default integration:** `runtime = 10800` s (**3 h**, JAMES paper). `prepare_case.sh` sets this in each run directory (`AYIL_DAY_RUNTIME_SEC`). Zenodo’s zip still ships `7200` s; git-tracked `namoptions` may lag until updated.
- **3D fielddump:** `dtav = 1800` → **6** snapshots per 3 h day. Zarr preset uses `FIELDDUMP_CHUNKS_TIME = 6`.
- **Local runs** (`run_local.sh`): one job per day, **`trestart = -1`** (no restart files).
- **Slurm (default):** `./scripts/slurm_submit.sh --pending` submits **6 chained jobs per day** (30 min sim each, `AYIL_CHUNK_SIM_SEC=1800`) so each job stays within typical **8 h wall** limits. Chunks warm-start from `initdlatest*`; timed restart files are deleted after each successful chunk; the last chunk does not write restarts. Many days can run in parallel (separate chains). Use `--no-chunked` only if your partition allows one job to finish the full 3 h simulation in walltime.
- **MPI ranks:** default **64** on Slurm (`AYIL_SLURM_NTASKS`); override in `scripts/env.local`.

### Fielddump + chunks (required reading)

**[`docs/fielddump_and_chunking.md`](docs/fielddump_and_chunking.md)** — why `profiles` can look fine while `fielddump` has `time=0`, and how chunk length relates to `dtav`.

**[`dales_ayil/MOSAiC_AYIL_FORK.md`](dales_ayil/MOSAiC_AYIL_FORK.md)** — **explicit list of Fortran changes** from upstream DALES (including `modfielddump.f90`). Rebuild with `./scripts/build_dales.sh` after pull.

**Do not** use `AYIL_CHUNK_SIM_SEC` &lt; **1800** unless you have rebuilt `dales4` from this repo’s `dales_ayil` (see fork doc). Values like **300** or **600** with stock `tnext = btime + dtav` produce **empty fielddump** while the LES still runs to completion.

## Reproduce everything (start here)

```bash
cd /path/to/MOSAiC_AYIL
./scripts/reproduce.sh
```

That single command checks dependencies, sets up the build tree, compiles `dales4`, and runs a short smoke test. **All steps are implemented in `scripts/`**—see **[scripts/README.md](scripts/README.md)** for the full script list and production workflow.

Optional site config:

```bash
cp scripts/env.example scripts/env.local   # edit modules, paths, DALES_NPROC
```

**Inputs on a fresh clone:** Git tracks **`ayil_config_input_results/*/namoptions`** (pipeline settings such as `trestart = -1`). Large Zenodo artifacts (NetCDF, `prof.inp.*`, `*.001`, …) are not in git. The first `prepare_case` / run downloads [Zenodo `ayil_config_input_results.zip`](https://zenodo.org/records/10491362/files/ayil_config_input_results.zip) (~870 MiB) and **adds only missing files** (`rsync --ignore-existing` — it does not overwrite tracked `namoptions`). Prefetch: `./scripts/fetch_zenodo_inputs.sh`.

## Repository layout

| Path | Role |
|------|------|
| `scripts/` | **Canonical pipeline** (build, prepare, run, smoke test, Slurm example) |
| `dales_ayil/` | AYIL DALES source + committed CMake bootstrap files |
| `ayil_config_input_results/YYYYMMDD/` | `namoptions` in git; Zenodo artifacts auto-downloaded on first run |
| `runs/` | Simulation working directories (created by scripts; gitignored) |
| `sim_dt/` | Versioned per-day timestep vs sim-time tables for Slurm wall estimates ([README](sim_dt/README.md)) |

## Run simulations locally (no Slurm)

```bash
./scripts/diagnose_mpi.sh          # MPI path + rank limit on this machine
./scripts/run_local.sh 20200720    # auto-uses recommended NPROC (40 on sampo)
```

Use the scripts (they locate `mpirun` via `PATH`, modules, or `OPENMPI_PREFIX`). For manual MPI: `source ./scripts/setup_env.sh`.

## Run on Slurm (HPC)

For batch systems such as the [Caltech Resnick HPC cluster](https://www.hpc.caltech.edu) ([resource summary](https://www.hpc.caltech.edu/resources)):

```bash
cp scripts/env.example scripts/env.local   # modules, optional AYIL_SLURM_* overrides
./scripts/build_dales.sh                   # once on the login node
./scripts/list_cases.sh                    # pending vs complete
./scripts/slurm_submit.sh --pending --dry-run   # preview; no sbatch
./scripts/slurm_submit.sh --pending               # one job array for all eligible days
```

- **Does not submit** days that already have `runs/YYYYMMDD/.ayil_complete` (unless `--force`).
- **Does not submit** days marked `.ayil_running` (unless `--force`).
- Default: **one Slurm job array** for all eligible days; Slurm schedules tasks as resources allow (no artificial concurrency cap unless you set `AYIL_SLURM_ARRAY_MAX` in `env.local`).
- Slurm CPU/memory/time defaults are tuned for Caltech HPC but are **only environment defaults** — override in `env.local` on other clusters.

See **[scripts/README.md](scripts/README.md)** for `sbatch` options, single-day jobs, and monitoring.

## Tests

```bash
./test/run_tests.sh                    # bash pipeline
cd python && conda run -n MOSAiC_AYIL pytest   # Zarr conversion
```

## Zarr output (after a run finishes)

```bash
./scripts/convert_to_zarr.sh runs/20200720
```

See [python/README.md](python/README.md).

See [scripts/README.md](scripts/README.md).

Contact for the published dataset: Niklas Schnierstein (nschnier@uni-koeln.de).

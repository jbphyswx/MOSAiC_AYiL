# MOSAiC_AYIL

Regenerate full 3D/4D DALES output for [Schnierstein et al. 2024 (JAMES)](https://doi.org/10.1029/2024MS004296) / [Zenodo 10.5281/zenodo.10491362](https://zenodo.org/records/10491362).

Zenodo provides **profile-averaged** outputs; full horizontal fields require rerunning DALES with the archived inputs.

**Cursor / agents:** see [AGENTS.md](AGENTS.md) for pipeline entry points, conda env rules, Slurm, and known config facts.

## Simulation length: paper vs Zenodo configs

> **Discrepancy (known):** [Schnierstein et al. 2024 (JAMES)](https://doi.org/10.1029/2024MS004296) states that each daily simulation runs for **3 hours**. Every `namoptions` in `ayil_config_input_results/` from Zenodo sets `runtime = 7200` (**2 hours**). This repo reproduces the **archived configs as-is** (`7200` s), not the paper’s 3 h wording.
>
> - Integration length: `runtime` in `&run` (seconds).
> - **3D field snapshots** (`fielddump.*.*.001.nc`): `namfielddump` `dtav = 1800` → one write every **30 min** → **4** snapshots per 2 h run (not higher cadence).
> - Other outputs (e.g. `profiles.001.nc`) are more frequent; see `namoptions` (`namgenstat`, `namtimestat`, etc.).
> - `tb_taunudge = 10800` is a **nudging timescale** (3 h), not simulation duration.
> - **Restart checkpoints:** Zenodo used `trestart = 1800` (full 3D `initd*` + scalar `inits*` every 30 min, ~77 GiB/day). This pipeline sets **`trestart = -1`** (no restart output; DALES treats `trestart < 0` as off). Applied in `prepare_case.sh` and in archived `ayil_config_input_results/*/namoptions`.
>
> To match the paper’s 3 h, you would need to change `runtime` (e.g. to `10800`) and revisit downstream assumptions (Zarr `FIELDDUMP_CHUNKS_TIME`, output size estimates). That is **not** the current default pipeline.

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

## Repository layout

| Path | Role |
|------|------|
| `scripts/` | **Canonical pipeline** (build, prepare, run, smoke test, Slurm example) |
| `dales_ayil/` | AYIL DALES source + committed CMake bootstrap files |
| `ayil_config_input_results/YYYYMMDD/` | Per-day inputs (and Zenodo profile outputs) |
| `runs/` | Simulation working directories (created by scripts; gitignored) |

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

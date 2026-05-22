# MOSAiC_AYIL tests

```bash
./test/run_tests.sh
```

**Always lightweight:** mock `mpirun` + `mock_dales4` exercise chunk orchestration, restart naming, Slurm helpers, and `run_slurm_day.sh` — **no** real 320×320 LES, no GPU/HPC memory requirements. Safe on laptops, GitHub CI, and login nodes.

| Layer | Examples |
|-------|----------|
| Unit | `test_restart_naming.sh`, `test_chunk_run.sh`, `test_mock_dales4.sh` |
| Integration | `test_chunk_restart_handoff.sh`, `test_chunk_orchestration_mock.sh` |

**Real `dales4` MPI** is **not** in this suite. Use `scripts/manual/` on a compute node when you choose to pay for a full-domain run.

```bash
./scripts/build_dales.sh
./scripts/manual/smoke_test.sh          # optional human check
./scripts/manual/chunk_warmstart_smoke_test.sh
```

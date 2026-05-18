# MOSAiC_AYIL tests

```bash
./test/run_tests.sh              # unit + integration (no compiled DALES)
./test/run_tests.sh --with-dales # adds smoke_test if dales4 exists
```

Tests use mock MPI (`test/fixtures/bin/mock_mpirun`) so they run on laptops, Slurm clusters, and CI without a fixed Open MPI path.

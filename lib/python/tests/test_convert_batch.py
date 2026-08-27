"""Batch convert discovery and stale detection."""

from __future__ import annotations

from pathlib import Path

import pytest

from ayil.convert_stamps import fielddump_newer_than_zarr, fielddump_source_stamp
from ayil.convert_batch import convert_runs_batch, discover_run_dirs, is_run_active
from ayil.fielddump import fielddump_n_time
from ayil.convert import convert_run


def test_discover_run_dirs(synthetic_run_dir: Path) -> None:
    runs = synthetic_run_dir.parent
    empty = runs / "20200101"
    empty.mkdir(parents=True, exist_ok=True)

    found = discover_run_dirs(runs)
    assert [p.name for p in found] == ["20990101"]


def test_is_run_active(tmp_path: Path) -> None:
    run = tmp_path / "runs" / "20200720"
    run.mkdir(parents=True)
    assert not is_run_active(run)
    (run / ".ayil_running").write_text("")
    assert is_run_active(run)
    (run / ".ayil_complete").write_text("")
    assert not is_run_active(run)


def test_batch_skips_empty_time_fielddump(tmp_path: Path) -> None:
    from conftest import _write_tile

    run = tmp_path / "runs" / "20200102"
    run.mkdir(parents=True)
    _write_tile(run / "fielddump.000.000.001.nc", ix=0, iy=0, nx=3, ny=3, nz=4, nt=0)

    assert fielddump_n_time(run) == 0
    results = convert_runs_batch([run], add_thermo=False, include_staggered=False, include_fluxes=False)
    assert results["skipped_no_snapshots"] == [str(run.resolve())]
    assert results["failed"] == []


def test_fielddump_newer_after_convert(synthetic_run_dir: Path) -> None:
    out = convert_run(
        synthetic_run_dir,
        overwrite=True,
        require_complete=False,
        add_thermo=False,
        include_staggered=False,
        include_fluxes=False,
    )
    assert not fielddump_newer_than_zarr(synthetic_run_dir, out)
    stamp = fielddump_source_stamp(synthetic_run_dir)
    assert stamp["fielddump_n_time"] >= 2

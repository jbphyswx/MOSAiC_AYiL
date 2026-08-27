"""Unit tests for fielddump discovery and merge."""

from __future__ import annotations

from pathlib import Path

import pytest

from ayil.fielddump import find_fielddump_tiles, merge_fielddump, parse_tile_index


def test_find_and_parse_tiles(synthetic_run_dir: Path) -> None:
    tiles = find_fielddump_tiles(synthetic_run_dir)
    assert len(tiles) == 4
    assert parse_tile_index(tiles[0]) == (0, 0)


def test_merge_fielddump(synthetic_run_dir: Path) -> None:
    ds = merge_fielddump(synthetic_run_dir, include_staggered=False)
    assert "qt" in ds
    assert ds.sizes["x"] == 6
    assert ds.sizes["y"] == 6
    assert ds.sizes["z"] == 4
    assert ds.sizes["time"] == 2


def test_merge_includes_staggered(synthetic_run_dir: Path) -> None:
    ds = merge_fielddump(synthetic_run_dir, include_staggered=True)
    assert "u" in ds and "v" in ds and "w" in ds
    assert not any(v.startswith("u_tile_") for v in ds.data_vars)
    assert ds.sizes["y"] == 6
    assert ds.sizes["xu"] == 6
    assert ds.sizes["yv"] == 6


def test_scalar_renamed(synthetic_run_dir: Path) -> None:
    ds = merge_fielddump(synthetic_run_dir, include_staggered=False)
    assert "n_rain" in ds
    assert "sv001" not in ds


def test_missing_tiles_raises(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        merge_fielddump(tmp_path)

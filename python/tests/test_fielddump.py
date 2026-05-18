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
    staggered = [v for v in ds.data_vars if v.startswith("u_tile_")]
    assert len(staggered) == 4


def test_missing_tiles_raises(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        merge_fielddump(tmp_path)
